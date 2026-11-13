-- Boards: guild leaderboards (deaths, deaths this week, honorable kills) and a
-- feed of recent guild deaths. Only members with Nemux Ledger are counted.
--
-- Message: S|1|<ver>|<deaths>|<deathsThisWeek>|<honorKills>
--   sent with hello, to a guild mate who says hello, and a while after new HKs.
-- The week starts at the weekly reset, so everyone's "this week" is the same.

local _, RL = ...
local B = RL:NewModule("Boards")
RL.Boards = B

local PROTO = "1"
local FEED_MAX = 50
local LIMIT = 10000000

-- Server time when the current week started (weekly reset); 7 days back as a fallback.
function B:WeekStart()
  local now = GetServerTime()
  if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
    local ok, left = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
    if ok and type(left) == "number" and not RL.Compat.IsSecret(left) and left >= 0 and left <= 7 * 86400 then
      return now + math.floor(left) - 7 * 86400
    end
  end
  return now - 7 * 86400
end

function B:MyHonorKills()
  if not GetPVPLifetimeStats then return 0 end
  local ok, hk = pcall(GetPVPLifetimeStats)
  if ok and type(hk) == "number" and not RL.Compat.IsSecret(hk) then return hk end
  return 0
end

function B:Message()
  local s = RL.Deaths:Stats()
  return table.concat({ "S", PROTO, RL.version, s and s.total or 0, s and s.week or 0, self:MyHonorKills() }, "|")
end

function B:Share(channel, target)
  if not IsInGuild() then return end
  RL.Guild:Queue(self:Message(), channel or "GUILD", target)
end

local function statsFor(who)
  local all = RL.db.guildStats
  local rec = all[who]
  if type(rec) ~= "table" then
    rec = { deaths = 0, week = 0, hk = 0, at = 0 }
    all[who] = rec
  end
  return rec
end

-- Returns the sender's version when the message was valid.
function B.OnMessage(who, _, _, msg)
  local proto, version, deaths, week, hk = msg:match("^S|(%d+)|(%d+%.%d+%.%d+)|(%d+)|(%d+)|(%d+)$")
  if proto ~= PROTO then return nil end
  deaths, week, hk = tonumber(deaths), tonumber(week), tonumber(hk)
  if deaths > LIMIT or week > deaths or hk > LIMIT then return nil end
  if RL.Weekly then RL.Weekly:Check() end -- close last week before new numbers overwrite it
  local rec = statsFor(who)
  rec.deaths, rec.week, rec.hk, rec.at = deaths, week, hk, GetServerTime()
  RL:Fire("RL_BOARDS_UPDATED")
  return version
end

-- ---------------------------------------------------------------------------
-- Death feed
-- ---------------------------------------------------------------------------
local function addFeed(e)
  local feed = RL.db.deathFeed
  table.insert(feed, 1, e)
  while #feed > FEED_MAX do table.remove(feed) end
  RL:Fire("RL_BOARDS_UPDATED")
end

RL:On("RL_MY_DEATH", function(entry, total)
  addFeed({ me = true, ts = GetServerTime(), total = total, where = entry and entry.where,
    zone = entry and entry.zone, boss = entry and entry.boss })
end)

-- From Guild.lua: a guild mate with the addon died (zone comes from the roster).
RL:On("RL_PEER_DEATH", function(who, deaths, where)
  if RL.Weekly then RL.Weekly:Check() end
  local rec = statsFor(who)
  if rec.at < B:WeekStart() then rec.week = 0 end
  -- One message = one death. (A first message from someone we knew nothing
  -- about must not count all their old deaths as this week's.)
  if deaths > (rec.deaths or 0) then rec.week = rec.week + 1 end
  rec.deaths, rec.at = deaths, GetServerTime()
  local row = RL.Guild.byName[who]
  addFeed({ who = who, ts = GetServerTime(), total = deaths, where = where, zone = row and row.zone })
end)

-- ---------------------------------------------------------------------------
-- Boards
-- ---------------------------------------------------------------------------
B.KINDS = {
  deaths = { label = "Deaths", title = "Floor Collector" },
  week = { label = "This week", title = "Floor Inspector of the Week" },
  hk = { label = "Honor kills", title = "Warlord of %s" },
}

-- Title for #1 on a board ("Warlord of <guild>").
function B:Title(kind)
  local t = B.KINDS[kind].title
  if t:find("%s", 1, true) then t = t:format(RL.Context:GuildName() or "the Guild") end
  return t
end

-- Sorted rows: { name, classFile, online, me, value }. Zero values are left out.
-- weekStart: which week "week" means (default: the current one).
function B:Board(kind, weekStart)
  local G = RL.Guild
  weekStart = weekStart or self:WeekStart()
  local rows = {}
  local s = RL.Deaths:Stats()
  local mine = { deaths = s and s.total or 0, week = RL.Deaths:CountBetween(weekStart, weekStart + 7 * 86400),
    hk = self:MyHonorKills() }
  if mine[kind] > 0 then
    local _, class = UnitClass("player")
    rows[#rows + 1] = { name = "you", me = true, online = true, classFile = class, value = mine[kind] }
  end
  for who, rec in pairs(RL.db.guildStats) do
    if not G:IsMe(who) then
      local v = rec[kind] or 0
      if kind == "week" and ((rec.at or 0) < weekStart or (rec.at or 0) >= weekStart + 7 * 86400 + 3600) then v = 0 end
      if v > 0 then
        local row = G.byName[who]
        rows[#rows + 1] = { name = G.Short(who), classFile = row and row.classFile, online = row and row.online or false, value = v }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.name < b.name
  end)
  return rows
end

function B:Feed() return RL.db.deathFeed end

-- Forget members who left the guild (once the roster is loaded).
function B:Prune()
  local G = RL.Guild
  if not IsInGuild() or G.total == 0 then return end
  for who in pairs(RL.db.guildStats) do
    if not G.byName[who] then RL.db.guildStats[who] = nil end
  end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function B:Init()
  RL.Guild.handlers.S = B.OnMessage
end

RL:On("RL_HELLO_SENT", function() C_Timer.After(7, function() B:Share("GUILD") end) end)
RL:On("RL_PEER_HELLO", function(sender) B:Share("WHISPER", sender) end)

-- New honorable kills: tell the guild at most every 5 minutes.
local hkPending = false
RL:On("PLAYER_PVP_KILLS_CHANGED", function()
  if hkPending then return end
  hkPending = true
  C_Timer.After(300, function()
    hkPending = false
    B:Share("GUILD")
  end)
end)

local pruned = false
RL:On("RL_GUILD_UPDATED", function()
  if not pruned and RL.Guild.total > 0 then
    pruned = true
    B:Prune()
  end
end)
