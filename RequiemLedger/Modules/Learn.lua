-- Learn mode: helps testers collect the real buff IDs of WoW: Forever.
--   /rq buffs         list your current buffs with spell IDs
--   /rq learn food    "the buff I just got is a food buff" (also flask, elixir)
--   /rq learn on|off  log every new buff to chat and SavedVariables
--   /rq learn show    print what was learned
--   /rq learn clear   forget learned IDs and the log

local _, RL = ...
local L = RL:NewModule("Learn")
RL.Learn = L
local Compat = RL.Compat

local recent = {}      -- newest first: { spellId, name, duration, at }
local MAX_RECENT = 10
local MAX_LOG = 100
local CATEGORIES = { food = true, flask = true, elixir = true }

local function addRecent(aura)
  table.insert(recent, 1, { spellId = aura.spellId, name = aura.name, duration = aura.duration or 0, icon = aura.icon, at = GetTime() })
  while #recent > MAX_RECENT do table.remove(recent) end
end

local function onAura(unit, info)
  if unit ~= "player" or type(info) ~= "table" or not info.addedAuras then return end
  for _, aura in ipairs(info.addedAuras) do
    if aura.isHelpful ~= false
      and not Compat.IsSecret(aura.spellId) and not Compat.IsSecret(aura.name) and not Compat.IsSecret(aura.duration) then
      addRecent(aura)
      if RL.db.learn.enabled then
        local log = RL.db.learn.log
        table.insert(log, 1, { ts = GetServerTime(), spellId = aura.spellId, name = aura.name, duration = aura.duration, zone = GetRealZoneText() })
        while #log > MAX_LOG do table.remove(log) end
        RL:Print("New buff: |cffd6d9df%s|r  spell %d  %s", tostring(aura.name), aura.spellId or 0,
          (aura.duration or 0) > 0 and RL.Readiness.FormatTime(aura.duration) or "no duration")
      end
    end
  end
end

function L:Mark(category)
  if not CATEGORIES[category] then
    RL:Print("Use: /rq learn food, /rq learn flask or /rq learn elixir")
    return
  end
  -- The newest buff gained in the last 3 minutes that lasts at least 1 minute.
  local pick
  for _, a in ipairs(recent) do
    if GetTime() - a.at <= 180 and (a.duration or 0) >= 60 then pick = a; break end
  end
  if not pick then
    RL:Print("No new buff in the last 3 minutes. Eat or drink first, wait for the buff, then try again.")
    return
  end
  local known = RL.db.learn.known or {}
  RL.db.learn.known = known
  known[category] = known[category] or {}
  known[category][pick.spellId] = pick.name or true
  RL:Print("Learned: |cffd6d9df%s|r (spell %d) is a %s buff. Thanks!", tostring(pick.name), pick.spellId, category)
  RL.Readiness:Schedule()
end

function L:ListBuffs()
  local buffs = Compat.GetPlayerBuffs()
  if not buffs then
    RL:Print("Buffs are hidden by the game right now (combat or a restricted area).")
    return
  end
  if #buffs == 0 then RL:Print("You have no buffs.") return end
  RL:Print("Your buffs:")
  local now = GetTime()
  for _, b in ipairs(buffs) do
    local left = (b.expirationTime or 0) > 0 and RL.Readiness.FormatTime(b.expirationTime - now) or "-"
    RL:Print("  %s  |cff97a3bbspell %d · %s left|r", tostring(b.name), b.spellId or 0, left)
  end
end

function L:Show()
  local known = RL.db.learn.known or {}
  local any = false
  for cat, ids in pairs(known) do
    for id, name in pairs(ids) do
      any = true
      RL:Print("  %s: %s (spell %d)", cat, tostring(name), id)
    end
  end
  if not any then RL:Print("Nothing learned yet.") end
  RL:Print("Learn log entries: %d", #RL.db.learn.log)
end

function L:Clear()
  RL.db.learn.known = {}
  wipe(RL.db.learn.log)
  RL:Print("Learned buffs and the log are cleared.")
  RL.Readiness:Schedule()
end

function L:SetEnabled(on)
  RL.db.learn.enabled = on and true or false
  RL:Print("Learn mode is %s.", on and "|cff5fbf7aon|r: every new buff is printed and saved" or "|cffd9574aoff|r")
end

RL:On("UNIT_AURA", onAura)
