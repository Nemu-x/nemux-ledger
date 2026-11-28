-- Open a guild mate's profession window ("which recipes does Ky have?").
--
-- Two ways, tried in this order:
--   1. The game's own profession link (|Htrade:<GUID>:<spell>:<skillLine>|h).
--      Clicking one in chat opens that player's recipes. Each Nemux Ledger user
--      reads their link when they open their profession window and shares it:
--        L|1|<version>|<link>     to GUILD, and by WHISPER after a hello
--      We open it the same way a chat click does (SetItemRef).
--   2. Blizzard's guild crafting list (the "Guild crafters" view comes from it):
--      C_GuildInfo.QueryGuildMemberRecipes(guid, skillLine) or the older
--      GetGuildMemberRecipes(name, skillLine). Works for members without the addon
--      on clients that have it.
-- Received links are checked strictly: the exact link format, and the GUID in
-- the link must be the sender's own GUID from the guild roster.

local _, RL = ...
local PL = RL:NewModule("ProfLinks")
RL.ProfLinks = PL

local PROTO = "1"
local LINK_PAT = "^|c%x%x%x%x%x%x%x%x|Htrade:(Player%-[%w%-]+):(%d+):(%d+)|h%[[^|%]]+%]|h|r$"
local NO_WINDOW = { [182] = true, [393] = true, [356] = true } -- Herbalism, Skinning, Fishing

-- link -> guid, spellID, skillLine (or nil)
function PL.Parse(link)
  if type(link) ~= "string" or #link > 160 then return nil end
  local guid, spell, line = link:match(LINK_PAT)
  if not guid then return nil end
  return guid, tonumber(spell), tonumber(line)
end

local function canOpen(line) return line ~= nil and not NO_WINDOW[line] end
PL.CanOpen = canOpen

-- ---------------------------------------------------------------------------
-- My links
-- ---------------------------------------------------------------------------
local function isTrue(fn)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn)
  return ok and v == true
end

local function message(link) return table.concat({ "L", PROTO, RL.version, link }, "|") end

-- Reads the link of the profession window that is open now, if it is mine.
function PL:Capture()
  local T = C_TradeSkillUI
  if not (T and T.GetTradeSkillListLink) then return nil end
  if isTrue(T.IsTradeSkillLinked) or isTrue(T.IsTradeSkillGuild) or isTrue(T.IsNPCCrafting) then return nil end
  local ok, link = pcall(T.GetTradeSkillListLink)
  if not ok then return nil end
  local guid, _, line = PL.Parse(link)
  if not guid or guid ~= UnitGUID("player") then return nil end
  local mine = RL.charDB.profLinks
  if mine[line] ~= link then
    mine[line] = link
    if IsInGuild() then RL.Guild:Queue(message(link), "GUILD") end
    RL:Fire("RL_PROFLINKS_UPDATED")
  end
  return link
end

-- Drops links for professions I no longer have.
local function prune()
  local have = {}
  for _, p in ipairs(RL.Compat.MyProfessions()) do if p.skillLine then have[p.skillLine] = true end end
  if next(have) == nil then return end
  for line in pairs(RL.charDB.profLinks) do
    if not have[line] then RL.charDB.profLinks[line] = nil end
  end
end

function PL:Share(channel, target)
  if not IsInGuild() then return end
  prune()
  for _, link in pairs(RL.charDB.profLinks) do
    RL.Guild:Queue(message(link), channel, target)
  end
end

-- ---------------------------------------------------------------------------
-- Their links
-- ---------------------------------------------------------------------------
function PL.OnMessage(who, _, _, msg)
  local proto, version, link = msg:match("^L|(%d+)|(%d+%.%d+%.%d+)|(.+)$")
  if proto ~= PROTO then return nil end
  local guid, _, line = PL.Parse(link)
  if not guid then return nil end
  local row = RL.Guild.byName[who]
  if not (row and row.guid == guid) then return nil end -- only their own link, checked against the roster
  local links = RL.db.guildLinks[who] or {}
  links[line] = link
  RL.db.guildLinks[who] = links
  RL:Fire("RL_PROFLINKS_UPDATED")
  return version
end

-- Roster row for a name from the guild crafting list ("Nemu Pvpdisc", maybe no realm).
local function rosterRow(name, fullName)
  local G = RL.Guild
  local row = G.byName[G.FullName(fullName or name) or ""] or G.byName[G.FullName(name) or ""]
  if row then return row end
  local s = G.Short(name)
  for _, r in ipairs(G.members) do
    if G.Short(r.name) == s then return r end
  end
  return nil
end

