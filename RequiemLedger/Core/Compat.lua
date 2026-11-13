-- Thin layer over client APIs.
-- WoW: Forever runs the Midnight (12.x) API with "secret values": during combat,
-- boss encounters and some instances, aura data can be secret. Secret values
-- cannot be compared or stored, so every read goes through here and comes back
-- either as a plain value or as nil + "unknown".

local _, RL = ...
local Compat = {}
RL.Compat = Compat

local issecretvalue = _G.issecretvalue

function Compat.IsSecret(v)
  return issecretvalue ~= nil and v ~= nil and issecretvalue(v) == true
end

-- True when the client says player auras are currently hidden from addons.
function Compat.AurasRestricted()
  if C_Secrets and C_Secrets.ShouldAurasBeSecret then
    local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
    if ok and secret == true then return true end
  end
  return false
end

-- Returns a plain list of the player's helpful auras, or nil when they are secret.
-- Each entry: { spellId, name, icon, duration, expirationTime }
function Compat.GetPlayerBuffs()
  if Compat.AurasRestricted() then return nil end
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  local list = {}
  for i = 1, 255 do
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not ok then return nil end
    if not aura then break end
    if Compat.IsSecret(aura.spellId) or Compat.IsSecret(aura.name) or Compat.IsSecret(aura.expirationTime) then
      return nil
    end
    list[#list + 1] = {
      spellId = aura.spellId,
      name = aura.name,
      icon = aura.icon,
      duration = aura.duration or 0,
      expirationTime = aura.expirationTime or 0,
    }
  end
  return list
end

function Compat.ItemCount(itemID)
  if C_Item and C_Item.GetItemCount then
    local ok, n = pcall(C_Item.GetItemCount, itemID, false, false)
    if ok and type(n) == "number" and not Compat.IsSecret(n) then return n end
  end
  return 0
end

-- Reagents of a recipe: { { itemID, count }, ... }, or nil when the game
-- does not say. Only basic, required reagents (Enum.CraftingReagentType 1).
function Compat.RecipeReagents(recipeID)
  if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return nil end
  local ok, s = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
  if not ok or type(s) ~= "table" or type(s.reagentSlotSchematics) ~= "table" then return nil end
  local out = {}
  for _, slot in ipairs(s.reagentSlotSchematics) do
    local basic = slot.reagentType == nil or slot.reagentType == 1
    local r = type(slot.reagents) == "table" and slot.reagents[1]
    if basic and slot.required ~= false and r and type(r.itemID) == "number" and not Compat.IsSecret(r.itemID) then
      local n = tonumber(slot.quantityRequired) or 1
      if not Compat.IsSecret(n) then out[#out + 1] = { r.itemID, n } end
    end
  end
  if #out == 0 then return nil end
  return out
end

-- Approximate price of one item, from Auctionator's public API (also answered
-- by NaowhForever when Auctionator itself is not installed). Copper, source
-- ("vendor" | "AH"), age of the AH price in days (or nil). nil when unknown.
function Compat.Price(itemID)
  local api = type(Auctionator) == "table" and type(Auctionator.API) == "table" and Auctionator.API.v1
  if type(api) ~= "table" then return nil end
  local function call(name)
    local fn = api[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, "RequiemLedger", itemID)
    if ok and type(v) == "number" and v > 0 and not Compat.IsSecret(v) then return v end
    return nil
  end
  local vendor = call("GetVendorPriceByItemID")
  if vendor then return vendor, "vendor", nil end
  local ah = call("GetAuctionPriceByItemID")
  if ah then return ah, "AH", call("GetAuctionAgeByItemID") end
  return nil
end

