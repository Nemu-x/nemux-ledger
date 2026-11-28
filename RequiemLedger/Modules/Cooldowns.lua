-- Cooldowns: profession cooldowns (Mooncloth, transmutes, Salt Shaker...) for
-- all your characters and for guild mates with Nemux Ledger.
--
-- Message: T|1|<ver>|<key>:<readyAt>,...
--   key = recipe (spell) ID, or "i<itemID>" for an item with a cooldown.
--   readyAt = server time when it is ready again, 0 = ready now.
--   Sent with hello, to a guild mate who says hello, and when one changes.
-- New cooldown recipes Forever may add are picked up when the game shows them
-- on cooldown in your profession window.

local _, RL = ...
local CD = RL:NewModule("Cooldowns")
RL.Cooldowns = CD

local Compat = RL.Compat
local PROTO = "1"
local MAX_KEYS = 12
local FAR = 30 * 86400 -- no profession cooldown is longer than this

-- Known cooldown recipes: [spellID] = skill line.
CD.RECIPES = {
  [18560] = 197, -- Mooncloth
  [17187] = 171, -- Transmute: Arcanite
  [11479] = 171, -- Transmute: Iron to Gold
  [11480] = 171, -- Transmute: Mithril to Truesilver
  [17559] = 171, [17560] = 171, [17561] = 171, [17562] = 171, -- elemental transmutes
  [17563] = 171, [17564] = 171, [17565] = 171, [17566] = 171,
}
-- Items with a cooldown: [itemID] = name if the game has none yet.
CD.ITEMS = {
  [15846] = "Salt Shaker",
}

local secret = Compat.IsSecret

local function num(v) return type(v) == "number" and not secret(v) end

-- Seconds left on a recipe, 0 when ready, nil when the game won't say.
local function recipeLeft(id)
  local best
  if C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown then
    local ok, s = pcall(C_TradeSkillUI.GetRecipeCooldown, id)
    if ok and num(s) then best = math.max(0, s) end
  end
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if ok and type(info) == "table" and num(info.startTime) and num(info.duration) then
      local left = 0
      if info.duration > 2 and info.startTime > 0 then left = math.max(0, info.startTime + info.duration - GetTime()) end
      best = math.max(best or 0, left)
    end
  end
  return best
end

local function itemLeft(itemID)
  local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  if not fn then return nil end
  local ok, start, duration = pcall(fn, itemID)
  if not (ok and num(start) and num(duration)) then return nil end
  if duration > 2 and start > 0 then return math.max(0, start + duration - GetTime()) end
  return 0
end

local function hasItem(itemID)
  local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not fn then return false end
  local ok, n = pcall(fn, itemID, true)
  return ok and num(n) and n > 0
end

local function knowsRecipe(id)
  for _, rec in pairs(RL.charDB.recipes) do
    if type(rec) == "table" and rec.ids and rec.ids[id] then return true end
  end
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, id)
    if ok and v == true then return true end
  end
  return false
end

-- Every recipe that has a cooldown (known list + ones seen in game).
local function allRecipes()
  local out = {}
  for id, line in pairs(CD.RECIPES) do out[id] = line end
  for id, line in pairs(RL.db.cdRecipes) do out[id] = line end
  return out
end

function CD:Name(key)
  if type(key) == "string" then
    local itemID = tonumber(key:match("^i(%d+)$"))
    return (itemID and (Compat.ItemName and Compat.ItemName(itemID))) or (itemID and CD.ITEMS[itemID]) or key
  end
  return RL.Recipes:RecipeName(key)
end

