-- HUD: a small panel that only lists what needs your attention.
--   Left-click: open the window. Right-click: snooze for 15 minutes.
--   Drag: move (unless locked). Hover: full status in a tooltip.
-- Hidden while dead, in combat (default) and when nothing is missing.

local _, RL = ...
local HUD = RL:NewModule("HUD")
RL.HUD = HUD
local T = RL.Theme

local ROW_H, ICON = 30, 26
local frame, header, countText, okText, headerTitle
local rows, icons = {}, {}
local snoozeUntil = 0
local allSetUntil = 0
local lastCount = 0

local function savePosition()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  RL.charDB.hud.point = { point, relPoint, x, y }
end

local function restorePosition()
  frame:ClearAllPoints()
  local p = RL.charDB.hud.point
  if type(p) == "table" and p[1] then
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -210, -24)
  end
end

local function makeRow(i)
  local row = CreateFrame("Frame", nil, frame)
  row:SetHeight(ROW_H)
  row.icon = T.Icon(row, ICON)
  row.icon:SetPoint("LEFT", 0, 0)
  row.title = T.Text(row, 12, "silver")
  row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -1)
  row.hint = T.Text(row, 10, "muted")
  row.hint:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  rows[i] = row
  return row
end

local function makeIcon(i)
  local ic = T.Icon(frame, ICON + 4)
  ic.timer = T.Text(ic, 10, "warn")
  ic.timer:SetPoint("TOP", ic, "BOTTOM", 0, -1)
  icons[i] = ic
  return ic
end

-- Status of every tracked check, for any tooltip (HUD and minimap button).
function HUD:AddStatusLines(tip)
  local mode = RL.Context.mode
  tip:AddLine("Checks for " .. mode, T.c.muted[1], T.c.muted[2], T.c.muted[3])
  for _, check in ipairs(RL.Data.CHECKS) do
    if RL.Readiness:IsTracked(check.id, mode) then
      local res = RL.Readiness.results[check.id]
      if res then
        local text, key = RL.Readiness:StatusLine(res)
        local c = T.c[key] or T.c.silver
        tip:AddDoubleLine(check.name, text, 0.9, 0.9, 0.9, c[1], c[2], c[3])
      end
    end
  end
  local state = HUD:State()
  if state ~= "shown" and state ~= "nothing to show" then
    tip:AddLine("HUD: " .. state, T.c.warn[1], T.c.warn[2], T.c.warn[3])
  end
end

-- Why the HUD is (not) on screen, in words. Used by tooltips and /rq report.
function HUD:State()
  local hud = RL.charDB.hud
  local ctx = RL.Context
  if hud.style == "off" then return "turned off (Settings)" end
  local snooze = snoozeUntil - GetTime()
  if snooze > 0 then
    return string.format("snoozed by right-click, %d min left (/rq hud)", math.ceil(snooze / 60))
  end
  if UnitIsDeadOrGhost("player") then return "hidden while dead" end
  if ctx.inCombat and hud.hideInCombat then return "hidden in combat (Settings)" end
  if ctx.mode == "solo" and ctx.resting and hud.quietInTownSolo then return "hidden in towns (Settings)" end
  if #RL.Readiness:Attention() == 0 then return "nothing to show" end
  return "shown"
end

local function showTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
  GameTooltip:AddLine("Nemux Ledger", T.c.silver[1], T.c.silver[2], T.c.silver[3])
  HUD:AddStatusLines(GameTooltip)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: open window · Right-click: snooze 15 min", T.c.muted[1], T.c.muted[2], T.c.muted[3])
  if not RL.charDB.hud.locked then
    GameTooltip:AddLine("Drag to move", T.c.muted[1], T.c.muted[2], T.c.muted[3])
  end
  GameTooltip:Show()
end

