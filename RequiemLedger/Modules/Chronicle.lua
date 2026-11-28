-- Chronicle: the guild's story, one line per event that matters.
--   kill   guild first kill of a boss          a = encounterID, b = boss name
--   max    someone reached the level cap       who
--   feat   someone earned a feat               who, a = feat id
--   join   someone joined the guild            who
--   leave  someone left the guild              who
--   deaths the guild passed N deaths in total  a = N
--   craft  a crafting request was done         who = crafter, a = requester, b = recipe ID
--
-- Every event has a key made from its kind and fields, so the same event seen
-- by 40 clients is stored once. The earliest time wins.
-- Message: E|1|<ver>|<kind>|<ts>|<who>|<a>|<b>
--   sent to the guild when this client records something new, and the last few
--   to a guild mate who comes online (so people who were offline catch up).

local _, RL = ...
local Ch = RL:NewModule("Chronicle")
RL.Chronicle = Ch

local PROTO = "1"
local MAX = 200
local CATCH_UP = 8            -- events sent to someone who logs in
local CATCH_UP_AGE = 14 * 86400
local DEATH_STEP = 100
Ch.KINDS = { kill = true, max = true, feat = true, join = true, leave = true, deaths = true, craft = true }

local function now() return math.floor(GetServerTime()) end

-- Same event, same key, on every client. Events that can repeat (joining
-- again, crafting the same thing again) carry the day they happened.
local function key(kind, ts, who, a, b)
  if kind == "kill" or kind == "deaths" then return kind .. ":" .. a end
  local k = kind .. ":" .. who .. ":" .. a .. ":" .. b
  if kind == "join" or kind == "leave" or kind == "craft" then k = k .. ":" .. date("%Y-%m-%d", ts) end
  return k
end

local function clean(v)
  v = tostring(v or "")
  v = v:gsub("[|\n\r]", "")
  return v:sub(1, 48)
end

-- Stores an event; returns it when it was new.
local function store(kind, ts, who, a, b)
  local c = RL.db.chronicle
  local k = key(kind, ts, who, a, b)
  local seen = c.keys[k]
  if seen then
    if ts < seen.ts then seen.ts = ts end
    return nil
  end
  -- Someone who was offline for days sees a join late: one join per member a month.
  if kind == "join" or kind == "leave" then
    for _, x in ipairs(c.list) do
      if x.kind == kind and x.who == who and math.abs(x.ts - ts) < 30 * 86400 then
        if ts < x.ts then x.ts = ts end
        return nil
      end
    end
  end
  local e = { key = k, kind = kind, ts = ts, who = who, a = a, b = b }
  c.keys[k] = e
  table.insert(c.list, 1, e)
  table.sort(c.list, function(x, y) return x.ts > y.ts end)
  while #c.list > MAX do
    local old = table.remove(c.list)
    c.keys[old.key] = nil
  end
  RL:Fire("RL_CHRONICLE_UPDATED")
  return e
end

function Ch:Message(e)
  return table.concat({ "E", PROTO, RL.version, e.kind, e.ts, e.who or "", e.a or "", e.b or "" }, "|")
end

-- Records an event seen by this client and tells the guild.
function Ch:Add(kind, who, a, b)
  if not Ch.KINDS[kind] then return end
  who, a, b = clean(who), clean(a), clean(b)
  local e = store(kind, now(), who, a, b)
  if e and IsInGuild() then RL.Guild:Queue(self:Message(e), "GUILD") end
  return e
end

function Ch.OnMessage(who, _, _, msg)
  local proto, version, kind, ts, ewho, a, b = msg:match("^E|(%d+)|(%d+%.%d+%.%d+)|(%a+)|(%d+)|([^|]*)|([^|]*)|([^|]*)$")
  if proto ~= PROTO or not Ch.KINDS[kind] then return nil end
  ts = tonumber(ts)
  if ts > now() + 3600 or ts < now() - 365 * 86400 then return nil end
  if #ewho > 48 or #a > 48 or #b > 48 then return nil end
  store(kind, ts, ewho, a, b)
  return version
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------
local function name(n)
  if not n or n == "" then return "Someone" end
  local G = RL.Guild
  if G:IsMe(n) then return RL.Theme.Color("You", "ok") end
  local row = G.byName[G.FullName(n) or ""]
  return RL.Theme.ClassColored(G.Short(n), row and row.classFile)
end

