-- Feats: small guild achievements, earned by each character and shared with
-- guild mates who run Nemux Ledger. Each client only counts its own
-- character; what others send is shown as they sent it (honour system).
--
-- Message: A|1|<ver>|<id,id,...>   every feat I have (with hello and when I earn one)

local _, RL = ...
local F = RL:NewModule("Feats")
RL.Feats = F
local Compat = RL.Compat

local PROTO = "1"
local SECONDARY = { [185] = true, [129] = true, [356] = true } -- Cooking, First Aid, Fishing

-- s = { level, maxPrimary, mastered, cooking, firstAid, fishing, deaths, meals, bags, hk, recipes, zones, bosses }
-- Feats without "test" are earned by events (boss fights).
F.DEFS = {
  { id = 1,  name = "Fresh Blood",        desc = "Reach level 10",                  test = function(s) return s.level >= 10 end },
  { id = 2,  name = "Getting Somewhere",  desc = "Reach level 20",                  test = function(s) return s.level >= 20 end },
  { id = 3,  name = "Saddle Up",          desc = "Reach level 40",                  test = function(s) return s.level >= 40 end },
  { id = 4,  name = "The Summit",         desc = "Reach level 60",                  test = function(s) return s.level >= 60 end },
  { id = 5,  name = "Journeyman",         desc = "A main profession at 150",        test = function(s) return s.maxPrimary >= 150 end },
  { id = 6,  name = "Expert",             desc = "A main profession at 225",        test = function(s) return s.maxPrimary >= 225 end },
  { id = 7,  name = "Artisan",            desc = "A main profession at 300",        test = function(s) return s.maxPrimary >= 300 end },
  { id = 8,  name = "Camp Cook",          desc = "Cooking at 150",                  test = function(s) return s.cooking >= 150 end },
  { id = 9,  name = "Gourmand",           desc = "Eat 25 meals with a food buff",   test = function(s) return s.meals >= 25 end },
  { id = 10, name = "Happy Camper",       desc = "Use the Sleeping Bag 10 times",   test = function(s) return s.bags >= 10 end },
  { id = 11, name = "First Floor Kiss",   desc = "Die for the first time",          test = function(s) return s.deaths >= 1 end },
  { id = 12, name = "Spirit Healer's Regular", desc = "Die 10 times",               test = function(s) return s.deaths >= 10 end },
  { id = 13, name = "Frequent Flier",     desc = "Die 50 times",                    test = function(s) return s.deaths >= 50 end },
  { id = 14, name = "Centurion of the Floor", desc = "Die 100 times",               test = function(s) return s.deaths >= 100 end },
  { id = 15, name = "Died Doing What They Loved", desc = "Die during a boss fight" },
  { id = 16, name = "Raid Ready",         desc = "Kill a raid boss" },
  { id = 17, name = "Not a Scratch",      desc = "Kill a raid boss without dying in the fight" },
  { id = 18, name = "Well Prepared",      desc = "Kill a raid boss with every raid buff you track" },
  -- 0.4.0
  { id = 19, name = "Halfway There",      desc = "Reach level 30",                  test = function(s) return s.level >= 30 end },
  { id = 20, name = "Almost There",       desc = "Reach level 50",                  test = function(s) return s.level >= 50 end },
  { id = 21, name = "First Blood",        desc = "Get an honorable kill",           test = function(s) return s.hk >= 1 end },
  { id = 22, name = "Bloodthirsty",       desc = "100 honorable kills",             test = function(s) return s.hk >= 100 end },
  { id = 23, name = "Thousand Cuts",      desc = "1000 honorable kills",            test = function(s) return s.hk >= 1000 end },
  { id = 24, name = "Master of Two Trades", desc = "Both main professions at 300",  test = function(s) return s.mastered >= 2 end },
  { id = 25, name = "Recipe Hoarder",     desc = "Know 100 recipes",                test = function(s) return s.recipes >= 100 end },
  { id = 26, name = "Field Medic",        desc = "First Aid at 150",                test = function(s) return s.firstAid >= 150 end },
  { id = 27, name = "Gone Fishing",       desc = "Fishing at 150",                  test = function(s) return s.fishing >= 150 end },
  { id = 28, name = "Glutton",            desc = "Eat 100 meals with a food buff",  test = function(s) return s.meals >= 100 end },
  { id = 29, name = "Professional Napper", desc = "Use the Sleeping Bag 50 times",  test = function(s) return s.bags >= 50 end },
  { id = 30, name = "Tourist of the Afterlife", desc = "Die in 10 different zones", test = function(s) return s.zones >= 10 end },
  { id = 31, name = "Dungeon Crawler",    desc = "Die in a dungeon" },
  { id = 32, name = "Raid Regular",       desc = "Kill 10 raid bosses",             test = function(s) return s.bosses >= 10 end },
  { id = 33, name = "Night Owl",          desc = "Level up between 2 and 5 a.m." },
}
F.byId = {}
for _, d in ipairs(F.DEFS) do F.byId[d.id] = d end