function HUD:Build()
  frame = CreateFrame("Frame", "RequiemLedgerHUD", UIParent, "BackdropTemplate")
  T.Panel(frame, { 0.047, 0.067, 0.125, 0.92 })
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScale(RL.charDB.hud.scale or 1)

  local top = frame:CreateTexture(nil, "ARTWORK")
  top:SetTexture(T.WHITE)
  top:SetVertexColor(unpack(T.c.crimson))
  top:SetPoint("TOPLEFT", 1, -1)
  top:SetPoint("TOPRIGHT", -1, -1)
  top:SetHeight(2)

  header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", 8, -6)
  header:SetPoint("TOPRIGHT", -8, -6)
  header:SetHeight(18)
  local crest = header:CreateTexture(nil, "ARTWORK")
  crest:SetTexture(T.CREST)
  crest:SetSize(18, 18)
  crest:SetPoint("LEFT")
  headerTitle = T.Text(header, 11, "silver", T.TITLE_FONT)
  headerTitle:SetText("LEDGER")
  headerTitle:SetPoint("LEFT", crest, "RIGHT", 5, 0)
  countText = T.Text(header, 10, "muted")
  countText:SetPoint("RIGHT")
  local rule = T.Rule(header, "crimson", 0.5)
  rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
  rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -3)

  okText = T.Text(frame, 12, "ok", T.TITLE_FONT)
  okText:SetText("All set")

  local dragging = false
  frame:SetScript("OnDragStart", function(self)
    if not RL.charDB.hud.locked then
      dragging = true
      self:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
    C_Timer.After(0.1, function() dragging = false end)
  end)
  frame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
      snoozeUntil = GetTime() + 15 * 60
      RL:Print("HUD snoozed for 15 minutes. /rq hud brings it back.")
      HUD:Update()
      C_Timer.After(15 * 60 + 1, function() HUD:Update() end)
    elseif button == "LeftButton" and not dragging then
      RL.UI:Toggle()
    end
  end)
  frame:SetScript("OnEnter", showTooltip)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

  restorePosition()
  frame:Hide()
end

local function hideAll()
  for _, r in ipairs(rows) do r:Hide() end
  for _, ic in ipairs(icons) do ic:Hide() end
  okText:Hide()
end

function HUD:Update()
  if not frame then return end
  local guild = RL.Context:GuildName()
  headerTitle:SetText(guild and #guild <= 16 and guild:upper() or "LEDGER")
  local hud = RL.charDB.hud
  local ctx = RL.Context

  if hud.style == "off" or GetTime() < snoozeUntil or UnitIsDeadOrGhost("player")
    or (ctx.inCombat and hud.hideInCombat) then
    frame:Hide()
    return
  end

  local list = RL.Readiness:Attention()
  local count = #list
  if count == 0 and lastCount > 0 then allSetUntil = GetTime() + 4 end
  lastCount = count

  hideAll()

  if count == 0 then
    if GetTime() < allSetUntil and hud.style == "text" then
      header:Show()
      countText:SetText("")
      okText:ClearAllPoints()
      okText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, -8)
      okText:Show()
      frame:SetSize(150, 52)
      frame:Show()
      C_Timer.After(4.1, function() HUD:Update() end)
    else
      frame:Hide()
    end
    return
  end

  if hud.style == "icons" then
    header:Hide()
    local x = 8
    for i, res in ipairs(list) do
      local ic = icons[i] or makeIcon(i)
      ic:ClearAllPoints()
      ic:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -7)
      ic.tex:SetTexture(res.icon)
      ic:SetStatus(T.ATTENTION_COLOR[RL.Readiness:AttentionKind(res)])
      ic.timer:SetText(res.status == "expiring" and RL.Readiness.FormatTime(res.left):gsub(" min", "m") or "")
      ic:Show()
      x = x + ICON + 4 + 6
    end
    frame:SetSize(x + 2, ICON + 4 + 26)
  else
    header:Show()
    countText:SetText(count == 1 and "1 to check" or (count .. " to check"))
    local width = 170
    local y = -32
    for i, res in ipairs(list) do
      local row = rows[i] or makeRow(i)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, y)
      row:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
      local kind = RL.Readiness:AttentionKind(res)
      local title, hint = RL.Readiness:Describe(res)
      row.icon.tex:SetTexture(res.icon)
      row.icon:SetStatus(T.ATTENTION_COLOR[kind])
      row.title:SetText(title)
      T.SetColor(row.title, kind == "miss" and "bad" or kind == "soon" and "warn" or "info")
      row.hint:SetText(hint or "")
      row:Show()
      width = math.max(width, 8 + ICON + 7 + math.max(row.title:GetStringWidth(), row.hint:GetStringWidth()) + 14)
      y = y - (ROW_H + 4)
    end
    frame:SetSize(math.min(width, 300), -y + 4)
  end
  frame:Show()
end

function HUD:ResetPosition()
  RL.charDB.hud.point = nil
  if frame then restorePosition() end
end

function HUD:Unsnooze()
  snoozeUntil = 0
  self:Update()
end

function HUD:ApplyScale()
  if frame then frame:SetScale(RL.charDB.hud.scale or 1) end
end

function HUD:OnLogin()
  self:Build()
end

RL:On("RL_READINESS_UPDATED", function() HUD:Update() end)
RL:On("RL_CONTEXT_CHANGED", function() HUD:Update() end)
RL:On("PLAYER_DEAD", function() HUD:Update() end)
RL:On("PLAYER_ALIVE", function() HUD:Update() end)
RL:On("PLAYER_UNGHOST", function() HUD:Update() end)
