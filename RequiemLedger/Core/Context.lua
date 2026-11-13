-- Where the player is: solo / party / raid, in combat, resting, active boss fight.
-- Fires "RL_CONTEXT_CHANGED" when any of it changes.

local _, RL = ...
local Context = RL:NewModule("Context")
RL.Context = Context

Context.mode = "solo"
Context.inCombat = false
Context.resting = false
Context.encounter = nil   -- { id, name, difficulty, size, start }

local function computeMode()
  if IsInRaid() then return "raid" end
  if IsInGroup() then return "party" end
  return "solo"
end

function Context:Refresh()
  local mode = computeMode()
  local combat = InCombatLockdown() and true or false
  local resting = IsResting() and true or false
  local changed = mode ~= self.mode or combat ~= self.inCombat or resting ~= self.resting
  self.mode, self.inCombat, self.resting = mode, combat, resting
  if changed then RL:Fire("RL_CONTEXT_CHANGED") end
end

-- Instance type for death records: "world", "party", "raid", "pvp", "arena", "scenario"
function Context:Instance()
  local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
  if instanceType == nil or instanceType == "none" then instanceType = "world" end
  return instanceType, name, instanceID
end

-- The player's guild name (nil when not in a guild or not loaded yet).
function Context:GuildName()
  if not IsInGuild() then return nil end
  local name = GetGuildInfo("player")
  if type(name) == "string" and name ~= "" and not RL.Compat.IsSecret(name) then return name end
  return RL.Guild and RL.Guild.info and RL.Guild.info.name or nil
end

-- "Alliance" / "Horde" (English key) and the name in the client's language.
function Context:Faction()
  local en, localized = UnitFactionGroup("player")
  return en, localized or en
end

function Context:IsMaxLevel()
  local max = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
  return UnitLevel("player") >= max
end

function Context:OnLogin()
  self:Refresh()
end

RL:On("GROUP_ROSTER_UPDATE", function() Context:Refresh() end)
RL:On("PLAYER_ENTERING_WORLD", function() Context.encounter = nil; Context:Refresh() end)
RL:On("PLAYER_UPDATE_RESTING", function() Context:Refresh() end)
RL:On("PLAYER_REGEN_DISABLED", function()
  Context.inCombat = true
  RL:Fire("RL_CONTEXT_CHANGED")
end)
RL:On("PLAYER_REGEN_ENABLED", function()
  Context.inCombat = false
  RL:Fire("RL_CONTEXT_CHANGED")
end)

RL:On("ENCOUNTER_START", function(id, name, difficulty, size)
  Context.encounter = { id = id, name = name, difficulty = difficulty, size = size, start = GetServerTime() }
end)
RL:On("ENCOUNTER_END", function()
  -- Keep it a moment longer: PLAYER_DEAD can arrive right after a wipe.
  local enc = Context.encounter
  C_Timer.After(3, function()
    if Context.encounter == enc then Context.encounter = nil end
  end)
end)
