-- Main window (/rq): tabs Me, Guild, Boards, Feats, Loot, Deaths, Settings.
-- Panes are built on first open and refreshed only while visible.

local _, RL = ...
local UI = RL:NewModule("UI")
RL.UI = UI
local T = RL.Theme

local W, H = 640, 470
local win, tabs, panes, activeTab = nil, {}, {}, "me"

-- ---------------------------------------------------------------------------
-- Session XP tracker (for "XP per hour")
-- ---------------------------------------------------------------------------
local xp = { start = nil, gained = 0, last = nil, lastMax = nil }

local function xpUpdate()
  local cur, max = UnitXP("player"), UnitXPMax("player")
  if xp.last then
    if cur >= xp.last then
      xp.gained = xp.gained + (cur - xp.last)
    else -- level up
      xp.gained = xp.gained + (xp.lastMax - xp.last) + cur
    end
  end
  xp.last, xp.lastMax = cur, max
end

RL:On("PLAYER_LOGIN", function()
  xp.start = GetTime()
  xp.last, xp.lastMax = UnitXP("player"), UnitXPMax("player")
end)
RL:On("PLAYER_XP_UPDATE", function(unit)
  if unit == "player" then xpUpdate(); UI:RefreshIfVisible("me") end
end)

-- ---------------------------------------------------------------------------
-- Small widget helpers
-- ---------------------------------------------------------------------------
local function SectionTitle(parent, text, width)
  return T.Section(parent, text, width or 290)
end

local function Button(parent, text, w, onClick)
  return T.Button(parent, text, w, 22, onClick)
end

local function Check(parent, label, get, set)
  return T.Check(parent, label, get, set)
end

local function timeAgo(ts)
  local d = GetServerTime() - (ts or 0)
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. " min ago" end
  if d < 86400 then return math.floor(d / 3600) .. " h ago" end
  return math.floor(d / 86400) .. " d ago"
end

local function commas(n)
  local s = tostring(math.floor(n or 0))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

-- ---------------------------------------------------------------------------
-- Me pane
-- ---------------------------------------------------------------------------
local SECONDARY_SKILL_LINES = { [185] = true, [129] = true, [356] = true } -- Cooking, First Aid, Fishing
local SECONDARY_NAMES = { Cooking = true, ["First Aid"] = true, Fishing = true }