local function state()
  local s = { level = UnitLevel("player") or 0, maxPrimary = 0, mastered = 0, cooking = 0, firstAid = 0, fishing = 0, deaths = 0 }
  for _, p in ipairs(Compat.MyProfessions()) do
    local rank = tonumber(p.rank) or 0
    if p.skillLine == 185 then s.cooking = rank end
    if p.skillLine == 129 then s.firstAid = rank end
    if p.skillLine == 356 then s.fishing = rank end
    if p.skillLine and not SECONDARY[p.skillLine] then
      if rank > s.maxPrimary then s.maxPrimary = rank end
      if rank >= 300 then s.mastered = s.mastered + 1 end
    end
  end
  s.hk = RL.Boards and RL.Boards:MyHonorKills() or 0
  s.recipes = 0
  for _, rec in pairs(RL.charDB.recipes) do s.recipes = s.recipes + (rec.n or 0) end
  local rec = RL.DB:Me()
  s.deaths = rec and tonumber(rec.deaths.total) or 0
  local counts = RL.charDB.feats.counts
  s.meals, s.bags = tonumber(counts.meals) or 0, tonumber(counts.bags) or 0
  s.bosses = tonumber(counts.bosses) or 0
  s.zones = 0
  for _ in pairs(type(counts.zones) == "table" and counts.zones or {}) do s.zones = s.zones + 1 end
  return s
end

function F:Has(id) return RL.charDB.feats.earned[id] ~= nil end

function F:Count()
  local n = 0
  for _ in pairs(RL.charDB.feats.earned) do n = n + 1 end
  return n
end

function F:Message()
  local ids = {}
  for id in pairs(RL.charDB.feats.earned) do if F.byId[id] then ids[#ids + 1] = id end end
  table.sort(ids)
  return table.concat({ "A", PROTO, RL.version, table.concat(ids, ",") }, "|")
end

function F:Share(channel, target)
  if not IsInGuild() then return end
  RL.Guild:Queue(self:Message(), channel or "GUILD", target)
end

function F:Earn(id, silent)
  local def = F.byId[id]
  if not def or self:Has(id) then return false end
  RL.charDB.feats.earned[id] = GetServerTime()
  if not silent then
    local T = RL.Theme
    local text = "Feat earned: " .. def.name
    RL:Print("%s %s", T.Color(text, "ok"), T.Color("(" .. def.desc .. ")", "muted"))
    if RaidNotice_AddMessage and RaidWarningFrame then
      pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = T.c.ok[1], g = T.c.ok[2], b = T.c.ok[3] })
    end
    self:Share("GUILD")
    RL:Fire("RL_FEAT_EARNED", id)
  end
  RL:Fire("RL_FEATS_UPDATED")
  return true
end

-- Checks every feat that can be worked out from the character's state.
function F:Check(silent)
  if not RL.charDB then return 0 end
  local f = RL.charDB.feats
  local first = not f.init
  if first then silent = true end -- first run: old progress counts without fanfare
  local s = state()
  local n = 0
  for _, d in ipairs(F.DEFS) do
    if d.test and not self:Has(d.id) and d.test(s) then
      if self:Earn(d.id, silent) then n = n + 1 end
    end
  end
  if first then
    f.init = true
    if n > 0 then RL:Print("You already have %d feats. See the Feats tab (/rq feats).", n) end
  end
  return n
end

