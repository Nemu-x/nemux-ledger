-- Guild: the roster (works for everyone, no addon needed) and a tiny exchange
-- between members who run Nemux Ledger.
--
-- Messages (addon channel, prefix "RQLedger"), plain text, never executed:
--   H|1|<version>|<deaths>          hello, sent to GUILD at login
--   R|1|<version>|<deaths>          reply to a hello, WHISPER to the sender
--   D|1|<version>|<deaths>|<where>  "I just died", sent to GUILD
--   P|1|<version>|<line:rank:max,...>  my professions (the game's guild list
--                                      shows skill 1 in Forever, so we share it)
--   K / Q / C                       recipes, handled by Recipes.lua
--   A                               feats, handled by Feats.lua
-- Everything received is checked against strict patterns; anything else is
-- dropped. Whispers are only accepted from people in your guild roster.
-- Sending pauses while the game blocks addon messages (boss fights); the
-- death message is sent afterwards.

local _, RL = ...
local G = RL:NewModule("Guild")
RL.Guild = G

G.PREFIX = "RQLedger"
local PROTO = "1"
local MAX_LEN = 200
local MAX_PROFS = 8
local WHERE_OK = { world = true, party = true, raid = true, pvp = true }

G.info = nil       -- { name, rank, rankIndex }
G.members = {}     -- roster rows
G.byName = {}      -- [Name-Realm] = row
G.peers = {}       -- [Name-Realm] = { version, deaths, seen }
G.online, G.total = 0, 0

local myName
local seenLevel = {} -- [Name-Realm] = level seen this session (for ding alerts)
local lastHello, lastRoster = -1000, -1000
local replied = {} -- [sender] = time of our last reply
local pending      -- message waiting for the lockdown to end

-- "Name" -> "Name-Realm" so names from the roster and from messages match.
local function full(name)
  if type(name) ~= "string" or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  local realm = GetNormalizedRealmName and GetNormalizedRealmName()
  if realm and realm ~= "" then return name .. "-" .. realm end
  return name
end
G.FullName = full

local function short(name)
  return name and (name:match("^([^%-]+)") or name) or "?"
end
G.Short = short

-- Is this name me? Names in Forever have a surname ("Nemu Pvpdisc") and a
-- mega-realm, so the roster entry with my GUID is the reliable answer.
local function isMe(name)
  if not name then return false end
  if myName then
    -- The guild profession list gives "Nemu Pvpdisc" without the realm,
    -- the roster gives "Nemu Pvpdisc-Realm", UnitName gives only "Nemu".
    if name == myName or short(name) == short(myName) then return true end
  end
  local mine = UnitName("player")
  return mine ~= nil and short(name) == short(mine)
end
G.IsMe = function(_, name) return isMe(name) end

-- ---------------------------------------------------------------------------
-- Roster
-- ---------------------------------------------------------------------------
function G:RequestRoster()
  if not IsInGuild() then return end
  if GetTime() - lastRoster < 10 then return end
  lastRoster = GetTime()
  if C_GuildInfo and C_GuildInfo.GuildRoster then
    pcall(C_GuildInfo.GuildRoster)
  elseif GuildRoster then
    pcall(GuildRoster)
  end
end

function G:ScanRoster()
  wipe(self.members)
  wipe(self.byName)
  self.online, self.total = 0, 0
  if not IsInGuild() then
    self.info = nil
    RL:Fire("RL_GUILD_UPDATED")
    return
  end
  local gname, rankName, rankIndex = GetGuildInfo("player")
  if gname then self.info = { name = gname, rank = rankName, rankIndex = rankIndex } end
  local n = GetNumGuildMembers() or 0
  for i = 1, n do
    local ok, name, rank, rIndex, level, className, zone, _, _, online, _, classFile, _, _, _, _, _, guid = pcall(GetGuildRosterInfo, i)
    if ok and type(name) == "string" then
      local row = {
        name = full(name), short = short(name), rank = rank, rankIndex = rIndex,
        level = level, className = className, classFile = classFile, zone = zone,
        online = online and true or false,
      }
      local me = guid and guid == UnitGUID("player")
      if me then myName = row.name; self.peers[row.name] = nil end
      local before = seenLevel[row.name]
      if type(level) == "number" then
        seenLevel[row.name] = level
        if before and level > before and not me then RL:Fire("RL_GUILD_DING", row, level) end
      end
      self.members[#self.members + 1] = row
      self.byName[row.name] = row
      if row.online then self.online = self.online + 1 end
    end
  end
  self.total = #self.members
  RL:Fire("RL_GUILD_UPDATED")
end

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------
local function myDeaths()
  local rec = RL.DB:Me()
  return rec and tonumber(rec.deaths.total) or 0
end

local function locked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, v = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and v == true then return true end
  end
  return false
end

local function send(msg, channel, target)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  if locked() then return false end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, G.PREFIX, msg, channel, target)
  return ok and result ~= false
end

G.Send = send

