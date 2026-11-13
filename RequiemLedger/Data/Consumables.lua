-- Consumable data for the readiness checks.
--
-- IMPORTANT: nothing here is verified in the live WoW: Forever client yet.
--  * Vanilla item IDs are from the original game data.
--  * IDs marked "Forever (beta)" come from third-party beta lists (method.gg).
--  * Flask/elixir/potion buffs are NOT listed by spell ID on purpose: the addon
--    asks the client which spell each item applies (C_Item.GetItemSpell), so it
--    stays correct even if Blizzard changed the auras.
--  * Food buffs cannot be found that way (the item spell is "Food", the buff is
--    "Well Fed"), so food matches by buff name plus IDs learned in game with
--    "/rq learn food".
-- Wrong IDs here only make a check miss something; they never break the addon.

local _, RL = ...

RL.Data = RL.Data or {}

RL.Data.SLEEPING_BAG_ITEM = 211527          -- Cozy Sleeping Bag (warcraft.wiki.gg, confirmed)
-- Buff IDs seen in the live Forever client (tester report, 0.1.0):
--   429959  "Well-Rested"  (Sleeping Bag buff)        confirmed
--   429961  Sleeping Bag item spell                    confirmed
--   1249520 "Well Fed"     (from a food with XP bonus) confirmed
--   1229741 "Camp Benefits"                            seen, meaning unknown yet
RL.Data.SLEEPING_BAG_SPELLS = { 429959 }

-- Food buffs: known spell IDs (any client language) plus English names.
RL.Data.FOOD_BUFF_SPELLS = { [1249520] = true }
RL.Data.FOOD_BUFF_NAMES = { ["Well Fed"] = true }

-- Any consumable in the bags whose item class says "elixir" or "flask" also
-- counts, so Forever's own elixirs work without being listed above.
-- Consumable = class 0. Elixir = subclass 2 (same in Retail and Classic enums);
-- Flask = 3 in the Retail enum (warcraft.wiki.gg), not verified in Forever yet.
RL.Data.CONSUMABLE_CLASS = 0
RL.Data.SUBCLASS_TO_CHECK = { [2] = "elixir", [3] = "flask" }

-- Utility / novelty "elixirs" that are not raid or leveling buffs. Never counted.
-- IDs confirmed on wowhead.com/classic. Players can add more with /rq ignore.
RL.Data.IGNORED_CONSUMABLES = {
  [8529]  = true, -- Noggenfogger Elixir
  [5996]  = true, -- Elixir of Water Breathing
  [18294] = true, -- Elixir of Greater Water Breathing
  [8827]  = true, -- Elixir of Water Walking
  [3828]  = true, -- Elixir of Detect Lesser Invisibility
  [9154]  = true, -- Elixir of Detect Undead
  [9233]  = true, -- Elixir of Detect Demon
  [6662]  = true, -- Elixir of Giant Growth
  [10592] = true, -- Catseye Elixir
  [3386]  = true, -- Elixir of Poison Resistance
}

-- Order here is the order shown in the HUD and the Me tab.
RL.Data.CHECKS = {
  {
    id = "food",
    kind = "food",
    name = "Food buff",
    missing = "No food buff",
    expiring = "Food runs out",
    warn = 5,   -- default minutes before the end to remind you
    defaults = { solo = true, party = true, raid = true },
    items = {
      -- Forever (beta)
      250068, -- Savory Turtle Stew
      250071, -- Steaming Stag Steak
      250072, -- Swiftstrike Steak
      250075, -- Prehistoric Pulled Raptor
      249876, -- Wicked Smoothie
      249870, -- Sage's Tea
      249869, -- Sunny Tea
      -- Vanilla
      13931,  -- Nightfin Soup
      13934,  -- Mightfish Steak
      13928,  -- Grilled Squid
      13929,  -- Hot Smoked Bass
      18254,  -- Runn Tum Tuber Surprise
      20452,  -- Smoked Desert Dumplings
      21023,  -- Dirge's Kickin' Chimaerok Chops
      12218,  -- Monster Omelet
      13851,  -- Hot Wolf Ribs
      12216,  -- Spiced Chili Crab
    },
  },
  {
    id = "flask",
    kind = "itemaura",
    name = "Flask",
    missing = "No flask",
    expiring = "Flask runs out",
    warn = 5,
    defaults = { solo = false, party = false, raid = true },
    items = {
      13510, 13511, 13512, 13513, 13506,           -- Titans, Distilled Wisdom, Supreme Power, Chromatic Resistance, Petrification
      274273, 274274, 274275, 274276,              -- Forever (beta): Natural Accuracy / Aggression / Precision / Swiftness
    },
  },
  {
    id = "elixir",
    kind = "itemaura",
    name = "Elixir",
    missing = "No elixir",
    expiring = "Elixir runs out",
    warn = 5,
    defaults = { solo = false, party = true, raid = true },
    items = {
      13452, -- Elixir of the Mongoose
      9206,  -- Elixir of Giants
      9187,  -- Elixir of Greater Agility
      21546, -- Elixir of Greater Firepower
      20007, -- Mageblood Potion
      9179,  -- Elixir of Greater Intellect
      9264,  -- Elixir of Shadow Power
      13454, -- Greater Arcane Elixir
      9155,  -- Arcane Elixir
      13445, -- Elixir of Superior Defense
      8951,  -- Elixir of Greater Defense
      3825,  -- Elixir of Fortitude
      13447, -- Elixir of the Sages
      9088,  -- Gift of Arthas
      250328, 250329, 250341, 250351, -- Forever (beta): Cunning, Phalanx, Greater Mageblood, Grizzly
    },
  },
  {
    id = "weapon",
    kind = "weapon",
    name = "Weapon oil / stone",
    missing = "No weapon oil or stone",
    expiring = "Weapon oil runs out",
    warn = 5,
    defaults = { solo = false, party = false, raid = true },
    items = {
      20749, 20748, 20750, 20747, 23123, -- Brilliant Wizard Oil, Brilliant Mana Oil, Wizard Oil, Lesser Mana Oil, Blessed Wizard Oil
      18262, 12404, 12643, 23122,        -- Elemental Sharpening Stone, Dense Sharpening Stone, Dense Weightstone, Consecrated Sharpening Stone
    },
  },
  {
    id = "potions",
    kind = "count",
    name = "Potions",
    missing = "Low on potions",
    defaults = { solo = false, party = true, raid = true },
    items = {
      13446, 13444, 3928, 13443, 1710, 6149, 929, 3827, 18253, -- healing / mana / rejuvenation
      250943, 250937, 274935,                                  -- Forever (beta): Major Frenzy, Major Spellblasting, Tessa's Tonic
    },
  },
  {
    id = "sleepingbag",
    kind = "sleepingbag",
    name = "Sleeping Bag",
    missing = "Sleeping Bag is ready",
    expiring = "Well-Rested runs out",
    warn = 10,
    defaults = { solo = true, party = false, raid = false },
  },
}