-- ---------------------------------------------------------------------------
-- Counting meals and Sleeping Bag uses (a new buff = a new expiry time)
-- ---------------------------------------------------------------------------
local function countNew(res, key, field)
  if not res or not res.expires or (res.status ~= "active" and res.status ~= "expiring") then return false end
  local ends = GetServerTime() + math.floor(res.expires - GetTime())
  local f = RL.charDB.feats
  local last = tonumber(f.last[key])
  if last and math.abs(last - ends) <= 120 then return false end
  f.last[key] = ends
  f.counts[field] = (tonumber(f.counts[field]) or 0) + 1
  return true
end

RL:On("RL_READINESS_UPDATED", function()
  if not RL.charDB then return end
  local r = RL.Readiness.results
  local a = countNew(r.food, "food", "meals")
  local b = countNew(r.sleepingbag, "bag", "bags")
  if a or b then F:Check() end
end)

-- ---------------------------------------------------------------------------
-- Boss fights
-- ---------------------------------------------------------------------------
local fight -- { died, prepared }

local function allRaidBuffs()
  local R = RL.Readiness
  local any = false
  for _, check in ipairs(RL.Data.CHECKS) do
    if check.kind ~= "sleepingbag" and R:IsTracked(check.id, "raid") then
      local res = R.results[check.id]
      if not res or res.status == "missing" or res.status == "low" or res.status == "unknown" then return false end
      any = true
    end
  end
  return any
end

RL:On("ENCOUNTER_START", function()
  fight = { died = false, prepared = allRaidBuffs() }
end)
RL:On("RL_MY_DEATH", function(entry)
  if fight then fight.died = true end
  if entry and entry.boss then F:Earn(15) end
  if entry and entry.where == "party" then F:Earn(31) end
  local counts = RL.charDB.feats.counts
  if entry and type(entry.zone) == "string" and entry.zone ~= "" then
    counts.zones = type(counts.zones) == "table" and counts.zones or {}
    counts.zones[entry.zone] = true
  end
  F:Check()
end)
RL:On("ENCOUNTER_END", function(_, _, _, _, success)
  local f = fight
  fight = nil
  if not f or success ~= 1 then return end
  if RL.Context:Instance() ~= "raid" then return end
  local counts = RL.charDB.feats.counts
  counts.bosses = (tonumber(counts.bosses) or 0) + 1
  F:Earn(16)
  F:Check()
  if not f.died then F:Earn(17) end
  if f.prepared then F:Earn(18) end
end)

-- ---------------------------------------------------------------------------
-- What guild mates have
-- ---------------------------------------------------------------------------
-- Returns the sender's version when the message was valid.
function F.OnMessage(who, _, _, msg)
  local proto, version, list = msg:match("^A|(%d+)|(%d+%.%d+%.%d+)|([%d,]*)$")
  if proto ~= PROTO then return nil end
  local ids, n = {}, 0
  for id in list:gmatch("[^,]+") do
    id = tonumber(id)
    if not id or not F.byId[id] then
      if not id or id > 999 then return nil end -- a newer version may know more feats
    else
      ids[id] = true
    end
    n = n + 1
    if n > 100 then return nil end
  end
  local all = RL.db.guildFeats
  local before = all[who]
  if before then
    local G = RL.Guild
    local row = G.byName[who]
    for id in pairs(ids) do
      if not before.ids[id] then
        RL:Fire("RL_PEER_FEAT", who, id)
        if RL.charDB.feats.guildAlerts then RL:Print("%s earned %s", RL.Theme.ClassColored(G.Short(who), row and row.classFile),
          RL.Theme.Color(F.byId[id].name, "ok")) end
      end
    end
  end
  all[who] = { ids = ids, at = GetServerTime() }
  RL:Fire("RL_FEATS_UPDATED")
  return version
end