-- ---------------------------------------------------------------------------
-- My cooldowns
-- ---------------------------------------------------------------------------
-- Reads my cooldowns into my character record. Returns true when something changed.
function CD:Scan()
  if InCombatLockdown and InCombatLockdown() then return false end
  local me = RL.DB:Me()
  if not me then return false end
  local now = GetServerTime()
  local old = type(me.cds) == "table" and me.cds or {}
  local cds = {}
  for id in pairs(allRecipes()) do
    if knowsRecipe(id) then
      local left = recipeLeft(id)
      if left then cds[id] = left > 0 and math.floor(now + left) or 0
      elseif old[id] then cds[id] = old[id] end -- keep the last known value
    end
  end
  for itemID in pairs(CD.ITEMS) do
    local key = "i" .. itemID
    if hasItem(itemID) then
      local left = itemLeft(itemID)
      if left then cds[key] = left > 0 and math.floor(now + left) or 0
      elseif old[key] then cds[key] = old[key] end
    end
  end
  local changed = false
  for k, v in pairs(cds) do
    if not old[k] or math.abs(old[k] - v) > 60 then changed = true end
  end
  for k in pairs(old) do if cds[k] == nil then changed = true end end
  me.cds = cds
  if changed then RL:Fire("RL_COOLDOWNS_UPDATED") end
  return changed
end

-- Cooldown recipes Forever adds: any of my recipes the game shows on cooldown.
function CD:Discover()
  if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown) then return end
  local found = false
  for line, rec in pairs(RL.charDB.recipes) do
    if type(rec) == "table" and rec.ids then
      for id in pairs(rec.ids) do
        if not CD.RECIPES[id] and not RL.db.cdRecipes[id] then
          local ok, s = pcall(C_TradeSkillUI.GetRecipeCooldown, id)
          if ok and num(s) and s > 0 and s <= FAR then
            RL.db.cdRecipes[id] = line
            found = true
          end
        end
      end
    end
  end
  return found
end

