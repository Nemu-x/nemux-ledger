-- Minimap button through LibDataBroker + LibDBIcon (bundled in Libs\).
--   Left-click: open the window. Right-click: show the HUD again.
--   Drag: move it around the minimap. Settings can hide it.
-- Using the standard library means button bags (MinimapButtonButton, the
-- addon compartment, ElvUI, ...) pick it up and show it as "Nemux Ledger".
-- When the libraries are missing (the test client), a plain button is used.

local _, RL = ...
local MM = RL:NewModule("Minimap")
RL.MinimapButton = MM
local T = RL.Theme

local LDB_NAME = "Nemux Ledger"
local dbicon, fallback

local function onClick(_, mouse)
  if mouse == "RightButton" then
    SlashCmdList.REQUIEMLEDGER("hud")
  else
    RL.UI:Toggle()
  end
end

local function fillTooltip(tt)
  tt:AddLine(T.Color("Nemux", "silver") .. " " .. T.Color("Ledger", "crimson"))
  RL.HUD:AddStatusLines(tt)
  tt:AddLine(" ")
  local m = T.c.muted
  tt:AddLine("Click: open the window", m[1], m[2], m[3])
  tt:AddLine("Right-click: show the HUD", m[1], m[2], m[3])
  tt:AddLine("Drag: move this button", m[1], m[2], m[3])
end

-- LibDBIcon keeps { hide, minimapPos, lock } in the table we hand it.
-- Older saves used `angle`; same convention (degrees, 0 = east).
local function settings()
  local s = RL.charDB.minimap
  if s.minimapPos == nil then s.minimapPos = tonumber(s.angle) or 200 end
  s.angle = nil
  return s
end

local function buildLDB()
  local LibStub = _G.LibStub
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  local icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (LDB and icon) then return false end
  local obj = LDB:GetDataObjectByName(LDB_NAME) or LDB:NewDataObject(LDB_NAME, {
    type = "launcher",
    label = LDB_NAME,
    text = LDB_NAME,
    icon = T.CREST,
    OnClick = onClick,
    OnTooltipShow = fillTooltip,
  })
  if not icon:IsRegistered(LDB_NAME) then icon:Register(LDB_NAME, obj, settings()) end
  dbicon = icon
  return true
end

-- Plain round button for clients without the libraries.
local function buildFallback()
  local s = settings()
  local b = CreateFrame("Button", "NemuxLedgerMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(T.CREST)
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(50, 50)
  border:SetPoint("TOPLEFT")
  local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
  local function place()
    local a = math.rad(tonumber(s.minimapPos) or 200)
    local r = (Minimap:GetWidth() / 2) + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  end
  b:SetScript("OnClick", onClick)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      s.minimapPos = math.floor(math.deg(atan2(py / scale - my, px / scale - mx)) + 0.5) % 360
      place()
    end)
    GameTooltip:Hide()
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    fillTooltip(GameTooltip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
  fallback = b
end

function MM:Build()
  if dbicon or fallback or not Minimap then return end
  if not buildLDB() then buildFallback() end
  self:Apply()
end

-- The button frame, whichever way it was made.
function MM:Button()
  if dbicon then return dbicon:GetMinimapButton(LDB_NAME) end
  return fallback
end

function MM:Apply()
  local hide = RL.charDB.minimap.hide
  if dbicon then
    if hide then dbicon:Hide(LDB_NAME) else dbicon:Show(LDB_NAME) end
  elseif fallback then
    fallback:SetShown(not hide)
  end
end

function MM:OnLogin()
  self:Build()
end