-- Spaced sending for bigger exchanges (recipes): the game allows about one
-- addon message per second per prefix on the guild channel.
local queue, draining = {}, false
local function drain()
  local item = table.remove(queue, 1)
  if not item then draining = false; return end
  if locked() then
    table.insert(queue, 1, item)
    C_Timer.After(5, drain)
    return
  end
  send(item[1], item[2], item[3])
  C_Timer.After(item[2] == "WHISPER" and 0.4 or 1.2, drain)
end

function G:Queue(msg, channel, target)
  if #queue >= 200 then return false end
  queue[#queue + 1] = { msg, channel, target }
  if not draining then
    draining = true
    C_Timer.After(0.1, drain)
  end
  return true
end

-- Handlers for message kinds owned by other modules: [letter] = fn(who, sender, channel, msg)
G.handlers = {}

local function build(kind, extra)
  local parts = { kind, PROTO, RL.version, tostring(myDeaths()) }
  if extra then parts[#parts + 1] = extra end
  return table.concat(parts, "|")
end
G.Build = build

-- "P|1|0.1.2|333:216:300,185:150:300"
local function profMessage()
  local parts = {}
  for _, p in ipairs(RL.Compat.MyProfessions()) do
    if p.skillLine and #parts < MAX_PROFS then
      parts[#parts + 1] = string.format("%d:%d:%d", p.skillLine, p.rank or 0, p.max or 0)
    end
  end
  return table.concat({ "P", PROTO, RL.version, table.concat(parts, ",") }, "|")
end
G.ProfMessage = profMessage

local lastProfSent, lastProfAt = nil, -1000
function G:ShareProfessions(channel, target, force)
  if not IsInGuild() then return end
  local msg = profMessage()
  if not force and msg == lastProfSent and GetTime() - lastProfAt < 600 then return end
  if send(msg, channel or "GUILD", target) and not target then
    lastProfSent, lastProfAt = msg, GetTime()
  end
end

function G:SayHello(force)
  if not IsInGuild() then return end
  if not force and GetTime() - lastHello < 60 then return end
  lastHello = GetTime()
  send(build("H"), "GUILD")
  self:ShareProfessions("GUILD", nil, true)
  RL:Fire("RL_HELLO_SENT")
end

-- Tries the waiting death message again (after a boss fight, for example).
function G:Flush()
  if pending and IsInGuild() and send(pending, "GUILD") then pending = nil end
end

-- Parses a message. Returns kind, version, deaths, where (H/R/D)
-- or "P", version, { [skillLine] = { rank, max } } -- or nil if invalid.
function G.Parse(msg)
  if type(msg) ~= "string" or #msg > MAX_LEN then return nil end
  if msg:sub(1, 2) == "P|" then
    local proto, version, list = msg:match("^P|(%d+)|(%d+%.%d+%.%d+)|([%d:,]*)$")
    if proto ~= PROTO then return nil end
    local profs, n = {}, 0
    for entry in list:gmatch("[^,]+") do
      local id, rank, max = entry:match("^(%d+):(%d+):(%d+)$")
      id, rank, max = tonumber(id), tonumber(rank), tonumber(max)
      if not id or id > 1000000 or rank > 5000 or max > 5000 then return nil end
      n = n + 1
      if n > MAX_PROFS then return nil end
      profs[id] = { rank = rank, max = max }
    end
    return "P", version, profs
  end
  local kind, proto, version, deaths, where = msg:match("^([HRD])|(%d+)|(%d+%.%d+%.%d+)|(%d+)|?(%l*)$")
  if not kind or proto ~= PROTO then return nil end
  deaths = tonumber(deaths)
  if not deaths or deaths > 1000000 then return nil end
  if kind == "D" then
    if not WHERE_OK[where] then return nil end
  elseif where ~= "" then
    return nil
  end
  return kind, version, deaths, where
end

function G:OnMessage(prefix, msg, channel, sender)
  if prefix ~= G.PREFIX then return end
  if channel ~= "GUILD" and channel ~= "WHISPER" then return end
  local who = full(sender)
  if not who or isMe(who) then return end
  if channel == "WHISPER" and not self.byName[who] then return end
  if type(msg) ~= "string" or #msg > MAX_LEN then return end
  local handler = G.handlers[msg:sub(1, 1)]
  if handler and msg:sub(2, 2) == "|" then
    local version = handler(who, sender, channel, msg)
    if version then
      local peer = self.peers[who] or {}
      peer.version, peer.seen = version, GetServerTime()
      self.peers[who] = peer
      RL:Fire("RL_GUILD_UPDATED")
    end
    return
  end
  local kind, version, deaths, where = G.Parse(msg)
  if not kind then return end

  local peer = self.peers[who] or {}
  local before = peer.deaths
  peer.version, peer.seen = version, GetServerTime()
  if kind == "P" then
    peer.profs = deaths -- the parsed profession table
  else
    peer.deaths = deaths
  end
  self.peers[who] = peer

  if kind == "H" then
    local last = replied[who]
    if not last or GetTime() - last > 60 then
      replied[who] = GetTime()
      send(build("R"), "WHISPER", sender)
      self:ShareProfessions("WHISPER", sender, true)
      RL:Fire("RL_PEER_HELLO", sender)
    end
  elseif kind == "D" and deaths ~= before then
    RL:Fire("RL_PEER_DEATH", who, deaths, where)
  end
  if kind == "D" and RL.charDB.deaths.guildAlerts and deaths ~= before then
    local row = self.byName[who]
    local name = RL.Theme.ClassColored(short(who), row and row.classFile)
    local text = RL.Deaths:PickPhrase({ name = name, count = deaths }, where)
    if text then RL:Print("%s |cff97a3bb(death #%d)|r", text, deaths) end
  end
  RL:Fire("RL_GUILD_UPDATED")
end

-- Peer record for a name with or without realm.
function G:PeerFor(name)
  if not name then return nil end
  local p = self.peers[full(name)]
  if p then return p end
  local s = short(name)
  for key, peer in pairs(self.peers) do
    if short(key) == s then return peer end
  end
  return nil
end

-- How many guild mates (online, or not in the roster yet) run the addon.
function G:PeerCount()
  local n = 0
  for name in pairs(self.peers) do
    local row = self.byName[name]
    if not row or row.online then n = n + 1 end
  end
  return n
end

-- ---------------------------------------------------------------------------
-- Guild professions (Blizzard's guild crafting list; may be off in Forever)
-- ---------------------------------------------------------------------------
local SECONDARY = { [185] = true, [129] = true, [356] = true } -- Cooking, First Aid, Fishing

function G:ProfessionsAvailable()
  return GetNumGuildTradeSkill ~= nil and GetGuildTradeSkillInfo ~= nil
end

function G:QueryProfessions()
  if QueryGuildRecipes then pcall(QueryGuildRecipes) end
end

-- Rows: { header = true, id, name, icon, players, online, collapsed, secondary }
--    or { name, classFile, skill, online, zone }
function G:Professions()
  local out = {}
  if not self:ProfessionsAvailable() then return out end
  local ok, n = pcall(GetNumGuildTradeSkill)
  if not ok or not n then return out end
  local currentSkill
  for i = 1, n do
    local okI, skillID, collapsed, icon, headerName, numOnline, _, numPlayers, playerName, _, _, online, zone, skill, classFile =
      pcall(GetGuildTradeSkillInfo, i)
    if okI then
      if headerName then
        currentSkill = skillID
        out[#out + 1] = { header = true, id = skillID, name = headerName, icon = icon, players = numPlayers or 0,
          online = numOnline or 0, collapsed = collapsed, secondary = SECONDARY[skillID] or false }
      elseif playerName then
        out[#out + 1] = { name = playerName, classFile = classFile, skill = skill or 0, online = online, zone = zone,
          skillID = currentSkill }
      end
    end
  end
  return out
end

function G:ToggleProfession(row)
  if not row or not row.header then return end
  local fn = row.collapsed and ExpandGuildTradeSkillHeader or CollapseGuildTradeSkillHeader
  if fn then pcall(fn, row.id) end
  RL:Fire("RL_GUILD_UPDATED")
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function G:Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, G.PREFIX)
  end
end

-- Keeps the roster fresh (levels for ding alerts, zones, who is online).
local function tick()
  G:RequestRoster()
  C_Timer.After(60, tick)
end

function G:OnLogin()
  C_Timer.After(5, tick)
  C_Timer.After(10, function() G:SayHello(true) end)
end

RL:On("CHAT_MSG_ADDON", function(...) G:OnMessage(...) end)
RL:On("GUILD_ROSTER_UPDATE", function() G:ScanRoster() end)
RL:On("PLAYER_GUILD_UPDATE", function() G:RequestRoster() end)
RL:On("SKILL_LINES_CHANGED", function()
  C_Timer.After(30, function() G:ShareProfessions() end)
end)
RL:On("GUILD_TRADESKILL_UPDATE", function() RL:Fire("RL_GUILD_UPDATED") end)
RL:On("RL_MY_DEATH", function(entry)
  if not IsInGuild() then return end
  local msg = build("D", entry and entry.where or "world")
  if not send(msg, "GUILD") then pending = msg end
end)
RL:On("ENCOUNTER_END", function() C_Timer.After(4, function() G:Flush() end) end)

-- "Nemu reached level 40!" -- from the roster, so it works for everyone in the guild.
RL:On("RL_GUILD_DING", function(row, level)
  local cfg = RL.charDB.dings
  if not cfg.alerts then return end
  local max = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
  if cfg.milestonesOnly and level % 10 ~= 0 and level < max then return end
  local T = RL.Theme
  local name = T.ClassColored(row.short, row.classFile)
  if level >= max then
    RL:Print("%s reached level %s! The summit!", name, T.Color(level, "warn"))
  else
    RL:Print("%s reached level %s.", name, T.Color(level, "ok"))
  end
end)
RL:On("PLAYER_REGEN_ENABLED", function() C_Timer.After(2, function() G:Flush() end) end)
RL:On("ADDON_RESTRICTION_STATE_CHANGED", function() C_Timer.After(1, function() G:Flush() end) end)
