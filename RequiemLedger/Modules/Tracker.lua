-- Recipe tracker: a small movable panel with what you need for the recipes
-- you track (click a recipe in Guild -> Recipes). It updates with your bags,
-- so at the auction house you see what is still missing.
--   Shift-click a reagent: link it in chat. Hover: item tooltip.
--   Right-click a recipe line: one craft less (removes it at zero). Left-click: one more.

local _, RL = ...
local TR = RL:NewModule("Tracker")
RL.Tracker = TR
local Compat = RL.Compat

local MAX_TRACKED = 6
local MAX_LINES = 18
local frame, lines = nil, {}

function TR:List() return RL.charDB.tracker.recipes end

function TR:IsTracked(id) return self:List()[id] ~= nil end

function TR:Toggle(id)
  local list = self:List()
  if list[id] then
    list[id] = nil
  else
    local n = 0
    for _ in pairs(list) do n = n + 1 end
    if n >= MAX_TRACKED then
      RL:Print("You can track up to %d recipes. Right-click one in the tracker to drop it.", MAX_TRACKED)
      return
    end
    list[id] = 1
    RL.charDB.tracker.hidden = false
  end
  self:Update()
  RL:Fire("RL_TRACKER_UPDATED")
end

function TR:Change(id, delta)
  local list = self:List()
  if not list[id] then return end
  list[id] = list[id] + delta
  if list[id] <= 0 then list[id] = nil end
  if list[id] and list[id] > 99 then list[id] = 99 end
  self:Update()
  RL:Fire("RL_TRACKER_UPDATED")
end

function TR:Clear()
  wipe(self:List())
  self:Update()
  RL:Fire("RL_TRACKER_UPDATED")
end

-- Shopping list for everything tracked:
-- recipes = { { id, name, count, known } }, mats = { { itemID, need, bags, total, name, icon, price } }
function TR:Needs()
  local recipes, byItem, mats = {}, {}, {}
  for id, count in pairs(self:List()) do
    local list = RL.Recipes:Reagents(id)
    recipes[#recipes + 1] = { id = id, name = RL.Recipes:RecipeName(id) or ("recipe " .. id), count = count, known = list ~= nil }
    for _, r in ipairs(list or {}) do
      local m = byItem[r[1]]
      if not m then
        m = { itemID = r[1], need = 0 }
        byItem[r[1]] = m
        mats[#mats + 1] = m
      end
      m.need = m.need + r[2] * count
    end
  end
  for _, m in ipairs(mats) do
    m.bags, m.total = Compat.ItemCounts(m.itemID)
    m.name = Compat.ItemName(m.itemID)
    if not m.name then Compat.RequestItem(m.itemID) end
    m.icon = Compat.ItemIcon(m.itemID)
    m.price = Compat.Price(m.itemID)
  end
  table.sort(recipes, function(a, b) return a.name < b.name end)
  table.sort(mats, function(a, b)
    local am, bm = a.bags < a.need, b.bags < b.need
    if am ~= bm then return am end
    return (a.name or "") < (b.name or "")
  end)
  return recipes, mats
end

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------
local function itemLink(itemID)
  if C_Item and C_Item.GetItemInfo then
    local ok, _, link = pcall(C_Item.GetItemInfo, itemID)
    if ok and type(link) == "string" then return link end
  end
  return nil
end

local function makeLine(i)
  local T = RL.Theme
  local b = CreateFrame("Button", nil, frame)
  b:SetHeight(16)
  b:SetPoint("TOPLEFT", 8, -26 - (i - 1) * 16)
  b:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.left = T.Text(b, 11, "silver")
  b.left:SetPoint("LEFT")
  b.left:SetPoint("RIGHT", b, "RIGHT", -86, 0)
  b.left:SetWordWrap(false)
  b.left:SetJustifyH("LEFT")
  b.right = T.Text(b, 11, "muted")
  b.right:SetPoint("RIGHT")
  b.right:SetJustifyH("RIGHT")
  b:SetScript("OnClick", function(self, button)
    if self.itemID then
      if IsModifiedClick and IsModifiedClick("CHATLINK") or (IsShiftKeyDown and IsShiftKeyDown()) then
        local link = itemLink(self.itemID)
        if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link)
        elseif not link then RL:Print("Item info is still loading, try again in a second.") end
      end
    elseif self.recipeID then
      TR:Change(self.recipeID, button == "RightButton" and -1 or 1)
    end
  end)
  b:SetScript("OnEnter", function(self)
    if self.itemID then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
      GameTooltip:AddLine("Shift-click: link in chat", 0.6, 0.64, 0.73)
      GameTooltip:Show()
    elseif self.recipeID then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine("Left-click: one more craft", 0.9, 0.9, 0.9)
      GameTooltip:AddLine("Right-click: one less (removes it at zero)", 0.9, 0.9, 0.9)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  lines[i] = b
  return b
end

local function build()
  local T = RL.Theme
  frame = CreateFrame("Frame", "RequiemLedgerTracker", UIParent, "BackdropTemplate")
  T.Panel(frame, { 0.047, 0.067, 0.125, 0.9 })
  frame:SetWidth(250)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    RL.charDB.tracker.point = { point, relPoint, x, y }
  end)
  local p = RL.charDB.tracker.point
  if type(p) == "table" and p[1] then
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
  end
  frame.title = T.Text(frame, 12, "silver", T.TITLE_FONT)
  frame.title:SetPoint("TOPLEFT", 8, -7)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function()
    RL.charDB.tracker.hidden = true
    frame:Hide()
    RL:Print("Tracker hidden. /rq track shows it again, /rq track clear stops tracking.")
  end)
  frame.footer = T.Text(frame, 10, "muted")
  frame.footer:SetPoint("BOTTOMLEFT", 8, 6)
  frame.footer:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
  frame.footer:SetJustifyH("LEFT")
