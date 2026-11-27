-- Loot log: who got which item, read from loot addons. Nemux Ledger never
-- distributes loot itself; it only listens.
--
-- Sources (each one optional; nothing happens when the addon is missing):
--   Gargul        global `Gargul`, events GL.ITEM_AWARDED / GL.ITEM_AWARD_EDITED /
--                 GL.ITEM_UNAWARDED (payload: the award entry, keyed by checksum),
--                 history in Gargul.DB.AwardHistory. Fires on every raid member.
--   RCLootCouncil comm "history" (every group member hears it), the ML's
--                 RCMLLootHistorySend message, and its saved history
--                 RCLootCouncilLootDB, read passively. See the RCLC section.
-- These are other addons' internals, not official APIs: every access is guarded.
--
-- RL.db.loot = { [key] = { key, ts, itemID, link, to, by, os, sr, roll, boss, source,
--                           RCLC only: color, instance, note, votes } }

local _, RL = ...
local L = RL:NewModule("Loot")
RL.Loot = L

local MAX_ENTRIES = 1000
local lastBoss -- { name, ts } of the last boss kill, to label awards

-- ---------------------------------------------------------------------------
-- Cleaning what other addons hand us
-- ---------------------------------------------------------------------------
local function cleanName(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub("|", "")
  if name == "" or #name > 80 then return nil end
  return name
end

-- Accept only a plain item link; anything else is rebuilt from the item ID.
local function cleanLink(link)
  if type(link) ~= "string" then return nil end
  if link:match("^|c%x+|Hitem:[%-%d:]+|h%[[^|%]]+%]|h|r$") then return link end
  return nil
end

local function itemIDFrom(link)
  return type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
end

function L:LinkFor(e)
  if e.link then return e.link end
  if e.itemID and C_Item and C_Item.GetItemInfo then
    local ok, _, link = pcall(C_Item.GetItemInfo, e.itemID)
    if ok and cleanLink(link) then
      e.link = link
      return link
    end
    RL.Compat.RequestItem(e.itemID)
  end
  return nil
end

-- Item name without colour codes (for the Discord report).
function L:ItemName(e)
  local link = self:LinkFor(e)
  local name = link and link:match("%[(.-)%]") or RL.Compat.ItemName(e.itemID or 0)
  return name or ("item " .. tostring(e.itemID))
end

-- ---------------------------------------------------------------------------
-- Store
-- ---------------------------------------------------------------------------
local function trim()
  local all = RL.db.loot
  local n, oldest, oldestKey = 0, nil, nil
  for key, e in pairs(all) do
    n = n + 1
    if not oldest or (e.ts or 0) < oldest then oldest, oldestKey = e.ts or 0, key end
  end
  if n > MAX_ENTRIES and oldestKey then all[oldestKey] = nil; trim() end
end

local function boss(ts)
  if lastBoss and ts and math.abs(ts - lastBoss.ts) < 15 * 60 then return lastBoss.name end
  return nil
end

function L:Put(e)
  if not (e.key and e.to and (e.itemID or e.link)) then return end
  local old = RL.db.loot[e.key]
  e.boss = e.boss or (old and old.boss) or boss(e.ts)
  e.by = e.by or (old and old.by)
  RL.db.loot[e.key] = e
  if not old then trim() end
  RL:Fire("RL_LOOT_UPDATED")
end

function L:Remove(key)
  if key and RL.db.loot[key] then
    RL.db.loot[key] = nil
    RL:Fire("RL_LOOT_UPDATED")
  end
end

-- Newest first, optionally filtered by text (player or item) and a start time.
function L:List(query, since)
  query = (query or ""):lower()
  local out = {}
  for _, e in pairs(RL.db.loot) do
    if (not since or (e.ts or 0) >= since) then
      local hit = query == "" or (e.to or ""):lower():find(query, 1, true)
        or self:ItemName(e):lower():find(query, 1, true)
      if hit then out[#out + 1] = e end
    end
  end
  table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
  return out
end

-- ---------------------------------------------------------------------------
-- Gargul
-- ---------------------------------------------------------------------------
local function fromGargul(a)
  if type(a) ~= "table" or a.checksum == nil then return nil end
  local link = cleanLink(a.itemLink)
  return {
    key = "G:" .. tostring(a.checksum):sub(1, 64),
    source = "Gargul",
    ts = tonumber(a.timestamp) or GetServerTime(),
    itemID = tonumber(a.itemID) or itemIDFrom(link),
    link = link,
    to = cleanName(a.awardedTo),
    by = cleanName(a.awardedBy),
    os = a.OS == true,
    sr = a.SR == true,
    roll = cleanName(a.winningRollType),
  }
end

function L:ImportGargul()
  local G = _G.Gargul
  local hist = type(G) == "table" and type(G.DB) == "table" and G.DB.AwardHistory
  if type(hist) ~= "table" then return 0 end
  local n = 0
  for _, a in pairs(hist) do
    local e = fromGargul(a)
    if e and e.to then
      local old = RL.db.loot[e.key]
      if not old or old.to ~= e.to or old.os ~= e.os then
        e.boss = old and old.boss
        RL.db.loot[e.key] = e
        n = n + 1
      end
    end
  end
  if n > 0 then trim(); RL:Fire("RL_LOOT_UPDATED") end
  return n
end

local gargulHooked = false
function L:HookGargul()
  if gargulHooked then return true end
  local G = _G.Gargul
  local ev = type(G) == "table" and G.Events
  if type(ev) ~= "table" or type(ev.register) ~= "function" then return false end
  local function put(_, a) local e = fromGargul(a); if e then L:Put(e) end end
  local ok = pcall(ev.register, ev, "RequiemLedgerAwarded", "GL.ITEM_AWARDED", put)
  ok = pcall(ev.register, ev, "RequiemLedgerEdited", "GL.ITEM_AWARD_EDITED", put) and ok
  ok = pcall(ev.register, ev, "RequiemLedgerUnawarded", "GL.ITEM_UNAWARDED", function(_, a)
    if type(a) == "table" and a.checksum ~= nil then L:Remove("G:" .. tostring(a.checksum):sub(1, 64)) end
  end) and ok
  gargulHooked = ok
  if ok then L:ImportGargul() end
  return ok
end

-- ---------------------------------------------------------------------------
-- RCLootCouncil (3.26+, has a Forever build)
-- ---------------------------------------------------------------------------
-- Live: RCLC's documented comm "history" (prefix RCLC). The master looter sends
-- it to the whole group (default) or the guild after every award, so every
-- raid member with RCLC hears it. Payload: { winner, historyEntry }.
-- "delete_history" { id } removes an entry. The ML also fires the AceEvent
-- message RCMLLootHistorySend(entry, winner) locally, which covers the case
-- where "send history" is turned off. Entries share the key "R:<entry.id>",
-- so whichever arrives first wins and the rest just update it.
-- Passive: the saved history RCLootCouncilLootDB.factionrealm[fr][player] = { entries }.

-- "2026/11/13" + "21:05:09" -> epoch. Only a fallback: entry.id starts with GetServerTime().
local function rcTime(d, t)
  if type(d) ~= "string" then return nil end
  local y, m, day = d:match("^(%d+)/(%d+)/(%d+)$")
  if not y then return nil end
  local h, mi, s = (type(t) == "string" and t or ""):match("^(%d+):(%d+):(%d+)$")
  y = tonumber(y); if y < 100 then y = y + 2000 end
  local ok, v = pcall(time, { year = y, month = tonumber(m), day = tonumber(day),
    hour = tonumber(h) or 12, min = tonumber(mi) or 0, sec = tonumber(s) or 0 })
  return ok and v or nil
end

local function cleanText(s, max)
  if type(s) ~= "string" then return nil end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
  s = s:match("^%s*(.-)%s*$")
  if s == "" then return nil end
  return #s > (max or 60) and s:sub(1, max or 60) or s
end

local function cleanColor(c)
  if type(c) ~= "table" then return nil end
  local r, g, b = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
  if not (r and g and b) then return nil end
  local function clamp(v) return math.max(0, math.min(1, v)) end
  return { clamp(r), clamp(g), clamp(b) }
end

local OS_WORDS = { "off", "greed", "^os", "transmog", "pvp" }
local function isOffspec(responseID, text)
  if responseID == 2 then return true end
  local t = (text or ""):lower()
  for _, w in ipairs(OS_WORDS) do if t:find(w) then return true end end
  return false
end

-- One RCLC history entry -> our entry (nil when it is not usable).
function L.FromRCLC(winner, h, sender)
  if type(h) ~= "table" or h.id == nil then return nil end
  local id = tostring(h.id):sub(1, 64)
  local link = cleanLink(h.lootWon)
  local itemID = itemIDFrom(h.lootWon)
  local to = cleanName(winner)
  if not (to and (link or itemID)) then return nil end
  local rid = h.responseID
  if rid == "PL" or rid == "PL_REJECT" or rid == "BONUSROLL" or rid == "BONUS_ROLL" then return nil end
  local response = cleanText(h.response, 40)
  return {
    key = "R:" .. id,
    source = "RCLootCouncil",
    ts = tonumber(id:match("^(%d+)")) or rcTime(h.date, h.time) or GetServerTime(),
    itemID = itemID, link = link, to = to,
    by = cleanName(sender),
    os = isOffspec(tonumber(rid), response),
    roll = response,
    color = cleanColor(h.color),
    boss = cleanText(h.boss, 60),
    instance = cleanText(h.instance, 60),
    note = cleanText(h.note, 120),
    votes = tonumber(h.votes),
  }
end

function L:ImportRCLC()
  local db = _G.RCLootCouncilLootDB
  local fr = type(db) == "table" and db.factionrealm
  if type(fr) ~= "table" then return 0 end
  local faction = RL.Context:Faction()
  local n = 0
  for frKey, players in pairs(fr) do
    if type(players) == "table" and (not faction or tostring(frKey):find(faction, 1, true)) then
      for player, entries in pairs(players) do
        if type(entries) == "table" then
          for _, h in ipairs(entries) do
            local e = L.FromRCLC(player, h)
            if e then
              local old = RL.db.loot[e.key]
              -- New, or edited in RCLC's history window (winner or response changed).
              if not old or old.to ~= e.to or old.roll ~= e.roll then
                e.by = old and old.by
                RL.db.loot[e.key] = e
                n = n + 1
              end
            end
          end
        end
      end
    end
  end
  if n > 0 then trim(); RL:Fire("RL_LOOT_UPDATED") end
  return n
end

local rclcHooked, rclcLive = false, false
function L:HookRCLC()
  if rclcHooked then return true end
  local RC = _G.RCLootCouncil
  if type(RC) ~= "table" then return false end

  -- 1) Comms: heard by every group member.
  local okReq, Comms = pcall(function() return RC.Require("Services.Comms") end)
  local prefix = type(RC.PREFIXES) == "table" and RC.PREFIXES.MAIN or "RCLC"
  if okReq and type(Comms) == "table" and type(Comms.Subscribe) == "function" then
    local ok1 = pcall(Comms.Subscribe, Comms, prefix, "history", function(data, sender)
      if type(data) ~= "table" then return end
      local e = L.FromRCLC(data[1], data[2], sender)
      if e then L:Put(e) end
    end)
    local ok2 = pcall(Comms.Subscribe, Comms, prefix, "delete_history", function(data)
      if type(data) == "table" and data[1] ~= nil then L:Remove("R:" .. tostring(data[1]):sub(1, 64)) end
    end)
    rclcLive = ok1 and ok2
  end

  -- 2) AceEvent messages: the ML's own copy, and edits made in RCLC's history window.
  local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
  if AceEvent then
    local listener = {}
    if pcall(AceEvent.Embed, AceEvent, listener) and type(listener.RegisterMessage) == "function" then
      listener:RegisterMessage("RCMLLootHistorySend", function(_, h, winner)
        local e = L.FromRCLC(winner, h)
        if e then L:Put(e) end
      end)
      local reimport = function() C_Timer.After(0.5, function() L:ImportRCLC() end) end
      listener:RegisterMessage("RCHistory_NameEdit", reimport)
      listener:RegisterMessage("RCHistory_ResponseEdit", reimport)
      listener:RegisterMessage("RCUpdateDB", reimport)
      rclcLive = true
    end
  end

  rclcHooked = true
  L:ImportRCLC()
  return true