function CD:Message()
  local me = RL.DB:Me()
  local parts = {}
  local now = GetServerTime()
  for k, v in pairs(me and me.cds or {}) do
    if #parts < MAX_KEYS then
      parts[#parts + 1] = string.format("%s:%d", tostring(k), v > now and v or 0)
    end
  end
  table.sort(parts)
  return table.concat({ "T", PROTO, RL.version, table.concat(parts, ",") }, "|")
end

function CD:Share(channel, target)
  if not IsInGuild() then return end
  RL.Guild:Queue(self:Message(), channel or "GUILD", target)
end

-- Returns the sender's version when the message was valid.
function CD.OnMessage(who, _, _, msg)
  local proto, version, list = msg:match("^T|(%d+)|(%d+%.%d+%.%d+)|([%di:,]*)$")
  if proto ~= PROTO then return nil end
  local now = GetServerTime()
  local cds, n = {}, 0
  for entry in list:gmatch("[^,]+") do
    local item, id, ready = entry:match("^(i?)(%d+):(%d+)$")
    id, ready = tonumber(id), tonumber(ready)
    if not id or id > 10000000 or ready > now + FAR then return nil end
    n = n + 1
    if n > MAX_KEYS then return nil end
    cds[item == "i" and ("i" .. id) or id] = ready
  end
  RL.db.guildCDs[who] = { at = now, list = cds }
  RL:Fire("RL_COOLDOWNS_UPDATED")
  return version
end

-- ---------------------------------------------------------------------------
-- Rows for the UI: { key, name, who, classFile, online, mine, readyAt }
-- ---------------------------------------------------------------------------
function CD:Rows()
  local G = RL.Guild
  local rows, seen = {}, {}
  local myGuid = UnitGUID("player")
  for guid, rec in pairs(RL.db.chars) do
    if type(rec) == "table" and type(rec.cds) == "table" and rec.name then
      local short = G.Short(rec.name)
      seen[short] = true
      for k, v in pairs(rec.cds) do
        rows[#rows + 1] = { key = k, name = self:Name(k), who = guid == myGuid and "you" or short, me = guid == myGuid,
          mine = true, classFile = rec.class, online = guid == myGuid, readyAt = v }
      end
    end
  end
  for who, rec in pairs(RL.db.guildCDs) do
    local short = G.Short(who)
    local row = G.byName[who]
    local myAlt = row and row.guid and RL.db.chars[row.guid] ~= nil -- already listed above
    if not G:IsMe(who) and not myAlt and not seen[short] and type(rec) == "table" and type(rec.list) == "table" then
      for k, v in pairs(rec.list) do
        rows[#rows + 1] = { key = k, name = self:Name(k), who = short, classFile = row and row.classFile,
          online = row and row.online or false, readyAt = v, at = rec.at }
      end
    end
  end
  local now = GetServerTime()
  table.sort(rows, function(a, b)
    local ra, rb = math.max(a.readyAt - now, 0), math.max(b.readyAt - now, 0)
    if ra ~= rb then return ra < rb end
    if a.name ~= b.name then return a.name < b.name end
    return a.who < b.who
  end)
  return rows
end

-- "Ready", "45m", "3h 12m", "2d 4h"
function CD.Left(readyAt)
  local s = (readyAt or 0) - GetServerTime()
  if s <= 0 then return nil end
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  if d > 0 then return string.format("%dd %dh", d, h) end
  if h > 0 then return string.format("%dh %dm", h, m) end
  return string.format("%dm", math.max(1, m))
end

-- ---------------------------------------------------------------------------
-- "Mooncloth is ready" in chat
-- ---------------------------------------------------------------------------
local told = {} -- [guid .. key] = readyAt we already announced

function CD:Announce(atLogin)
  if not RL.charDB.cooldowns.notify then return end
  local now = GetServerTime()
  local ready = {}
  local myGuid = UnitGUID("player")
  for guid, rec in pairs(RL.db.chars) do
    if type(rec) == "table" and type(rec.cds) == "table" then
      for k, v in pairs(rec.cds) do
        local tag = guid .. "#" .. tostring(k)
        if v > 0 and v <= now and told[tag] ~= v then
          told[tag] = v
          local name = self:Name(k)
          ready[#ready + 1] = guid == myGuid and name or (name .. " (" .. RL.Guild.Short(rec.name or "?") .. ")")
        elseif atLogin and v == 0 then
          told[tag] = 0
        end
      end
    end
  end
  if #ready > 0 then
    table.sort(ready)
    RL:Print("|cff4fd16eReady again:|r %s", table.concat(ready, ", "))
  end
end

function CD:Prune()
  local G = RL.Guild
  if not IsInGuild() or G.total == 0 then return end
  for who in pairs(RL.db.guildCDs) do
    if not G.byName[who] then RL.db.guildCDs[who] = nil end
  end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function CD:Init()
  RL.Guild.handlers.T = CD.OnMessage
end

local function tick()
  if CD:Scan() then CD:Share("GUILD") end
  CD:Announce(false)
  C_Timer.After(60, tick)
end

function CD:OnLogin()
  C_Timer.After(6, function()
    CD:Scan()
    CD:Announce(true)
    C_Timer.After(60, tick)
  end)
end

local pending = false
local function soon()
  if pending then return end
  pending = true
  C_Timer.After(3, function()
    pending = false
    CD:Discover()
    if CD:Scan() then CD:Share("GUILD") end
  end)
end

RL:On("TRADE_SKILL_LIST_UPDATE", soon)
RL:On("TRADE_SKILL_SHOW", soon)
RL:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit ~= "player" or not num(spellID) then return end
  if CD.RECIPES[spellID] or RL.db.cdRecipes[spellID] then
    RL:Fire("RL_COOLDOWN_USED", spellID)
    soon()
  end
end)
RL:On("BAG_UPDATE_COOLDOWN", soon)
RL:On("RL_HELLO_SENT", function() C_Timer.After(9, function() CD:Share("GUILD") end) end)
RL:On("RL_PEER_HELLO", function(sender) CD:Share("WHISPER", sender) end)
local pruned = false
RL:On("RL_GUILD_UPDATED", function()
  if not pruned and RL.Guild.total > 0 then
    pruned = true
    CD:Prune()
  end
end)