-- One line for an event (with colours).
function Ch:Text(e)
  local T = RL.Theme
  if e.kind == "kill" then
    return T.Color("Guild first kill: ", "warn") .. (e.b ~= "" and e.b or "a boss")
  elseif e.kind == "max" then
    return name(e.who) .. " reached the level cap"
  elseif e.kind == "feat" then
    local def = RL.Feats and RL.Feats.byId and RL.Feats.byId[tonumber(e.a) or 0]
    return name(e.who) .. " earned " .. T.Color(def and def.name or e.a, "info")
  elseif e.kind == "join" then
    return name(e.who) .. " joined the guild"
  elseif e.kind == "leave" then
    return T.Color(RL.Guild.Short(e.who), "muted") .. " left the guild"
  elseif e.kind == "deaths" then
    return "The guild passed " .. T.Color(e.a .. " deaths", "bad")
  elseif e.kind == "craft" then
    return name(e.who) .. " crafted " .. RL.Recipes:RecipeName(tonumber(e.b) or 0) .. " for " .. name(e.a)
  end
  return e.kind
end

-- Plain text (for the weekly report).
function Ch:PlainText(e)
  return (self:Text(e):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Ch:List() return RL.db.chronicle.list end

-- ---------------------------------------------------------------------------
-- Sources
-- ---------------------------------------------------------------------------
-- Roster changes: who joined and who left since the last scan we saved.
function Ch:CheckRoster()
  if RL.demo then return end
  local G = RL.Guild
  if not IsInGuild() or G.total == 0 then return end
  local seen = RL.db.rosterSeen
  local first = next(seen) == nil
  local nowSet = {}
  for _, m in ipairs(G.members) do
    nowSet[m.name] = true
    if not seen[m.name] then
      seen[m.name] = true
      if not first then self:Add("join", m.name) end
    end
  end
  -- Only trust "left" with a full roster (the list can come in partly).
  if not first and G.total >= 1 then
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    if n - G.total <= math.max(3, n * 0.1) then -- more at once looks like a half-loaded roster
      for who in pairs(seen) do
        if not nowSet[who] then
          seen[who] = nil
          self:Add("leave", who)
        end
      end
    end
  end
end

-- Total guild deaths passed a round number.
function Ch:CheckDeaths()
  local total = 0
  local s = RL.Deaths:Stats()
  total = total + (s and s.total or 0)
  for who, rec in pairs(RL.db.guildStats) do
    if not RL.Guild:IsMe(who) then total = total + (rec.deaths or 0) end
  end
  local step = math.floor(total / DEATH_STEP) * DEATH_STEP
  local last = RL.db.chronicleDeaths or 0
  if step > last then
    RL.db.chronicleDeaths = step
    if last > 0 then self:Add("deaths", "", tostring(step)) end -- the first count is only a baseline
  end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function Ch:Init()
  RL.Guild.handlers.E = Ch.OnMessage
end

RL:On("RL_GUILD_UPDATED", function()
  if Ch.rosterTimer then return end
  Ch.rosterTimer = true
  C_Timer.After(5, function() Ch.rosterTimer = nil; Ch:CheckRoster() end)
end)

RL:On("RL_GUILD_DING", function(row, level)
  local max = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
  if level >= max then Ch:Add("max", row.name) end
end)
RL:On("PLAYER_LEVEL_UP", function(level)
  local max = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
  if type(level) == "number" and level >= max then
    for _, m in ipairs(RL.Guild.members) do
      if RL.Guild:IsMe(m.name) then Ch:Add("max", m.name) end
    end
  end
end)
RL:On("RL_FEAT_EARNED", function(id)
  for _, m in ipairs(RL.Guild.members) do
    if RL.Guild:IsMe(m.name) then Ch:Add("feat", m.name, id) end
  end
end)
RL:On("RL_PEER_FEAT", function(who, id) Ch:Add("feat", who, id) end)
RL:On("RL_BOARDS_UPDATED", function() Ch:CheckDeaths() end)
RL:On("RL_ORDER_DONE", function(o) Ch:Add("craft", o.to, o.from, tostring(o.recipe)) end)

RL:On("RL_PEER_HELLO", function(sender)
  local sent = 0
  for _, e in ipairs(RL.db.chronicle.list) do
    if sent >= CATCH_UP or now() - e.ts > CATCH_UP_AGE then break end
    RL.Guild:Queue(Ch:Message(e), "WHISPER", sender)
    sent = sent + 1
  end
end)