local function readProfessions()
  local main, secondary = {}, {}
  for _, entry in ipairs(RL.Compat.MyProfessions()) do
    if SECONDARY_SKILL_LINES[entry.skillLine] or SECONDARY_NAMES[entry.name] then
      secondary[#secondary + 1] = entry
    else
      main[#main + 1] = entry
    end
  end
  return main, secondary
end

local function buildMe(p)
  -- Left: readiness list
  local title = SectionTitle(p, "Readiness")
  title:SetPoint("TOPLEFT", 4, -4)
  p.modeText = T.Text(p, 11, "muted")
  p.modeText:SetPoint("LEFT", title, "RIGHT", 8, -1)

  p.checkRows = {}
  local y = -28
  for i, check in ipairs(RL.Data.CHECKS) do
    local row = CreateFrame("Frame", nil, p, "BackdropTemplate")
    T.Panel(row, T.c.row, { 0, 0, 0, 0 })
    row:SetSize(300, 30)
    row:SetPoint("TOPLEFT", 0, y)
    row.icon = T.Icon(row, 24)
    row.icon:SetPoint("LEFT", 4, 0)
    row.name = T.Text(row, 12, "silver")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetText(check.name)
    row.status = T.Text(row, 11, "muted")
    row.status:SetPoint("RIGHT", -8, 0)
    row.status:SetJustifyH("RIGHT")
    row.check = check
    p.checkRows[i] = row
    y = y - 34
  end
  p.restrictedNote = T.Text(p, 10, "muted")
  p.restrictedNote:SetPoint("TOPLEFT", 4, y - 2)
  p.restrictedNote:SetWidth(296)
  p.restrictedNote:SetText("Buffs are hidden by the game in combat and some instances. They update afterwards.")

  -- Right: experience
  local xpTitle = SectionTitle(p, "Experience")
  xpTitle:SetPoint("TOPLEFT", 324, -4)
  p.xpLines = {}
  for i = 1, 5 do
    local fs = T.Text(p, 12, "silver")
    fs:SetPoint("TOPLEFT", 324, -28 - (i - 1) * 18)
    fs:SetWidth(270)
    p.xpLines[i] = fs
  end

  -- Right: professions
  local profTitle = SectionTitle(p, "Professions")
  profTitle:SetPoint("TOPLEFT", 324, -130)
  p.profBars = {}
  for i = 1, 2 do
    local bar = CreateFrame("StatusBar", nil, p, "BackdropTemplate")
    T.Panel(bar, { 0.03, 0.05, 0.1, 1 }, { 0, 0, 0, 1 })
    bar:SetStatusBarTexture(T.WHITE)
    bar:SetStatusBarColor(T.c.bronze[1], T.c.bronze[2], T.c.bronze[3], 0.9)
    bar:SetSize(270, 16)
    bar:SetPoint("TOPLEFT", 324, -156 - (i - 1) * 24)
    bar.text = T.Text(bar, 11, "silver")
    bar.text:SetPoint("LEFT", 6, 0)
    bar.value = T.Text(bar, 11, "silver")
    bar.value:SetPoint("RIGHT", -6, 0)
    p.profBars[i] = bar
  end
  p.secTitle = T.Text(p, 11, "muted")
  p.secTitle:SetPoint("TOPLEFT", 324, -210)
  p.secTitle:SetText("Secondary")
  p.secText = T.Text(p, 12, "silver")
  p.secText:SetPoint("TOPLEFT", 324, -226)
  p.secText:SetWidth(270)
  p.profEmpty = T.Text(p, 11, "muted")
  p.profEmpty:SetPoint("TOPLEFT", 324, -156)
  p.profEmpty:SetWidth(270)
  p.profEmpty:SetText("No professions learned yet.")
end

local function refreshMe(p)
  local mode = RL.Context.mode
  p.modeText:SetText("· " .. mode)
  for _, row in ipairs(p.checkRows) do
    local res = RL.Readiness.results[row.check.id]
    if res then
      local text, key = RL.Readiness:StatusLine(res)
      row.status:SetText(text)
      T.SetColor(row.status, key)
      row.icon.tex:SetTexture(res.icon)
      row.icon:SetStatus(key == "muted" and "bronze" or key)
    else
      row.status:SetText("…")
    end
    row:SetAlpha(RL.Readiness:IsTracked(row.check.id, mode) and 1 or 0.55)
  end
  p.restrictedNote:SetShown(RL.Readiness.restricted)

  -- Experience
  local L = p.xpLines
  local level = UnitLevel("player")
  if RL.Context:IsMaxLevel() then
    L[1]:SetText("Level " .. level .. " · max level")
    for i = 2, 5 do L[i]:SetText("") end
  else
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local pct = max > 0 and math.floor(cur / max * 100) or 0
    L[1]:SetText(string.format("Level %d · %d%%", level, pct))
    local rested = GetXPExhaustion() or 0
    if rested > 0 and max > 0 then
      L[2]:SetText(string.format("Rested: %s of a level", T.Color(math.floor(rested / max * 100) .. "%", "info")))
    else
      L[2]:SetText("Rested: " .. T.Color("none", "muted"))
    end
    L[3]:SetText(RL.Context.resting and T.Color("Resting now", "ok") or T.Color("Not resting", "muted"))
    local elapsed = xp.start and (GetTime() - xp.start) or 0
    L[4]:SetText("This session: " .. commas(xp.gained) .. " XP")
    local perHour = elapsed > 300 and (xp.gained / elapsed * 3600) or nil
    L[5]:SetText("Per hour: " .. (perHour and commas(perHour) or T.Color("after 5 min", "muted")))
  end

  -- Professions
  local main, secondary = readProfessions()
  for i, bar in ipairs(p.profBars) do
    local e = main[i]
    if e then
      bar:SetMinMaxValues(0, math.max(1, e.max))
      bar:SetValue(e.rank)
      bar.text:SetText(e.name)
      bar.value:SetText(e.rank .. " / " .. e.max)
      bar:Show()
    else
      bar:Hide()
    end
  end
  p.profEmpty:SetShown(#main == 0)
  local parts = {}
  for _, e in ipairs(secondary) do parts[#parts + 1] = e.name .. " " .. T.Color(e.rank, "silver") end
  p.secText:SetText(#parts > 0 and table.concat(parts, T.Color("  ·  ", "muted")) or T.Color("None", "muted"))
end

-- ---------------------------------------------------------------------------
-- Deaths pane
-- ---------------------------------------------------------------------------
local function bigStat(p, label, x)
  local num = T.Text(p, 28, "silver", T.TITLE_FONT)
  num:SetPoint("TOPLEFT", x, -28)
  local lab = T.Text(p, 11, "muted")
  lab:SetPoint("TOPLEFT", num, "BOTTOMLEFT", 0, -2)
  lab:SetText(label)
  return num
end

local function buildDeaths(p)
  local title = SectionTitle(p, "My deaths")
  title:SetPoint("TOPLEFT", 4, -4)
  p.total = bigStat(p, "Total", 4)
  p.week = bigStat(p, "Last 7 days", 130)
  p.session = bigStat(p, "This session", 256)
  p.split = T.Text(p, 12, "silver")
  p.split:SetPoint("TOPLEFT", 4, -96)

  local recent = SectionTitle(p, "Recent")
  recent:SetPoint("TOPLEFT", 4, -126)
  p.rows = {}
  for i = 1, 8 do
    local when = T.Text(p, 11, "muted")
    when:SetPoint("TOPLEFT", 4, -150 - (i - 1) * 20)
    when:SetWidth(90)
    local where = T.Text(p, 12, "silver")
    where:SetPoint("LEFT", when, "RIGHT", 6, 0)
    where:SetWidth(480)
    p.rows[i] = { when = when, where = where }
  end
  p.empty = T.Text(p, 12, "muted")
  p.empty:SetPoint("TOPLEFT", 4, -150)
  p.empty:SetText("No deaths yet. Suspicious.")

  p.phrase = Check(p, "Funny phrase in my chat when I die",
    function() return RL.charDB.deaths.chatPhrase end,
    function(v) RL.charDB.deaths.chatPhrase = v end)
  p.phrase:SetPoint("BOTTOMLEFT", 4, 10)
  local preview = Button(p, "Preview a phrase", 140, function() RL.Deaths:Preview() end)
  preview:SetPoint("BOTTOMRIGHT", -4, 7)

  local note = T.Text(p, 10, "muted")
  note:SetPoint("BOTTOMLEFT", 4, 34)
  note:SetText("Counted since you installed Nemux Ledger. Guild mates with the addon see your deaths too.")
  p.guildAlerts = Check(p, "Show guild deaths in my chat",
    function() return RL.charDB.deaths.guildAlerts end,
    function(v) RL.charDB.deaths.guildAlerts = v end)
  p.guildAlerts:SetPoint("BOTTOMLEFT", 260, 10)
end

local WHERE_LABEL = { world = "Open world", party = "Dungeon", raid = "Raid", pvp = "PvP" }

local function refreshDeaths(p)
  local s = RL.Deaths:Stats()
  if not s then return end
  p.total:SetText(s.total)
  p.week:SetText(s.week)
  p.session:SetText(s.session)
  local b = s.byType
  p.split:SetText(string.format("Open world %s  ·  Dungeons %s  ·  Raids %s  ·  PvP %s",
    T.Color(b.world or 0, "silver"), T.Color(b.party or 0, "silver"), T.Color(b.raid or 0, "silver"), T.Color(b.pvp or 0, "silver")))
  for i, row in ipairs(p.rows) do
    local e = s.list[i]
    if e then
      row.when:SetText(timeAgo(e.ts))
      local where = (e.zone or "?") .. T.Color("  " .. (WHERE_LABEL[e.where] or ""), "muted")
      if e.boss then where = where .. T.Color("  · " .. e.boss, "bad") end
      row.where:SetText(where)
      row.when:Show(); row.where:Show()
    else
      row.when:Hide(); row.where:Hide()
    end
  end
  p.empty:SetShown(#s.list == 0)
  p.phrase:Refresh()
  p.guildAlerts:Refresh()
end

-- ---------------------------------------------------------------------------
-- Guild pane: roster from the game (no addon needed) + who runs the addon.
-- ---------------------------------------------------------------------------
local GUILD_ROWS = 14
local GCOL = { name = 8, level = 166, zone = 206, rank = 372, ledger = 482 }

local function guildRow(p, i)
  local row = CreateFrame("Button", nil, p)
  row:SetHeight(20)
  row:SetPoint("TOPLEFT", 0, -68 - (i - 1) * 20)
  row:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetTexture(T.WHITE)
  row.bg:SetVertexColor(1, 1, 1, i % 2 == 0 and 0.03 or 0)
  row.hl = row:CreateTexture(nil, "HIGHLIGHT")
  row.hl:SetAllPoints()
  row.hl:SetTexture(T.WHITE)
  row.hl:SetVertexColor(T.c.crimson[1], T.c.crimson[2], T.c.crimson[3], 0.18)
  local function col(key, w, color)
    local fs = T.Text(row, 12, color or "silver")
    fs:SetPoint("LEFT", GCOL[key], 0)
    fs:SetWidth(w)
    fs:SetWordWrap(false)
    row[key] = fs
  end
  col("name", 154)
  col("level", 36, "muted")
  col("zone", 160, "muted")
  col("rank", 104, "muted")
  col("ledger", 126)
  row:SetScript("OnClick", function(self)
    if self.data and self.data.header then RL.Guild:ToggleProfession(self.data) end
    if self.data and self.data.crafters then
      RL.Tracker:Toggle(self.data.id)
      UI:Refresh()
      local fn = self:GetScript("OnEnter")
      if fn then fn(self) end
    end
  end)
  row:SetScript("OnEnter", function(self)
    local d = self.data
    if not (d and d.crafters) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(d.name, T.c.silver[1], T.c.silver[2], T.c.silver[3])
    GameTooltip:AddLine(RL.Recipes:LineName(d.line), T.c.muted[1], T.c.muted[2], T.c.muted[3])
    for _, c in ipairs(d.crafters) do
      local col = c.online and T.c.ok or T.c.muted
      GameTooltip:AddLine(c.name .. (c.online and "" or "  (offline)"), col[1], col[2], col[3])
    end
    GameTooltip:AddLine(" ")
    local mats, ready = RL.Recipes:ReagentStatus(d.id)
    if not mats then
      GameTooltip:AddLine("Reagents: the game did not give them for this recipe.", T.c.muted[1], T.c.muted[2], T.c.muted[3], true)
    else
      GameTooltip:AddDoubleLine("Reagents", "in bags / need", T.c.silver[1], T.c.silver[2], T.c.silver[3],
        T.c.muted[1], T.c.muted[2], T.c.muted[3])
      for _, m in ipairs(mats) do
        local icon = m.icon and ("|T" .. m.icon .. ":14:14|t ") or ""
        local col = m.bags >= m.need and T.c.ok or (m.total >= m.need and T.c.warn or T.c.bad)
        local have = m.bags .. " / " .. m.need
        if m.total > m.bags then have = have .. string.format("  (+%d bank)", m.total - m.bags) end
        if m.price then have = T.Color("~" .. RL.Compat.Money(m.price * m.need) .. "  ", "muted") .. have end
        GameTooltip:AddDoubleLine(icon .. (m.name or ("item " .. m.itemID)), have, 0.9, 0.9, 0.9, col[1], col[2], col[3])
      end
      local total, missing, complete = RL.Recipes:Cost(mats)
      if total > 0 then
        local text = "~" .. RL.Compat.Money(total) .. (complete and "" or "+")
        if missing > 0 and missing < total then text = text .. "  (missing: ~" .. RL.Compat.Money(missing) .. ")" end
        GameTooltip:AddDoubleLine("Approx. cost", text, T.c.silver[1], T.c.silver[2], T.c.silver[3], T.c.warn[1], T.c.warn[2], T.c.warn[3])
        local oldest
        for _, m in ipairs(mats) do if m.age and (not oldest or m.age > oldest) then oldest = m.age end end
        GameTooltip:AddLine("Prices from your price addon" .. (oldest and oldest > 0 and (", up to " .. oldest .. " days old") or "") .. ".",
          T.c.muted[1], T.c.muted[2], T.c.muted[3])
      end
      if ready then
        GameTooltip:AddLine("You have everything for one craft.", T.c.ok[1], T.c.ok[2], T.c.ok[3])
      end
    end
    GameTooltip:AddLine(RL.Tracker:IsTracked(d.id) and "Click: stop tracking" or "Click: track (shopping list on screen)",
      T.c.info[1], T.c.info[2], T.c.info[3])
    GameTooltip:Show()
    UI.hoverRow = self
  end)
  row:SetScript("OnLeave", function() UI.hoverRow = nil; GameTooltip:Hide() end)
  return row
end

local function buildGuild(p)
  p.view, p.offset = "members", 0
  p.title = T.Text(p, 16, "silver", T.TITLE_FONT)
  p.title:SetPoint("TOPLEFT", 4, -2)
  p.sub = T.Text(p, 11, "muted")
  p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3)

  -- View switch: Members / Professions / Recipes
  p.viewBtns = {}
  local prev
  for _, v in ipairs({ { "recipes", "Recipes" }, { "professions", "Professions" }, { "members", "Members" } }) do
    local b = Button(p, v[2], 86, function()
      p.view = v[1]
      p.offset = 0
      if p.view == "professions" then RL.Guild:QueryProfessions() end
      if p.view == "recipes" then p.search:SetFocus() end
      UI:Refresh()
    end)
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -4, -4) end
    b.view = v[1]
    p.viewBtns[#p.viewBtns + 1] = b
    prev = b
  end
  p.offline = Check(p, "Show offline",
    function() return RL.charDB.guild.showOffline end,
    function(v) RL.charDB.guild.showOffline = v; p.offset = 0; UI:Refresh() end)
  p.offline:SetPoint("TOPRIGHT", -4, -28)

  -- Recipe search box (recipes view only)
  p.search = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  p.search:SetSize(180, 20)
  p.search:SetPoint("TOPLEFT", 10, -40)
  p.search:SetAutoFocus(false)
  p.search:SetMaxLetters(40)
  p.search:SetScript("OnTextChanged", function() p.offset = 0; UI:Refresh() end)
  p.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  p.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  p.searchHint = T.Text(p, 11, "muted")
  p.searchHint:SetPoint("LEFT", p.search, "RIGHT", 10, 0)
  p.searchHint:SetText("type a recipe name")

  p.head = {}
  for key, label in pairs({ name = "Name", level = "Lvl", zone = "Zone", rank = "Rank", ledger = "Nemux Ledger" }) do
    local fs = T.Text(p, 10, "muted")
    fs:SetPoint("TOPLEFT", GCOL[key], -50)
    fs:SetText(label:upper())
    p.head[key] = fs
  end
  local rule = T.Rule(p, "bronze", 0.45)
  rule:SetPoint("TOPLEFT", 0, -64)
  rule:SetPoint("TOPRIGHT", 0, -64)

  p.rows = {}
  for i = 1, GUILD_ROWS do p.rows[i] = guildRow(p, i) end

  p.empty = T.Text(p, 12, "muted")
  p.empty:SetPoint("TOP", 0, -120)
  p.empty:SetWidth(460)
  p.empty:SetJustifyH("CENTER")

  p.more = T.Text(p, 10, "muted")
  p.more:SetPoint("BOTTOMRIGHT", -4, 0)
  p.note = T.Text(p, 10, "muted")
  p.note:SetPoint("BOTTOMLEFT", 4, 0)

  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    p.offset = math.max(0, p.offset - delta * 3)
    UI:Refresh()
  end)
end

local function sortedMembers()
  local G = RL.Guild
  local showOffline = RL.charDB.guild.showOffline
  local list = {}
  for _, m in ipairs(G.members) do
    if m.online or showOffline then list[#list + 1] = m end
  end
  table.sort(list, function(a, b)
    if a.online ~= b.online then return a.online end
    local pa, pb = G.peers[a.name] and 1 or 0, G.peers[b.name] and 1 or 0
    if pa ~= pb then return pa > pb end
    local ra, rb = a.rankIndex or 99, b.rankIndex or 99
    if ra ~= rb then return ra < rb end
    return (a.short or "") < (b.short or "")
  end)
  return list
end

local function setHeaders(p, labels)
  for key, fs in pairs(p.head) do fs:SetText(labels[key] or "") end
end

-- Skill for a member row in the professions view. The game reports 1 in
-- Forever, so the real value comes from the member's own addon.
local function memberSkill(d)
  local G = RL.Guild
  if G:IsMe(d.name) then
    for _, prof in ipairs(RL.Compat.MyProfessions()) do
      if prof.skillLine == d.skillID then return T.Color(prof.rank, "silver") end
    end
  end
  local peer = G:PeerFor(d.name)
  local pr = peer and peer.profs and peer.profs[d.skillID]
  if pr then return T.Color(pr.rank, "silver") end
  if (tonumber(d.skill) or 0) > 1 then return tostring(d.skill) end
  return T.Color("?", "muted")
end

local function refreshGuild(p)
  local G = RL.Guild
  for _, row in ipairs(p.rows) do row:Hide(); row.data = nil end
  p.more:SetText("")
  p.note:SetText("")

  local isRecipes = p.view == "recipes"
  p.search:SetShown(isRecipes and IsInGuild())
  p.searchHint:SetShown(isRecipes and IsInGuild())
  for _, row in ipairs(p.rows) do
    row.name:SetWidth(isRecipes and 196 or 154)
    row.rank:SetWidth(isRecipes and 236 or 104)
  end
  for _, b in ipairs(p.viewBtns) do
    b:SetShown(IsInGuild())
    b:SetAlpha(b.view == p.view and 1 or 0.6)
  end

  if not IsInGuild() then
    p.title:SetText("No guild")
    p.sub:SetText("")
    p.offline:Hide()
    setHeaders(p, {})
    p.empty:SetText("You are not in a guild. Everything else in the addon works solo.")
    p.empty:Show()
    return
  end
  p.title:SetText(G.info and G.info.name or "Guild")
  local peers = G:PeerCount()
  p.sub:SetText(string.format("%d online of %d  ·  %s", G.online, G.total,
    peers > 0 and (T.Color(peers + 1, "ok") .. " with Nemux Ledger (you included)") or "only you have Nemux Ledger online"))

  local list
  if p.view == "members" then
    p.offline:Show()
    setHeaders(p, { name = "NAME", level = "LVL", zone = "ZONE", rank = "RANK", ledger = "NEMUX LEDGER" })
    list = sortedMembers()
    p.empty:SetText(G.total == 0 and "Loading the guild list..." or "Nobody online right now. Tick 'Show offline' to see everyone.")
  elseif isRecipes then
    p.offline:Hide()
    setHeaders(p, { zone = "PROFESSION", rank = "WHO CAN CRAFT" })
    local mine, people, total = RL.Recipes:Stats()
    p.note:SetText(string.format("Your recipes: %d  ·  from %d guild mates: %d. Open your profession window once to share yours.",
      mine, people, total))
    list = RL.Recipes:Search(p.search:GetText()) or {}
    local q = p.search:GetText() or ""
    p.searchHint:SetShown(q == "")
    if #q < 2 then
      p.empty:SetText("Type at least 2 letters of a recipe name, for example 'bracer' or 'elixir'.\nOnly members with Nemux Ledger are searched.")
    else
      p.empty:SetText("Nobody with Nemux Ledger knows a recipe like that yet.")
    end
  else
    p.offline:Hide()
    setHeaders(p, { name = "PROFESSION / MEMBER", level = "SKILL", zone = "ZONE", ledger = "MEMBERS" })
    list = G:Professions()
    p.note:SetText("Skill: shown for members with Nemux Ledger. ? = they don't have the addon.")
    if not G:ProfessionsAvailable() then
      p.empty:SetText("This client has no guild profession list. Guild crafting will come through the addon in a later version.")
    else
      p.empty:SetText("The game returned no guild professions yet. Try again in a few seconds; if it stays empty, Forever has this list turned off.")
    end
  end
  p.empty:SetShown(#list == 0)

  local maxOffset = math.max(0, #list - GUILD_ROWS)
  if p.offset > maxOffset then p.offset = maxOffset end

  for i, row in ipairs(p.rows) do
    local d = list[i + p.offset]
    if d then
      row.data = d
      if p.view == "members" then
        row.name:SetText(d.online and T.ClassColored(d.short, d.classFile) or T.Color(d.short, "muted"))
        row.level:SetText(d.level or "")
        row.zone:SetText(d.online and (d.zone or "") or "offline")
        row.rank:SetText(d.rank or "")
        local peer = G:PeerFor(d.name)
        if G:IsMe(d.name) then
          local s = RL.Deaths:Stats()
          row.ledger:SetText(T.Color("you", "ok") .. T.Color(string.format("  ·  %d deaths", s and s.total or 0), "muted"))
        elseif peer then
          row.ledger:SetText(T.Color("v" .. peer.version, "ok") .. T.Color(string.format("  ·  %d deaths", peer.deaths or 0), "muted"))
        else
          row.ledger:SetText(T.Color("-", "muted"))
        end
        row:SetAlpha(d.online and 1 or 0.6)
      elseif isRecipes then
        row.name:SetText(RL.Tracker:IsTracked(d.id) and (T.Color("» ", "info") .. T.Color(d.name, "info")) or d.name)
        row.level:SetText("")
        row.zone:SetText(RL.Recipes:LineName(d.line))
        local names = {}
        for k, c in ipairs(d.crafters) do
          if k > 4 then names[#names + 1] = T.Color("+" .. (#d.crafters - 4), "muted"); break end
          names[#names + 1] = c.me and T.Color("you", "ok") or (c.online and T.ClassColored(c.name, c.classFile) or T.Color(c.name, "muted"))
        end
        row.rank:SetText(table.concat(names, ", "))
        row.ledger:SetText("")
        row:SetAlpha(1)
      elseif d.header then
        local icon = d.icon and ("|T" .. d.icon .. ":14:14|t ") or ""
        row.name:SetText(icon .. (d.collapsed and "+ " or "- ") .. d.name .. (d.secondary and T.Color("  secondary", "muted") or ""))
        row.level:SetText("")
        row.zone:SetText("")
        row.rank:SetText("")
        row.ledger:SetText(string.format("%d  ·  %s", d.players, T.Color(d.online .. " online", "muted")))
        row:SetAlpha(1)
      else
        row.name:SetText("     " .. (d.online and T.ClassColored(G.Short(d.name), d.classFile) or T.Color(G.Short(d.name), "muted")))
        row.level:SetText(memberSkill(d))
        row.zone:SetText(d.online and (d.zone or "") or "offline")
        row.rank:SetText("")
        row.ledger:SetText("")
        row:SetAlpha(d.online and 1 or 0.6)
      end
      row:Show()
    end
  end
  if #list > GUILD_ROWS then
    p.more:SetText(string.format("%d-%d of %d  ·  scroll for more", p.offset + 1, math.min(#list, p.offset + GUILD_ROWS), #list))
  end
end

-- ---------------------------------------------------------------------------
-- Settings pane
-- ---------------------------------------------------------------------------
local STYLE_LABEL = { text = "Icons with text", icons = "Icons only", off = "Hidden" }
local STYLE_NEXT = { text = "icons", icons = "off", off = "text" }
local COL_X = { solo = 178, party = 226, raid = 274, warn = 326 }

local function buildSettings(p)
  -- Left column: what the HUD checks, per mode, and when it warns.
  local title = SectionTitle(p, "Show in the HUD", 356)
  title:SetPoint("TOPLEFT", 4, -4)
  for key, label in pairs({ solo = "Solo", party = "Party", raid = "Raid", warn = "Warn" }) do
    local h = T.Text(p, 11, "muted")
    h:SetPoint("CENTER", p, "TOPLEFT", COL_X[key], -38)
    h:SetJustifyH("CENTER")
    h:SetText(label)
  end

  p.checks, p.warnSteppers = {}, {}
  for r, check in ipairs(RL.Data.CHECKS) do
    local cy = -62 - (r - 1) * 30
    if r % 2 == 0 then
      local band = p:CreateTexture(nil, "BACKGROUND")
      band:SetTexture(T.WHITE)
      band:SetVertexColor(1, 1, 1, 0.03)
      band:SetPoint("LEFT", p, "TOPLEFT", 0, cy)
      band:SetSize(360, 28)
    end
    local name = T.Text(p, 12, "silver")
    name:SetPoint("LEFT", p, "TOPLEFT", 8, cy)
    name:SetText(check.name)
    for _, m in ipairs({ "solo", "party", "raid" }) do
      local cb = Check(p, nil,
        function() return RL.charDB.readiness.track[check.id][m] end,
        function(v) RL.charDB.readiness.track[check.id][m] = v; RL.HUD:Update() end)
      cb:SetPoint("CENTER", p, "TOPLEFT", COL_X[m], cy)
      p.checks[#p.checks + 1] = cb
    end
    local st
    if check.kind == "count" then
      st = T.Stepper(p,
        function() return RL.charDB.readiness.potionMin end,
        function(v) RL.charDB.readiness.potionMin = v; RL.Readiness:Schedule() end,
        1, 40, 1, function(v) return v .. " pcs" end, 70)
    elseif check.expiring then
      st = T.Stepper(p,
        function() return RL.Readiness:WarnMinutes(check) end,
        function(v) RL.charDB.readiness.warn[check.id] = v; RL.Readiness:Schedule() end,
        1, 60, 1, function(v) return v .. " min" end, 70)
    end
    if st then
      st:SetPoint("CENTER", p, "TOPLEFT", COL_X.warn, cy)
      p.warnSteppers[#p.warnSteppers + 1] = st
    end
  end

  local bottom = -62 - (#RL.Data.CHECKS - 1) * 30 - 26
  local reset = Button(p, "Reset to default", 150, function()
    for _, check in ipairs(RL.Data.CHECKS) do
      RL.charDB.readiness.track[check.id] = { solo = check.defaults.solo, party = check.defaults.party, raid = check.defaults.raid }
    end
    wipe(RL.charDB.readiness.warn)
    RL.charDB.readiness.potionMin = 5
    RL.Readiness:Schedule()
    UI:Refresh()
    RL.HUD:Update()
  end)
  reset:SetPoint("TOPLEFT", 4, bottom)
  local foot = T.Text(p, 10, "muted")
  foot:SetPoint("TOPLEFT", 4, bottom - 32)
  foot:SetWidth(350)
  foot:SetText("Warn: how many minutes before a buff ends you get a reminder. Potions: how many you want to carry.")

  -- Right column: HUD look, reminders.
  local x, w = 384, 224
  local hudTitle = SectionTitle(p, "HUD", w)
  hudTitle:SetPoint("TOPLEFT", x, -4)
  p.styleBtn = Button(p, "", w, function()
    local hud = RL.charDB.hud
    hud.style = STYLE_NEXT[hud.style] or "text"
    UI:Refresh()
    RL.HUD:Update()
  end)
  p.styleBtn:SetPoint("TOPLEFT", x, -30)

  local opts = {
    { "Lock position", function() return RL.charDB.hud.locked end, function(v) RL.charDB.hud.locked = v end },
    { "Hide in combat", function() return RL.charDB.hud.hideInCombat end, function(v) RL.charDB.hud.hideInCombat = v; RL.HUD:Update() end },
    { "Hide HUD in towns and inns (solo)", function() return RL.charDB.hud.quietInTownSolo end, function(v) RL.charDB.hud.quietInTownSolo = v; RL.HUD:Update() end },
    { "Minimap button", function() return not RL.charDB.minimap.hide end, function(v) RL.charDB.minimap.hide = not v; RL.MinimapButton:Apply() end },
  }
  p.opts = {}
  for i, o in ipairs(opts) do
    local cb = Check(p, o[1], o[2], o[3])
    cb:SetPoint("LEFT", p, "TOPLEFT", x + 2, -68 - (i - 1) * 24)
    p.opts[#p.opts + 1] = cb
  end

  local sizeLabel = T.Text(p, 12, "silver")
  sizeLabel:SetPoint("LEFT", p, "TOPLEFT", x + 2, -170)
  sizeLabel:SetText("HUD size")
  p.sizeStepper = T.Stepper(p,
    function() return RL.charDB.hud.scale or 1 end,
    function(v) RL.charDB.hud.scale = math.floor(v * 10 + 0.5) / 10; RL.HUD:ApplyScale() end,
    0.7, 1.6, 0.1, function(v) return string.format("%.1f", v) end, 78)
  p.sizeStepper:SetPoint("RIGHT", p, "TOPLEFT", x + w, -170)
  local resetPos = Button(p, "Reset HUD position", w, function() RL.HUD:ResetPosition() end)
  resetPos:SetPoint("TOPLEFT", x, -186)

  local remTitle = SectionTitle(p, "Reminders", w)
  remTitle:SetPoint("TOPLEFT", x, -224)
  local rem = {
    { "Remind me before a buff ends", function() return RL.charDB.readiness.remind end, function(v) RL.charDB.readiness.remind = v end },
    { "Play a sound", function() return RL.charDB.readiness.remindSound end, function(v) RL.charDB.readiness.remindSound = v end },
  }
  for i, o in ipairs(rem) do
    local cb = Check(p, o[1], o[2], o[3])
    cb:SetPoint("LEFT", p, "TOPLEFT", x + 2, -258 - (i - 1) * 24)
    p.opts[#p.opts + 1] = cb
  end
  local test = Button(p, "Test reminder", w, function() RL.Readiness:TestReminder() end)
  test:SetPoint("TOPLEFT", x, -292)

  local help = T.Text(p, 10, "muted")
  help:SetPoint("TOPLEFT", x, -324)
  help:SetWidth(w)
  help:SetText("Right-click the HUD to snooze it for 15 minutes. /rq help lists all commands.")
end

local function refreshSettings(p)
  for _, cb in ipairs(p.checks) do cb:Refresh() end
  for _, cb in ipairs(p.opts) do cb:Refresh() end
  for _, s in ipairs(p.warnSteppers) do s:Refresh() end
  p.sizeStepper:Refresh()
  p.styleBtn:SetLabel("Style: " .. (STYLE_LABEL[RL.charDB.hud.style] or "?"))
end

-- ---------------------------------------------------------------------------
-- Boards pane: leaderboards (left) and recent guild deaths (right)
-- ---------------------------------------------------------------------------
local BOARD_ROWS = 14
local FEED_X = 318

local function boardLine(p, i, x, cols)
  local row = CreateFrame("Frame", nil, p)
  row:SetHeight(20)
  row:SetPoint("TOPLEFT", x, -68 - (i - 1) * 20)
  row:SetWidth(x == 0 and 300 or 294)
  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(T.WHITE)
  bg:SetVertexColor(1, 1, 1, i % 2 == 0 and 0.03 or 0)
  for key, c in pairs(cols) do
    local fs = T.Text(row, 12, c.color or "silver")
    fs:SetPoint("LEFT", c.x, 0)
    fs:SetWidth(c.w)
    fs:SetWordWrap(false)
    if c.right then fs:SetJustifyH("RIGHT") end
    row[key] = fs
  end
  return row
end

local function buildBoards(p)
  p.kind = "deaths"
  p.title = T.Text(p, 16, "silver", T.TITLE_FONT)
  p.title:SetPoint("TOPLEFT", 4, -2)
  p.title:SetText("Leaderboards")
  p.sub = T.Text(p, 11, "muted")
  p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3)
  p.sub:SetWidth(300)
  p.sub:SetWordWrap(false)

  p.kindBtns = {}
  local x = 0
  for _, k in ipairs({ "deaths", "week", "hk" }) do
    local b = Button(p, RL.Boards.KINDS[k].label, 96, function() p.kind = k; UI:Refresh() end)
    b:SetPoint("TOPLEFT", x, -38)
    b.kind = k
    p.kindBtns[#p.kindBtns + 1] = b
    x = x + 100
  end

  local feedTitle = T.Text(p, 13, "silver", T.TITLE_FONT)
  feedTitle:SetPoint("TOPLEFT", FEED_X, -46)
  feedTitle:SetText("Recent guild deaths")

  -- Level-up alerts and the weekly report
  p.opts = {}
  local dings = Check(p, "Guild level-ups in chat",
    function() return RL.charDB.dings.alerts end, function(v) RL.charDB.dings.alerts = v end)
  dings:SetPoint("TOPLEFT", FEED_X, -2)
  local tens = Check(p, "Only every 10 levels",
    function() return RL.charDB.dings.milestonesOnly end, function(v) RL.charDB.dings.milestonesOnly = v end)
  tens:SetPoint("TOPLEFT", FEED_X, -20)
  local weekBtn = Button(p, "Weekly report", 110, function()
    RL.Export:ShowText("Weekly report", function() return RL.Weekly:FullText() end)
  end)
  weekBtn:SetPoint("TOPRIGHT", -4, -2)
  local notify = Check(p, "Remind me",
    function() return RL.charDB.week.notify end, function(v) RL.charDB.week.notify = v end)
  notify:SetPoint("TOPRIGHT", -24, -26)
  p.opts = { dings, tens, notify }
  local rule = T.Rule(p, "bronze", 0.45)
  rule:SetPoint("TOPLEFT", 0, -64)
  rule:SetPoint("TOPRIGHT", 0, -64)

  p.rows, p.feed = {}, {}
  for i = 1, BOARD_ROWS do
    p.rows[i] = boardLine(p, i, 0, {
      rank = { x = 4, w = 28, color = "muted" },
      name = { x = 34, w = 200 },
      value = { x = 236, w = 58, right = true },
    })
    p.feed[i] = boardLine(p, i, FEED_X, {
      name = { x = 4, w = 96 },
      zone = { x = 102, w = 128, color = "muted" },
      when = { x = 232, w = 58, color = "muted", right = true },
    })
  end
  p.empty = T.Text(p, 12, "muted")
  p.empty:SetPoint("TOPLEFT", 8, -110)
  p.empty:SetWidth(290)
  p.feedEmpty = T.Text(p, 12, "muted")
  p.feedEmpty:SetPoint("TOPLEFT", FEED_X + 8, -110)
  p.feedEmpty:SetWidth(280)
  p.feedEmpty:SetText("No deaths yet. Suspicious.")
  p.note = T.Text(p, 10, "muted")
  p.note:SetPoint("BOTTOMLEFT", 4, 0)
  p.note:SetText("Only members with Nemux Ledger are counted. 'This week' starts at the weekly reset.")
end

local WHERE_TEXT = { party = "dungeon", raid = "raid", pvp = "PvP" }

local function refreshBoards(p)
  local Bd, G = RL.Boards, RL.Guild
  for _, b in ipairs(p.kindBtns) do b:SetAlpha(b.kind == p.kind and 1 or 0.6) end
  for _, cb in ipairs(p.opts) do cb:Refresh() end
  local list = Bd:Board(p.kind)
  local kind = Bd.KINDS[p.kind]
  if list[1] then
    p.sub:SetText(string.format("%s  ·  %s", T.Color(list[1].name, "warn"), Bd:Title(p.kind)))
  else
    p.sub:SetText(Bd:Title(p.kind) .. ": nobody yet")
  end
  for i, row in ipairs(p.rows) do
    local d = list[i]
    if d then
      row.rank:SetText(i == 1 and T.Color("#1", "warn") or ("#" .. i))
      local name = d.me and T.Color("you", "ok") or (d.online and T.ClassColored(d.name, d.classFile) or T.Color(d.name, "muted"))
      row.name:SetText(name)
      row.value:SetText(d.value)
      row:Show()
    else
      row:Hide()
    end
  end
  p.empty:SetShown(#list == 0)
  p.empty:SetText(p.kind == "hk" and "No honorable kills yet. The " .. (select(2, RL.Context:Faction()) or "guild") .. " is peaceful." or "Nobody has died. Yet.")

  local feed = Bd:Feed()
  for i, row in ipairs(p.feed) do
    local e = feed[i]
    if e then
      local name
      if e.me then
        name = T.Color("you", "ok")
      else
        local r = G.byName[e.who]
        name = T.ClassColored(G.Short(e.who), r and r.classFile)
      end
      row.name:SetText(name .. T.Color(" #" .. (e.total or "?"), "muted"))
      local place = e.boss or e.zone or WHERE_TEXT[e.where] or ""
      row.zone:SetText(place)
      row.when:SetText(timeAgo(e.ts))
      row:Show()
    else
      row:Hide()
    end
  end
  p.feedEmpty:SetShown(#feed == 0)
end

-- ---------------------------------------------------------------------------
-- Loot pane: who got what, from Gargul / RCLootCouncil
-- ---------------------------------------------------------------------------
local LOOT_ROWS = 14
local LCOL = { when = 8, item = 72, to = 292, tag = 404, boss = 456 }

local function buildLoot(p)
  p.offset = 0
  p.title = T.Text(p, 16, "silver", T.TITLE_FONT)
  p.title:SetPoint("TOPLEFT", 4, -2)
  p.title:SetText("Loot")
  p.sub = T.Text(p, 11, "muted")
  p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3)
  p.sub:SetWidth(600)
  p.sub:SetWordWrap(false)

  p.search = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  p.search:SetSize(180, 20)
  p.search:SetPoint("TOPLEFT", 10, -40)
  p.search:SetAutoFocus(false)
  p.search:SetMaxLetters(40)
  p.search:SetScript("OnTextChanged", function() p.offset = 0; UI:Refresh() end)
  p.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  p.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  p.hint = T.Text(p, 11, "muted")
  p.hint:SetPoint("LEFT", p.search, "RIGHT", 10, 0)
  p.hint:SetText("player or item")
  p.week = Check(p, "This week only",
    function() return RL.charDB.lootWeekOnly end,
    function(v) RL.charDB.lootWeekOnly = v; p.offset = 0; UI:Refresh() end)
  p.week:SetPoint("TOPRIGHT", -4, -40)

  local rule = T.Rule(p, "bronze", 0.45)
  rule:SetPoint("TOPLEFT", 0, -64)
  rule:SetPoint("TOPRIGHT", 0, -64)

  p.rows = {}
  for i = 1, LOOT_ROWS do
    local row = CreateFrame("Button", nil, p)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", 0, -68 - (i - 1) * 20)
    row:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(T.WHITE)
    bg:SetVertexColor(1, 1, 1, i % 2 == 0 and 0.03 or 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(T.WHITE)
    hl:SetVertexColor(T.c.crimson[1], T.c.crimson[2], T.c.crimson[3], 0.18)
    for key, w in pairs({ when = 60, item = 216, to = 108, tag = 48, boss = 150 }) do
      local fs = T.Text(row, 12, (key == "when" or key == "tag" or key == "boss") and "muted" or "silver")
      fs:SetPoint("LEFT", LCOL[key], 0)
      fs:SetWidth(w)
      fs:SetWordWrap(false)
      row[key] = fs
    end
    row:SetScript("OnEnter", function(self)
      local link = self.data and RL.Loot:LinkFor(self.data)
      if not link then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(link)
      GameTooltip:AddLine("From " .. tostring(self.data.source) .. " · Shift-click: link in chat", T.c.muted[1], T.c.muted[2], T.c.muted[3])
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
      local link = self.data and RL.Loot:LinkFor(self.data)
      if link and IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
    end)
    p.rows[i] = row
  end

  p.empty = T.Text(p, 12, "muted")
  p.empty:SetPoint("TOP", 0, -120)
  p.empty:SetWidth(520)
  p.empty:SetJustifyH("CENTER")
  p.more = T.Text(p, 10, "muted")
  p.more:SetPoint("BOTTOMRIGHT", -4, 0)
  p.note = T.Text(p, 10, "muted")
  p.note:SetPoint("BOTTOMLEFT", 4, 0)
  p.note:SetText("Read from your loot addon. Nemux Ledger never hands out loot.")

  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    p.offset = math.max(0, p.offset - delta * 3)
    UI:Refresh()
  end)
end

local function refreshLoot(p)
  local Lt, G = RL.Loot, RL.Guild
  p.week:Refresh()
  local q = p.search:GetText() or ""
  p.hint:SetShown(q == "")
  local since = RL.charDB.lootWeekOnly and RL.Boards:WeekStart() or nil
  local list = Lt:List(q, since)
  local sources = Lt:Sources()
  if #sources > 0 then
    p.sub:SetText(string.format("%d items  ·  listening to %s", #list, table.concat(sources, ", ")))
  else
    p.sub:SetText(T.Color("No loot addon found. Install Gargul (or RCLootCouncil) and loot shows up here.", "warn"))
  end
  local maxOffset = math.max(0, #list - LOOT_ROWS)
  if p.offset > maxOffset then p.offset = maxOffset end
  for i, row in ipairs(p.rows) do
    local e = list[i + p.offset]
    row.data = e
    if e then
      row.when:SetText(e.ts and e.ts > 0 and date("%d %b", math.floor(e.ts)) or "?")
      row.item:SetText(Lt:LinkFor(e) or Lt:ItemName(e))
      local member = G.byName[G.FullName(e.to)]
      row.to:SetText(G:IsMe(e.to) and T.Color("you", "ok") or T.ClassColored(G.Short(e.to), member and member.classFile))
      row.tag:SetText(e.os and "OS" or (e.sr and "SR" or "MS"))
      row.boss:SetText(e.boss or "")
      row:Show()
    else
      row:Hide()
    end
  end
  if #list == 0 then
    p.empty:SetText(#sources == 0 and "Nothing yet." or "No loot recorded yet. Awards from your loot addon appear here.")
  end
  p.empty:SetShown(#list == 0)
  p.more:SetText(#list > LOOT_ROWS and string.format("%d-%d of %d  ·  scroll for more", p.offset + 1, math.min(#list, p.offset + LOOT_ROWS), #list) or "")
end

-- ---------------------------------------------------------------------------
-- Feats pane: small guild achievements
-- ---------------------------------------------------------------------------
local FEAT_ROWS = 14
local FCOL = { name = 8, desc = 196, you = 424, guild = 500 }

local function buildFeats(p)
  p.offset = 0
  p.title = T.Text(p, 16, "silver", T.TITLE_FONT)
  p.title:SetPoint("TOPLEFT", 4, -2)
  p.title:SetText("Feats")
  p.sub = T.Text(p, 11, "muted")
  p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3)
  p.leaders = T.Text(p, 11, "muted")
  p.leaders:SetPoint("TOPLEFT", p.sub, "BOTTOMLEFT", 0, -3)
  p.leaders:SetWidth(440)
  p.leaders:SetWordWrap(false)
  p.alerts = Check(p, "Show guild feats in chat",
    function() return RL.charDB.feats.guildAlerts end,
    function(v) RL.charDB.feats.guildAlerts = v end)
  p.alerts:SetPoint("TOPRIGHT", -4, -4)
  p.view = "personal"
  p.viewBtns = {}
  local prev
  for _, v in ipairs({ { "goals", "Guild goals" }, { "personal", "Personal" } }) do
    local b = Button(p, v[2], 96, function() p.view = v[1]; p.offset = 0; UI:Refresh() end)
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -4, -24) end
    b.view = v[1]
    p.viewBtns[#p.viewBtns + 1] = b
    prev = b
  end

  p.head = {}
  for key, label in pairs({ name = "FEAT", desc = "HOW", you = "YOU", guild = "GUILD" }) do
    local fs = T.Text(p, 10, "muted")
    fs:SetPoint("TOPLEFT", FCOL[key], -50)
    fs:SetText(label)
    p.head[key] = fs
  end
  local rule = T.Rule(p, "bronze", 0.45)
  rule:SetPoint("TOPLEFT", 0, -64)
  rule:SetPoint("TOPRIGHT", 0, -64)

  p.rows = {}
  for i = 1, FEAT_ROWS do
    local row = CreateFrame("Frame", nil, p)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", 0, -68 - (i - 1) * 20)
    row:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    row:EnableMouse(true)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(T.WHITE)
    bg:SetVertexColor(1, 1, 1, i % 2 == 0 and 0.03 or 0)
    for key, w in pairs({ name = 184, desc = 224, you = 72, guild = 108 }) do
      local fs = T.Text(row, 12, key == "name" and "silver" or "muted")
      fs:SetPoint("LEFT", FCOL[key], 0)
      fs:SetWidth(w)
      fs:SetWordWrap(false)
      row[key] = fs
    end
    row:SetScript("OnEnter", function(self)
      local d = self.data
      if not d then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(d.def.name, T.c.silver[1], T.c.silver[2], T.c.silver[3])
      GameTooltip:AddLine(d.def.desc, T.c.muted[1], T.c.muted[2], T.c.muted[3])
      if d.holders and #d.holders > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Guild: " .. table.concat(d.holders, ", "), 0.9, 0.9, 0.9, true)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.rows[i] = row
  end

  p.more = T.Text(p, 10, "muted")
  p.more:SetPoint("BOTTOMRIGHT", -4, 0)
  p.note = T.Text(p, 10, "muted")
  p.note:SetPoint("BOTTOMLEFT", 4, 0)
  p.note:SetText("Each member's own addon counts their feats. Only members with Nemux Ledger show up.")

  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    local n = p.view == "goals" and #RL.Feats.GOALS or #RL.Feats.DEFS
    p.offset = math.max(0, math.min(n - FEAT_ROWS, p.offset - delta * 3))
    UI:Refresh()
  end)
end

local function refreshFeats(p)
  local F = RL.Feats
  local holders, totals = F:Guild()
  p.sub:SetText(string.format("You have %s of %d", T.Color(F:Count(), "ok"), #F.DEFS))
  if #totals > 0 then
    local top = {}
    for i = 1, math.min(#totals, 5) do top[#top + 1] = string.format("%s %d", totals[i].name, totals[i].n) end
    p.leaders:SetText("Guild: " .. table.concat(top, "  ·  "))
  else
    p.leaders:SetText("No guild mates with Nemux Ledger seen yet.")
  end
  p.alerts:Refresh()
  for _, b in ipairs(p.viewBtns) do b:SetAlpha(b.view == p.view and 1 or 0.6) end
  if p.view == "goals" then
    p.head.you:SetText("PROGRESS"); p.head.guild:SetText("REACHED")
    local goals = F:Goals()
    for i, row in ipairs(p.rows) do
      local g = goals[i + p.offset]
      if g then
        row.data = { def = g.def }
        row.name:SetText(g.reached and T.Color(g.def.name, "ok") or g.def.name)
        row:SetAlpha(g.reached and 1 or 0.8)
        row.desc:SetText(g.def.desc)
        row.you:SetText(T.Color(math.min(g.value, g.def.goal) .. " / " .. g.def.goal, g.reached and "ok" or "silver"))
        row.guild:SetText(g.reached and T.Color(date("%d %b", math.floor(g.reached)), "ok") or T.Color("-", "muted"))
        row:Show()
      else
        row.data = nil
        row:Hide()
      end
    end
    p.more:SetText("")
    return
  end
  p.head.you:SetText("YOU"); p.head.guild:SetText("GUILD")
  for i, row in ipairs(p.rows) do
    local def = F.DEFS[i + p.offset]
    if def then
      local when = RL.charDB.feats.earned[def.id]
      local h = holders[def.id] or {}
      row.data = { def = def, holders = h }
      row.name:SetText(when and T.Color(def.name, "ok") or def.name)
      row:SetAlpha(when and 1 or 0.75)
      row.desc:SetText(def.desc)
      row.you:SetText(when and T.Color(date("%d %b", math.floor(when)), "ok") or T.Color("-", "muted"))
      row.guild:SetText(#h > 0 and (#h == 1 and h[1] or (#h .. " members")) or T.Color("-", "muted"))
      row:Show()
    else
      row.data = nil
      row:Hide()
    end
  end
  local n = #F.DEFS
  p.more:SetText(n > FEAT_ROWS and string.format("%d-%d of %d  ·  scroll for more", p.offset + 1, math.min(n, p.offset + FEAT_ROWS), n) or "")
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local PANES = {
  { id = "me", label = "Me", build = buildMe, refresh = refreshMe },
  { id = "guild", label = "Guild", build = buildGuild, refresh = refreshGuild },
  { id = "boards", label = "Boards", build = buildBoards, refresh = refreshBoards },
  { id = "feats", label = "Feats", build = buildFeats, refresh = refreshFeats },
  { id = "loot", label = "Loot", build = buildLoot, refresh = refreshLoot },
  { id = "deaths", label = "Deaths", build = buildDeaths, refresh = refreshDeaths },
  { id = "settings", label = "Settings", build = buildSettings, refresh = refreshSettings },
}

local function savePos()
  local point, _, relPoint, x, y = win:GetPoint(1)
  RL.charDB.window.point = { point, relPoint, x, y }
end

local function build()
  win = CreateFrame("Frame", "RequiemLedgerWindow", UIParent, "BackdropTemplate")
  T.Panel(win, T.c.bg)
  win:SetSize(W, H)
  win:SetFrameStrata("HIGH")
  win:SetClampedToScreen(true)
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
  local p = RL.charDB.window.point
  if type(p) == "table" and p[1] then
    win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    win:SetPoint("CENTER")
  end
  tinsert(UISpecialFrames, "RequiemLedgerWindow") -- Esc closes it

  local top = win:CreateTexture(nil, "ARTWORK")
  top:SetTexture(T.WHITE)
  top:SetVertexColor(unpack(T.c.crimson))
  top:SetPoint("TOPLEFT", 1, -1)
  top:SetPoint("TOPRIGHT", -1, -1)
  top:SetHeight(3)

  local crest = win:CreateTexture(nil, "OVERLAY")
  crest:SetTexture(T.CREST)
  crest:SetSize(56, 56)
  crest:SetPoint("TOPLEFT", 8, 6)

  local title = T.Text(win, 20, "silver", T.TITLE_FONT)
  title:SetPoint("TOPLEFT", 70, -12)
  title:SetText("Nemux Ledger")
  local sub = T.Text(win, 11, "muted")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  win.sub = sub

  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  -- Tabs
  local x = 70
  for _, def in ipairs(PANES) do
    local b = CreateFrame("Button", nil, win)
    b:SetHeight(24)
    b.text = T.Text(b, 13, "muted")
    b.text:SetPoint("CENTER")
    b.text:SetText(def.label)
    b:SetWidth(b.text:GetStringWidth() + 24)
    b:SetPoint("TOPLEFT", x, -54)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetTexture(T.WHITE)
    b.line:SetVertexColor(unpack(T.c.crimson))
    b.line:SetPoint("BOTTOMLEFT", 6, 0)
    b.line:SetPoint("BOTTOMRIGHT", -6, 0)
    b.line:SetHeight(2)
    b:SetScript("OnClick", function() UI:Show(def.id) end)
    b:SetScript("OnEnter", function(self) if activeTab ~= def.id then T.SetColor(self.text, "silver") end end)
    b:SetScript("OnLeave", function(self) if activeTab ~= def.id then T.SetColor(self.text, "muted") end end)
    tabs[def.id] = b
    x = x + b:GetWidth() + 4
  end
  local rule = T.Rule(win, "bronze", 0.5)
  rule:SetPoint("TOPLEFT", 1, -79)
  rule:SetPoint("TOPRIGHT", -1, -79)

  win:SetScript("OnHide", function() GameTooltip:Hide() end)
  win:Hide()
end

local function paneFrame(def)
  local p = panes[def.id]
  if not p then
    p = CreateFrame("Frame", nil, win)
    p:SetPoint("TOPLEFT", 14, -88)
    p:SetPoint("BOTTOMRIGHT", -14, 12)
    def.build(p)
    p.def = def
    panes[def.id] = p
  end
  return p
end

function UI:Refresh()
  if not win or not win:IsShown() then return end
  local p = panes[activeTab]
  if p then p.def.refresh(p) end
end

function UI:RefreshIfVisible(id)
  if win and win:IsShown() and activeTab == id then self:Refresh() end
end

-- "Requiem Forever · Alliance · v0.5.0": from the game, so any guild can use the addon.
local function subtitle()
  local _, faction = RL.Context:Faction()
  local parts = { RL.Context:GuildName() or "No guild" }
  if faction then parts[#parts + 1] = faction end
  parts[#parts + 1] = "v" .. RL.version
  return table.concat(parts, " · ")
end

function UI:Show(id)
  if not win then build() end
  win.sub:SetText(subtitle())
  activeTab = id or activeTab
  for _, def in ipairs(PANES) do
    local selected = def.id == activeTab
    local b = tabs[def.id]
    b.line:SetShown(selected)
    T.SetColor(b.text, selected and "silver" or "muted")
    if selected then
      paneFrame(def):Show()
    elseif panes[def.id] then
      panes[def.id]:Hide()
    end
  end
  win:Show()
  if activeTab == "guild" then
    RL.Guild:RequestRoster()
    RL.Guild:SayHello()
  end
  self:Refresh()
end

-- Guild tab, recipes view, with an optional search text.
function UI:ShowRecipes(query)
  self:Show("guild")
  local p = panes.guild
  if not p then return end
  p.view, p.offset = "recipes", 0
  p.search:SetText(query or "")
  if not query or query == "" then p.search:SetFocus() end
  self:Refresh()
end

function UI:ShowLoot(query)
  self:Show("loot")
  local p = panes.loot
  if p and query then p.search:SetText(query); p.offset = 0; self:Refresh() end
end

function UI:Toggle()
  if win and win:IsShown() then win:Hide() else self:Show() end
end

RL:On("RL_READINESS_UPDATED", function() UI:RefreshIfVisible("me") end)
RL:On("RL_CONTEXT_CHANGED", function() UI:RefreshIfVisible("me") end)
RL:On("RL_DEATHS_UPDATED", function() UI:RefreshIfVisible("deaths") end)
RL:On("SKILL_LINES_CHANGED", function() UI:RefreshIfVisible("me") end)
RL:On("UPDATE_EXHAUSTION", function() UI:RefreshIfVisible("me") end)
RL:On("RL_GUILD_UPDATED", function() UI:RefreshIfVisible("guild") end)
RL:On("RL_RECIPES_UPDATED", function() UI:RefreshIfVisible("guild") end)
-- Item names load later than the tooltip opens; bags change while hovering.
local function rehover()
  local row = UI.hoverRow
  if row and row:IsVisible() and GameTooltip:IsOwned(row) then
    local fn = row:GetScript("OnEnter")
    if fn then fn(row) end
  end
end
RL:On("ITEM_DATA_LOAD_RESULT", rehover)
RL:On("BAG_UPDATE_DELAYED", rehover)
RL:On("RL_FEATS_UPDATED", function() UI:RefreshIfVisible("feats") end)
RL:On("RL_BOARDS_UPDATED", function() UI:RefreshIfVisible("boards") end)
RL:On("RL_LOOT_UPDATED", function() UI:RefreshIfVisible("loot") end)
