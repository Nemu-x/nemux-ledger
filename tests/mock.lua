-- Minimal fake of the WoW client for offline logic tests.
-- These tests prove the addon's own logic only. They do NOT prove that the
-- real WoW: Forever client behaves the same way; that needs in-game testing.

unpack = unpack or table.unpack
math.randomseed(1)

local now, server = 1000, 1700000000
function GetTime() return now end
function GetServerTime() return server end
function __advance(s) now = now + s; server = server + s end

-- Timers --------------------------------------------------------------------
local timers = {}
C_Timer = {
  After = function(s, fn) timers[#timers + 1] = { at = now + s, fn = fn } end,
  NewTimer = function(s, fn)
    local t = { at = now + s, fn = fn }
    function t:Cancel() self.cancelled = true end
    timers[#timers + 1] = t
    return t
  end,
}
function __runTimers()
  local ran = true
  while ran do
    ran = false
    for _, t in ipairs(timers) do
      if t.at <= now and not t.cancelled and not t.done then
        t.done = true; t.fn(); ran = true
      end
    end
  end
end

-- Frames --------------------------------------------------------------------
local eventFrames = {}
local function stub()
  local f = { shown = false, scripts = {}, events = {}, text = "" }
  f.Show = function(self) self.shown = true end
  f.Hide = function(self) self.shown = false end
  f.IsShown = function(self) return self.shown end
  f.SetShown = function(self, v) self.shown = v and true or false end
  f.SetScript = function(self, k, fn) self.scripts[k] = fn end
  f.RegisterEvent = function(self, e) self.events[e] = true; eventFrames[self] = true end
  f.CreateTexture = function() return stub() end
  f.CreateFontString = function() return stub() end
  f.SetText = function(self, t) self.text = t end
  f.GetText = function(self) return self.text end
  f.GetStringWidth = function() return 80 end
  f.GetWidth = function() return 60 end
  f.GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end
  f.GetChecked = function(self) return self.checked end
  f.SetChecked = function(self, v) self.checked = v end
  return setmetatable(f, { __index = function() return function() end end })
end
__stub = stub
function CreateFrame(_, name)
  local f = stub()
  if name then _G[name] = f end
  return f
end
function __fire(event, ...)
  for f in pairs(eventFrames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

UIParent, GameTooltip = stub(), stub()
UISpecialFrames, SlashCmdList = {}, {}
tinsert = table.insert
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
__chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) __chat[#__chat + 1] = m end }
function geterrorhandler() return function(e) error(e, 0) end end

-- Player state the tests change ---------------------------------------------
__P = {
  level = 47, xp = 1000, xpmax = 5000, rested = 1900,
  resting = false, combat = false, raid = false, group = false, dead = false,
  secret = false, buffs = {}, items = {}, itemSpell = {}, cooldowns = {}, weapon = nil,
  bag = {}, itemClass = {}, -- bag = { {itemID, count}, ... } in bag 0; itemClass[id] = { classID, subClassID }
}
function UnitGUID() return "Player-1-00000001" end
function UnitName() return "Tester" end
UnitNameUnmodified = UnitName
function UnitClass() return "Warrior", "WARRIOR" end
function UnitLevel() return __P.level end
function UnitXP() return __P.xp end
function UnitXPMax() return __P.xpmax end
function GetXPExhaustion() return __P.rested end
function IsResting() return __P.resting end
function InCombatLockdown() return __P.combat end
function IsInRaid() return __P.raid end
function IsInGroup() return __P.group or __P.raid end
function UnitIsDeadOrGhost() return __P.dead end
function GetMaxLevelForPlayerExpansion() return 60 end
__P.instance = "none"
function GetInstanceInfo() return "Westfall", __P.instance, 0, "", 5, 0, false, 0 end
date = date or os.date
function GetPVPLifetimeStats() return __P.hk or 0, 0 end
__resetIn = 3 * 86400 -- seconds until the weekly reset
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return __resetIn end }
-- Profession window: __TS = { line, name, recipes = { [id] = learned } } or nil
__TS = nil
C_TradeSkillUI = {
  GetAllRecipeIDs = function() local t = {}; if __TS then for id in pairs(__TS.recipes) do t[#t + 1] = id end end; return t end,
  GetRecipeInfo = function(id) if __TS and __TS.recipes[id] ~= nil then return { recipeID = id, name = "Spell " .. id, learned = __TS.recipes[id] } end end,
  GetBaseProfessionInfo = function() if __TS then return { professionID = __TS.line, professionName = __TS.name } end end,
  IsTradeSkillLinked = function() return false end,
  IsTradeSkillGuild = function() return false end,
  IsNPCCrafting = function() return false end,
  IsTradeSkillReady = function() return __TS ~= nil end,
  -- __SCHEM[recipeID] = { { itemID, count, reagentType }, ... }; only answers while __SCHEM_OPEN or __TS
  GetRecipeSchematic = function(id)
    local list = __SCHEM[id]
    if not list or not (__TS or __SCHEM_OPEN) then return nil end
    local slots = {}
    for _, r in ipairs(list) do
      slots[#slots + 1] = { reagents = { { itemID = r[1] } }, quantityRequired = r[2], reagentType = r[3] or 1, required = true }
    end
    return { recipeID = id, reagentSlotSchematics = slots }
  end,
}
__SCHEM, __SCHEM_OPEN = {}, false
function GetRealZoneText() return "Westfall" end
function GetBuildInfo() return "1.60.1", "70790", "Nov 3 2026", 16001 end
function issecretvalue() return false end

C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
C_Secrets = { ShouldAurasBeSecret = function() return __P.secret end }
C_UnitAuras = { GetAuraDataByIndex = function(_, i) return __P.buffs[i] end }
C_Item = {
  GetItemCount = function(id, bank) return (__P.items[id] or 0) + (bank and __P.bank and __P.bank[id] or 0) end,
  GetItemSpell = function(id) local s = __P.itemSpell[id]; if s then return s.name, s.id end end,
  GetItemIconByID = function(id) return 100000 + id end,
  GetItemNameByID = function(id) return "Item " .. id end,
  IsItemDataCachedByID = function() return true end,
  RequestLoadItemDataByID = function() end,
  GetItemInfoInstant = function(id) local c = __P.itemClass[id] or { 7, 0 }; return id, "t", "s", "", 1, c[1], c[2] end,
}
C_Container = {
  GetItemCooldown = function(id) local c = __P.cooldowns[id]; if c then return c[1], c[2], 1 end return 0, 0, 1 end,
  GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
  GetContainerItemInfo = function(bag, slot)
    local e = bag == 0 and __P.bag[slot]
    if e then return { itemID = e[1], stackCount = e[2] } end
  end,
}
C_Spell = { GetSpellName = function(id) return "Spell " .. id end }
C_ClassColor = { GetClassColor = function() return { WrapTextInColorCode = function(_, t) return t end } end }
function GetWeaponEnchantInfo()
  if __P.weapon then return true, __P.weapon * 1000, 0, 0, false, 0 end
  return false
end
function GetProfessions() return 1, 2, nil, 4, 5 end
local PROFS = {
  [1] = { "Mining", 1, 300, 300, 0, 0, 186 },
  [2] = { "Blacksmithing", 2, 285, 300, 0, 0, 164 },
  [4] = { "Fishing", 4, 150, 300, 0, 0, 356 },
  [5] = { "Cooking", 5, 75, 300, 0, 0, 185 },
}
function GetProfessionInfo(i) return unpack(PROFS[i]) end

-- 0.1.1: reminders, minimap, guild ------------------------------------------
Minimap = stub()
function GetCursorPosition() return 0, 0 end
__notices, __sounds, __sent = {}, {}, {}
RaidWarningFrame = stub()
function RaidNotice_AddMessage(_, text) __notices[#__notices + 1] = text end
UIErrorsFrame = stub()
SOUNDKIT = { RAID_WARNING = 8959 }
function PlaySound(id) __sounds[#__sounds + 1] = id end
function GetNormalizedRealmName() return "Forever" end

__G = {
  inGuild = true, lockdown = false,
  roster = {
    -- Forever names have a surname; the realm is a mega-realm id. My row has my GUID.
    { "Tester Ironside-CAMWOWEU4Realm8PvP", "Officer", 1, 47, "Warrior", "Westfall", "", "", true, 0, "WARRIOR", 0, 0, false, false, 0, "Player-1-00000001" },
    { "Friend-Forever", "Member", 3, 40, "Mage", "Duskwood", "", "", true, 0, "MAGE" },
    { "Sleepy-Forever", "Member", 3, 20, "Rogue", "Elwynn", "", "", false, 0, "ROGUE" },
  },
}
function IsInGuild() return __G.inGuild end
function GetGuildInfo() if __G.inGuild then return "Requiem", "Officer", 1 end end
__P.faction = "Alliance"
function UnitFactionGroup() return __P.faction, __P.faction end
function GetNumGuildMembers() return #__G.roster, 2, 2 end
function GetGuildRosterInfo(i) return unpack(__G.roster[i]) end
C_GuildInfo = { GuildRoster = function() end }
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  InChatMessagingLockdown = function() return __G.lockdown end,
  SendAddonMessage = function(prefix, msg, channel, target)
    __sent[#__sent + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
    return true
  end,
}
