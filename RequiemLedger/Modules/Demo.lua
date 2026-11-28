-- Demo mode (/rq demo): a made-up guild for screenshots, so no real player
-- shows up on the addon's page. The real saved data is set aside untouched:
-- the addon works on a copy filled with demo members, nothing is sent or
-- received, and /rq demo again (or a /reload) brings everything back.
-- The game saves the real tables (the SavedVariables globals never change).

local _, RL = ...
local Demo = RL:NewModule("Demo")
RL.Demo = Demo

local GUILD = "Ironbound Covenant"

-- name, classFile, className, level, rank, rankIndex, online, zone
local MEMBERS = {
  { "Aldric Stormbrow",  "PALADIN", "Paladin", 60, "Guild Master", 0, true,  "Stormwind City" },
  { "Lyra Dawnwhisper",  "PRIEST",  "Priest",  60, "Officer",      1, true,  "Ironforge" },
  { "Bram Ironfist",     "WARRIOR", "Warrior", 60, "Officer",      1, true,  "Blackrock Mountain" },
  { "Seline Frostweave", "MAGE",    "Mage",    60, "Raider",       2, true,  "Winterspring" },
  { "Mira Thistledown",  "DRUID",   "Druid",   60, "Raider",       2, true,  "Moonglade" },
  { "Corwin Blackthorn", "ROGUE",   "Rogue",   60, "Raider",       2, false, "" },
  { "Elsbeth Grayvale",  "WARLOCK", "Warlock", 60, "Raider",       2, true,  "Felwood" },
  { "Odo Tinkerbolt",    "WARLOCK", "Warlock", 60, "Member",       3, false, "" },
  { "Torvin Ashguard",   "WARRIOR", "Warrior", 58, "Member",       3, false, "" },
  { "Dain Coppervein",   "HUNTER",  "Hunter",  54, "Member",       3, true,  "Eastern Plaguelands" },
  { "Rowan Hollowell",   "PRIEST",  "Priest",  47, "Member",       3, true,  "Stranglethorn Vale" },
  { "Kessa Brightwater", "MAGE",    "Mage",    41, "Member",       3, false, "" },
  { "Gideon Marsh",      "PALADIN", "Paladin", 33, "Initiate",     4, false, "" },
  { "Wren Applebrook",   "HUNTER",  "Hunter",  21, "Initiate",     4, true,  "Duskwood" },
}
-- [member index] = { [skill line] = rank }
local PROFS = {
  [1] = { [164] = 300, [186] = 300, [185] = 225 },
  [2] = { [197] = 300, [333] = 285, [129] = 300 },
  [3] = { [164] = 290, [186] = 275, [356] = 150 },
  [4] = { [197] = 300, [333] = 300, [185] = 300 },
  [5] = { [171] = 300, [182] = 300, [129] = 225 },
  [6] = { [165] = 280, [393] = 300 },
  [7] = { [197] = 275, [333] = 240 },
  [8] = { [202] = 300, [186] = 300, [185] = 150 },
  [9] = { [164] = 210, [186] = 225 },
  [10] = { [202] = 245, [165] = 230, [356] = 300 },
  [11] = { [171] = 200, [182] = 210, [129] = 150 },
  [12] = { [197] = 180, [333] = 165 },
  [13] = { [164] = 120, [186] = 125 },
  [14] = { [165] = 60, [393] = 75, [185] = 90 },
}
local STATS = { -- deaths, this week, honor kills
  { 214, 3, 1840 }, { 96, 1, 310 }, { 342, 9, 2650 }, { 128, 4, 720 }, { 77, 0, 150 }, { 263, 6, 4120 },
  { 151, 5, 980 }, { 189, 2, 430 }, { 58, 4, 90 }, { 121, 7, 640 }, { 44, 3, 25 }, { 39, 2, 12 },
  { 17, 1, 0 }, { 9, 2, 0 },
}

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = deepcopy(v) end
  return out
