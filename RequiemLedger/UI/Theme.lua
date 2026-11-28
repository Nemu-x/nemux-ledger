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
  bg      = { 0.039, 0.059, 0.114, 0.97 },
  header  = { 0.027, 0.039, 0.082, 1 },
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

-- Live themes: everything drawn in a theme colour registers a repaint here,
-- and switching the theme repaints it all without a /reload.
T.repaint = {}
function T.OnTheme(fn) T.repaint[#T.repaint + 1] = fn end

-- A texture tinted with a theme colour (kept in sync with the theme).
function T.Tint(tex, key, alpha)
  local function paint()
    local c = T.c[key]
    tex:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
  end
  paint()
  T.OnTheme(paint)
  return tex
end

-- Flat 1px-border panel. Frame must be created with "BackdropTemplate".
function T.Panel(frame, bg, border)
  frame:SetBackdrop({ bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = 1 })
  local function paint()
    frame:SetBackdropColor(unpack(bg or T.c.bg))
    frame:SetBackdropBorderColor(unpack(border or T.c.bronze))
  end
  paint()
  T.OnTheme(paint) -- colour tables are shared: a repaint picks up the new values
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
  T.OnTheme(function() if not holder.status then holder:SetBackdropBorderColor(unpack(T.c.bronze)) end end)
  local tex = holder:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", 2, -2)
  tex:SetPoint("BOTTOMRIGHT", -2, 2)
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  holder.tex = tex
  function holder:SetStatus(key)
    self.status = key ~= "bronze" and key or nil
    local c = T.c[key] or T.c.bronze
    self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
  end
  return holder
end

-- Thin horizontal rule.
function T.Rule(parent, colorKey, alpha)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetTexture(T.WHITE)
  T.Tint(t, colorKey or "bronze", alpha or 0.5)
  t:SetHeight(1)
  return t
end

T.ATTENTION_COLOR = { miss = "bad", soon = "warn", tip = "info" }

-- ---------------------------------------------------------------------------
-- Flat widgets in the tabard style (same look everywhere in the addon)
-- ---------------------------------------------------------------------------
local FIELD = { 0.02, 0.03, 0.07, 1 }
local BUTTON_BG = { 0.10, 0.13, 0.24, 1 }
local BUTTON_HOVER = { 0.15, 0.19, 0.33, 1 }
local BUTTON_ACTIVE = { 0.33, 0.08, 0.13, 1 }
T.FIELD = FIELD

-- ---------------------------------------------------------------------------
-- Colour themes. Applied once when saved settings load (before any frame is
-- made), so a change needs a /reload. Values are copied into the shared
-- colour tables, which keeps every existing reference working.
-- ---------------------------------------------------------------------------
T.THEMES = {
  { id = "requiem", name = "Requiem", desc = "Navy, crimson and bronze" },
  { id = "alliance", name = "Alliance", desc = "Royal blue and gold",
    bg = { 0.03, 0.07, 0.16, 0.97 }, header = { 0.02, 0.05, 0.12, 1 }, panel = { 0.06, 0.12, 0.26, 0.95 },
    row = { 0.08, 0.15, 0.30, 0.85 }, bronze = { 0.78, 0.63, 0.25, 1 }, crimson = { 0.85, 0.68, 0.20, 1 },
    field = { 0.01, 0.04, 0.10, 1 }, button = { 0.07, 0.13, 0.28, 1 }, hover = { 0.11, 0.19, 0.38, 1 },
    active = { 0.35, 0.28, 0.06, 1 }, hex = "ffd9ad33" },
  { id = "midnight", name = "Midnight", desc = "Graphite and ice blue",
    bg = { 0.06, 0.06, 0.07, 0.97 }, header = { 0.035, 0.035, 0.04, 1 }, panel = { 0.10, 0.10, 0.11, 0.95 },
    row = { 0.13, 0.13, 0.15, 0.85 }, bronze = { 0.40, 0.42, 0.46, 1 }, crimson = { 0.30, 0.55, 0.85, 1 },
    field = { 0.03, 0.03, 0.035, 1 }, button = { 0.12, 0.12, 0.14, 1 }, hover = { 0.18, 0.18, 0.21, 1 },
    active = { 0.12, 0.25, 0.42, 1 }, hex = "ff4d8cd9" },
  { id = "emerald", name = "Emerald Dream", desc = "Deep green and moss",
    bg = { 0.03, 0.08, 0.06, 0.97 }, header = { 0.02, 0.05, 0.04, 1 }, panel = { 0.06, 0.14, 0.10, 0.95 },
    row = { 0.08, 0.17, 0.12, 0.85 }, bronze = { 0.55, 0.48, 0.30, 1 }, crimson = { 0.30, 0.70, 0.40, 1 },
    field = { 0.01, 0.04, 0.03, 1 }, button = { 0.07, 0.15, 0.11, 1 }, hover = { 0.10, 0.21, 0.15, 1 },
    active = { 0.10, 0.30, 0.16, 1 }, hex = "ff4db366" },
  { id = "blood", name = "Blood and Iron", desc = "Dark red and iron",
    bg = { 0.08, 0.03, 0.03, 0.97 }, header = { 0.05, 0.02, 0.02, 1 }, panel = { 0.15, 0.06, 0.06, 0.95 },
    row = { 0.18, 0.07, 0.07, 0.85 }, bronze = { 0.50, 0.45, 0.42, 1 }, crimson = { 0.80, 0.15, 0.15, 1 },
    field = { 0.04, 0.01, 0.01, 1 }, button = { 0.16, 0.06, 0.06, 1 }, hover = { 0.23, 0.09, 0.09, 1 },
    active = { 0.40, 0.06, 0.06, 1 }, hex = "ffcc2626" },
}

local function copyInto(dst, src) for i = 1, 4 do dst[i] = src[i] end end
local function copyOf(src) return { src[1], src[2], src[3], src[4] } end

-- The built-in look is the first theme; its values are the colours above.
do
  local th = T.THEMES[1]
  for _, k in ipairs({ "bg", "header", "panel", "row", "bronze", "crimson" }) do th[k] = copyOf(T.c[k]) end
  th.field, th.button, th.hover, th.active = copyOf(FIELD), copyOf(BUTTON_BG), copyOf(BUTTON_HOVER), copyOf(BUTTON_ACTIVE)
  th.hex = T.hex.crimson
end

function T.ThemeById(id)
  for _, th in ipairs(T.THEMES) do if th.id == id then return th end end
  return T.THEMES[1]
end

-- Sets the theme and repaints everything already on screen.
function T.ApplyTheme(id)
  local th = T.ThemeById(id)
  T.current = th.id
  for _, k in ipairs({ "bg", "header", "panel", "row", "bronze", "crimson" }) do copyInto(T.c[k], th[k]) end
  copyInto(FIELD, th.field)
  copyInto(BUTTON_BG, th.button)
  copyInto(BUTTON_HOVER, th.hover)
  copyInto(BUTTON_ACTIVE, th.active)
  T.hex.crimson = th.hex
  for _, fn in ipairs(T.repaint) do pcall(fn) end
end

-- Flat button: navy with a bronze edge. SetActive(true) marks the selected
-- option of a group (crimson), instead of fading the others out.
function T.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w or 120, h or 22)
  T.Panel(b, BUTTON_BG, T.c.bronze)
  b.text = T.Text(b, 12, "silver")
  b.text:SetPoint("CENTER")
  b.text:SetJustifyH("CENTER")
  b.text:SetText(text or "")
  function b:SetLabel(t) self.text:SetText(t) end
  function b:Paint(hover)
    if self.active then
      self:SetBackdropColor(unpack(BUTTON_ACTIVE))
      self:SetBackdropBorderColor(unpack(T.c.crimson))
      T.SetColor(self.text, "silver")
    else
      self:SetBackdropColor(unpack(hover and BUTTON_HOVER or BUTTON_BG))
      self:SetBackdropBorderColor(unpack(hover and T.c.silver or T.c.bronze))
      T.SetColor(self.text, (hover or self.active == nil) and "silver" or "muted")
    end
  end
  function b:SetActive(on)
    self.active = on and true or false
    self:Paint(self:IsMouseOver())
  end
  b:SetScript("OnEnter", function(self) self:Paint(true) end)
  b:SetScript("OnLeave", function(self) self:Paint(false) end)
  T.OnTheme(function() b:Paint(false) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- Flat close button: a silver x that turns crimson on hover.
function T.CloseButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(22, 22)
  T.Panel(b, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
  b.text = T.Text(b, 16, "muted")
  b.text:SetPoint("CENTER", 0, 1)
  b.text:SetJustifyH("CENTER")
  b.text:SetText("x")
  b:SetScript("OnEnter", function(self)
    self:SetBackdropColor(unpack(BUTTON_ACTIVE))
    self:SetBackdropBorderColor(unpack(T.c.crimson))
    T.SetColor(self.text, "silver")
  end)
  b:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0, 0, 0, 0)
    self:SetBackdropBorderColor(0, 0, 0, 0)
    T.SetColor(self.text, "muted")
  end)
  b:SetScript("OnClick", onClick)
  return b
end

-- Flat search field with a grey placeholder. onChange(text) on every edit.
function T.SearchBox(parent, w, placeholder, onChange)
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  e:SetSize(w or 180, 22)
  T.Panel(e, FIELD, T.c.bronze)
  e:SetFont(T.FONT, 12, "")
  e:SetTextColor(unpack(T.c.silver))
  e:SetTextInsets(8, 8, 0, 0)
  e:SetAutoFocus(false)
  e:SetMaxLetters(40)
  e.hint = T.Text(e, 12, "muted")
  e.hint:SetPoint("LEFT", 8, 0)
  e.hint:SetText(placeholder or "Search")
  e:SetScript("OnTextChanged", function(self)
    self.hint:SetShown((self:GetText() or "") == "")
    if onChange then onChange(self:GetText() or "") end
  end)
  e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(T.c.silver)) end)
  e:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(T.c.bronze)) end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
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
  T.Tint(b.fill, "crimson")
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
  value:SetWordWrap(false)
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
