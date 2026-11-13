-- Readiness: checks your own buffs, bags and the Sleeping Bag, and works out
-- what needs your attention in the current context (solo / party / raid).
--
-- Event-driven: re-evaluates on aura / bag / context changes (coalesced), plus
-- one timer scheduled for the next moment something expires. No OnUpdate loop.
-- In combat nothing is evaluated (auras may be secret); results stay as they were.

local _, RL = ...
local R = RL:NewModule("Readiness")
RL.Readiness = R
local Compat = RL.Compat

R.results = {}        -- [checkId] = result table (see Evaluate)
R.restricted = false  -- true when buffs could not be read last time

local QUESTION_ICON = 134400 -- INV_Misc_QuestionMark

-- itemID -> { id = spellID, name = spellName }. Only hits are cached; a miss is
-- asked again next time (item data may still be loading).
local itemSpell = {}

local function spellForItem(itemID)
  local cached = itemSpell[itemID]
  if cached then return cached end
  local name, id = Compat.ItemSpell(itemID)
  if id and not Compat.IsSecret(id) then
    itemSpell[itemID] = { id = id, name = name }
    return itemSpell[itemID]
  end
  Compat.RequestItem(itemID)
  return nil
end

local function countItems(items)
  local total, first = 0, nil
  if not items then return 0, nil end
  for i = 1, #items do
    local n = Compat.ItemCount(items[i])
    if n > 0 then
      total = total + n
      first = first or items[i]
    end
  end
  return total, first
end

local function checkIcon(check, preferItem)
  if preferItem then return Compat.ItemIcon(preferItem) or QUESTION_ICON end
  if check.items and check.items[1] then return Compat.ItemIcon(check.items[1]) or QUESTION_ICON end
  return QUESTION_ICON
end

function R:IsTracked(checkId, mode)
  local t = RL.charDB.readiness.track[checkId]
  return t and t[mode] and true or false
end

-- Elixirs and flasks found in the bags by item class (not in our item lists).
-- Their spells are remembered in RL.db.learn.seen, so the buff is still
-- recognised after the last one is used.
local bagExtra = {} -- [checkId] = { total = n, first = itemID }

function R:IsIgnored(itemID)
  return RL.Data.IGNORED_CONSUMABLES[itemID] or (RL.db.ignoreItems and RL.db.ignoreItems[itemID] ~= nil) or false
end

-- Spell IDs and names of ignored items' buffs: these never satisfy a check.
local function ignoredSpells()
  local ids, names = {}, {}
  local function add(itemID)
    local s = spellForItem(itemID)
    if s then
      ids[s.id] = true
      if s.name then names[s.name] = true end
    end
  end
  for itemID in pairs(RL.Data.IGNORED_CONSUMABLES) do add(itemID) end
  for itemID in pairs(RL.db.ignoreItems or {}) do add(itemID) end
  return ids, names
end

local function scanBags()
  bagExtra = {}
  local listed = R.listedItems
  if not listed then
    listed = {}
    for _, check in ipairs(RL.Data.CHECKS) do
      for _, id in ipairs(check.items or {}) do listed[id] = true end
    end
    R.listedItems = listed
  end
  local seen = RL.db.learn.seen or {}
  RL.db.learn.seen = seen
  Compat.EachBagItem(function(itemID, count)
    local classID, sub = Compat.ItemClass(itemID)
    local checkId = classID == RL.Data.CONSUMABLE_CLASS and RL.Data.SUBCLASS_TO_CHECK[sub]
    if not checkId or R:IsIgnored(itemID) then return end
    if not listed[itemID] then
      local e = bagExtra[checkId] or { total = 0 }
      e.total = e.total + count
      e.first = e.first or itemID
      bagExtra[checkId] = e
    end
    local s = spellForItem(itemID)
    if s then
      seen[checkId] = seen[checkId] or {}
      seen[checkId][s.id] = s.name or true
    end
  end)
end

local function matchKnown(known, bySpell, byName)
  if not known then return nil end
  for spellId, name in pairs(known) do
    if bySpell[spellId] then return bySpell[spellId] end
    -- Same buff name from a different food or flask also counts.
    if type(name) == "string" and byName[name] then return byName[name] end
  end
  return nil