function PL:LinkFor(name, line, fullName)
  local G = RL.Guild
  local row = rosterRow(name, fullName)
  local keys = { row and row.name, G.FullName(fullName or name) }
  for _, k in ipairs(keys) do
    local t = k and RL.db.guildLinks[k]
    if t and t[line] then return t[line] end
  end
  local s = G.Short(name)
  for who, t in pairs(RL.db.guildLinks) do
    if G.Short(who) == s and t[line] then return t[line] end
  end
  return nil
end

local function guildApi()
  if C_GuildInfo and C_GuildInfo.QueryGuildMemberRecipes then return "query" end
  if GetGuildMemberRecipes then return "old" end
  return nil
end

-- How a member's recipes would open: "me", "link", "guild" or nil.
function PL:HowToOpen(d)
  if not (d and canOpen(d.skillID)) then return nil end
  if RL.Guild:IsMe(d.fullName or d.name) then return "me" end
  if self:LinkFor(d.name, d.skillID, d.fullName) then return "link" end
  local api = guildApi()
  if api == "old" then return "guild" end
  if api == "query" then
    local row = rosterRow(d.name, d.fullName)
    if row and row.guid then return "guild" end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Opening, step by step
-- ---------------------------------------------------------------------------
-- Calling the game's functions only asks the server for the data. The window
-- itself is shown by Blizzard's UI code (ShowUIPanel(ProfessionsFrame)), which
-- does not run when an addon makes the request. So after each request we wait
-- for the answer (TRADE_SKILL_* events with a linked or guild profession) and
-- show the window ourselves. If nothing answers, the next way is tried.
-- The last attempt is kept in PL.last for /rq report.

local STEP_WAIT = 2.5
local attempt -- { d, steps = { {how, ok, err} }, events = {}, done, gen }
PL.last = nil

-- What the profession data shows right now (also written to /rq report).
-- On Forever IsTradeSkillLinked can say false while another player's
-- profession is loaded, so the owner GUID in the window's own link counts too.
local function snapshot()
  local T = C_TradeSkillUI
  local s = {}
  if not T then return s end
  local function raw(fn)
    if type(fn) ~= "function" then return "n/a" end
    local ok, a, b = pcall(fn)
    if not ok then return "error" end
    return tostring(a) .. (b ~= nil and ("/" .. tostring(b)) or "")
  end
  s.linked, s.guild = raw(T.IsTradeSkillLinked), raw(T.IsTradeSkillGuild)
  s.isLinked = isTrue(T.IsTradeSkillLinked) or isTrue(T.IsTradeSkillGuild)
  if T.GetBaseProfessionInfo then
    local ok, info = pcall(T.GetBaseProfessionInfo)
    if ok and type(info) == "table" then s.line, s.prof = info.professionID, info.professionName end
  end
  if T.GetTradeSkillListLink then
    local ok, link = pcall(T.GetTradeSkillListLink)
    local guid = ok and PL.Parse(link)
    s.owner = guid and (guid == UnitGUID("player") and "me" or guid) or "none"
  end
  local f = _G.ProfessionsFrame or _G.TradeSkillFrame
  s.frame = f and f:IsShown() and "shown" or "hidden"
  return s
end

local function snapText(s)
  return string.format("[%s %s owner=%s linked=%s guild=%s frame=%s]", tostring(s.line), tostring(s.prof),
    tostring(s.owner), tostring(s.linked), tostring(s.guild), tostring(s.frame))
end

local function viewingOther(line, s)
  s = s or snapshot()
  local other = s.isLinked or (s.owner ~= nil and s.owner ~= "me" and s.owner ~= "none")
  if not other then return false end
  return not (line and s.line and s.line ~= line)
end

local function showWindow()
  if ProfessionsFrame_LoadUI then pcall(ProfessionsFrame_LoadUI) end
  local f = _G.ProfessionsFrame or _G.TradeSkillFrame
  if not f then return false end
  if not f:IsShown() and ShowUIPanel then pcall(ShowUIPanel, f) end
  if not f:IsShown() then pcall(f.Show, f) end
  return f:IsShown() and true or false
end

