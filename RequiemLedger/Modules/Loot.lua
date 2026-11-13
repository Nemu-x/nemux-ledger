-- Loot log: who got which item, read from loot addons. Nemux Ledger never
-- distributes loot itself; it only listens.
--
-- Sources (each one optional; nothing happens when the addon is missing):
--   Gargul        global `Gargul`, events GL.ITEM_AWARDED / GL.ITEM_AWARD_EDITED /
--                 GL.ITEM_UNAWARDED (payload: the award entry, keyed by checksum),
--                 history in Gargul.DB.AwardHistory. Fires on every raid member.
--   RCLootCouncil AceEvent message RCMLAwardSuccess (master looter only), and its
--                 saved history RCLootCouncilLootDB, read passively.
-- These are other addons' internals, not official APIs: every access is guarded.
--
-- RL.db.loot = { [key] = { key, ts, itemID, link, to, by, os, sr, roll, boss, source } }

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
-- RCLootCouncil (prepared; it may not run on every client)
-- ---------------------------------------------------------------------------
-- "2026/11/13" + "21:05:09" (local time) -> server-ish time
local function rcTime(d, t)
  if type(d) ~= "string" then return nil end
  local y, m, day = d:match("^(%d+)/(%d+)/(%d+)$")
  if not y then return nil end
  local h, mi, s = (t or ""):match("^(%d+):(%d+):(%d+)$")
  y = tonumber(y); if y < 100 then y = y + 2000 end
  local ok, v = pcall(time, { year = y, month = tonumber(m), day = tonumber(day),
    hour = tonumber(h) or 12, min = tonumber(mi) or 0, sec = tonumber(s) or 0 })
  return ok and v or nil
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
            if type(h) == "table" and h.id then
              local key = "R:" .. tostring(h.id):sub(1, 64)
              if not RL.db.loot[key] then
                local link = cleanLink(h.lootWon)
                RL.db.loot[key] = {
                  key = key, source = "RCLootCouncil", ts = rcTime(h.date, h.time) or 0,
                  itemID = itemIDFrom(link), link = link, to = cleanName(player),
                  os = false, roll = cleanName(h.response), boss = cleanName(h.boss),
                }
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

local rclcHooked = false
function L:HookRCLC()
  if rclcHooked or type(_G.RCLootCouncil) ~= "table" then return rclcHooked end
  local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
  if not AceEvent then return false end
  local listener = {}
  local ok = pcall(AceEvent.Embed, AceEvent, listener)
  if not ok or type(listener.RegisterMessage) ~= "function" then return false end
  -- RCMLAwardSuccess(event, session, winner, status, link, responseText): master looter only.
  listener:RegisterMessage("RCMLAwardSuccess", function(_, _, winner, status, link, response)
    if status == "test_mode" then return end
    local clean = cleanLink(link)
    local to = cleanName(winner)
    if not (to and (clean or itemIDFrom(link))) then return end
    local ts = GetServerTime()
    L:Put({ key = string.format("R:%s:%s:%d", to, tostring(itemIDFrom(link)), math.floor(ts / 60)),
      source = "RCLootCouncil", ts = ts, itemID = itemIDFrom(link), link = clean, to = to,
      os = false, roll = cleanName(response) })
  end)
  rclcHooked = true
  L:ImportRCLC()
  return true
end

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
  if name == "Gargul" or name == "RCLootCouncil" or name == "RCLootCouncil_Classic" then
    C_Timer.After(1, hookAll)
  end
end)
RL:On("ENCOUNTER_END", function(_, name, _, _, success)
  if success == 1 and type(name) == "string" then lastBoss = { name = name, ts = GetServerTime() } end
end)
RL:On("ITEM_DATA_LOAD_RESULT", function() RL:Fire("RL_LOOT_UPDATED") end)