end

-- Real recipe IDs we already know, per profession (names and icons resolve in game).
local function recipePools(db, charDB)
  local pools = {}
  local function add(line, ids)
    pools[line] = pools[line] or {}
    for id in pairs(ids or {}) do pools[line][id] = true end
  end
  for line, rec in pairs(charDB.recipes or {}) do if type(rec) == "table" then add(line, rec.ids) end end
  for _, rec in pairs(db.guildRecipes or {}) do
    for line, l in pairs(type(rec) == "table" and rec.lines or {}) do add(line, l.ids) end
  end
  local out = {}
  for line, set in pairs(pools) do
    local list = {}
    for id in pairs(set) do list[#list + 1] = id end
    table.sort(list)
    out[line] = list
  end
  return out
end

function Demo:Active() return RL.demo ~= nil end

function Demo:Start()
  if RL.demo then return end
  local G = RL.Guild
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or "Demo"
  local now = math.floor(GetServerTime())
  RL.demo = {
    guild = GUILD,
    db = RL.db, charDB = RL.charDB,
    g = { members = G.members, byName = G.byName, peers = G.peers, info = G.info, online = G.online, total = G.total },
    raid = RL.Raids.current, ready = RL.Raids.ready,
  }
  local pools = recipePools(RL.db, RL.charDB)
  local db = deepcopy(RL.db)
  RL.charDB = deepcopy(RL.charDB)
  RL.db = db

  -- Roster: the demo members plus you.
  local members, byName = {}, {}
  local me
  for _, m in ipairs(RL.demo.g.members) do if G:IsMe(m.name) then me = deepcopy(m) end end
  if me then me.rank, me.rankIndex = "Raider", 2; members[1] = me; byName[me.name] = me end
  local keys = {}
  for i, m in ipairs(MEMBERS) do
    local key = m[1] .. "-" .. realm
    keys[i] = key
    local row = { name = key, short = m[1], classFile = m[2], className = m[3], level = m[4], rank = m[5],
      rankIndex = m[6], online = m[7], zone = m[7] and m[8] or "", guid = "Player-0-DEMO" .. i }
    members[#members + 1] = row
    byName[key] = row
  end
  G.members, G.byName, G.peers = members, byName, {}
  G.info = { name = GUILD, rank = "Raider", rankIndex = 2 }
  G.total, G.online = #members, 0
  for _, r in ipairs(members) do if r.online then G.online = G.online + 1 end end

  -- Synced data, as if every member ran Nemux Ledger.
  for _, k in ipairs({ "guildRecipes", "guildProfs", "guildStats", "guildFeats", "guildCDs", "guildLinks", "orders",
    "loot", "deathFeed", "raids", "raidRecords", "guildKills" }) do db[k] = {} end
  db.chronicle = { list = {}, keys = {} }
  for i, key in ipairs(keys) do
    local list, lines = {}, {}
    for line, rank in pairs(PROFS[i]) do
      list[line] = { rank = rank, max = 300 }
      local pool = pools[line]
      if pool and #pool > 0 then
        local ids, n = {}, 0
        local share = math.max(1, math.floor(#pool * rank / 300))
        for k = 1, share do ids[pool[k]] = true; n = n + 1 end
        lines[line] = { ids = ids, n = n, sum = 0 }
      end
    end
    db.guildProfs[key] = { at = now - i * 3600, list = list }
    db.guildRecipes[key] = { at = now - i * 3600, lines = lines }
    local st = STATS[i]
    db.guildStats[key] = { deaths = st[1], week = st[2], hk = st[3], at = now - 600 }
    G.peers[key] = { version = RL.version, deaths = st[1], profs = list, seen = now - 60 }
    local feats = { ids = {}, at = now - 600 }
    for _, def in ipairs(RL.Feats.DEFS) do
      if (def.id * 7 + i * 3) % 10 < (MEMBERS[i][4] >= 60 and 7 or 3) then feats.ids[def.id] = true end
    end
    db.guildFeats[key] = feats
  end

  -- Profession cooldowns
  db.guildCDs[keys[4]] = { at = now, list = { [18560] = now + 2 * 86400 + 4 * 3600 } }
  db.guildCDs[keys[2]] = { at = now, list = { [18560] = 0 } }
  db.guildCDs[keys[5]] = { at = now, list = { [17187] = 0, [17559] = now + 19 * 3600 } }
  db.guildCDs[keys[11]] = { at = now, list = { [17187] = now + 3 * 86400 } }
  db.guildCDs[keys[6]] = { at = now, list = { i15846 = now + 2 * 3600 + 40 * 60 } }

  -- Crafting requests
  local myName = me and me.name or "you"
  local function pick(line, k) local p = pools[line]; return p and p[math.min(#p, k)] or 18560 end
  local orders = {
    { from = keys[2], to = keys[4], recipe = 18560, qty = 2, mats = true, status = "A", ago = 3 * 3600 },
    { from = myName, to = keys[5], recipe = 17187, qty = 1, mats = true, status = "O", ago = 40 * 60 },
    { from = keys[14], to = "", recipe = pick(333, 3), qty = 1, mats = false, status = "O", ago = 2 * 3600 },
    { from = keys[3], to = keys[8], recipe = pick(202, 5), qty = 1, mats = true, status = "D", ago = 26 * 3600 },
    { from = keys[10], to = myName, recipe = pick(197, 4), qty = 3, mats = true, status = "O", ago = 20 * 60 },
  }
  for i, o in ipairs(orders) do
    local id = "Player-0-DEMO:" .. i
    db.orders[id] = { id = id, recipe = o.recipe, qty = o.qty, mats = o.mats, status = o.status, upd = now - o.ago,
      from = o.from, to = o.to, created = now - o.ago - 600 }
  end

  -- Raids: six weeks of Onyxia
  local ONY = 1084
  local records = { 412, 377, 351, 338, 330, 312 }
  for w = 6, 1, -1 do
    local start = now - (w - 1) * 7 * 86400 - 3 * 86400 - 2 * 3600
    local roster = {}
    for i, key in ipairs(keys) do if MEMBERS[i][4] >= 58 and (i + w) % 5 ~= 0 then roster[key] = true end end
    if me then roster[me.name] = true end
    local wipes = w == 6 and 3 or (w == 5 and 1 or 0)
    table.insert(db.raids, {
      id = "DEMO-RAID-" .. w, instanceID = 249, name = "Onyxia's Lair", start = start, stop = start + 2400 + wipes * 600,
      bosses = { [ONY] = { name = "Onyxia", pulls = wipes + 1, kills = 1, deaths = 2 + wipes * 6, best = records[7 - w] } },
      order = { ONY }, kills = 1, wipes = wipes, deaths = 2 + wipes * 6, roster = roster, size = 20,
    })
  end
  table.sort(db.raids, function(a, b) return a.start > b.start end)
  db.raidRecords[ONY] = { secs = 312, ts = db.raids[1].start, name = "Onyxia" }
  db.guildKills[ONY] = { ts = db.raids[#db.raids].start, name = "Onyxia", instance = "Onyxia's Lair" }

  -- Loot (Onyxia's table)
  local loot = {
    { 18205, keys[7], "Mainspec" }, { 17078, keys[2], "Mainspec" }, { 18813, keys[3], "Minor Upgrade" },
    { 17067, keys[4], "Mainspec" }, { 17064, keys[5], "Offspec" }, { 18423, keys[1], "Mainspec" },
  }
  for i, l in ipairs(loot) do
    db.loot["R:DEMO" .. i] = { key = "R:DEMO" .. i, source = "RCLootCouncil", ts = now - i * 3 * 86400, itemID = l[1],
      to = l[2], roll = l[3], os = l[3] == "Offspec", boss = "Onyxia", instance = "Onyxia's Lair", by = keys[1] }
  end

  -- Guild deaths
  local places = { { "Blackrock Spire", "party" }, { "Onyxia's Lair", "raid", "Onyxia" }, { "Winterspring", "world" },
    { "Stratholme", "party" }, { "Alterac Valley", "pvp" }, { "Scholomance", "party" }, { "Felwood", "world" } }
  for i = 1, 7 do
    local m = ((i * 3) % #keys) + 1
    local pl = places[i]
    table.insert(db.deathFeed, { who = keys[m], ts = now - i * 47 * 60, total = STATS[m][1], where = pl[2], zone = pl[1], boss = pl[3] })
  end

  -- Chronicle
  local ch = RL.Chronicle
  local function ev(kind, ago, who, a, b)
    local e = { kind = kind, ts = now - ago, who = who or "", a = a or "", b = b or "" }
    e.key = kind .. ":" .. e.who .. ":" .. e.a .. ":" .. e.b
    db.chronicle.keys[e.key] = e
    db.chronicle.list[#db.chronicle.list + 1] = e
  end
  ev("craft", 26 * 3600, keys[8], keys[3], tostring(pick(202, 5)))
  ev("feat", 5 * 3600, keys[4], "45")
  ev("max", 2 * 86400, keys[7])
  ev("join", 3 * 86400, keys[14])
  ev("deaths", 4 * 86400, "", "1700")
  ev("feat", 5 * 86400, keys[3], "59")
  ev("kill", 35 * 86400, "", tostring(ONY), "Onyxia")
  table.sort(db.chronicle.list, function(a, b) return a.ts > b.ts end)
  if ch then RL:Fire("RL_CHRONICLE_UPDATED") end

  -- The last ready check
  RL.Raids.current = nil
  local by = {}
  local states = { "o", "o", "o", "s", "m" }
  for i = 1, 9 do
    local s = MEMBERS[i][1]
    by[s] = { food = states[(i % 5) + 1] == "m" and "m" or "o", flask = (i % 3 == 0) and "m" or "o",
      elixir = (i % 2 == 0) and "o" or "u", weapon = states[((i + 2) % 5) + 1], potions = (i % 4 == 0) and "s" or "o" }
  end
  RL.Raids.ready = { at = now - 90, by = by }

  RL:Print("%s %s. Nothing is saved or sent. Type %s again to go back to your real guild.",
    RL.Theme.Color("Demo mode on:", "warn"), GUILD, RL.Theme.Color("/rq demo", "info"))
  self:Changed()
end

function Demo:Stop()
  local d = RL.demo
  if not d then return end
  local G = RL.Guild
  RL.db, RL.charDB = d.db, d.charDB
  G.members, G.byName, G.peers, G.info, G.online, G.total = d.g.members, d.g.byName, d.g.peers, d.g.info, d.g.online, d.g.total
  RL.Raids.current, RL.Raids.ready = d.raid, d.ready
  RL.demo = nil
  RL.Theme.ApplyTheme(RL.db.theme)
  RL:Print("Demo mode off: back to your guild.")
  G:RequestRoster()
  self:Changed()
end

function Demo:Toggle()
  if RL.demo then self:Stop() else self:Start() end
end

function Demo:Changed()
  for _, ev in ipairs({ "RL_GUILD_UPDATED", "RL_BOARDS_UPDATED", "RL_FEATS_UPDATED", "RL_CHRONICLE_UPDATED", "RL_RAIDS_UPDATED",
    "RL_ORDERS_UPDATED", "RL_COOLDOWNS_UPDATED", "RL_LOOT_UPDATED", "RL_RECIPES_UPDATED" }) do
    RL:Fire(ev)
  end
  if RL.UI and RL.UI.Refresh then RL.UI:Refresh() end
end
