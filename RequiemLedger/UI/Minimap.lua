-- Round button on the minimap ring, like other addons have.
--   Left-click: open the window. Right-click: show the HUD again.
--   Drag: move it around the minimap. Settings can hide it.
-- No libraries: the button sits on Minimap at a saved angle.

local _, RL = ...
local MM = RL:NewModule("Minimap")
RL.MinimapButton = MM
local T = RL.Theme

local button
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function place()
  local angle = math.rad(tonumber(RL.charDB.minimap.angle) or 200)
  local radius = (Minimap:GetWidth() / 2) + 5
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function dragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  px, py = px / scale, py / scale
  RL.charDB.minimap.angle = math.floor(math.deg(atan2(py - my, px - mx)) + 0.5) % 360
  place()
end

function MM:Build()
  if button or not Minimap then return end
  button = CreateFrame("Button", "RequiemLedgerMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(24, 24)
  bg:SetPoint("CENTER")

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(T.CREST)
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
      SlashCmdList.REQUIEMLEDGER("hud")
    else
      RL.UI:Toggle()
    end
  end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", dragUpdate)
    GameTooltip:Hide()
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Nemux Ledger", T.c.silver[1], T.c.silver[2], T.c.silver[3])
    RL.HUD:AddStatusLines(GameTooltip)
    GameTooltip:AddLine(" ")
    local m = T.c.muted
    GameTooltip:AddLine("Click: open the window", m[1], m[2], m[3])
    GameTooltip:AddLine("Right-click: show the HUD", m[1], m[2], m[3])
    GameTooltip:AddLine("Drag: move this button", m[1], m[2], m[3])
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  place()
  self:Apply()
end

function MM:Apply()
  if not button then return end
  button:SetShown(not RL.charDB.minimap.hide)
end

function MM:OnLogin()
  self:Build()
end
