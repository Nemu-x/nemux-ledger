-- Visual style: navy field, crimson accents, bronze rim, silver text.
-- Emblem: Media\emblem.tga (128x128, drawn for Nemux Ledger).

local _, RL = ...
local T = {}
RL.Theme = T

T.CREST = "Interface\\AddOns\\RequiemLedger\\Media\\emblem"
T.WHITE = "Interface\\Buttons\\WHITE8x8"
T.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
T.TITLE_FONT = "Fonts\\MORPHEUS.TTF"

T.c = {
  bg      = { 0.047, 0.071, 0.133, 0.94 },
  panel   = { 0.078, 0.122, 0.220, 0.95 },
  row     = { 0.098, 0.145, 0.255, 0.85 },
  bronze  = { 0.541, 0.416, 0.243, 1 },
  crimson = { 0.608, 0.137, 0.208, 1 },
  silver  = { 0.839, 0.851, 0.875, 1 },
  muted   = { 0.592, 0.639, 0.733, 1 },
  ok      = { 0.373, 0.749, 0.478, 1 },
  warn    = { 0.886, 0.635, 0.231, 1 },
  bad     = { 0.851, 0.341, 0.290, 1 },
  info    = { 0.353, 0.635, 0.878, 1 },
}

T.hex = {
  silver = "ffd6d9df", crimson = "ff9b2335", muted = "ff97a3bb",
  ok = "ff5fbf7a", warn = "ffe2a23b", bad = "ffd9574a", info = "ff5aa2e0",
}

function T.Color(text, key)
  return "|c" .. (T.hex[key] or T.hex.silver) .. tostring(text) .. "|r"
end

-- Flat 1px-border panel. Frame must be created with "BackdropTemplate".
function T.Panel(frame, bg, border)
  frame:SetBackdrop({ bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = 1 })
  frame:SetBackdropColor(unpack(bg or T.c.bg))
  frame:SetBackdropBorderColor(unpack(border or T.c.bronze))
end

function T.Text(parent, size, colorKey, font, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(font or T.FONT, size or 12, "")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.9)
  local c = T.c[colorKey or "silver"] or T.c.silver
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  fs:SetJustifyH("LEFT")
  return fs
end

function T.SetColor(fs, colorKey)
  local c = T.c[colorKey] or T.c.silver
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- Item/spell icon with a colored 2px frame (frame color = status).
function T.Icon(parent, size)
  local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  holder:SetSize(size, size)
  holder:SetBackdrop({ edgeFile = T.WHITE, edgeSize = 2 })
  holder:SetBackdropBorderColor(unpack(T.c.bronze))
  local tex = holder:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", 2, -2)
  tex:SetPoint("BOTTOMRIGHT", -2, 2)
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  holder.tex = tex
  function holder:SetStatus(key)
    local c = T.c[key] or T.c.bronze
    self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
  end
  return holder
end

-- Thin horizontal rule.
function T.Rule(parent, colorKey, alpha)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetTexture(T.WHITE)
  local c = T.c[colorKey or "bronze"]
  t:SetVertexColor(c[1], c[2], c[3], alpha or 0.5)
  t:SetHeight(1)
  return t
end

T.ATTENTION_COLOR = { miss = "bad", soon = "warn", tip = "info" }

-- ---------------------------------------------------------------------------
-- Flat widgets in the tabard style (same look everywhere in the addon)
-- ---------------------------------------------------------------------------
local FIELD = { 0.02, 0.03, 0.07, 1 }
local BUTTON_BG = { 0.10, 0.13, 0.24, 1 }
local BUTTON_HOVER = { 0.36, 0.09, 0.14, 1 }

-- Flat button: navy with a bronze edge, crimson on hover.
function T.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w or 120, h or 22)
  T.Panel(b, BUTTON_BG, T.c.bronze)
  b.text = T.Text(b, 12, "silver")
  b.text:SetPoint("CENTER")
  b.text:SetJustifyH("CENTER")
  b.text:SetText(text or "")
  function b:SetLabel(t) self.text:SetText(t) end
  b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(BUTTON_HOVER)) end)
  b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(BUTTON_BG)) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- Flat check box with an optional label. The label is clickable too.
-- get() returns the current value, set(v) stores it.
function T.Check(parent, label, get, set, size)
  size = size or 16
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(size, size)
  T.Panel(b, FIELD, T.c.bronze)
  b.fill = b:CreateTexture(nil, "ARTWORK")
  b.fill:SetTexture(T.WHITE)
  b.fill:SetVertexColor(unpack(T.c.crimson))
  b.fill:SetPoint("TOPLEFT", 3, -3)
  b.fill:SetPoint("BOTTOMRIGHT", -3, 3)
  b.mark = b:CreateTexture(nil, "OVERLAY")
  b.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b.mark:SetVertexColor(unpack(T.c.silver))
  b.mark:SetSize(size + 6, size + 6)
  b.mark:SetPoint("CENTER", 1, 0)
  if label then
    b.label = T.Text(b, 12, "silver")
    b.label:SetPoint("LEFT", b, "RIGHT", 7, 0)
    b.label:SetText(label)
    b:SetHitRectInsets(0, -(b.label:GetStringWidth() + 10), -2, -2)
  end
  function b:Refresh()
    local on = get() and true or false
    self.fill:SetShown(on)
    self.mark:SetShown(on)
  end
  b:SetScript("OnClick", function(self)
    set(not get())
    self:Refresh()
  end)
  b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(T.c.silver)) end)
  b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(T.c.bronze)) end)
  return b
end

-- Compact "[-] value [+]" control. fmt(value) returns the text to show.
function T.Stepper(parent, get, set, minV, maxV, step, fmt, width)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width or 78, 18)
  local function change(d)
    local v = get() + d
    v = math.floor(v / step + 0.5) * step
    set(math.max(minV, math.min(maxV, v)))
    f:Refresh()
  end
  local minus = T.Button(f, "-", 18, 18, function() change(-step) end)
  minus:SetPoint("LEFT")
  local plus = T.Button(f, "+", 18, 18, function() change(step) end)
  plus:SetPoint("RIGHT")
  local value = T.Text(f, 12, "silver")
  value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
  value:SetPoint("RIGHT", plus, "LEFT", -2, 0)
  value:SetJustifyH("CENTER")
  function f:Refresh()
    local v = get()
    value:SetText(fmt and fmt(v) or tostring(v))
  end
  return f
end

-- Section header: Morpheus title with a thin bronze line under it.
function T.Section(parent, text, width)
  local fs = T.Text(parent, 14, "silver", T.TITLE_FONT)
  fs:SetText(text)
  local rule = T.Rule(parent, "bronze", 0.45)
  rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
  rule:SetWidth(width or 300)
  fs.rule = rule
  return fs
end

function T.ClassColored(name, classFile)
  if classFile and C_ClassColor and C_ClassColor.GetClassColor then
    local c = C_ClassColor.GetClassColor(classFile)
    if c and c.WrapTextInColorCode then return c:WrapTextInColorCode(name) end
  end
  return name
end