end

function TR:Update()
  if not RL.charDB then return end
  local recipes, mats = self:Needs()
  if #recipes == 0 or RL.charDB.tracker.hidden then
    if frame then frame:Hide() end
    return
  end
  if not frame then build() end
  local T = RL.Theme
  for _, l in ipairs(lines) do l:Hide(); l.itemID, l.recipeID = nil, nil end

  local i = 0
  local function line()
    i = i + 1
    if i > MAX_LINES then return nil end
    local l = lines[i] or makeLine(i)
    l:Show()
    return l
  end
  for _, r in ipairs(recipes) do
    local l = line()
    if l then
      l.recipeID = r.id
      l.left:SetText(T.Color(r.name, "info"))
      l.right:SetText(T.Color("x" .. r.count, "info") .. (r.known and "" or T.Color("  ?", "muted")))
    end
  end
  local missingAll, cost, ready = 0, 0, true
  for _, m in ipairs(mats) do
    local l = line()
    if m.bags < m.need then ready = false; missingAll = missingAll + 1 end
    if m.price then cost = cost + m.price * math.max(0, m.need - m.bags) end
    if l then
      l.itemID = m.itemID
      local icon = m.icon and ("|T" .. m.icon .. ":13:13|t ") or ""
      l.left:SetText(icon .. (m.name or ("item " .. m.itemID)))
      local key = m.bags >= m.need and "ok" or (m.total >= m.need and "warn" or "bad")
      l.right:SetText(T.Color(m.bags .. " / " .. m.need, key))
    end
  end
  local unknown = false
  for _, r in ipairs(recipes) do if not r.known then unknown = true end end
  if ready and #mats > 0 then
    frame.title:SetText(T.Color("Ready to craft", "ok"))
  else
    frame.title:SetText(string.format("Tracking · %d to buy", missingAll))
  end
  local foot = {}
  if cost > 0 then foot[#foot + 1] = "Missing ~" .. Compat.Money(cost) end
  if unknown then foot[#foot + 1] = "? = reagents unknown" end
  frame.footer:SetText(table.concat(foot, "  ·  "))
  frame:SetHeight(26 + math.min(i, MAX_LINES) * 16 + (#foot > 0 and 22 or 8))
  frame:Show()
end

function TR:Show()
  RL.charDB.tracker.hidden = false
  self:Update()
  if not next(self:List()) then RL:Print("Nothing tracked. Guild tab -> Recipes, click a recipe to track it.") end
end

function TR:OnLogin()
  C_Timer.After(4, function() TR:Update() end)
end

local pending = false
local function soon()
  if pending or not next(RL.charDB and RL.charDB.tracker.recipes or {}) then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    TR:Update()
  end)
end
RL:On("BAG_UPDATE_DELAYED", soon)
RL:On("ITEM_DATA_LOAD_RESULT", soon)
RL:On("RL_RECIPES_UPDATED", soon)
