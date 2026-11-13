-- SavedVariables: defaults, schema version, migrations, light validation.
--   RequiemLedgerDB      (account-wide): per-character records keyed by player GUID,
--                                        learn-mode log. Shared by all your characters.
--   RequiemLedgerCharDB  (per character): settings and HUD position.

local _, RL = ...
local DB = {}
RL.DB = DB

DB.SCHEMA = 2

local CHAR_DEFAULTS = {
  schema = DB.SCHEMA,
  debug = false,
  hud = {
    style = "text",          -- "text" | "icons" | "off"
    locked = false,
    hideInCombat = true,
    quietInTownSolo = false, -- solo: say nothing in cities and inns
    point = nil,             -- { point, relPoint, x, y }
    scale = 1,
  },
  readiness = {
    warnMinutes = 5,         -- fallback; each check has its own time in "warn"
    warn = {},               -- [checkId] = minutes before the end to remind
    remind = true,           -- reminder in the middle of the screen + chat
    remindSound = true,
    potionMin = 5,
    -- which checks run in which context; filled from Consumables defaults
    track = {},
  },
  deaths = {
    chatPhrase = true,
    guildAlerts = true,      -- "X kissed the floor" when a guild mate with the addon dies
  },
  minimap = { hide = false, angle = 200 },
  guild = { showOffline = false },
  dings = { alerts = true, milestonesOnly = false },
  tracker = { recipes = {}, hidden = false, point = nil },
  lootWeekOnly = false,      -- Loot tab filter -- [recipeID] = crafts wanted -- guild level-up lines in chat
  week = { notify = true },  -- tell me when last week's report is ready
  window = { point = nil },
  recipes = {},              -- [skillLine] = { ids = { [recipeID] = true }, n, sum, name, at }
  feats = {
    earned = {},             -- [featId] = server time
    counts = {},             -- meals, bags
    last = {},               -- last food / sleeping bag expiry seen (server time)
    init = false,            -- first check done (old progress counted silently)
    guildAlerts = true,      -- "X earned Y" in chat
  },
}

local ACCOUNT_DEFAULTS = {
  schema = DB.SCHEMA,
  chars = {},     -- [guid] = { name, class, level, seq, deaths = { total, list } }
  learn = { enabled = false, log = {} },
  guildRecipes = {}, -- [Name-Realm] = { at, lines = { [skillLine] = { ids, n, sum } } }
  guildFeats = {},   -- [Name-Realm] = { at, ids = { [featId] = true } }
  guildStats = {},   -- [Name-Realm] = { deaths, week, hk, at }
  deathFeed = {},    -- newest first: { who | me, ts, total, where, zone, boss }
  reagents = {},
  loot = {},         -- loot log from Gargul / RCLootCouncil: [key] = { ts, itemID, link, to, os, boss, source }
  ignoreItems = {},  -- [itemID] = name: never counted as an elixir or flask (/rq ignore)
  guildGoals = {},   -- [goalId] = server time this client saw it reached
  week = {},         -- weekly report: { start, levels, hk, feats, last }     -- [recipeID] = { { itemID, count }, ... } as the game reported them
}

-- Copies missing keys from defaults into t (deep), without touching existing values.
local function fill(t, defaults)
  for k, v in pairs(defaults) do
    if t[k] == nil then
      if type(v) == "table" then
        t[k] = {}
        fill(t[k], v)
      else
        t[k] = v
      end
    elseif type(v) == "table" and type(t[k]) == "table" then
      fill(t[k], v)
    end
  end
  return t
end
DB.fill = fill

-- migrations[n] upgrades a table from schema n to n + 1.
local accountMigrations = {}
local charMigrations = {
  -- 0.1.2: the HUD hid itself in towns by default and testers thought it was
  -- broken. Turn that off once; people can switch it back on in Settings.
  [1] = function(t)
    if type(t.hud) == "table" then t.hud.quietInTownSolo = false end
  end,
}

local function migrate(t, migrations, label)
  local from = tonumber(t.schema) or DB.SCHEMA
  if from > DB.SCHEMA then
    RL:Print("Saved data is from a newer version (schema %d). Please update the addon.", from)
    return
  end
  while from < DB.SCHEMA do
    local step = migrations[from]
    if step then
      local ok, err = pcall(step, t)
      if not ok then
        RL:Print("Could not upgrade %s data: %s", label, tostring(err))
        return
      end
    end
    from = from + 1
    t.schema = from
  end
end

function DB:Load()
  if type(RequiemLedgerDB) ~= "table" then RequiemLedgerDB = {} end
  if type(RequiemLedgerCharDB) ~= "table" then RequiemLedgerCharDB = {} end

  migrate(RequiemLedgerDB, accountMigrations, "account")
  migrate(RequiemLedgerCharDB, charMigrations, "character")

  RL.db = fill(RequiemLedgerDB, ACCOUNT_DEFAULTS)
  RL.charDB = fill(RequiemLedgerCharDB, CHAR_DEFAULTS)
end

-- The record for the logged-in character (needs PLAYER_LOGIN for the GUID).
function DB:Me()
  local guid = UnitGUID("player")
  if not guid then return nil end
  local rec = RL.db.chars[guid]
  if type(rec) ~= "table" then
    rec = {}
    RL.db.chars[guid] = rec
  end
  fill(rec, { seq = 0, deaths = { total = 0, list = {} } })
  rec.name = UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player")
  local _, class = UnitClass("player")
  rec.class = class
  rec.level = UnitLevel("player")
  return rec, guid
end

-- Unique, never reused id for an event authored by this character.
-- Format "<guid>:<seq>" — sync in later versions deduplicates on it.
function DB:NextEventId()
  local rec, guid = self:Me()
  if not rec then return nil end
  rec.seq = (tonumber(rec.seq) or 0) + 1
  return guid .. ":" .. rec.seq
end
