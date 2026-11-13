-- Deaths: counts your own deaths and prints a random phrase in your chat.
-- Records live in the account-wide DB under the character's GUID, so later
-- versions can share them with the guild without changing the format.

local _, RL = ...
local D = RL:NewModule("Deaths")
RL.Deaths = D

D.session = 0
local lastDeathAt = 0
local MAX_LIST = 200
local RECENT_MEMORY = 10

local function deathData()
  local rec = RL.DB:Me()
  if not rec then return nil end
  local d = rec.deaths
  d.total = tonumber(d.total) or 0
  d.byType = d.byType or {}
  d.list = d.list or {}
  return d
end

-- Maps instance types to the buckets shown in the UI.
local function bucket(instanceType)
  if instanceType == "raid" then return "raid" end
  if instanceType == "party" or instanceType == "scenario" then return "party" end
  if instanceType == "pvp" or instanceType == "arena" then return "pvp" end
  return "world"
end
D.Bucket = bucket

-- ---------------------------------------------------------------------------
-- Phrase picker: random, avoids the last few phrases, prefers context lines.
-- ---------------------------------------------------------------------------
local function fillTemplate(tpl, vars)
  local ok = true
  local text = tpl:gsub("{(%w+)}", function(key)
    local v = vars[key]
    if v == nil and key == "guild" then v = RL.Context:GuildName() end
    if v == nil or v == "" then ok = false; return "" end
    return tostring(v)
  end)
  return ok and text or nil
end

local function recentList()
  RL.db.deathRecent = RL.db.deathRecent or {}
  return RL.db.deathRecent
end

local function isRecent(tpl)
  local recent = recentList()
  for i = 1, #recent do
    if recent[i] == tpl then return true end
  end
  return false
end

local function remember(tpl)
  local recent = recentList()
  table.insert(recent, 1, tpl)
  while #recent > RECENT_MEMORY do table.remove(recent) end
end

-- vars: name, zone, boss, count; where: "world" | "party" | "raid" | "pvp"
function D:PickPhrase(vars, where)
  local P = RL.Data.DEATH_PHRASES
  local milestone = RL.Data.DEATH_MILESTONES[vars.count or -1]
  if milestone then
    local text = fillTemplate(milestone, vars)
    if text then return text end
  end

  local candidates = {}
  local function add(list, weight)
    if not list then return end
    for _, tpl in ipairs(list) do
      if not isRecent(tpl) and fillTemplate(tpl, vars) then
        for _ = 1, weight do candidates[#candidates + 1] = tpl end
      end
    end
  end
  if vars.boss then add(P.boss, 3) end
  add(P[where], 2)
  add(P.any, 1)

  if #candidates == 0 then
    wipe(recentList())
    return fillTemplate(P.any[math.random(#P.any)], vars)
  end
  local tpl = candidates[math.random(#candidates)]
  remember(tpl)
  return fillTemplate(tpl, vars)
end

local function coloredName(name, class)
  if C_ClassColor and C_ClassColor.GetClassColor and class then
    local c = C_ClassColor.GetClassColor(class)
    if c and c.WrapTextInColorCode then return c:WrapTextInColorCode(name) end
  end
  return name
end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------
function D:OnPlayerDead()
  local now = GetTime()
  if now - lastDeathAt < 5 then return end -- the client can repeat the event
  lastDeathAt = now

  local d = deathData()
  if not d then return end
  local instanceType, instanceName, instanceID = RL.Context:Instance()
  local where = bucket(instanceType)
  local enc = RL.Context.encounter

  local entry = {
    id = RL.DB:NextEventId(),
    ts = GetServerTime(),
    zone = GetRealZoneText() or instanceName,
    where = where,
    instanceID = instanceID,
    level = UnitLevel("player"),
    mode = RL.Context.mode,
  }
  if enc then
    entry.encounterID = enc.id
    entry.boss = enc.name
  end

  d.total = d.total + 1
  d.byType[where] = (d.byType[where] or 0) + 1
  table.insert(d.list, 1, entry)
  while #d.list > MAX_LIST do table.remove(d.list) end
  self.session = self.session + 1

  if RL.charDB.deaths.chatPhrase then
    local _, class = UnitClass("player")
    local name = UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player")
    local text = self:PickPhrase({ name = coloredName(name, class), zone = entry.zone, boss = entry.boss, count = d.total }, where)
    if text then RL:Print("%s |cff97a3bb(death #%d)|r", text, d.total) end
  end
  RL:Fire("RL_DEATHS_UPDATED")
  RL:Fire("RL_MY_DEATH", entry, d.total)
end

-- Shows a phrase in chat without recording anything.
function D:Preview()
  local _, class = UnitClass("player")
  local name = UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player")
  local zone = GetRealZoneText()
  local d = deathData()
  local text = self:PickPhrase({ name = coloredName(name, class), zone = zone, count = ((d and d.total) or 0) + 1 }, "world")
  RL:Print("%s |cff97a3bb(preview, not counted)|r", text or "?")
end

-- My deaths with from <= time < to (server time).
function D:CountBetween(from, to)
  local d = deathData()
  if not d then return 0 end
  local n = 0
  for _, e in ipairs(d.list) do
    local ts = e.ts or 0
    if ts >= from and ts < to then n = n + 1 end
  end
  return n
end

function D:Stats()
  local d = deathData()
  if not d then return nil end
  -- "This week" starts at the weekly reset, the same for the whole guild.
  local week, cutoff = 0, RL.Boards and RL.Boards:WeekStart() or (GetServerTime() - 7 * 24 * 3600)
  for _, e in ipairs(d.list) do
    if (e.ts or 0) >= cutoff then week = week + 1 end
  end
  return {
    total = d.total,
    session = self.session,
    week = week,
    byType = d.byType,
    list = d.list,
  }
end

RL:On("PLAYER_DEAD", function() D:OnPlayerDead() end)