-- 12345 copper -> "1g 23s 45c" (short: no copper above 1 gold).
function Compat.Money(copper)
  copper = math.floor((copper or 0) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return s > 0 and string.format("%dg %ds", g, s) or (g .. "g") end
  if s > 0 then return c > 0 and string.format("%ds %dc", s, c) or (s .. "s") end
  return c .. "c"
end

-- Count in bags, and in bags + bank (the bank count is the last one the game saw).
function Compat.ItemCounts(itemID)
  if not (C_Item and C_Item.GetItemCount) then return 0, 0 end
  local ok1, bags = pcall(C_Item.GetItemCount, itemID, false)
  local ok2, all = pcall(C_Item.GetItemCount, itemID, true)
  bags = (ok1 and type(bags) == "number" and not Compat.IsSecret(bags)) and bags or 0
  all = (ok2 and type(all) == "number" and not Compat.IsSecret(all)) and all or bags
  return bags, math.max(all, bags)
end

-- classID, subClassID of an item (works without the item being cached).
function Compat.ItemClass(itemID)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return nil, nil end
  local ok, _, _, _, _, _, classID, subClassID = pcall(fn, itemID)
  if ok then return classID, subClassID end
  return nil, nil
end

-- Calls fn(itemID, count) for every stack in the backpack and bags.
-- Returns false when the container API is missing.
function Compat.EachBagItem(fn)
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return false end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do -- +1: the reagent bag, when there is one
    local okN, slots = pcall(C_Container.GetContainerNumSlots, bag)
    if okN and type(slots) == "number" then
      for slot = 1, slots do
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" and info.itemID and not Compat.IsSecret(info.itemID) then
          fn(info.itemID, info.stackCount or 1)
        end
      end
    end
  end
  return true
end

-- spellName, spellID of the effect an item applies (e.g. a flask's aura).
function Compat.ItemSpell(itemID)
  if C_Item and C_Item.GetItemSpell then
    local ok, name, id = pcall(C_Item.GetItemSpell, itemID)
    if ok then return name, id end
  end
  return nil, nil
end

function Compat.ItemIcon(itemID)
  if C_Item and C_Item.GetItemIconByID then
    local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
    if ok then return icon end
  end
  return nil
end

function Compat.ItemName(itemID)
  if C_Item and C_Item.GetItemNameByID then
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if ok then return name end
  end
  return nil
end

function Compat.RequestItem(itemID)
  if C_Item and C_Item.IsItemDataCachedByID and C_Item.RequestLoadItemDataByID then
    if not C_Item.IsItemDataCachedByID(itemID) then
      pcall(C_Item.RequestLoadItemDataByID, itemID)
      return false
    end
    return true
  end
  return true
end

-- Remaining cooldown in seconds for an item (0 when ready).
function Compat.ItemCooldownLeft(itemID)
  local fn = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown)
  if not fn then return 0 end
  local ok, start, duration = pcall(fn, itemID)
  if not ok or not start or Compat.IsSecret(start) or Compat.IsSecret(duration) then return 0 end
  if start > 0 and duration and duration > 1.5 then
    local left = start + duration - GetTime()
    return left > 0 and left or 0
  end
  return 0
end

function Compat.SpellName(spellID)
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok then return name end
  end
  return nil
end

-- Your professions: { name, icon, rank, max, skillLine }, main and secondary mixed.
function Compat.MyProfessions()
  local out = {}
  if not (GetProfessions and GetProfessionInfo) then return out end
  local ok, a, b, c, d, e, f = pcall(GetProfessions)
  if not ok then return out end
  local idx = { a, b, c, d, e, f }
  for i = 1, 6 do
    if idx[i] then
      local okInfo, name, icon, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, idx[i])
      if okInfo and name then
        out[#out + 1] = { name = name, icon = icon, rank = rank or 0, max = maxRank or 300, skillLine = skillLine }
      end
    end
  end
  return out
end

-- Main hand / off hand temporary enchants (oils, stones). Seconds left or nil.
function Compat.WeaponEnchants()
  if not GetWeaponEnchantInfo then return nil end
  local ok, hasMain, mainExp, _, _, hasOff, offExp = pcall(GetWeaponEnchantInfo)
  if not ok or Compat.IsSecret(hasMain) then return nil end
  return {
    main = hasMain and (mainExp or 0) / 1000 or nil,
    off = hasOff and (offExp or 0) / 1000 or nil,
  }
end

function Compat.Has(path)
  local t = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(t) ~= "table" then return false end
    t = t[part]
  end
  return t ~= nil
end