end

-- Looks for an active buff that satisfies the check.
local function findAura(check, bySpell, byName, learned)
  local hit = matchKnown(learned, bySpell, byName)
  if hit then return hit end
  local seen = RL.db.learn.seen
  hit = matchKnown(seen and seen[check.id], bySpell, byName)
  if hit then return hit end
  if check.kind == "food" then
    -- Every food gives a buff with the same name ("Well Fed" in English) but a
    -- different spell ID. Ask the game for the name of a known one: that is the
    -- name in the player's own language, so any food is found on any client.
    for spellId in pairs(RL.Data.FOOD_BUFF_SPELLS) do
      if bySpell[spellId] then return bySpell[spellId] end
      local localName = Compat.SpellName(spellId)
      if localName and not Compat.IsSecret(localName) and byName[localName] then return byName[localName] end
    end
    for name in pairs(RL.Data.FOOD_BUFF_NAMES) do
      if byName[name] then return byName[name] end
    end
    return nil
  end
  if check.items then
    for i = 1, #check.items do
      local s = spellForItem(check.items[i])
      if s then
        if bySpell[s.id] then return bySpell[s.id] end
        if s.name and byName[s.name] then return byName[s.name] end
      end
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Evaluation
-- ---------------------------------------------------------------------------
local wakeTimer

-- Minutes before the end at which a buff counts as "running out".
function R:WarnMinutes(check)
  local cfg = RL.charDB.readiness
  return tonumber(cfg.warn[check.id]) or check.warn or tonumber(cfg.warnMinutes) or 5
end

local function scheduleWake(seconds)
  if wakeTimer then wakeTimer:Cancel(); wakeTimer = nil end
  if seconds and seconds > 0 then
    wakeTimer = C_Timer.NewTimer(math.max(1, seconds), function()
      wakeTimer = nil
      R:Evaluate()
    end)
  end
end

function R:Evaluate()
  if not RL.charDB then return end
  if RL.Context.inCombat then return end

  local cfg = RL.charDB.readiness
  local now = GetTime()
  local buffs = Compat.GetPlayerBuffs()
  self.restricted = (buffs == nil)

  local bySpell, byName = {}, {}
  local skipId, skipName = ignoredSpells()
  if buffs then
    for i = 1, #buffs do
      local b = buffs[i]
      if not skipId[b.spellId] and not (b.name and skipName[b.name]) then
        bySpell[b.spellId] = b
        if b.name then byName[b.name] = b end
      end
    end
  end
  local learnedAll = RL.db.learn.known or {}
  scanBags()
  self.evaluatedAt = now

  local nextWake
  local anyExpiring = false
  local function wake(t)
    if t and t > 0 and (not nextWake or t < nextWake) then nextWake = t end
  end

  local results = {}
  for _, check in ipairs(RL.Data.CHECKS) do
    local res = { id = check.id, check = check }
    local kind = check.kind
    local warn = self:WarnMinutes(check) * 60

    -- Shared by every timed buff: active / expiring + when to wake up next.
    local function timed(left)
      res.left = left
      res.expires = now + left
      if left <= warn then
        res.status = "expiring"; anyExpiring = true; wake(left)
      else
        res.status = "active"; wake(left - warn)
      end
    end

    if kind == "food" or kind == "itemaura" then
      res.inBags, res.firstItem = countItems(check.items)
      local extra = bagExtra[check.id]
      if extra then
        res.inBags = res.inBags + extra.total
        res.firstItem = res.firstItem or extra.first
      end
      res.icon = checkIcon(check, res.firstItem)
      if not buffs then
        res.status = "unknown"
      else
        local aura = findAura(check, bySpell, byName, learnedAll[check.id])
        if aura then
          res.icon = aura.icon or res.icon
          res.auraName = aura.name
          if aura.expirationTime and aura.expirationTime > 0 then
            timed(aura.expirationTime - now)
          else
            res.status = "active"
          end
        else
          res.status = "missing"
        end
      end

    elseif kind == "weapon" then
      res.inBags, res.firstItem = countItems(check.items)
      res.icon = checkIcon(check, res.firstItem)
      local w = Compat.WeaponEnchants()
      if not w then
        res.status = "unknown"
      elseif w.main then
        timed(w.main)
      else
        res.status = "missing"
      end

    elseif kind == "count" then
      res.count, res.firstItem = countItems(check.items)
      res.icon = checkIcon(check, res.firstItem)
      res.want = tonumber(cfg.potionMin) or 5
      res.status = (res.count >= res.want) and "ok" or "low"

    elseif kind == "sleepingbag" then
      local item = RL.Data.SLEEPING_BAG_ITEM
      res.icon = Compat.ItemIcon(item) or QUESTION_ICON
      res.count = Compat.ItemCount(item)
      if res.count == 0 then
        res.status = "none"
      elseif RL.Context:IsMaxLevel() then
        res.status = "maxlevel"
      else
        local aura
        if buffs then
          for _, id in ipairs(RL.Data.SLEEPING_BAG_SPELLS) do
            aura = aura or bySpell[id]
          end
          local s = spellForItem(item)
          if not aura and s then aura = bySpell[s.id] end
        end
        local cd = Compat.ItemCooldownLeft(item)
        if aura then
          if aura.icon then res.icon = aura.icon end
          if aura.expirationTime and aura.expirationTime > 0 then
            timed(aura.expirationTime - now)
          else
            res.status = "active"
          end
        elseif cd > 0 then
          res.status = "cooldown"; res.left = cd; wake(cd)
        elseif RL.Context.resting then
          res.status = "resting"
        else
          res.status = "ready"
        end
      end
    end

    results[check.id] = res
  end

  self.results = results
  -- Refresh countdown text once a minute while something is about to expire.
  if anyExpiring then wake(60) end
  scheduleWake(nextWake)
  self:CheckReminders()
  RL:Fire("RL_READINESS_UPDATED")