end

-- True when RCLC is hooked live (not only its saved history).
function L:RCLCLive() return rclcHooked and rclcLive end

-- Which loot addons we listen to right now.
function L:Sources()
  local s = {}
  if gargulHooked then s[#s + 1] = "Gargul" end
  if rclcHooked then s[#s + 1] = "RCLootCouncil" end
  return s
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local function hookAll()
  L:HookGargul()
  L:HookRCLC()
end

function L:OnLogin()
  C_Timer.After(2, hookAll)
  C_Timer.After(15, hookAll) -- loot addons may finish setting up late
end

RL:On("ADDON_LOADED", function(name)
  if name == "Gargul" or name == "RCLootCouncil" or name == "RCLootCouncil_Classic" or name == "RCLootCouncil_Forever" then
    C_Timer.After(1, hookAll)
  end
end)
RL:On("ENCOUNTER_END", function(_, name, _, _, success)
  if success == 1 and type(name) == "string" then lastBoss = { name = name, ts = GetServerTime() } end
end)
RL:On("ITEM_DATA_LOAD_RESULT", function() RL:Fire("RL_LOOT_UPDATED") end)

-- Short coloured label for the Response column: RCLC's own response text and
-- colour when there is one ("Mainspec/Need" -> "Mainspec"), else MS/OS/SR.
function L:TagText(e)
  if e.roll and e.source == "RCLootCouncil" then
    local short = e.roll:match("^([^/]+)") or e.roll
    if #short > 14 then short = short:sub(1, 13) .. "." end
    local c = e.color
    if c then
      local function b(v) return math.floor(v * 255 + 0.5) end
      return string.format("|cff%02x%02x%02x%s|r", b(c[1]), b(c[2]), b(c[3]), short)
    end
    return short
  end
  return e.os and "OS" or (e.sr and "SR" or "MS")
end
