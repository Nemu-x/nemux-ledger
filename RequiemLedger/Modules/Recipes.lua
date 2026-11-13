-- Recipes: who in the guild can craft what.
--
-- Your own recipes are read when you open your profession window (the game
-- only lists them then). Members with Nemux Ledger share recipe IDs; names
-- are looked up on each client, so only numbers travel. Shared recipes are
-- kept account-wide, so offline crafters can be found too.
--
-- Messages (prefix and sender rules: see Guild.lua):
--   K|1|<ver>|<line>:<count>:<sum>,...           summary of my recipes (with hello)
--   Q|1|<ver>|<line>                              "send me that list" (WHISPER)
--   C|1|<ver>|<line>|<part>|<total>|<id,id,...>   recipe IDs in parts (WHISPER)
-- A list is only accepted if we asked for it (Q) in the last two minutes.

local _, RL = ...
local Rc = RL:NewModule("Recipes")
RL.Recipes = Rc
local Compat = RL.Compat

local PROTO = "1"
local VER = "(%d+%.%d+%.%d+)"
local MAX_LINES = 8
local MAX_PER_LINE = 600
local MAX_PARTS = 30
local IDS_PER_MSG = 20      -- 20 IDs of up to 8 digits stay under 200 characters
local ASK_TIMEOUT = 120

