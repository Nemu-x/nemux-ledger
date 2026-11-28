-- Raids: a raid history built from what the game reliably tells every client.
--   * sessions: one per raid instance visit (start, end, who from the guild was there)
--   * pulls: ENCOUNTER_START / ENCOUNTER_END -> kills, wipes, kill time, guild records
--   * deaths: your own, plus guild mates with Nemux Ledger (their death messages)
--   * attendance: raid nights each guild member was in, as seen by this client
--   * ready check: members with Nemux Ledger report their own consumables
-- Forever has no combat log for addons and hides much in raids (secrets), so
-- nothing here reads other players' auras or combat data.
--
-- Message: Y|1|<ver>|<check>:<state>,...   state: o ok, s expiring soon, m missing, u unknown
--   sent to the raid (or party) when a ready check starts. Read only from guild mates.

local _, RL = ...
local Rd = RL:NewModule("Raids")
RL.Raids = Rd

local Compat = RL.Compat
local PROTO = "1"
local MAX_SESSIONS = 60
local RESUME = 2 * 3600 -- back in the same raid within 2h: same session
Rd.READY_CHECKS = { "food", "flask", "elixir", "weapon", "potions" }
local READY_STATE = { active = "o", ok = "o", expiring = "s", missing = "m", low = "m" }

Rd.current = nil -- the open session
Rd.ready = { at = 0, by = {} } -- last ready check: [Short name] = { [check] = state }

local function now() return math.floor(GetServerTime()) end
local function secret(v) return Compat.IsSecret(v) end
local function num(v) return type(v) == "number" and not secret(v) end

-- Guild member (Name-Realm) for a group member's name, or nil.
local function guildName(name)
  if type(name) ~= "string" or secret(name) then return nil end
  local G = RL.Guild
  local full = G.FullName(name)
  if full and G.byName[full] then return full end
  local s = G.Short(name)
  for key in pairs(G.byName) do
    if G.Short(key) == s then return key end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Sessions
-- ---------------------------------------------------------------------------
local function inRaid()
  local kind, name, instanceID = RL.Context:Instance()
  if kind ~= "raid" then return nil end
  return name, instanceID
end

function Rd:SnapshotRoster()
  local s = self.current
  if not s then return end
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, n do
    local ok, name = pcall(GetRaidRosterInfo, i)
    local who = ok and guildName(name)
    if who then s.roster[who] = true end
  end
  for _, m in ipairs(RL.Guild.members) do
    if RL.Guild:IsMe(m.name) then s.roster[m.name] = true end
  end
  s.size = math.max(s.size or 0, n)
  s.seen = now()
end

function Rd:Begin()
  local name, instanceID = inRaid()
  if not name then return end
  local list = RL.db.raids
  local last = list[1]
  if last and last.instanceID == instanceID and now() - (last.stop or last.seen or last.start) < RESUME then
    self.current = last
    last.stop = nil
  elseif not (self.current and self.current.instanceID == instanceID and list[1] == self.current) then
    self.current = { id = RL.DB:NextEventId() or tostring(now()), instanceID = instanceID, name = name, start = now(),
      bosses = {}, order = {}, kills = 0, wipes = 0, deaths = 0, roster = {}, size = 0 }
    table.insert(list, 1, self.current)
    while #list > MAX_SESSIONS do table.remove(list) end
  end
  self:SnapshotRoster()
  RL:Fire("RL_RAIDS_UPDATED")
end

function Rd:End()
  local s = self.current
  if not s then return end
  s.stop = now()
  self.current = nil
  -- A visit with no pulls at all is not worth keeping.
  if #s.order == 0 and RL.db.raids[1] == s and (s.stop - s.start) < 600 then table.remove(RL.db.raids, 1) end
  RL:Fire("RL_RAIDS_UPDATED")
end

function Rd:CheckZone()
  if inRaid() then self:Begin() elseif self.current then self:End() end
end

-- ---------------------------------------------------------------------------
-- Pulls
-- ---------------------------------------------------------------------------
local pull -- { id, name, start }