-- { [id] = { short names } } of guild mates (not me), plus totals per person.
function F:Guild()
  local G = RL.Guild
  local holders, totals = {}, {}
  for who, rec in pairs(RL.db.guildFeats) do
    if not G:IsMe(who) then
      local n = 0
      for id in pairs(rec.ids or {}) do
        holders[id] = holders[id] or {}
        table.insert(holders[id], G.Short(who))
        n = n + 1
      end
      totals[#totals + 1] = { name = G.Short(who), n = n }
    end
  end
  for _, list in pairs(holders) do table.sort(list) end
  table.sort(totals, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  return holders, totals
end

-- ---------------------------------------------------------------------------
-- Guild goals: worked out on each client from what it knows (roster + addon data)
-- ---------------------------------------------------------------------------
local function guildNumbers()
  local G = RL.Guild
  local max = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
  local n = { online = G.online or 0, maxed = 0, ledger = 1, weekDeaths = 0, hk = 0, recipes = 0 }
  for _, m in ipairs(G.members) do
    if (m.level or 0) >= max then n.maxed = n.maxed + 1 end
  end
  local seen = {}
  for _, t in ipairs({ G.peers, RL.db.guildStats, RL.db.guildFeats, RL.db.guildRecipes }) do
    for who in pairs(t) do
      if not seen[who] and not G:IsMe(who) and (G.total == 0 or G.byName[who]) then
        seen[who] = true
        n.ledger = n.ledger + 1
      end
    end
  end
  if RL.Boards then
    for _, r in ipairs(RL.Boards:Board("week")) do n.weekDeaths = n.weekDeaths + r.value end
    for _, r in ipairs(RL.Boards:Board("hk")) do n.hk = n.hk + r.value end
  end
  if RL.Recipes then
    local mine, _, total = RL.Recipes:Stats()
    n.recipes = mine + total
  end
  return n
end

F.GOALS = {
  { id = 101, name = "Packed Tavern",   desc = "25 members online at once",          key = "online",     goal = 25 },
  { id = 102, name = "Army of Sixty",   desc = "10 members at max level",            key = "maxed",      goal = 10 },
  { id = 103, name = "Ledger Keepers",  desc = "10 members with Nemux Ledger",     key = "ledger",     goal = 10 },
  { id = 104, name = "Mass Grave",      desc = "50 guild deaths in one week",        key = "weekDeaths", goal = 50 },
  { id = 105, name = "Bloodbath",       desc = "1000 honorable kills together",      key = "hk",         goal = 1000 },
  { id = 106, name = "Crafting Guild",  desc = "500 recipes shared in the addon",    key = "recipes",    goal = 500 },
}

-- Rows: { def, value, reached = server time or nil }
function F:Goals()
  local n = guildNumbers()
  local out = {}
  for _, g in ipairs(F.GOALS) do
    out[#out + 1] = { def = g, value = n[g.key] or 0, reached = RL.db.guildGoals[g.id] }
  end
  return out
end

function F:CheckGoals()
  if not (RL.db and IsInGuild()) then return end
  local n = guildNumbers()
  for _, g in ipairs(F.GOALS) do
    if not RL.db.guildGoals[g.id] and (n[g.key] or 0) >= g.goal then
      RL.db.guildGoals[g.id] = GetServerTime()
      if RL.charDB.feats.guildAlerts then
        RL:Print("%s %s", RL.Theme.Color("Guild goal reached: " .. g.name, "warn"), RL.Theme.Color("(" .. g.desc .. ")", "muted"))
      end
      RL:Fire("RL_FEATS_UPDATED")
    end
  end
end

local goalsPending = false
local function goalsSoon()
  if goalsPending then return end
  goalsPending = true
  C_Timer.After(5, function()
    goalsPending = false
    F:CheckGoals()
  end)
end
RL:On("RL_GUILD_UPDATED", goalsSoon)
RL:On("RL_BOARDS_UPDATED", goalsSoon)
RL:On("RL_RECIPES_UPDATED", goalsSoon)

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function F:Init()
  RL.Guild.handlers.A = F.OnMessage
end

function F:OnLogin()
  C_Timer.After(3, function() F:Check() end)
end

RL:On("PLAYER_LEVEL_UP", function()
  local hour = tonumber(date("%H"))
  if hour and hour >= 2 and hour < 5 then F:Earn(33) end
  C_Timer.After(1, function() F:Check() end)
end)
RL:On("PLAYER_PVP_KILLS_CHANGED", function() C_Timer.After(1, function() F:Check() end) end)
RL:On("RL_RECIPES_UPDATED", function() F:Check() end)
RL:On("SKILL_LINES_CHANGED", function() C_Timer.After(2, function() F:Check() end) end)
RL:On("RL_DEATHS_UPDATED", function() F:Check() end)
RL:On("RL_HELLO_SENT", function() C_Timer.After(5, function() F:Share("GUILD") end) end)
RL:On("RL_PEER_HELLO", function(sender) F:Share("WHISPER", sender) end)
