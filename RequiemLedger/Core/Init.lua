-- Nemux Ledger: namespace, logging and a single event bus.
-- Every module registers handlers through RL:On(event, fn) instead of
-- creating its own frame, so there is exactly one event frame in the addon.

local ADDON_NAME, RL = ...
_G.RequiemLedger = RL

RL.name = ADDON_NAME
RL.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"
RL.modules = {}

local PREFIX = "|cffd6d9dfLedger|r|cff9b2335:|r "

function RL:Print(fmt, ...)
  local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
  DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

function RL:Debug(fmt, ...)
  if self.charDB and self.charDB.debug then
    self:Print("|cff8a93a8[debug]|r " .. fmt, ...)
  end
end

-- ---------------------------------------------------------------------------
-- Event bus
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}   -- event -> list of functions

function RL:On(event, fn)
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
    -- Some events may not exist on every client build; never let that break loading.
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then
      self:Debug("Event not available: %s", event)
    end
  end
  list[#list + 1] = fn
end

-- Internal messages between modules use the same bus, prefixed with "RL_".
function RL:Fire(event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then geterrorhandler()(err) end
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  RL:Fire(event, ...)
end)

-- Modules declare themselves here; Init() runs after SavedVariables are loaded.
function RL:NewModule(name)
  local m = { name = name }
  self.modules[#self.modules + 1] = m
  self.modules[name] = m
  return m
end

RL:On("ADDON_LOADED", function(addon)
  if addon ~= ADDON_NAME then return end
  RL.DB:Load()
  for i = 1, #RL.modules do
    local m = RL.modules[i]
    if m.Init then
      local ok, err = pcall(m.Init, m)
      if not ok then geterrorhandler()(err) end
    end
  end
end)

RL:On("PLAYER_LOGIN", function()
  for i = 1, #RL.modules do
    local m = RL.modules[i]
    if m.OnLogin then
      local ok, err = pcall(m.OnLogin, m)
      if not ok then geterrorhandler()(err) end
    end
  end
end)

-- Addon compartment (the addon list button by the minimap), if the client has it.
function RequiemLedger_OnCompartmentClick()
  if RL.UI and RL.UI.Toggle then RL.UI:Toggle() end
end