-- Profession names for lines we may only know by number.
local LINE_NAMES = {
  [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
  [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering",
  [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning", [129] = "First Aid",
  [755] = "Jewelcrafting", [773] = "Inscription",
}

local asked = {}     -- [who .. "#" .. line] = time we sent Q
local answered = {}  -- [sender .. "#" .. line] = time we answered a Q
local incoming = {}  -- [who .. "#" .. line] = { total, got = {}, parts = 0, ids = {} }
local nameCache = {}

local function summary(ids)
  local n, sum = 0, 0
  for id in pairs(ids) do
    n = n + 1
    sum = (sum + id) % 1000003
  end
  return n, sum
end
Rc.Summary = summary

function Rc:LineName(line)
  local mine = RL.charDB.recipes[line]
  return (mine and mine.name) or LINE_NAMES[line] or ("Profession " .. tostring(line))
end

function Rc:RecipeName(id)
  local n = nameCache[id]
  if n then return n end
  n = Compat.SpellName(id)
  if type(n) == "string" and n ~= "" and not Compat.IsSecret(n) then
    nameCache[id] = n
    return n
  end
  return nil
end

-- Reagents: asked from the game, remembered account-wide (the game may only
-- answer while a profession window is open, so our own are saved on scan).
function Rc:Reagents(id)
  local cache = RL.db.reagents
  local list = Compat.RecipeReagents(id)
  if list then
    cache[id] = list
    return list
  end
  return cache[id]
end

-- Each reagent with what I have: { itemID, need, bags, total, name, icon }, and
-- whether the bags hold enough for one craft. nil when reagents are unknown.
function Rc:ReagentStatus(id)
  local list = self:Reagents(id)
  if not list then return nil end
  local out, ready = {}, true
  for _, r in ipairs(list) do
    local itemID, need = r[1], r[2]
    local bags, total = Compat.ItemCounts(itemID)
    local name = Compat.ItemName(itemID)
    if not name then Compat.RequestItem(itemID) end
    local price, source, age = Compat.Price(itemID)
    out[#out + 1] = { itemID = itemID, need = need, bags = bags, total = total, name = name, icon = Compat.ItemIcon(itemID),
      price = price, source = source, age = age }
    if bags < need then ready = false end
  end
  return out, ready
end

-- Approximate cost of one craft: total, cost of what is missing from the bags,
-- and whether every reagent had a price.
function Rc:Cost(mats)
  local total, missing, complete = 0, 0, true
  for _, m in ipairs(mats) do
    if m.price then
      total = total + m.price * m.need
      missing = missing + m.price * math.max(0, m.need - m.bags)
    else
      complete = false
    end
  end
  return total, missing, complete
end

-- ---------------------------------------------------------------------------
-- My recipes (read from the open profession window)
-- ---------------------------------------------------------------------------
local function ownWindowOpen()
  local TS = C_TradeSkillUI
  if not (TS and TS.GetAllRecipeIDs and TS.GetRecipeInfo and TS.GetBaseProfessionInfo) then return false end
  for _, f in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
    if TS[f] then
      local ok, v = pcall(TS[f])
      if ok and v then return false end -- someone else's or the guild's list, not mine
    end
  end
  if TS.IsTradeSkillReady then
    local ok, v = pcall(TS.IsTradeSkillReady)
    if ok and v == false then return false end
  end
  return true
end

-- The skill line that my professions list (and the P message) uses for this
-- profession. The window may report a different ID, so the name decides.
local function lineFor(id, name)
  local byName
  for _, p in ipairs(Compat.MyProfessions()) do
    if p.skillLine and p.skillLine == id then return id end
    if type(name) == "string" and type(p.name) == "string" and p.name:lower() == name:lower() then byName = p.skillLine end
  end
  return byName or id
end

-- Three ways to read the open window, newest first. Each returns
-- ids, line, name, source -- or nil, reason.
local function readModern()
  if not ownWindowOpen() then
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return nil, "no C_TradeSkillUI" end
    return nil, "modern: window not ready or not mine"
  end
  local name, line
  for _, fn in ipairs({ "GetBaseProfessionInfo", "GetChildProfessionInfo" }) do
    if not line and C_TradeSkillUI[fn] then
      local ok, info = pcall(C_TradeSkillUI[fn])
      if ok and type(info) == "table" then
        local id = info.parentProfessionID or info.professionID
        if type(id) == "number" and id > 0 and not Compat.IsSecret(id) then line = id end
        name = name or info.parentProfessionName or info.professionName
      end
    end
  end
  local okAll, all = pcall(C_TradeSkillUI.GetAllRecipeIDs)
  if not okAll or type(all) ~= "table" or #all == 0 then return nil, "modern: 0 recipe IDs" end
  local ids, n = {}, 0
  for _, id in ipairs(all) do
    if n >= MAX_PER_LINE then break end
    local okR, r = pcall(C_TradeSkillUI.GetRecipeInfo, id)
    if okR and type(r) == "table" and r.learned and type(id) == "number" and not Compat.IsSecret(id) then
      ids[id] = true
      n = n + 1
      if type(r.name) == "string" and not Compat.IsSecret(r.name) then nameCache[id] = r.name end
      Rc:Reagents(id) -- remember while the window is open
    end
  end
  if n == 0 then return nil, string.format("modern: %d recipes, none learned", #all) end
  line = lineFor(line, name)
  if not line then return nil, "modern: unknown profession" end
  return ids, line, name, "modern"
end

-- Classic API: the list holds only learned recipes; IDs come from the links.
local function idFromLink(link)
  return type(link) == "string" and tonumber(link:match("enchant:(%d+)")) or nil
end

local function readClassic(countFn, infoFn, linkFns, lineFn, label)
  if not (countFn and infoFn and lineFn) then return nil, label .. ": no API" end
  local okL, name = pcall(lineFn)
  if not okL or type(name) ~= "string" or name == "" or name == "UNKNOWN" then return nil, label .. ": not open" end
  local okN, total = pcall(countFn)
  if not okN or type(total) ~= "number" or total == 0 then return nil, label .. ": 0 rows" end
  local ids, n = {}, 0
  for i = 1, total do
    local ok, rname, kind = pcall(infoFn, i)
    if ok and kind ~= "header" and kind ~= "subheader" and n < MAX_PER_LINE then
      local id
      for k = 1, 2 do -- either function may be missing (nil), so no ipairs here
        local fn = linkFns[k]
        if not id and fn then
          local okK, link = pcall(fn, i)
          if okK then id = idFromLink(link) end
        end
      end
      if id then
        ids[id] = true
        n = n + 1
        if type(rname) == "string" then nameCache[id] = rname end
      end
    end
  end
  if n == 0 then return nil, string.format("%s: %d rows, no recipe IDs", label, total) end
  local line = lineFor(nil, name)
  if not line then return nil, label .. ": unknown profession " .. name end
  return ids, line, name, label
end

Rc.lastScan = nil -- { at, ok, reason, source, line, n } for /rq report

function Rc:ScanOpen()
  local ids, line, name, source
  local reasons = {}
  local readers = {
    readModern,
    function() return readClassic(GetNumTradeSkills, GetTradeSkillInfo, { GetTradeSkillRecipeLink, GetTradeSkillItemLink }, GetTradeSkillLine, "classic") end,
    function() return readClassic(GetNumCrafts, GetCraftInfo, { GetCraftRecipeLink, GetCraftItemLink }, GetCraftDisplaySkillLine or GetCraftName, "craft") end,
  }
  for _, read in ipairs(readers) do
    if not ids then
      local a, b, c, d = read()
      if a then ids, line, name, source = a, b, c, d else reasons[#reasons + 1] = tostring(b) end
    end
  end
  if not ids then
    self.lastScan = { at = GetServerTime(), ok = false, reason = table.concat(reasons, "; ") }
    return false
  end

  local old = RL.charDB.recipes[line]
  local count, sum = summary(ids)
  self.lastScan = { at = GetServerTime(), ok = true, source = source, line = line, n = count }
  RL.charDB.recipes[line] = { ids = ids, n = count, sum = sum, at = GetServerTime(),
    name = type(name) == "string" and name or LINE_NAMES[line] }
  if not old or old.n ~= count or old.sum ~= sum then
    RL:Print("Saved %d %s recipes. Guild mates with Nemux Ledger can find them now.", count, self:LineName(line))
    self:SendSummary("GUILD")
  end
  RL:Fire("RL_RECIPES_UPDATED")
  return true
end

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------
function Rc:SummaryMessage()
  local parts = {}
  for line, rec in pairs(RL.charDB.recipes) do
    if #parts < MAX_LINES and type(line) == "number" and type(rec) == "table" then
      parts[#parts + 1] = string.format("%d:%d:%d", line, rec.n or 0, rec.sum or 0)
    end
  end
  if #parts == 0 then return nil end
  table.sort(parts)
  return table.concat({ "K", PROTO, RL.version, table.concat(parts, ",") }, "|")
end

function Rc:SendSummary(channel, target)
  if not IsInGuild() then return end
  local msg = self:SummaryMessage()
  if msg then RL.Guild:Queue(msg, channel, target) end
end

-- All parts of one profession list, as messages.
function Rc:ListMessages(line)
  local rec = RL.charDB.recipes[line]
  if not rec then return {} end
  local sorted = {}
  for id in pairs(rec.ids) do sorted[#sorted + 1] = id end
  table.sort(sorted)
  local total = math.max(1, math.ceil(#sorted / IDS_PER_MSG))
  if total > MAX_PARTS then total = MAX_PARTS end
  local out = {}
  for part = 1, total do
    local chunk = {}
    for i = (part - 1) * IDS_PER_MSG + 1, math.min(#sorted, part * IDS_PER_MSG) do chunk[#chunk + 1] = sorted[i] end
    out[#out + 1] = table.concat({ "C", PROTO, RL.version, line, part, total, table.concat(chunk, ",") }, "|")
  end
  return out
end

local function store(who)
  local all = RL.db.guildRecipes
  local rec = all[who]
  if type(rec) ~= "table" then
    rec = { lines = {} }
    all[who] = rec
  end
  return rec
end

local function onSummary(who, sender, list)
  local rec = RL.db.guildRecipes[who]
  local n = 0
  for entry in list:gmatch("[^,]+") do
    local line, count, sum = entry:match("^(%d+):(%d+):(%d+)$")
    line, count, sum = tonumber(line), tonumber(count), tonumber(sum)
    if not line or line > 1000000 or count > MAX_PER_LINE then return false end
    n = n + 1
    if n > MAX_LINES then return false end
    local have = rec and rec.lines[line]
    if not have or have.n ~= count or have.sum ~= sum then
      local key = who .. "#" .. line
      if count > 0 and (not asked[key] or GetTime() - asked[key] > ASK_TIMEOUT) then
        asked[key] = GetTime()
        RL.Guild:Queue(table.concat({ "Q", PROTO, RL.version, line }, "|"), "WHISPER", sender)
      end
    end
  end
  return true
end

local function onAsk(who, sender, line)
  line = tonumber(line)
  if not line or not RL.charDB.recipes[line] then return end
  local key = who .. "#" .. line
  if answered[key] and GetTime() - answered[key] < 300 then return end
  answered[key] = GetTime()
  for _, msg in ipairs(Rc:ListMessages(line)) do RL.Guild:Queue(msg, "WHISPER", sender) end
end

local function onPart(who, line, part, total, list)
  line, part, total = tonumber(line), tonumber(part), tonumber(total)
  if not (line and part and total) or total < 1 or total > MAX_PARTS or part < 1 or part > total then return false end
  local key = who .. "#" .. line
  if not asked[key] or GetTime() - asked[key] > ASK_TIMEOUT then return true end -- not asked for: ignore quietly
  local ids, n = {}, 0
  for id in list:gmatch("[^,]+") do
    if not id:match("^%d+$") or #id > 8 then return false end
    n = n + 1
    if n > IDS_PER_MSG then return false end
    ids[#ids + 1] = tonumber(id)
  end
  local inc = incoming[key]
  if not inc or inc.total ~= total or part == 1 then
    inc = { total = total, got = {}, parts = 0, ids = {} }
    incoming[key] = inc
  end
  if not inc.got[part] then
    inc.got[part] = true
    inc.parts = inc.parts + 1
    for _, id in ipairs(ids) do inc.ids[id] = true end
  end
  if inc.parts == inc.total then
    incoming[key], asked[key] = nil, nil
    local count, sum = summary(inc.ids)
    local rec = store(who)
    rec.lines[line] = { ids = inc.ids, n = count, sum = sum }
    rec.at = GetServerTime()
    RL:Fire("RL_RECIPES_UPDATED")
  end
  return true
end

-- Returns the sender's version when the message was valid.
function Rc.OnMessage(who, sender, channel, msg)
  local kind = msg:sub(1, 1)
  if kind == "K" then
    local proto, version, list = msg:match("^K|(%d+)|" .. VER .. "|([%d:,]+)$")
    if proto ~= PROTO then return nil end
    return onSummary(who, sender, list) and version or nil
  elseif kind == "Q" then
    if channel ~= "WHISPER" then return nil end
    local proto, version, line = msg:match("^Q|(%d+)|" .. VER .. "|(%d+)$")
    if proto ~= PROTO then return nil end
    onAsk(who, sender, line)
    return version
  elseif kind == "C" then
    if channel ~= "WHISPER" then return nil end
    local proto, version, line, part, total, list = msg:match("^C|(%d+)|" .. VER .. "|(%d+)|(%d+)|(%d+)|([%d,]*)$")
    if proto ~= PROTO then return nil end
    return onPart(who, line, part, total, list) and version or nil
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------------
-- Results: { id, name, line, crafters = { { name, me, online, classFile } } },
-- sorted by name. nil when the query is too short.
function Rc:Search(query)
  query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if #query < 2 then return nil end
  local G = RL.Guild
  local found = {}
  local function add(id, line, who, me)
    local name = self:RecipeName(id)
    if not name or not name:lower():find(query, 1, true) then return end
    local key = line .. ":" .. id
    local r = found[key]
    if not r then
      r = { id = id, name = name, line = line, crafters = {} }
      found[key] = r
    end
    local row = not me and G.byName[who]
    r.crafters[#r.crafters + 1] = { name = me and "you" or G.Short(who), me = me,
      online = me or (row and row.online) or false, classFile = row and row.classFile }
  end
  for line, rec in pairs(RL.charDB.recipes) do
    for id in pairs(rec.ids or {}) do add(id, line, nil, true) end
  end
  for who, rec in pairs(RL.db.guildRecipes) do
    if not G:IsMe(who) then
      for line, l in pairs(rec.lines or {}) do
        for id in pairs(l.ids or {}) do add(id, line, who, false) end
      end
    end
  end
  local out = {}
  for _, r in pairs(found) do
    table.sort(r.crafters, function(a, b)
      if a.me ~= b.me then return a.me end
      if a.online ~= b.online then return a.online end
      return a.name < b.name
    end)
    out[#out + 1] = r
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Numbers for the UI and the report.
function Rc:Stats()
  local mine, people, total = 0, 0, 0
  for _, rec in pairs(RL.charDB.recipes) do mine = mine + (rec.n or 0) end
  for who, rec in pairs(RL.db.guildRecipes) do
    if not RL.Guild:IsMe(who) then
      people = people + 1
      for _, l in pairs(rec.lines or {}) do total = total + (l.n or 0) end
    end
  end
  return mine, people, total
end

-- Forget members who left the guild (only once the roster is loaded).
function Rc:Prune()
  local G = RL.Guild
  if not IsInGuild() or G.total == 0 then return end
  for who in pairs(RL.db.guildRecipes) do
    if not G.byName[who] then RL.db.guildRecipes[who] = nil end
  end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function Rc:Init()
  RL.Guild.handlers.K = Rc.OnMessage
  RL.Guild.handlers.Q = Rc.OnMessage
  RL.Guild.handlers.C = Rc.OnMessage
end

local scanPending = false
local function scanSoon()
  if scanPending then return end
  scanPending = true
  C_Timer.After(1, function()
    scanPending = false
    Rc:ScanOpen()
  end)
end

-- A profession window opened: if nothing could be read a few seconds later,
-- say so once per session instead of failing silently.
local told = false
local function windowOpened()
  scanSoon()
  C_Timer.After(4, function()
    if Rc:ScanOpen() or told then return end
    told = true
    RL:Print("Could not read this profession window (%s). Please send /rq report.",
      Rc.lastScan and Rc.lastScan.reason or "?")
  end)
end

RL:On("TRADE_SKILL_SHOW", windowOpened)
RL:On("CRAFT_SHOW", windowOpened)
RL:On("TRADE_SKILL_LIST_UPDATE", scanSoon)
RL:On("TRADE_SKILL_UPDATE", scanSoon)
RL:On("TRADE_SKILL_DATA_SOURCE_CHANGED", scanSoon)
RL:On("CRAFT_UPDATE", scanSoon)
RL:On("NEW_RECIPE_LEARNED", scanSoon)
RL:On("RL_HELLO_SENT", function() C_Timer.After(3, function() Rc:SendSummary("GUILD") end) end)
RL:On("RL_PEER_HELLO", function(sender) Rc:SendSummary("WHISPER", sender) end)
local pruned = false
RL:On("RL_GUILD_UPDATED", function()
  if not pruned and RL.Guild.total > 0 then
    pruned = true
    Rc:Prune()
  end
end)