end

-- ---------------------------------------------------------------------------
-- Reminders: one message per buff when it starts running out
-- ---------------------------------------------------------------------------
local reminded = {} -- [checkId] = expiry time we already reminded about

function R:CheckReminders()
  local cfg = RL.charDB.readiness
  if not cfg.remind then return end
  local mode = RL.Context.mode
  for _, check in ipairs(RL.Data.CHECKS) do
    local res = self.results[check.id]
    if res and res.status == "expiring" and res.expires and self:IsTracked(check.id, mode) then
      local prev = reminded[check.id]
      if not prev or math.abs(prev - res.expires) > 60 then
        reminded[check.id] = res.expires
        self:Remind(res)
      end
    end
  end
end

-- Shows the reminder in the middle of the screen and in chat, with a sound.
function R:Remind(res)
  local title, hint = self:Describe(res)
  local text = title .. (hint ~= "" and (" " .. hint) or "")
  local T = RL.Theme
  RL:Print(T.Color(text, "warn"))
  local c = T.c.warn
  local shown = false
  if RaidNotice_AddMessage and RaidWarningFrame then
    shown = pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = c[1], g = c[2], b = c[3] })
  end
  if not shown and UIErrorsFrame then
    pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, c[1], c[2], c[3])
  end
  if RL.charDB.readiness.remindSound and PlaySound then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
  end
end

-- "Test reminder" button in Settings.
-- /rq ignore: never count this item (and its buff) as an elixir or flask.
function R:Ignore(itemID, on)
  RL.db.ignoreItems = RL.db.ignoreItems or {}
  if on then
    RL.db.ignoreItems[itemID] = Compat.ItemName(itemID) or true
    local s = spellForItem(itemID)
    for _, ids in pairs(RL.db.learn.seen or {}) do
      if s then ids[s.id] = nil end
    end
  else
    RL.db.ignoreItems[itemID] = nil
  end
  self:Schedule()
end

function R:TestReminder()
  local food = RL.Data.CHECKS[1]
  self:Remind({ id = food.id, check = food, status = "expiring", left = self:WarnMinutes(food) * 60 })
end

