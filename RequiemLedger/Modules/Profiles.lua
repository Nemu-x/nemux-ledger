-- Profiles: one guild member on one page, from what the addon already knows.
-- Nothing new is sent: deaths, feats, honor kills, professions, cooldowns,
-- raid attendance and chronicle lines all come from the other modules, so a
-- profile works while the member is offline.

local _, RL = ...
local Pf = RL:NewModule("Profiles")
RL.Profiles = Pf

local SECONDARY = { [185] = true, [129] = true, [356] = true }

local function G() return RL.Guild end

-- Guild key (Name-Realm) for a name with or without realm.
local function keyFor(name)
  local g = G()
  local full = g.FullName(name)
  if full and g.byName[full] then return full end
  local s = g.Short(name)
  for k in pairs(g.byName) do if g.Short(k) == s then return k end end
  return full or name
end

-- Returns a table with everything the profile page shows.
function Pf:Get(name)
  local g = G()
  local who = keyFor(name)
  local row = g.byName[who]
  local me = g:IsMe(who)
  local peer = g:PeerFor(who)
  local p = {
    key = who, short = g.Short(who), me = me, row = row,
    classFile = row and row.classFile, className = row and row.className, level = row and row.level,
    rank = row and row.rank, online = me or (row and row.online) or false, zone = row and row.zone,
    version = me and RL.version or (peer and peer.version),
  }

  -- Numbers
  local stats = RL.db.guildStats[who]
  if me then
    local s = RL.Deaths:Stats()
    p.deaths, p.week, p.hk = s and s.total or 0, s and s.week or 0, RL.Boards:MyHonorKills()
  else
    p.deaths, p.week, p.hk = stats and stats.deaths, stats and stats.week, stats and stats.hk
    if stats and (stats.at or 0) < RL.Boards:WeekStart() then p.week = 0 end
    if peer and peer.deaths and (not p.deaths or peer.deaths > p.deaths) then p.deaths = peer.deaths end
  end
  local feats = {}
  if me then
    for id in pairs(RL.charDB.feats.earned) do if RL.Feats.byId[id] then feats[#feats + 1] = id end end
  else
    local rec = RL.db.guildFeats[who]
    for id in pairs(rec and rec.ids or {}) do if RL.Feats.byId[id] then feats[#feats + 1] = id end end
  end
  table.sort(feats, function(a, b) return a > b end) -- newest feats have the highest ids
  p.feats, p.featTotal = feats, #RL.Feats.DEFS
  p.hasData = me or stats ~= nil or peer ~= nil or RL.db.guildFeats[who] ~= nil

  -- Professions: { line, name, rank, max, recipes, secondary }
  p.profs = {}
  local seen = {}
  local function addProf(line, rank, max)
    if seen[line] then return end
    seen[line] = true
    p.profs[#p.profs + 1] = { line = line, name = RL.Recipes:LineName(line), rank = rank, max = max,
      recipes = (RL.Recipes:MemberCount(who, line)), secondary = SECONDARY[line] or false }
  end
  if me then
    for _, pr in ipairs(RL.Compat.MyProfessions()) do
      if pr.skillLine then addProf(pr.skillLine, pr.rank, pr.max) end
    end
  else
    local list = (peer and peer.profs) or (RL.db.guildProfs[who] and RL.db.guildProfs[who].list) or {}
    for line, pr in pairs(list) do addProf(line, pr.rank, pr.max) end
    local rec = RL.Recipes:MemberRecord(who)
    for line, l in pairs(rec and rec.lines or {}) do
      if (l.n or 0) > 0 then addProf(line, nil, nil) end
    end
  end
  table.sort(p.profs, function(a, b)
    if a.secondary ~= b.secondary then return b.secondary end
    return (a.rank or 0) > (b.rank or 0)
  end)

  -- Cooldowns: { name, readyAt }
  p.cds = {}
  local cds
  if me then
    local rec = RL.DB:Me()
    cds = rec and rec.cds
  else
    cds = RL.db.guildCDs[who] and RL.db.guildCDs[who].list
  end
  for k, v in pairs(cds or {}) do p.cds[#p.cds + 1] = { name = RL.Cooldowns:Name(k), readyAt = v } end
  table.sort(p.cds, function(a, b) return a.readyAt < b.readyAt end)

  -- Raid attendance (last 30 days)
  local rows, total = RL.Raids:Attendance(30)
  p.raidNights, p.raidTotal = 0, total
  for _, r in ipairs(rows) do
    if g.Short(r.name) == p.short or (me and r.me) then p.raidNights = r.nights end
  end

  -- Titles: #1 on a leaderboard
  p.titles = {}
  for _, kind in ipairs({ "deaths", "week", "hk" }) do
    local top = RL.Boards:Board(kind)[1]
    if top and ((me and top.me) or (not me and top.name == p.short)) then p.titles[#p.titles + 1] = RL.Boards:Title(kind) end
  end

  -- Recent chronicle lines about them
  p.recent = {}
  for _, e in ipairs(RL.Chronicle:List()) do
    if e.who ~= "" and (g.Short(e.who) == p.short or (e.kind == "craft" and g.Short(e.a) == p.short)) then
      p.recent[#p.recent + 1] = e
      if #p.recent >= 6 then break end
    end
  end

  -- Open crafting requests involving them
  p.orders = 0
  for _, o in pairs(RL.db.orders) do
    if (o.status == "O" or o.status == "A") and (g.Short(o.from) == p.short or (o.to ~= "" and g.Short(o.to) == p.short)) then
      p.orders = p.orders + 1
    end
  end
  return p
end
