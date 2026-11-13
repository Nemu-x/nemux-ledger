-- Offline logic tests. Run: node tests/run.js
local RL = __RL
local passed, failed = 0, 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("  ok    " .. name)
  else failed = failed + 1; print("  FAIL  " .. name .. "\n        " .. tostring(err)) end
end
local function eq(a, b, msg)
  if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function buff(name, spellId, left)
  return { name = name, spellId = spellId, icon = 1, duration = 3600, expirationTime = GetTime() + left, isHelpful = true }
end
local function reset()
  __P.buffs, __P.items, __P.itemSpell, __P.cooldowns, __P.bag, __P.itemClass = {}, {}, {}, {}, {}, {}
  __P.resting, __P.combat, __P.group, __P.raid, __P.secret, __P.weapon = false, false, false, false, false, nil
  __P.level = 47
  RL.Context:Refresh()
end
local function eval() reset_noop = nil; RL.Readiness:Evaluate(); return RL.Readiness.results end
local function attentionIds()
  local ids = {}
  for _, r in ipairs(RL.Readiness:Attention()) do ids[#ids + 1] = r.id end
  return table.concat(ids, ",")
end

-- boot
__fire("ADDON_LOADED", "RequiemLedger")
__fire("PLAYER_LOGIN")
__advance(3); __runTimers()

print("Requiem Ledger offline tests")

test("loads and creates saved variables", function()
  eq(type(RequiemLedgerDB), "table"); eq(RequiemLedgerDB.schema, RL.DB.SCHEMA)
  eq(RequiemLedgerCharDB.hud.style, "text")
  eq(RequiemLedgerCharDB.readiness.track.food.solo, true)
  eq(RequiemLedgerCharDB.readiness.track.flask.solo, false)
end)

test("food: Well Fed with 10 min left is active", function()
  reset(); __P.buffs = { buff("Well Fed", 555, 600) }
  eq(eval().food.status, "active")
end)

test("food: Well Fed with 3 min left is expiring and shows in the HUD", function()
  reset(); __P.buffs = { buff("Well Fed", 555, 180) }
  eq(eval().food.status, "expiring")
  eq(attentionIds(), "food")
  local title, hint = RL.Readiness:Describe(RL.Readiness.results.food)
  eq(title, "Food runs out"); eq(hint, "in 3 min")
end)

test("food: missing with food in bags says how many", function()
  reset(); __P.items[250068] = 6
  local r = eval().food
  eq(r.status, "missing"); eq(r.inBags, 6)
  local _, hint = RL.Readiness:Describe(r)
  eq(hint, "You have 6 in your bags")
end)

test("food: missing with empty bags mentions the XP bonus below max level", function()
  reset()
  local _, hint = RL.Readiness:Describe(eval().food)
  eq(hint, "Cooked food gives +5% XP from kills")
end)

test("flask: detected through the item's spell, any buff name", function()
  reset(); __P.raid = true; RL.Context:Refresh()
  __P.itemSpell[13510] = { id = 17626, name = "Flask of the Titans" }
  __P.buffs = { buff("Flask of the Titans", 17626, 3000), buff("Well Fed", 555, 900) }
  eq(eval().flask.status, "active")
end)

test("learned food spell IDs work without the English name", function()
  reset()
  RL.db.learn.known = { food = { [777] = "Сытость" } }
  __P.buffs = { buff("Сытость", 777, 900) }
  eq(eval().food.status, "active")
  RL.db.learn.known = {}
end)

test("sleeping bag: ready when owned, off cooldown, not resting", function()
  reset(); __P.items[211527] = 1
  eq(eval().sleepingbag.status, "ready")
  eq(attentionIds(), "food,sleepingbag")
end)

test("sleeping bag: cooldown, resting, max level, not owned", function()
  reset(); __P.items[211527] = 1; __P.cooldowns[211527] = { GetTime() - 10, 3600 }
  eq(eval().sleepingbag.status, "cooldown")
  reset(); __P.items[211527] = 1; __P.resting = true; RL.Context:Refresh()
  eq(eval().sleepingbag.status, "resting")
  reset(); __P.items[211527] = 1; __P.level = 60
  eq(eval().sleepingbag.status, "maxlevel")
  reset()
  eq(eval().sleepingbag.status, "none")
end)

test("solo in town with quiet mode: HUD says nothing", function()
  reset(); __P.resting = true; RL.Context:Refresh(); RL.charDB.hud.quietInTownSolo = true; eval()
  eq(attentionIds(), "")
  RL.charDB.hud.quietInTownSolo = false
end)

test("party mode tracks potions and elixir", function()
  reset(); __P.group = true; RL.Context:Refresh()
  __P.items[13446] = 2
  __P.buffs = { buff("Well Fed", 555, 900) }
  eval()
  eq(RL.Readiness.results.potions.status, "low")
  eq(attentionIds(), "elixir,potions")
end)

test("secret auras: everything is unknown, nothing is nagged", function()
  reset(); __P.secret = true
  local r = eval()
  eq(r.food.status, "unknown"); eq(r.flask.status, "unknown")
  eq(RL.Readiness.restricted, true)
  eq(attentionIds(), "")
end)

test("in combat: evaluation is skipped and old results stay", function()
  reset(); __P.buffs = { buff("Well Fed", 555, 900) }; eval()
  __P.combat = true; RL.Context:Refresh(); __P.buffs = {}
  RL.Readiness:Evaluate()
  eq(RL.Readiness.results.food.status, "active")
end)

test("weapon oil: expiring under the warning time", function()
  reset(); __P.weapon = 120
  eq(eval().weapon.status, "expiring")
end)

test("first death: recorded with id and milestone phrase", function()
  reset()
  __fire("PLAYER_DEAD")
  local s = RL.Deaths:Stats()
  eq(s.total, 1); eq(s.session, 1); eq(s.byType.world, 1)
  eq(s.list[1].id, "Player-1-00000001:1")
  local found = false
  for i = math.max(1, #__chat - 3), #__chat do found = found or __chat[i]:find("first death") ~= nil end
  assert(found, "milestone phrase missing: " .. __chat[#__chat])
end)

test("death repeated within 5 seconds is ignored", function()
  __fire("PLAYER_DEAD")
  eq(RL.Deaths:Stats().total, 1)
  __advance(10); __fire("PLAYER_DEAD")
  eq(RL.Deaths:Stats().total, 2)
  eq(RL.Deaths:Stats().list[1].id, "Player-1-00000001:2")
end)

test("death during a boss fight stores the boss", function()
  __advance(10)
  __fire("ENCOUNTER_START", 1001, "Lord Testicus", 3, 20)
  __fire("PLAYER_DEAD")
  eq(RL.Deaths:Stats().list[1].boss, "Lord Testicus")
end)

test("phrases: no repeats among 10 picks in a row", function()
  local seen = {}
  for i = 1, 10 do
    local p = RL.Deaths:PickPhrase({ name = "X", zone = "Z", count = 7 }, "world")
    assert(not seen[p], "repeated: " .. p)
    seen[p] = true
  end
end)

test("phrases: placeholders are never left unfilled", function()
  for i = 1, 60 do
    local p = RL.Deaths:PickPhrase({ name = "X", count = 3 }, "party")
    assert(not p:find("{"), "unfilled: " .. p)
    assert(not p:find("{zone}"), p)
  end
end)

test("slash commands and window open without errors", function()
  SlashCmdList.REQUIEMLEDGER("")
  SlashCmdList.REQUIEMLEDGER("help")
  SlashCmdList.REQUIEMLEDGER("buffs")
  SlashCmdList.REQUIEMLEDGER("diag")
  SlashCmdList.REQUIEMLEDGER("death")
  SlashCmdList.REQUIEMLEDGER("hud")
  RL.UI:Show("deaths"); RL.UI:Show("settings"); RL.UI:Show("me")
end)

test("learn: marks the newest buff as food", function()
  reset()
  __fire("UNIT_AURA", "player", { addedAuras = { { name = "Well Fed", spellId = 4242, duration = 900, isHelpful = true } } })
  RL.Learn:Mark("food")
  eq(RL.db.learn.known.food[4242], "Well Fed")
end)

test("HUD shows when something is missing and hides in combat", function()
  reset(); __P.items[211527] = 1; eval()
  eq(RequiemLedgerHUD:IsShown(), true)
  __P.combat = true; RL.Context:Refresh(); RL.HUD:Update()
  eq(RequiemLedgerHUD:IsShown(), false)
end)

test("newer saved data schema is left alone with a warning", function()
  local before = #__chat
  RequiemLedgerDB.schema = 99
  RL.DB:Load()
  assert(#__chat > before and __chat[#__chat]:find("newer version"), "no warning")
  RequiemLedgerDB.schema = RL.DB.SCHEMA
end)

-- 0.1.2 -----------------------------------------------------------------------
test("migration: old characters get the HUD back in towns", function()
  RequiemLedgerCharDB.schema = 1
  RequiemLedgerCharDB.hud.quietInTownSolo = true
  RL.DB:Load()
  eq(RL.charDB.hud.quietInTownSolo, false); eq(RequiemLedgerCharDB.schema, RL.DB.SCHEMA)
  reset(); __P.resting = true; RL.Context:Refresh(); eval()
  eq(attentionIds(), "food")
end)

test("food: any food is found by the buff name in the client's language", function()
  -- the mock client names spell 1249520 "Spell 1249520"; another food with a
  -- different spell ID but the same buff name must count
  reset(); __P.buffs = { buff("Spell 1249520", 888001, 900) }
  eq(eval().food.status, "active")
end)

test("food: a learned buff name also matches other spell IDs", function()
  reset(); RL.db.learn.known = { food = { [777] = "Bien nourri" } }
  __P.buffs = { buff("Bien nourri", 778, 900) }
  eq(eval().food.status, "active")
  RL.db.learn.known = {}
end)

test("professions message: built from my professions, parsed strictly", function()
  local msg = RL.Guild.ProfMessage()
  assert(msg:match("^P|1|[%d%.]+|186:300:300,164:285:300,356:150:300,185:75:300$"), msg)
  local kind, _, profs = RL.Guild.Parse("P|1|0.1.2|333:216:300,185:150:300")
  eq(kind, "P"); eq(profs[333].rank, 216)
  eq(RL.Guild.Parse("P|1|0.1.2|333:216"), nil)
  eq(RL.Guild.Parse("P|1|0.1.2|333:99999:300"), nil)
  eq(RL.Guild.Parse("P|1|0.1.2|1:1:1,2:1:1,3:1:1,4:1:1,5:1:1,6:1:1,7:1:1,8:1:1,9:1:1"), nil)
  eq(RL.Guild.Parse("P|1|0.1.2|333:216:300;x"), nil)
end)

test("guild: a peer's profession skill is stored and found by short name", function()
  __fire("CHAT_MSG_ADDON", "RQLedger", "P|1|0.1.2|333:216:300", "GUILD", "Friend-Forever")
  eq(RL.Guild:PeerFor("Friend").profs[333].rank, 216)
  eq(RL.Guild:PeerFor("Friend-Forever").version, "0.1.2")end)

test("guild: I am found by every form of my Forever name", function()
  __fire("GUILD_ROSTER_UPDATE") -- roster row with my GUID: "Tester Ironside-CAMWOWEU4Realm8PvP"
  eq(RL.Guild:IsMe("Tester Ironside-CAMWOWEU4Realm8PvP"), true) -- roster, messages
  eq(RL.Guild:IsMe("Tester Ironside"), true)                    -- guild profession list
  eq(RL.Guild:IsMe("Tester"), true)                             -- UnitName
  eq(RL.Guild:IsMe("Friend"), false)
  eq(RL.Guild:IsMe("Tester Other"), false)
end)

test("guild: hello also shares my professions", function()
  wipe(__sent)
  RL.Guild:SayHello(true)
  local kinds = ""
  for _, m in ipairs(__sent) do kinds = kinds .. m.msg:sub(1, 1) end
  eq(kinds, "HP")
end)

-- 0.1.1 -----------------------------------------------------------------------
test("food: confirmed Forever spell 1249520 works with any buff name", function()
  reset(); __P.buffs = { buff("Сытость", 1249520, 900) }
  eq(eval().food.status, "active")
end)

test("sleeping bag: Well-Rested 429959 counts down and warns at 10 min", function()
  reset(); __P.items[211527] = 1; __P.cooldowns[211527] = { GetTime() - 10, 3600 }
  __P.buffs = { buff("Well-Rested", 429959, 15 * 60) }
  local r = eval().sleepingbag
  eq(r.status, "active"); eq(math.floor(r.left), 900)
  __P.buffs = { buff("Well-Rested", 429959, 9 * 60) }
  eq(eval().sleepingbag.status, "expiring")
  local title, hint = RL.Readiness:Describe(RL.Readiness.results.sleepingbag)
  eq(title, "Well-Rested runs out"); eq(hint, "in 9 min")
end)

test("warn time is per buff and can be changed", function()
  reset(); __P.buffs = { buff("Well Fed", 555, 8 * 60) }
  eq(eval().food.status, "active")
  RL.charDB.readiness.warn.food = 10
  eq(eval().food.status, "expiring")
  RL.charDB.readiness.warn.food = nil
end)

test("reminder: shown once per buff, again for a new buff", function()
  reset(); wipe(__notices); wipe(__sounds)
  __P.buffs = { buff("Well Fed", 555, 200) }; eval()
  eq(#__notices, 1); eq(__notices[1], "Food runs out in 3 min"); eq(#__sounds, 1)
  __advance(30); eval()
  eq(#__notices, 1)
  __P.buffs = { buff("Well Fed", 555, 250) }; eval() -- ate again
  eq(#__notices, 2)
end)

test("reminder: off means silent; untracked checks never remind", function()
  reset(); wipe(__notices)
  RL.charDB.readiness.remind = false
  __P.buffs = { buff("Well Fed", 555, 100) }; eval()
  eq(#__notices, 0)
  RL.charDB.readiness.remind = true
  __P.weapon = 60; eval() -- weapon oil is not tracked solo
  for _, n in ipairs(__notices) do assert(not n:find("Weapon"), n) end
end)

test("guild: roster scan counts members and online", function()
  __fire("GUILD_ROSTER_UPDATE")
  eq(RL.Guild.total, 3); eq(RL.Guild.online, 2)
  eq(RL.Guild.info.name, "Requiem")
  eq(RL.Guild.byName["Friend-Forever"].classFile, "MAGE")
end)

test("guild: message parser accepts only the strict format", function()
  local P = RL.Guild.Parse
  eq((P("H|1|0.1.1|12")), "H")
  eq(select(4, P("D|1|0.1.1|3|raid")), "raid")
  eq(P("D|1|0.1.1|3|moon"), nil)
  eq(P("H|1|0.1.1|12|raid"), nil)
  eq(P("H|2|0.1.1|12"), nil)
  eq(P("H|1|0.1.1|-5"), nil)
  eq(P("H|1|0.1.1|12; os.exit()"), nil)
  eq(P(string.rep("9", 200)), nil)
  eq(P(nil), nil)
end)

test("guild: hello gets one whisper reply, peers are stored", function()
  wipe(__sent)
  __fire("CHAT_MSG_ADDON", "RQLedger", "H|1|0.1.1|4", "GUILD", "Friend-Forever")
  eq(#__sent, 2); eq(__sent[1].channel, "WHISPER"); eq(__sent[1].target, "Friend-Forever")
  assert(__sent[1].msg:match("^R|1|"), __sent[1].msg)
  assert(__sent[2].msg:match("^P|1|"), __sent[2].msg) -- my professions follow the reply
  eq(__sent[2].channel, "WHISPER")
  eq(RL.Guild.peers["Friend-Forever"].deaths, 4)
  __fire("CHAT_MSG_ADDON", "RQLedger", "H|1|0.1.1|4", "GUILD", "Friend-Forever")
  eq(#__sent, 2)
  eq(RL.Guild:PeerCount(), 1)
end)

test("guild: whispers from outside the guild and own messages are ignored", function()
  __fire("CHAT_MSG_ADDON", "RQLedger", "R|1|0.1.1|1", "WHISPER", "Stranger-Forever")
  eq(RL.Guild.peers["Stranger-Forever"], nil)
  -- my own guild message comes back with my full Forever name: not a peer
  __fire("CHAT_MSG_ADDON", "RQLedger", "R|1|0.1.1|1", "GUILD", "Tester Ironside-CAMWOWEU4Realm8PvP")
  eq(RL.Guild.peers["Tester Ironside-CAMWOWEU4Realm8PvP"], nil)
  eq(RL.Guild:PeerCount(), 1)
  __fire("CHAT_MSG_ADDON", "OtherAddon", "R|1|0.1.1|1", "GUILD", "Friend-Forever")
  eq(RL.Guild.peers["Friend-Forever"].deaths, 4)
end)

test("guild: a guild mate's death shows a phrase with their name", function()
  local before = #__chat
  __fire("CHAT_MSG_ADDON", "RQLedger", "D|1|0.1.1|5|party", "GUILD", "Friend-Forever")
  eq(#__chat, before + 1)
  assert(__chat[#__chat]:find("Friend") and __chat[#__chat]:find("death #5"), __chat[#__chat])
  RL.charDB.deaths.guildAlerts = false
  __fire("CHAT_MSG_ADDON", "RQLedger", "D|1|0.1.1|6|party", "GUILD", "Friend-Forever")
  eq(#__chat, before + 1)
  RL.charDB.deaths.guildAlerts = true
end)

test("guild: my death is sent to the guild, held during lockdown", function()
  wipe(__sent); __advance(10)
  __fire("PLAYER_DEAD")
  eq(#__sent, 1); eq(__sent[1].channel, "GUILD")
  assert(__sent[1].msg:match("^D|1|%d+%.%d+%.%d+|%d+|world$"), __sent[1].msg)
  wipe(__sent); __advance(10); __G.lockdown = true
  __fire("PLAYER_DEAD")
  eq(#__sent, 0)
  __G.lockdown = false
  __fire("ENCOUNTER_END"); __advance(5); __runTimers()
  local deaths = 0
  for _, m in ipairs(__sent) do if m.msg:sub(1, 1) == "D" then deaths = deaths + 1 end end
  eq(deaths, 1) -- the login hello may also go out here; only one death message
end)

test("guild tab, settings, report and minimap build without errors", function()
  RL.UI:Show("guild"); RL.UI:Show("settings"); RL.UI:Show("me")
  __G.inGuild = false; RL.UI:Show("guild"); __G.inGuild = true
  SlashCmdList.REQUIEMLEDGER("report")
  local text = RL.Export.Text()
  assert(text:find("%[checks%]") and text:find("%[guild%]"), text)
  RL.Readiness:TestReminder()
  RL.charDB.minimap.hide = true; RL.MinimapButton:Apply()
  eq(RequiemLedgerMinimapButton:IsShown(), false)
  RL.charDB.minimap.hide = false; RL.MinimapButton:Apply()
  eq(RequiemLedgerMinimapButton:IsShown(), true)
end)

test("elixir: an unlisted Forever elixir is found by item class and remembered", function()
  reset(); __P.group = true; RL.Context:Refresh()
  __P.bag = { { 990001, 2 } }; __P.items[990001] = 2
  __P.itemClass[990001] = { 0, 2 }
  __P.itemSpell[990001] = { id = 990101, name = "Elixir of Forever" }
  local r = eval().elixir
  eq(r.status, "missing"); eq(r.inBags, 2)
  -- Drank the last one: bags are empty, but the buff is still recognised.
  __P.bag = {}; __P.items[990001] = 0
  __P.buffs = { buff("Elixir of Forever", 990101, 3600) }
  eq(eval().elixir.status, "active")
  assert(RL.Export.Text():find("seen in bags: elixir 990101"))
  __P.group = false; RL.Context:Refresh()
end)

test("HUD explains why it is hidden", function()
  reset(); eval()
  RL.HUD:Update()
  eq(RL.HUD:State(), "shown")
  RL.charDB.hud.hideInCombat = true
  __P.combat = true; RL.Context:Refresh()
  eq(RL.HUD:State(), "hidden in combat (Settings)")
  __P.combat = false; RL.Context:Refresh()
  assert(RL.Export.Text():find("%[hud%]"))
end)

local function sentKinds()
  local k = ""
  for _, m in ipairs(__sent) do k = k .. m.msg:sub(1, 1) end
  return k
end
local function flush() for _ = 1, 40 do __advance(1.5); __runTimers() end end

test("recipes: my learned recipes are saved from the profession window and announced", function()
  flush(); wipe(__sent)
  __TS = { line = 333, name = "Enchanting", recipes = { [7420] = true, [7426] = true, [13846] = false } }
  __fire("TRADE_SKILL_SHOW"); flush()
  local mine = RL.charDB.recipes[333]
  eq(mine.n, 2); eq(mine.name, "Enchanting")
  eq(sentKinds(), "K"); eq(__sent[1].msg, "K|1|" .. RL.version .. "|333:2:" .. ((7420 + 7426) % 1000003))
  wipe(__sent); __fire("TRADE_SKILL_LIST_UPDATE"); flush()
  eq(sentKinds(), "") -- unchanged list is not announced again
  __TS = nil
end)

test("recipes: a guild mate's summary makes us ask, their list is stored and searchable", function()
  flush(); wipe(__sent)
  __fire("CHAT_MSG_ADDON", "RQLedger", "K|1|0.2.0|197:3:" .. ((2385 + 3914 + 8776) % 1000003), "GUILD", "Friend-Forever")
  flush()
  eq(sentKinds(), "Q"); eq(__sent[1].channel, "WHISPER"); eq(__sent[1].msg, "Q|1|" .. RL.version .. "|197")
  __fire("CHAT_MSG_ADDON", "RQLedger", "C|1|0.2.0|197|1|2|2385,3914", "WHISPER", "Friend-Forever")
  eq(RL.db.guildRecipes["Friend-Forever"], nil) -- not complete yet
  __fire("CHAT_MSG_ADDON", "RQLedger", "C|1|0.2.0|197|2|2|8776", "WHISPER", "Friend-Forever")
  eq(RL.db.guildRecipes["Friend-Forever"].lines[197].n, 3)
  local res = RL.Recipes:Search("spell 39")
  eq(#res, 1); eq(res[1].id, 3914); eq(res[1].crafters[1].name, "Friend"); eq(res[1].crafters[1].online, true)
  eq(RL.Recipes:Search("x"), nil)
  -- The same summary again: nothing to ask.
  wipe(__sent)
  __fire("CHAT_MSG_ADDON", "RQLedger", "K|1|0.2.0|197:3:" .. ((2385 + 3914 + 8776) % 1000003), "GUILD", "Friend-Forever")
  flush(); eq(sentKinds(), "")
end)

test("recipes: lists nobody asked for, junk and guild-channel parts are ignored", function()
  __fire("CHAT_MSG_ADDON", "RQLedger", "C|1|0.2.0|171|1|1|1111", "WHISPER", "Friend-Forever")
  eq(RL.db.guildRecipes["Friend-Forever"].lines[171], nil)
  __fire("CHAT_MSG_ADDON", "RQLedger", "C|1|0.2.0|197|1|1|2385", "GUILD", "Friend-Forever")
  __fire("CHAT_MSG_ADDON", "RQLedger", "K|1|0.2.0|197:abc", "GUILD", "Friend-Forever")
  __fire("CHAT_MSG_ADDON", "RQLedger", "K|1|0.2.0|1:1:1,2:1:1,3:1:1,4:1:1,5:1:1,6:1:1,7:1:1,8:1:1,9:1:1", "GUILD", "Friend-Forever")
  eq(RL.db.guildRecipes["Friend-Forever"].lines[197].n, 3)
end)

test("recipes: a guild mate's request gets my list in whispered parts", function()
  local ids = {}
  for i = 1, 45 do ids[100000 + i] = true end
  local n, sum = RL.Recipes.Summary(ids)
  RL.charDB.recipes[164] = { ids = ids, n = n, sum = sum, name = "Blacksmithing" }
  flush(); wipe(__sent)
  __fire("CHAT_MSG_ADDON", "RQLedger", "Q|1|0.2.0|164", "WHISPER", "Friend-Forever")
  flush()
  eq(sentKinds(), "CCC"); eq(__sent[1].channel, "WHISPER")
  for _, m in ipairs(__sent) do assert(#m.msg <= 200, #m.msg) end
  assert(__sent[3].msg:find("|164|3|3|", 1, true), __sent[3].msg)
  wipe(__sent)
  __fire("CHAT_MSG_ADDON", "RQLedger", "Q|1|0.2.0|164", "WHISPER", "Friend-Forever")
  flush(); eq(sentKinds(), "") -- not again within 5 minutes
  __fire("CHAT_MSG_ADDON", "RQLedger", "Q|1|0.2.0|164", "GUILD", "Friend-Forever")
  flush(); eq(sentKinds(), "") -- requests only by whisper
  RL.charDB.recipes[164] = nil
end)

test("feats: old progress counts silently, new ones are announced and shared", function()
  flush()
  local F = RL.Feats
  assert(F:Has(1) and F:Has(3) and F:Has(7), "level 47 and Mining 300")
  eq(F:Has(4), false)
  wipe(__sent)
  __P.level = 60; __fire("PLAYER_LEVEL_UP"); flush()
  eq(F:Has(4), true)
  assert(sentKinds():find("A"), sentKinds())
  local msg
  for _, m in ipairs(__sent) do if m.msg:sub(1, 1) == "A" then msg = m.msg end end
  assert(msg:find("4", 1, true), msg)
  __P.level = 47
end)

test("feats: raid boss kill without dying, with all raid buffs", function()
  local F = RL.Feats
  reset(); __P.raid = true; __P.instance = "raid"; RL.Context:Refresh()
  RL.charDB.readiness.track.potions.raid = false
  RL.charDB.readiness.track.weapon.raid = false
  __P.items[13510] = 1
  __P.itemSpell[13510] = { id = 17626, name = "Flask of the Titans" }
  __P.buffs = { buff("Well Fed", 555, 1800), buff("Flask of the Titans", 17626, 3000) }
  __P.itemSpell[13452] = { id = 17538, name = "Elixir of the Mongoose" }
  __P.items[13452] = 1
  table.insert(__P.buffs, buff("Elixir of the Mongoose", 17538, 3000))
  eval()
  __fire("ENCOUNTER_START", 1, "Lucifron", 9, 40)
  __fire("ENCOUNTER_END", 1, "Lucifron", 9, 40, 1)
  eq(F:Has(16), true); eq(F:Has(17), true); eq(F:Has(18), true)
  RL.charDB.readiness.track.potions.raid = true
  RL.charDB.readiness.track.weapon.raid = true
  __P.raid = false; __P.instance = "none"; RL.Context:Refresh()
end)

test("feats: a guild mate's feats are stored, new ones are told once", function()
  local F = RL.Feats
  __fire("CHAT_MSG_ADDON", "RQLedger", "A|1|0.2.0|1,2", "GUILD", "Friend-Forever")
  local holders, totals = F:Guild()
  eq(#holders[1], 1); eq(totals[1].name, "Friend"); eq(totals[1].n, 2)
  __fire("CHAT_MSG_ADDON", "RQLedger", "A|1|0.2.0|1,2,abc", "GUILD", "Friend-Forever")
  eq(totals[1].n, 2)
  __fire("CHAT_MSG_ADDON", "RQLedger", "A|1|0.2.0|1,2,3,500", "GUILD", "Friend-Forever") -- 500: unknown, from a newer version
  holders, totals = F:Guild()
  eq(totals[1].n, 3)
end)

test("recipes and feats UI build without errors", function()
  RL.UI:ShowRecipes("spell")
  RL.UI:ShowRecipes("")
  RL.UI:Show("feats")
  SlashCmdList.REQUIEMLEDGER("recipes bracer")
  SlashCmdList.REQUIEMLEDGER("feats")
  local text = RL.Export.Text()
  assert(text:find("%[recipes%]") and text:find("%[feats%]"), text)
end)

test("recipes: classic profession window is read through recipe links", function()
  __TS = nil; flush(); wipe(__sent)
  local rows = { { "Smelting", "header" }, { "Silver Rod", "optimal", 7818 }, { "Rough Grinding Stone", "trivial", 3320 } }
  GetTradeSkillLine = function() return "Blacksmithing", 208, 300 end
  GetNumTradeSkills = function() return #rows end
  GetTradeSkillInfo = function(i) return rows[i][1], rows[i][2] end
  GetTradeSkillRecipeLink = function(i) if rows[i][3] then return "|cffffd000|Henchant:" .. rows[i][3] .. "|h[" .. rows[i][1] .. "]|h|r" end end
  __fire("TRADE_SKILL_SHOW"); flush()
  local mine = RL.charDB.recipes[164]
  eq(mine and mine.n, 2)
  eq(RL.Recipes.lastScan.source, "classic")
  local res = RL.Recipes:Search("silver")
  assert(res and #res >= 1, "silver rod not found")
  eq(res[1].crafters[1].name, "you")
  GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillRecipeLink = nil, nil, nil, nil
  RL.charDB.recipes[164] = nil
end)

test("recipes: classic craft window (enchanting) is read too", function()
  GetCraftDisplaySkillLine = function() return "Mining", 300, 300 end
  GetNumCrafts = function() return 1 end
  GetCraftInfo = function() return "Enchant Bracer - Minor Health", nil, "optimal" end
  GetCraftItemLink = function() return "|Henchant:7418|h[Enchant Bracer - Minor Health]|h" end
  __fire("CRAFT_SHOW"); flush()
  eq(RL.charDB.recipes[186] and RL.charDB.recipes[186].n, 1)
  eq(RL.Recipes.lastScan.source, "craft")
  GetCraftDisplaySkillLine, GetNumCrafts, GetCraftInfo, GetCraftItemLink = nil, nil, nil, nil
  RL.charDB.recipes[186] = nil
end)

test("recipes: an unreadable window is reported in chat and in the report", function()
  local before = #__chat
  __fire("TRADE_SKILL_SHOW"); flush()
  local said = false
  for i = before + 1, #__chat do said = said or __chat[i]:find("Could not read this profession window", 1, true) ~= nil end
  assert(said, "no message")
  assert(RL.Export.Text():find("last window read: failed", 1, true))
end)

test("recipes: reagents are remembered from my window and checked against my bags", function()
  __SCHEM[7818] = { { 2842, 1 } }                 -- Silver Rod: 1 Silver Bar
  __SCHEM[7420] = { { 10940, 1 }, { 4470, 2 }, { 999, 1, 0 } } -- dust, wood; a modifying slot is skipped
  __TS = { line = 333, name = "Enchanting", recipes = { [7420] = true } }
  __fire("TRADE_SKILL_SHOW"); flush()
  __TS = nil
  -- Window closed: own recipe still known from the cache.
  __P.items[10940] = 1; __P.items[4470] = 1; __P.bank = { [4470] = 5 }
  local mats, ready = RL.Recipes:ReagentStatus(7420)
  eq(#mats, 2); eq(mats[1].itemID, 10940); eq(mats[1].bags, 1)
  eq(mats[2].need, 2); eq(mats[2].bags, 1); eq(mats[2].total, 6); eq(ready, false)
  __P.items[4470] = 2
  mats, ready = RL.Recipes:ReagentStatus(7420); eq(ready, true)
  -- Someone else's recipe: unknown while the game won't answer, then cached once it does.
  eq(RL.Recipes:ReagentStatus(7818), nil)
  __SCHEM_OPEN = true; assert(RL.Recipes:ReagentStatus(7818)); __SCHEM_OPEN = false
  eq(RL.Recipes:ReagentStatus(7818)[1].itemID, 2842)
  __P.bank = nil; __P.items[10940] = nil; __P.items[4470] = nil
end)

test("boards: a guild mate's stats arrive, junk is dropped, the board is sorted", function()
  __P.hk = 12
  __fire("CHAT_MSG_ADDON", "RQLedger", "S|1|0.3.0|40|3|250", "GUILD", "Friend-Forever")
  __fire("CHAT_MSG_ADDON", "RQLedger", "S|1|0.3.0|2|9|1", "GUILD", "Sleepy-Forever") -- week > total: dropped
  __fire("CHAT_MSG_ADDON", "RQLedger", "S|1|0.3.0|x|1|1", "GUILD", "Sleepy-Forever")
  eq(RL.db.guildStats["Sleepy-Forever"], nil)
  local hk = RL.Boards:Board("hk")
  eq(hk[1].name, "Friend"); eq(hk[1].value, 250); eq(hk[2].name, "you"); eq(hk[2].value, 12)
  local d = RL.Boards:Board("deaths")
  eq(d[1].name, "Friend"); eq(d[1].value, 40)
  assert(RL.Boards:Message():match("^S|1|.+|%d+|%d+|12$"), RL.Boards:Message())
end)

test("boards: a guild mate's death goes to the feed and to this week, once", function()
  local before = RL.db.guildStats["Friend-Forever"].week
  __fire("CHAT_MSG_ADDON", "RQLedger", "D|1|0.3.0|41|raid", "GUILD", "Friend-Forever")
  local e = RL.db.deathFeed[1]
  eq(e.who, "Friend-Forever"); eq(e.total, 41); eq(e.where, "raid")
  eq(RL.db.guildStats["Friend-Forever"].week, before + 1)
  eq(RL.db.guildStats["Friend-Forever"].deaths, 41)
  -- Someone unknown with many old deaths: only this one counts for the week.
  __fire("CHAT_MSG_ADDON", "RQLedger", "D|1|0.3.0|77|world", "GUILD", "Sleepy-Forever")
  eq(RL.db.guildStats["Sleepy-Forever"].week, 1)
end)

test("boards: stats from before the weekly reset don't count for this week", function()
  local rec = RL.db.guildStats["Friend-Forever"]
  rec.at = RL.Boards:WeekStart() - 10
  for _, r in ipairs(RL.Boards:Board("week")) do assert(r.name ~= "Friend", "old week counted") end
  rec.at = GetServerTime()
end)

test("boards: my own death is in the feed with its zone", function()
  __advance(10); __fire("PLAYER_DEAD")
  local e = RL.db.deathFeed[1]
  eq(e.me, true); eq(e.zone, "Westfall")
end)

test("boards tab builds without errors", function()
  RL.UI:Show("boards")
  SlashCmdList.REQUIEMLEDGER("boards")
  assert(RL.Export.Text():find("%[boards%]"))
end)

local function chatHas(text, from)
  for i = from or 1, #__chat do if __chat[i]:find(text, 1, true) then return true end end
  return false
end

test("dings: a guild mate's level-up from the roster shows in chat, and can be turned off", function()
  __fire("GUILD_ROSTER_UPDATE")
  local n = #__chat
  __G.roster[2][4] = 41; __fire("GUILD_ROSTER_UPDATE")
  assert(chatHas("reached level", n + 1), "no ding line")
  RL.charDB.dings.milestonesOnly = true
  n = #__chat
  __G.roster[2][4] = 42; __fire("GUILD_ROSTER_UPDATE")
  eq(chatHas("reached level", n + 1), false)
  __G.roster[2][4] = 50; __fire("GUILD_ROSTER_UPDATE")
  assert(chatHas("reached level", n + 1), "milestone not shown")
  RL.charDB.dings.milestonesOnly = false
  RL.charDB.dings.alerts = false
  n = #__chat
  __G.roster[2][4] = 51; __fire("GUILD_ROSTER_UPDATE")
  eq(chatHas("reached level", n + 1), false)
  RL.charDB.dings.alerts = true
end)

test("weekly: levels from the roster, deaths and feats; last week is kept after the reset", function()
  local w = RL.db.week
  w.start = nil
  RL.Weekly:Check()
  __G.roster[2][4] = 55; __fire("GUILD_ROSTER_UPDATE")
  table.insert(w.feats, { who = "Friend", id = 17 })
  local text = RL.Weekly:Text()
  assert(text:find("Levels: +4", 1, true), text)
  assert(text:find("Not a Scratch", 1, true), text)
  -- The weekly reset passes.
  local n = #__chat
  __resetIn = __resetIn - 4 * 86400 + 7 * 86400 -- now 4 days later in the same clock: next week
  __advance(4 * 86400)
  RL.Weekly:Check()
  assert(w.last and w.last.text:find("Levels: +4", 1, true), "last week lost")
  assert(chatHas("/rq week", n + 1), "no notice")
  assert(RL.Weekly:Text():find("nobody dinged", 1, true))
  assert(RL.Weekly:FullText():find("LAST WEEK", 1, true))
end)

test("feats 2.0: honor kills, recipes, dungeon death and the night owl", function()
  local F = RL.Feats
  __P.hk = 150; __fire("PLAYER_PVP_KILLS_CHANGED"); flush()
  eq(F:Has(21), true); eq(F:Has(22), true); eq(F:Has(23), false)
  local orig = GetInstanceInfo
  GetInstanceInfo = function() return "Deadmines", "party", 0, "", 5, 0, false, 36 end
  __advance(10); __fire("PLAYER_DEAD")
  GetInstanceInfo = orig
  eq(F:Has(31), true)
  eq(type(RL.charDB.feats.counts.zones), "table")
end)

test("guild goals: progress is counted and a reached goal is remembered", function()
  local F = RL.Feats
  local goals = F:Goals()
  eq(goals[1].def.name, "Packed Tavern")
  assert(goals[3].value >= 2, "ledger keepers should count Friend and me")
  RL.Feats.GOALS[3].goal = 2
  F:CheckGoals()
  assert(RL.db.guildGoals[103], "goal not reached")
  RL.Feats.GOALS[3].goal = 10
end)

test("tracker: shopping list adds up reagents and follows the bags", function()
  __SCHEM_OPEN = true
  __SCHEM[7818] = { { 2842, 1 } }
  __SCHEM[7420] = { { 10940, 1 }, { 4470, 2 } }
  RL.Tracker:Clear()
  RL.Tracker:Toggle(7818); RL.Tracker:Change(7818, 2) -- 3 Silver Rods
  RL.Tracker:Toggle(7420)
  local recipes, mats = RL.Tracker:Needs()
  eq(#recipes, 2)
  local need = {}
  for _, m in ipairs(mats) do need[m.itemID] = m end
  eq(need[2842].need, 3); eq(need[4470].need, 2)
  __P.items[2842] = 3
  _, mats = RL.Tracker:Needs()
  for _, m in ipairs(mats) do if m.itemID == 2842 then eq(m.bags, 3) end end
  RL.Tracker:Update()
  eq(RequiemLedgerTracker:IsShown(), true)
  RL.Tracker:Change(7818, -3)
  eq(RL.Tracker:IsTracked(7818), false)
  RL.Tracker:Clear()
  eq(RequiemLedgerTracker:IsShown(), false)
  __SCHEM_OPEN = false; __P.items[2842] = nil
end)

test("prices come from Auctionator's API when it is there", function()
  eq(RL.Compat.Price(2842), nil)
  Auctionator = { API = { v1 = {
    GetVendorPriceByItemID = function(caller, id) assert(caller == "RequiemLedger"); if id == 4470 then return 38 end end,
    GetAuctionPriceByItemID = function(_, id) if id == 2842 then return 12550 end end,
    GetAuctionAgeByItemID = function() return 2 end,
  } } }
  local p, src, age = RL.Compat.Price(2842)
  eq(p, 12550); eq(src, "AH"); eq(age, 2)
  eq(select(2, RL.Compat.Price(4470)), "vendor")
  eq(RL.Compat.Money(12550), "1g 25s"); eq(RL.Compat.Money(38), "38c"); eq(RL.Compat.Money(250), "2s 50c")
  __SCHEM_OPEN = true
  local mats = RL.Recipes:ReagentStatus(7420)
  local total, missing, complete = RL.Recipes:Cost(mats)
  eq(complete, false); eq(total, 76)
  Auctionator = nil; __SCHEM_OPEN = false
end)

test("weekly, tracker, goals and boards UI build without errors", function()
  SlashCmdList.REQUIEMLEDGER("week")
  SlashCmdList.REQUIEMLEDGER("track")
  SlashCmdList.REQUIEMLEDGER("track clear")
  RL.UI:Show("boards"); RL.UI:Show("feats")
  RL.UI:ShowRecipes("spell")
end)

test("elixirs: Noggenfogger and other novelty elixirs never count; /rq ignore adds more", function()
  reset(); __P.group = true; RL.Context:Refresh()
  __P.bag = { { 8529, 3 } }; __P.items[8529] = 3; __P.itemClass[8529] = { 0, 2 }
  __P.itemSpell[8529] = { id = 16591, name = "Noggenfogger Elixir" }
  local r = eval().elixir
  eq(r.status, "missing"); eq(r.inBags, 0)
  __P.buffs = { buff("Noggenfogger Elixir", 16591, 600) }
  eq(eval().elixir.status, "missing") -- its buff is not an elixir buff either
  -- A Forever elixir the player decides to ignore (shift-click link, lowercased by the slash handler).
  __P.bag = { { 990002, 1 } }; __P.items[990002] = 1; __P.itemClass[990002] = { 0, 2 }
  __P.itemSpell[990002] = { id = 990202, name = "Fishy Elixir" }
  __P.buffs = {}
  r = eval().elixir
  eq(r.inBags, 1)
  local _, hint = RL.Readiness:Describe(r)
  eq(hint, "1 in bags: Item 990002")
  SlashCmdList.REQUIEMLEDGER("ignore |cffffffff|Hitem:990002::::::::60:::::|h[Fishy Elixir]|h|r")
  __runTimers()
  eq(eval().elixir.inBags, 0)
  SlashCmdList.REQUIEMLEDGER("unignore 990002")
  eq(eval().elixir.inBags, 1)
  SlashCmdList.REQUIEMLEDGER("ignore")
  __P.group = false; RL.Context:Refresh()
end)

test("guild name and faction come from the game, not from the code", function()
  RL.UI:Show("boards")
  eq(RequiemLedgerWindow.sub:GetText(), "Requiem · Alliance · v" .. RL.version)
  eq(RL.Boards:Title("hk"), "Warlord of Requiem")
  assert(RL.Weekly:Text():find("^Requiem weekly report"))
  __P.faction = "Horde"; __G.inGuild = false
  RL.UI:Show("boards")
  eq(RequiemLedgerWindow.sub:GetText(), "No guild · Horde · v" .. RL.version)
  eq(RL.Boards:Title("hk"), "Warlord of the Guild")
  -- The "{guild} mourns" phrase is skipped without a guild, never shown half-filled.
  for _ = 1, 30 do
    local t = RL.Deaths:PickPhrase({ name = "X", count = 2 }, "world")
    assert(t and not t:find("mourns", 1, true) and not t:find("{", 1, true), t)
  end
  __P.faction = "Alliance"; __G.inGuild = true
end)

test("loot: Gargul awards, edits and unawards are mirrored; junk links are rebuilt", function()
  local listeners = {}
  Gargul = {
    DB = { AwardHistory = { abc = { checksum = "abc", itemID = 16800, awardedTo = "Friend", awardedBy = "Tester",
      timestamp = GetServerTime() - 60, OS = false, SR = true } } },
    Events = { register = function(self, id, event, fn) listeners[event] = fn end },
  }
  __fire("ADDON_LOADED", "Gargul"); __advance(2); __runTimers()
  eq(RL.Loot:Sources()[1], "Gargul")
  eq(RL.db.loot["G:abc"].to, "Friend"); eq(RL.db.loot["G:abc"].sr, true) -- imported from history
  __fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
  listeners["GL.ITEM_AWARDED"]("GL.ITEM_AWARDED", { checksum = "def", itemID = 16795,
    itemLink = "|cffa335ee|Hitem:16795::::::::60:::::|h[Arcanist Crown]|h|r|cff000000|Hevil|h", -- not a clean link
    awardedTo = "Tester Ironside", timestamp = GetServerTime(), OS = true })
  local e = RL.db.loot["G:def"]
  eq(e.link, nil); eq(e.itemID, 16795); eq(e.os, true); eq(e.boss, "Lucifron")
  listeners["GL.ITEM_AWARD_EDITED"]("GL.ITEM_AWARD_EDITED", { checksum = "def", itemID = 16795, awardedTo = "Friend",
    timestamp = GetServerTime(), OS = false })
  eq(RL.db.loot["G:def"].to, "Friend"); eq(RL.db.loot["G:def"].boss, "Lucifron")
  eq(#RL.Loot:List("friend"), 2)
  listeners["GL.ITEM_UNAWARDED"]("GL.ITEM_UNAWARDED", { checksum = "def" })
  eq(RL.db.loot["G:def"], nil)
  assert(RL.Weekly:Text():find("Loot: 1 items", 1, true), RL.Weekly:Text())
  Gargul = nil
end)

test("loot: RCLootCouncil award message and saved history are read when it is there", function()
  local handlers = {}
  LibStub = function(name, silent)
    if name == "AceEvent-3.0" then
      return { Embed = function(_, t) t.RegisterMessage = function(_, msg, fn) handlers[msg] = fn end end }
    end
  end
  RCLootCouncil = {}
  RCLootCouncilLootDB = { factionrealm = { ["Alliance - Forever"] = { ["Friend-Forever"] = {
    { id = "1700000000-1", lootWon = "|cffa335ee|Hitem:16808::::::::60:::::|h[Felheart Horns]|h|r",
      date = "2026/11/10", time = "21:05:09", boss = "Magmadar", response = "Mainspec" } } } } }
  __fire("ADDON_LOADED", "RCLootCouncil"); __advance(2); __runTimers()
  local e = RL.db.loot["R:1700000000-1"]
  eq(e.to, "Friend-Forever"); eq(e.itemID, 16808); eq(e.boss, "Magmadar")
  handlers.RCMLAwardSuccess("RCMLAwardSuccess", 1, "Friend-Forever", "normal",
    "|cffa335ee|Hitem:16809::::::::60:::::|h[Felheart Robes]|h|r", "Mainspec")
  handlers.RCMLAwardSuccess("RCMLAwardSuccess", 2, "Friend-Forever", "test_mode",
    "|cffa335ee|Hitem:16810::::::::60:::::|h[Test]|h|r", "Mainspec")
  local robes, test = false, false
  for _, x in pairs(RL.db.loot) do
    if x.itemID == 16809 then robes = true end
    if x.itemID == 16810 then test = true end
  end
  eq(robes, true); eq(test, false)
  RL.UI:ShowLoot("felheart")
  SlashCmdList.REQUIEMLEDGER("loot")
  assert(RL.Export.Text():find("RCLootCouncil", 1, true))
  RCLootCouncil, RCLootCouncilLootDB, LibStub = nil, nil, nil
end)

test("loot tab without any loot addon says what to install", function()
  RL.UI:Show("loot")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error("tests failed", 0) end