-- ---------------------------------------------------------------------------
-- Presentation helpers shared by the HUD and the window
-- ---------------------------------------------------------------------------
local function minutes(sec)
  if not sec then return "" end
  if sec >= 3600 then return string.format("%dh %dm", math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
  if sec >= 60 then return string.format("%d min", math.floor(sec / 60 + 0.5)) end
  return "<1 min"
end
R.FormatTime = minutes

-- "miss" | "soon" | "tip" | nil (nil = nothing to say)
function R:AttentionKind(res)
  if not res then return nil end
  local s = res.status
  if s == "missing" or s == "low" then return "miss" end
  if s == "expiring" then return "soon" end
  if s == "ready" then return "tip" end
  return nil
end

-- headline, hint for the HUD
function R:Describe(res)
  local c = res.check
  local s = res.status
  if s == "expiring" then
    return c.expiring or c.name, "in " .. minutes(res.left)
  elseif s == "missing" then
    if res.inBags and res.inBags > 0 then
      local item = res.firstItem and Compat.ItemName(res.firstItem)
      if item and c.kind ~= "food" then return c.missing, string.format("%d in bags: %s", res.inBags, item) end
      return c.missing, string.format("You have %d in your bags", res.inBags)
    elseif c.kind == "food" and not RL.Context:IsMaxLevel() then
      return c.missing, "Cooked food gives +5% XP from kills"
    end
    return c.missing, ""
  elseif s == "low" then
    return c.missing, string.format("%d left, you want %d", res.count or 0, res.want or 0)
  elseif s == "ready" then
    return c.missing, "Rest for up to +3% XP"
  end
  return c.name, ""
end

-- Short status line for the Me tab: text, colorKey
function R:StatusLine(res)
  local s = res.status
  if s == "active" then
    return res.left and ("Active · " .. minutes(res.left)) or "Active", "ok"
  elseif s == "expiring" then
    return "Expiring · " .. minutes(res.left), "warn"
  elseif s == "missing" then
    if res.inBags and res.inBags > 0 then return string.format("Missing · %d in bags", res.inBags), "bad" end
    return "Missing", "bad"
  elseif s == "unknown" then
    return "Unknown right now", "muted"
  elseif s == "ok" then
    return string.format("%d in bags", res.count or 0), "ok"
  elseif s == "low" then
    return string.format("%d in bags (want %d)", res.count or 0, res.want or 0), "bad"
  elseif s == "none" then
    return "Not in your bags", "muted"
  elseif s == "maxlevel" then
    return "Not needed at max level", "muted"
  elseif s == "cooldown" then
    return "Cooldown · " .. minutes(res.left), "muted"
  elseif s == "resting" then
    return "Ready (not usable in town)", "info"
  elseif s == "ready" then
    return "Ready to use", "info"
  end
  return s or "", "muted"
end

-- What the HUD should list right now, in display order.
function R:Attention()
  local mode = RL.Context.mode
  local hud = RL.charDB.hud
  if mode == "solo" and RL.Context.resting and hud.quietInTownSolo then return {} end
  local out = {}
  for _, check in ipairs(RL.Data.CHECKS) do
    local res = self.results[check.id]
    if res and self:IsTracked(check.id, mode) and self:AttentionKind(res) then
      out[#out + 1] = res
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local pending = false
function R:Schedule(delay)
  if pending then return end
  pending = true
  C_Timer.After(delay or 0.25, function()
    pending = false
    R:Evaluate()
  end)
end

function R:Init()
  local track = RL.charDB.readiness.track
  for _, check in ipairs(RL.Data.CHECKS) do
    if type(track[check.id]) ~= "table" then
      track[check.id] = { solo = check.defaults.solo, party = check.defaults.party, raid = check.defaults.raid }
    end
  end
end

function R:OnLogin()
  self:Schedule(2) -- item data and auras settle shortly after login
end

RL:On("UNIT_AURA", function(unit)
  if unit == "player" then R:Schedule() end
end)
RL:On("UNIT_INVENTORY_CHANGED", function(unit)
  if unit == "player" then R:Schedule() end
end)
RL:On("BAG_UPDATE_DELAYED", function() R:Schedule() end)
RL:On("BAG_UPDATE_COOLDOWN", function() R:Schedule(0.5) end)
RL:On("PLAYER_LEVEL_UP", function() R:Schedule(1) end)
RL:On("RL_CONTEXT_CHANGED", function() R:Schedule() end)
RL:On("ITEM_DATA_LOAD_RESULT", function(itemID)
  if not itemSpell[itemID] then R:Schedule(1) end
end)
