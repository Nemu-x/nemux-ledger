-- Weekly report: what the guild did since the weekly reset, as text to paste
-- in Discord (/rq week). Levels come from the guild roster (everyone); deaths,
-- honor kills and feats come from members with Nemux Ledger.
--
-- RL.db.week = {
--   start  = server time of the week start,
--   levels = { [Name-Realm] = level when first seen this week },
--   hk     = { [Name-Realm | "me"] = honor kills when first seen this week },
--   feats  = { { who = short name, id = featId }, ... },
--   last   = { start, text } -- last week's report, kept after the reset
-- }

local _, RL = ...
local W = RL:NewModule("Weekly")
RL.Weekly = W

local function data() return RL.db.week end

local function maxLevel()
  return (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
end

local function reset(w, start)
  w.start, w.levels, w.hk, w.feats = start, {}, {}, {}
end

-- Fills in starting values for anyone not seen yet this week.
function W:Baseline()
  local w = data()
  for _, m in ipairs(RL.Guild.members) do
    if type(m.level) == "number" and w.levels[m.name] == nil then w.levels[m.name] = m.level end
  end
  for who, rec in pairs(RL.db.guildStats) do
    if w.hk[who] == nil then w.hk[who] = rec.hk or 0 end
  end
  if w.hk.me == nil then w.hk.me = RL.Boards:MyHonorKills() end
end

-- Starts a new week after the reset; keeps last week's report.
function W:Check()
  if not RL.db then return end
  local w = data()
  local start = RL.Boards:WeekStart()
  if not w.start then
    reset(w, start)
  elseif start - w.start > 3600 then -- a new week (an hour of slack for clock jitter)
    w.last = { start = w.start, text = self:Text(w.start) }
    reset(w, start)
    if RL.charDB.week.notify then RL:Print("Last week's guild report is ready: /rq week") end
  end
  self:Baseline()
end

local function top(list, n, fmt)
  table.sort(list, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.name < b.name end)
  local parts = {}
  for i = 1, math.min(n, #list) do parts[#parts + 1] = string.format(fmt, list[i].name, list[i].v) end
  return table.concat(parts, ", ")
end

-- Report text for the week that started at weekStart (default: this week).
function W:Text(weekStart)
  local w = data()
  local G, B = RL.Guild, RL.Boards
  local out = {}
  local function add(fmt, ...) out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
  add("%s weekly report · week of %s", RL.Context:GuildName() or "Guild", date("%d %b", math.floor(weekStart or w.start or GetServerTime())))

  -- Deaths (members with the addon)
  local deaths, total = {}, 0
  for _, r in ipairs(B:Board("week", weekStart or w.start)) do
    deaths[#deaths + 1] = { name = r.name, v = r.value }
    total = total + r.value
  end
  if total > 0 then
    add("Deaths: %d · most: %s · Floor Inspector of the Week: %s", total, top(deaths, 3, "%s %d"), deaths[1].name)
  else
    add("Deaths: none. Suspicious.")
  end

  -- Levels (whole guild, from the roster)
  local levels, gained, maxed = {}, 0, {}
  for _, m in ipairs(G.members) do
    local base = w.levels and w.levels[m.name]
    if base and type(m.level) == "number" and m.level > base then
      levels[#levels + 1] = { name = m.short, v = m.level - base }
      gained = gained + (m.level - base)
      if m.level >= maxLevel() then maxed[#maxed + 1] = m.short end
    end
  end
  if gained > 0 then add("Levels: +%d · most: %s", gained, top(levels, 3, "%s +%d")) else add("Levels: nobody dinged.") end
  if #maxed > 0 then table.sort(maxed); add("New level %d: %s", maxLevel(), table.concat(maxed, ", ")) end

  -- Honor kills (members with the addon)
  local hks, hkTotal = {}, 0
  local mine = B:MyHonorKills() - (w.hk and w.hk.me or B:MyHonorKills())
  if mine > 0 then hks[#hks + 1] = { name = "you", v = mine }; hkTotal = hkTotal + mine end
  for who, rec in pairs(RL.db.guildStats) do
    local base = w.hk and w.hk[who]
    if base and (rec.hk or 0) > base and not G:IsMe(who) then
      hks[#hks + 1] = { name = G.Short(who), v = rec.hk - base }
      hkTotal = hkTotal + rec.hk - base
    end
  end
  if hkTotal > 0 then add("Honor kills: +%d · most: %s", hkTotal, top(hks, 3, "%s +%d")) end

  -- Feats
  local byWho, order = {}, {}
  for _, f in ipairs(w.feats or {}) do
    local def = RL.Feats.byId[f.id]
    if def then
      if not byWho[f.who] then byWho[f.who] = {}; order[#order + 1] = f.who end
      table.insert(byWho[f.who], def.name)
    end
  end
  if #order > 0 then
    local parts = {}
    for _, who in ipairs(order) do parts[#parts + 1] = who .. ": " .. table.concat(byWho[who], ", ") end
    add("Feats: %s", table.concat(parts, " · "))
  end
  -- Loot (from Gargul / RCLootCouncil, as this client saw it)
  local start = weekStart or w.start or 0
  local loot = RL.Loot:List("", start)
  local items = {}
  for _, e in ipairs(loot) do
    if (e.ts or 0) < start + 7 * 86400 then
      items[#items + 1] = RL.Guild.Short(e.to) .. ": " .. RL.Loot:ItemName(e) .. (e.os and " (OS)" or "")
    end
  end
  if #items > 0 then
    local shown = {}
    for i = 1, math.min(8, #items) do shown[i] = items[i] end
    add("Loot: %d items · %s%s", #items, table.concat(shown, ", "), #items > 8 and ", ..." or "")
  end
  add("Deaths, honor kills and feats: members with Nemux Ledger only.")
  return table.concat(out, "\n")
end

-- This week so far, plus last week's report when there is one.
function W:FullText()
  self:Check()
  local text = "THIS WEEK SO FAR\n" .. self:Text()
  local last = data().last
  if last and last.text then text = text .. "\n\nLAST WEEK\n" .. last.text end
  return text
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local function myName()
  return UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player") or "you"
end

RL:On("RL_FEAT_EARNED", function(id)
  W:Check()
  table.insert(data().feats, { who = myName(), id = id })
end)
RL:On("RL_PEER_FEAT", function(who, id)
  W:Check()
  table.insert(data().feats, { who = RL.Guild.Short(who), id = id })
end)
RL:On("RL_GUILD_UPDATED", function() if RL.Guild.total > 0 then W:Check() end end)
RL:On("RL_BOARDS_UPDATED", function() W:Check() end)

function W:OnLogin()
  C_Timer.After(8, function() W:Check() end)
end