local function boss(s, id, name)
  local b = s.bosses[id]
  if not b then
    b = { name = name, pulls = 0, kills = 0, deaths = 0 }
    s.bosses[id] = b
    s.order[#s.order + 1] = id
  end
  if name and not secret(name) then b.name = name end
  return b
end

function Rd:EncounterStart(id, name)
  if not num(id) then return end
  if not self.current then self:Begin() end
  if not self.current then return end
  pull = { id = id, name = (not secret(name)) and name or nil, start = GetTime() }
  boss(self.current, id, pull.name)
  self:SnapshotRoster()
end

function Rd:EncounterEnd(id, name, success)
  local s = self.current
  if not s or not num(id) then return end
  local b = boss(s, id, (not secret(name)) and name or nil)
  b.pulls = b.pulls + 1
  local won = success == 1 or success == true
  if won then
    b.kills = b.kills + 1
    s.kills = s.kills + 1
    local secs = pull and pull.id == id and math.floor(GetTime() - pull.start) or nil
    if secs and secs > 5 then
      b.best = math.min(b.best or secs, secs)
      local rec = RL.db.raidRecords[id]
      if not rec or secs < rec.secs then
        local beat = rec ~= nil
        RL.db.raidRecords[id] = { secs = secs, ts = now(), name = b.name }
        if beat then
          RL:Print("New guild record on %s: %s.", b.name or "the boss", Rd.Duration(secs))
          RL:Fire("RL_RAID_RECORD", id)
        end
      end
    end
    if not RL.db.guildKills[id] then
      RL.db.guildKills[id] = { ts = now(), name = b.name, instance = s.name }
      if RL.Chronicle then RL.Chronicle:Add("kill", "", tostring(id), b.name or "?") end
      RL:Print("|cffffd100Guild first kill:|r %s!", b.name or "a boss")
      RL:Fire("RL_RAID_FIRST_KILL", id)
    end
    if b.pulls - b.kills >= 5 then RL:Fire("RL_RAID_STUBBORN", id) end
  else
    s.wipes = s.wipes + 1
  end
  pull = nil
  s.seen = now()
  RL:Fire("RL_RAIDS_UPDATED")
end

-- Deaths in the current session: mine, and guild mates' who report them.
function Rd:CountDeath(encounterID)
  local s = self.current
  if not s then return end
  s.deaths = s.deaths + 1
  local id = encounterID or (pull and pull.id)
  if id and s.bosses[id] then s.bosses[id].deaths = s.bosses[id].deaths + 1 end
  RL:Fire("RL_RAIDS_UPDATED")
end

-- ---------------------------------------------------------------------------
-- Attendance: raid nights per guild member (a night = a date with a raid).
-- ---------------------------------------------------------------------------
local function night(ts)
  return date("%Y-%m-%d", ts - 6 * 3600) -- a raid after midnight belongs to the evening before
end

-- Rows: { name, classFile, online, nights, total, pct, last }
function Rd:Attendance(days)
  local since = now() - (days or 30) * 86400
  local nights, total = {}, 0
  local per = {}
  for _, s in ipairs(RL.db.raids) do
    if s.start >= since and #s.order > 0 then
      local n = night(s.start)
      if not nights[n] then nights[n] = {}; total = total + 1 end
      for who in pairs(s.roster) do
        if not nights[n][who] then
          nights[n][who] = true
          local p = per[who] or { nights = 0, last = 0 }
          p.nights = p.nights + 1
          p.last = math.max(p.last, s.start)
          per[who] = p
        end
      end
    end
  end
  local rows = {}
  local G = RL.Guild
  for who, p in pairs(per) do
    local row = G.byName[who]
    if row then
      rows[#rows + 1] = { key = who, name = G.Short(who), me = G:IsMe(who), classFile = row.classFile, online = row.online,
        nights = p.nights, total = total, pct = math.floor(p.nights * 100 / math.max(1, total) + 0.5), last = p.last }
    end
  end
  table.sort(rows, function(a, b)
    if a.pct ~= b.pct then return a.pct > b.pct end
    return a.name < b.name
  end)
  return rows, total
end

-- Raid nights the current character was in (for feats).
function Rd:MyNights()
  local nights, n = {}, 0
  for _, s in ipairs(RL.db.raids) do
    if #s.order > 0 then
      for who in pairs(s.roster) do
        if RL.Guild:IsMe(who) then
          local k = night(s.start)
          if not nights[k] then nights[k] = true; n = n + 1 end
          break
        end
      end
    end
  end
  return n
end

-- "1h 48m", "4m 12s"
function Rd.Duration(secs)
  secs = math.floor(secs or 0)
  local fl = math.floor
  if secs >= 3600 then return string.format("%dh %dm", fl(secs / 3600), fl(secs % 3600 / 60)) end
  if secs >= 60 then return string.format("%dm %02ds", fl(secs / 60), fl(secs % 60)) end
  return secs .. "s"
end

-- ---------------------------------------------------------------------------
-- Ready check report
-- ---------------------------------------------------------------------------
function Rd:ReadyMessage()
  local R = RL.Readiness
  R:Evaluate()
  local parts = {}
  for _, id in ipairs(Rd.READY_CHECKS) do
    local res = R.results[id]
    parts[#parts + 1] = id .. ":" .. ((res and READY_STATE[res.status]) or "u")
  end
  return table.concat({ "Y", PROTO, RL.version, table.concat(parts, ",") }, "|")
end

local function myReport()
  local by = {}
  for entry in Rd:ReadyMessage():match("|([%a:,]+)$"):gmatch("[^,]+") do
    local k, v = entry:match("^(%a+):(%a)$")
    if k then by[k] = v end
  end
  return by
end

function Rd:OnReadyCheck()
  self.ready = { at = now(), by = {} }
  -- UnitName gives only the first name on Forever; the roster has the full one.
  local me = RL.Guild.Short(UnitName("player") or "you")
  for _, m in ipairs(RL.Guild.members) do
    if RL.Guild:IsMe(m.name) then me = m.short or RL.Guild.Short(m.name) end
  end
  self.ready.by[me] = myReport()
  RL:Fire("RL_READY_REPORT", self.ready.by[me])
  self.ready.me = me
  local channel = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY" or nil)
  if channel then RL.Guild:Queue(self:ReadyMessage(), channel) end
  RL:Fire("RL_RAIDS_UPDATED")
end

function Rd.OnMessage(who, _, channel, msg)
  local proto, version, list = msg:match("^Y|(%d+)|(%d+%.%d+%.%d+)|([%a:,]+)$")
  if proto ~= PROTO then return nil end
  local by = {}
  for entry in list:gmatch("[^,]+") do
    local k, v = entry:match("^(%a+):([osmu])$")
    if k and #k <= 12 then by[k] = v end
  end
  if now() - (Rd.ready.at or 0) > 300 then Rd.ready = { at = now(), by = {} } end
  Rd.ready.by[RL.Guild.Short(who)] = by
  RL:Fire("RL_RAIDS_UPDATED")
  return version
end

-- Rows for the ready view: everyone in the group, with their report or nil.
function Rd:ReadyRows()
  local rows, seen = {}, {}
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, n do
    local ok, name, _, _, _, _, classFile = pcall(GetRaidRosterInfo, i)
    if ok and type(name) == "string" and not secret(name) then
      local s = RL.Guild.Short(name)
      seen[s] = true
      rows[#rows + 1] = { name = s, classFile = classFile, report = self.ready.by[s], guild = guildName(name) ~= nil,
        me = RL.Guild:IsMe(name) or s == self.ready.me }
    end
  end
  for s, rep in pairs(self.ready.by) do
    if not seen[s] then rows[#rows + 1] = { name = s, report = rep, guild = true, me = s == self.ready.me } end
  end
  local function score(r)
    if not r.report then return 50 end
    local miss = 0
    for _, v in pairs(r.report) do if v == "m" then miss = miss + 1 end end
    return -miss
  end
  table.sort(rows, function(a, b)
    local sa, sb = score(a), score(b)
    if sa ~= sb then return sa < sb end
    return a.name < b.name
  end)
  return rows
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function Rd:Init()
  RL.Guild.handlers.Y = Rd.OnMessage
  RL.Guild.groupKinds.Y = true
end

function Rd:OnLogin()
  C_Timer.After(4, function() Rd:CheckZone() end)
end

RL:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, function() Rd:CheckZone() end) end)
RL:On("ZONE_CHANGED_NEW_AREA", function() Rd:CheckZone() end)
RL:On("GROUP_ROSTER_UPDATE", function() Rd:SnapshotRoster() end)
RL:On("ENCOUNTER_START", function(id, name) Rd:EncounterStart(id, name) end)
RL:On("ENCOUNTER_END", function(id, name, _, _, success) Rd:EncounterEnd(id, name, success) end)
RL:On("READY_CHECK", function() C_Timer.After(0.5, function() Rd:OnReadyCheck() end) end)
RL:On("RL_MY_DEATH", function(entry)
  if entry and entry.where == "raid" then Rd:CountDeath(entry.encounterID) end
end)
RL:On("RL_PEER_DEATH", function(who, _, where)
  if where == "raid" and Rd.current and Rd.current.roster[who] then Rd:CountDeath() end
end)