-- The ways to ask for this member's profession, in order.
local function stepsFor(d)
  local steps = {}
  local link = PL:LinkFor(d.name, d.skillID, d.fullName)
  local inner = link and link:match("|H(trade:[^|]+)|h")
  if inner then
    if SetItemRef then
      steps[#steps + 1] = { how = "link", run = function() SetItemRef(inner, link, "LeftButton", DEFAULT_CHAT_FRAME) end }
    end
    if ItemRefTooltip and ItemRefTooltip.SetHyperlink then
      steps[#steps + 1] = { how = "link-tooltip", run = function()
        ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
        ItemRefTooltip:SetHyperlink(inner)
      end }
    end
  end
  local row = rosterRow(d.name, d.fullName)
  if C_GuildInfo and C_GuildInfo.QueryGuildMemberRecipes and row and row.guid then
    steps[#steps + 1] = { how = "guild", run = function() C_GuildInfo.QueryGuildMemberRecipes(row.guid, d.skillID) end }
  end
  if GetGuildMemberRecipes then
    steps[#steps + 1] = { how = "guild-old", run = function() GetGuildMemberRecipes(d.fullName or d.name, d.skillID) end }
  end
  return steps
end

local function finish(a, ok)
  a.done = true
  a.ok = ok
  if attempt == a then attempt = nil end
  if ItemRefTooltip and not ok then pcall(ItemRefTooltip.Hide, ItemRefTooltip) end
  RL:Fire("RL_PROFVIEW_DONE", a)
end

local function runStep(a, i)
  if a.done or attempt ~= a then return end
  local step = a.steps[i]
  if not step then
    finish(a, false)
    local tried = {}
    for _, s in ipairs(a.tried) do tried[#tried + 1] = s.how .. (s.err and (" (error)") or "") end
    RL:Print("The game did not open %s's %s (tried: %s). They may need to be online. /rq report has the details.",
      RL.Guild.Short(a.d.name), RL.Recipes:LineName(a.d.skillID), table.concat(tried, ", "))
    return
  end
  local ok, err = pcall(step.run)
  a.tried[#a.tried + 1] = { how = step.how, err = not ok and tostring(err):sub(1, 120) or nil, at = GetTime() }
  if viewingOther(a.d.skillID) and showWindow() then return finish(a, true) end
  C_Timer.After(ok and STEP_WAIT or 0.1, function() runStep(a, i + 1) end)
end

local function onTradeEvent(event)
  local a = attempt
  if not a or a.done then return end
  a.events[#a.events + 1] = event
  if #a.events > 12 then table.remove(a.events, 1) end
  local snap = snapshot()
  a.snap = snapText(snap)
  if viewingOther(a.d.skillID, snap) then
    C_Timer.After(0, function()
      if not a.done and showWindow() then finish(a, true) end
    end)
  end
end
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
  "TRADE_SKILL_DATA_SOURCE_CHANGING", "GUILD_RECIPE_KNOWN_BY_MEMBERS" }) do
  RL:On(e, function() onTradeEvent(e) end)
end

-- Opens a member's profession. d = { name, fullName, skillID } (a "Guild crafters" row).
-- Returns true (asked; the window shows when the game answers), or false and a
-- reason: "nowindow", "combat", "nolink", "failed".
function PL:Open(d)
  if not (d and canOpen(d.skillID)) then return false, "nowindow" end
  if InCombatLockdown and InCombatLockdown() then return false, "combat" end
  if RL.Guild:IsMe(d.fullName or d.name) then return RL.Compat.OpenProfession(d.skillID) end
  local steps = stepsFor(d)
  if #steps == 0 then return false, "nolink" end
  local a = { d = d, steps = steps, tried = {}, events = {}, started = GetServerTime() }
  attempt, PL.last = a, a
  runStep(a, 1)
  return true
end

-- One line for /rq report.
function PL:LastText()
  local a = self.last
  if not a then return "none" end
  local tried = {}
  for _, s in ipairs(a.tried) do tried[#tried + 1] = s.how .. (s.err and ("=error:" .. s.err) or "=ok") end
  return string.format("%s line %s, %s; steps %s; events %s; at last event %s; now %s",
    tostring(a.d.name), tostring(a.d.skillID), a.done and (a.ok and "OPENED" or "not opened") or "waiting",
    table.concat(tried, ", "), #a.events > 0 and table.concat(a.events, ",") or "none",
    a.snap or "-", snapText(snapshot()))
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function PL:Init()
  RL.Guild.handlers.L = PL.OnMessage
end

local function captureSoon() C_Timer.After(1.5, function() PL:Capture() end) end
RL:On("TRADE_SKILL_SHOW", captureSoon)
RL:On("TRADE_SKILL_LIST_UPDATE", captureSoon)
RL:On("RL_HELLO_SENT", function() C_Timer.After(6, function() PL:Share("GUILD") end) end)
RL:On("RL_PEER_HELLO", function(sender) PL:Share("WHISPER", sender) end)
RL:On("RL_GUILD_UPDATED", function()
  -- forget members who left (only once the roster is loaded)
  local G = RL.Guild
  if not IsInGuild() or G.total == 0 then return end
  for who in pairs(RL.db.guildLinks) do
    if not G.byName[who] then RL.db.guildLinks[who] = nil end
  end
end)
