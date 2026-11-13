-- Report window (/rq report): everything a tester needs to send, as text that
-- is already selected. Ctrl+C, then paste it into Discord. No file hunting.

local _, RL = ...
local E = RL:NewModule("Export")
RL.Export = E
local T = RL.Theme
local Compat = RL.Compat

local win, edit

local function lines()
  local out = {}
  local function add(fmt, ...) out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
  local version, build, _, iface = GetBuildInfo()
  add("Nemux Ledger %s report", RL.version)
  add("client %s (%s), interface %s", tostring(version), tostring(build), tostring(iface))
  add("level %d, mode %s, resting %s, guild %s", UnitLevel("player"), RL.Context.mode,
    tostring(RL.Context.resting), tostring(IsInGuild()))
  add("buffs readable %s, auras secret %s", tostring(not RL.Readiness.restricted), tostring(Compat.AurasRestricted()))

  add("")
  add("[checks]")
  for _, check in ipairs(RL.Data.CHECKS) do
    local res = RL.Readiness.results[check.id]
    if res then
      add("%s: %s%s%s", check.id, tostring(res.status),
        res.left and string.format(" left=%ds", math.floor(res.left)) or "",
        res.auraName and (" aura=" .. tostring(res.auraName)) or "")
    end
  end

  add("")
  add("[hud]")
  local hud = RL.charDB.hud
  add("state: %s; style %s, hideInCombat %s, inCombat %s", RL.HUD:State(), tostring(hud.style),
    tostring(hud.hideInCombat), tostring(RL.Context.inCombat))
  local tracked, shownIds = {}, {}
  for _, check in ipairs(RL.Data.CHECKS) do
    if RL.Readiness:IsTracked(check.id, RL.Context.mode) then tracked[#tracked + 1] = check.id end
  end
  for _, res in ipairs(RL.Readiness:Attention()) do shownIds[#shownIds + 1] = res.id end
  add("tracked in %s: %s", RL.Context.mode, #tracked > 0 and table.concat(tracked, ",") or "none")
  add("in HUD: %s; last check %s", #shownIds > 0 and table.concat(shownIds, ",") or "none",
    RL.Readiness.evaluatedAt and (math.floor(GetTime() - RL.Readiness.evaluatedAt) .. "s ago") or "never")

  add("")
  add("[buffs now]")
  local buffs = Compat.GetPlayerBuffs()
  if not buffs then
    add("(hidden by the game right now)")
  else
    for _, b in ipairs(buffs) do
      local left = (b.expirationTime and b.expirationTime > 0) and math.floor(b.expirationTime - GetTime()) or -1
      add("%d %s dur=%s left=%s", b.spellId or 0, tostring(b.name), tostring(b.duration), left >= 0 and (left .. "s") or "-")
    end
  end

  add("")
  add("[learned]")
  for cat, ids in pairs(RL.db.learn.known or {}) do
    for id, name in pairs(ids) do add("%s %d %s", cat, id, tostring(name)) end
  end
  for cat, ids in pairs(RL.db.learn.seen or {}) do
    for id, name in pairs(ids) do add("seen in bags: %s %d %s", cat, id, tostring(name)) end
  end
  local log = RL.db.learn.log or {}
  if #log > 0 then
    add("[learn log]")
    for i = 1, math.min(#log, 40) do
      local e = log[i]
      add("%d %s dur=%s zone=%s", e.spellId or 0, tostring(e.name), tostring(e.duration), tostring(e.zone))
    end
  end

  add("")
  add("[sleeping bag]")
  local _, sid = Compat.ItemSpell(RL.Data.SLEEPING_BAG_ITEM)
  add("item spell %s, in bags %d, cooldown %ds", tostring(sid), Compat.ItemCount(RL.Data.SLEEPING_BAG_ITEM),
    math.floor(Compat.ItemCooldownLeft(RL.Data.SLEEPING_BAG_ITEM)))

  add("")
  add("[my professions]")
  for _, pr in ipairs(Compat.MyProfessions()) do
    add("%s line=%s %d/%d", tostring(pr.name), tostring(pr.skillLine), pr.rank or 0, pr.max or 0)
  end
  local gp = RL.Guild:Professions()
  local shown = 0
  for _, r in ipairs(gp) do
    if shown < 6 then
      if r.header then add("guild header %s id=%s players=%d", tostring(r.name), tostring(r.id), r.players or 0)
      else add("guild member %s skillID=%s skill=%s", tostring(r.name), tostring(r.skillID), tostring(r.skill)) end
      shown = shown + 1
    end
  end

  add("")
  add("[deaths]")
  local s = RL.Deaths:Stats()
  if s then
    add("total %d, session %d, week %d", s.total, s.session, s.week)
    for i = 1, math.min(#s.list, 5) do
      local e = s.list[i]
      add("%s %s %s%s", e.id or "?", tostring(e.where), tostring(e.zone), e.boss and (" boss=" .. e.boss) or "")
    end
  end

  add("")
  add("[guild]")
  local G = RL.Guild
  add("name %s, members %d, online %d, with addon %d, professions api %s", G.info and G.info.name or "-",
    G.total, G.online, G:PeerCount(), tostring(G:ProfessionsAvailable()))
  add("me in roster: %s", tostring(G:IsMe(G.FullName(UnitName("player")))))
  for name, p in pairs(G.peers) do
    local profs = {}
    for id, pr in pairs(p.profs or {}) do profs[#profs + 1] = id .. ":" .. pr.rank end
    add("peer %s v%s deaths=%d profs=%s", name, p.version, p.deaths or 0, table.concat(profs, ","))
  end

  add("")
  add("[recipes]")
  for line, rec in pairs(RL.charDB.recipes) do
    add("mine %s (line %s): %d", RL.Recipes:LineName(line), tostring(line), rec.n or 0)
  end
  for who, rec in pairs(RL.db.guildRecipes) do
    local parts = {}
    for line, l in pairs(rec.lines or {}) do parts[#parts + 1] = line .. ":" .. (l.n or 0) end
    add("from %s: %s", who, table.concat(parts, ","))
  end
  -- Does the game give reagents for someone else's recipe right now?
  local tried = 0
  for who, rec in pairs(RL.db.guildRecipes) do
    for line, l in pairs(rec.lines or {}) do
      for id in pairs(l.ids or {}) do
        if tried < 2 then
          tried = tried + 1
          local live = Compat.RecipeReagents(id)
          add("reagents live for %s's %d (%s): %s", RL.Guild.Short(who), id, tostring(RL.Recipes:RecipeName(id)),
            live and (#live .. " reagents") or "no answer")
        end
      end
    end
  end
  local cached = 0
  for _ in pairs(RL.db.reagents) do cached = cached + 1 end
  add("reagents remembered: %d recipes", cached)
  local ls = RL.Recipes.lastScan
  add("last window read: %s", ls and (ls.ok and string.format("ok via %s, line %s, %d recipes", ls.source, tostring(ls.line), ls.n)
    or ("failed: " .. tostring(ls.reason))) or "no profession window opened this session")
  local has = {}
  for _, a in ipairs({ "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetBaseProfessionInfo", "GetNumTradeSkills",
    "GetTradeSkillRecipeLink", "GetNumCrafts", "GetCraftItemLink", "GetCraftRecipeLink" }) do
    has[#has + 1] = a .. "=" .. (Compat.Has(a) and "y" or "n")
  end
  add("apis: %s", table.concat(has, " "))
  for line, rec in pairs(RL.charDB.recipes) do
    local shown = 0
    for id in pairs(rec.ids or {}) do
      if shown < 3 then add("sample %s: %d = %s", tostring(line), id, tostring(RL.Recipes:RecipeName(id))); shown = shown + 1 end
    end
  end

  add("")
  add("[feats]")
  local ids = {}
  for id in pairs(RL.charDB.feats.earned) do ids[#ids + 1] = id end
  table.sort(ids)
  add("mine: %s; meals %s, sleeping bags %s", #ids > 0 and table.concat(ids, ",") or "none",
    tostring(RL.charDB.feats.counts.meals or 0), tostring(RL.charDB.feats.counts.bags or 0))
  for who, rec in pairs(RL.db.guildFeats) do
    local n = 0
    for _ in pairs(rec.ids or {}) do n = n + 1 end
    add("from %s: %d", who, n)
  end

  add("")
  add("[boards]")
  add("my hk %d, week starts %ds ago", RL.Boards:MyHonorKills(), GetServerTime() - RL.Boards:WeekStart())
  for who, rec in pairs(RL.db.guildStats) do
    add("%s deaths=%d week=%d hk=%d", who, rec.deaths or 0, rec.week or 0, rec.hk or 0)
  end
  add("feed entries %d", #RL.db.deathFeed)

  add("")
  add("[loot]")
  local lootN = 0
  for _ in pairs(RL.db.loot) do lootN = lootN + 1 end
  add("sources: %s; entries %d; Gargul %s, RCLootCouncil %s", table.concat(RL.Loot:Sources(), ","), lootN,
    tostring(type(_G.Gargul) == "table"), tostring(type(_G.RCLootCouncil) == "table"))

  local apis = { "C_UnitAuras.GetAuraDataByIndex", "C_Item.GetItemSpell", "C_Container.GetItemCooldown",
    "C_ChatInfo.SendAddonMessage", "C_ChatInfo.InChatMessagingLockdown", "C_GuildInfo.GuildRoster",
    "GetGuildRosterInfo", "GetNumGuildTradeSkill", "QueryGuildRecipes", "RaidNotice_AddMessage" }
  local missing = {}
  for _, a in ipairs(apis) do if not Compat.Has(a) then missing[#missing + 1] = a end end
  add("")
  add("missing apis: %s", #missing == 0 and "none" or table.concat(missing, ", "))
  return table.concat(out, "\n")
end
E.Text = lines

local function build()
  win = CreateFrame("Frame", "RequiemLedgerReport", UIParent, "BackdropTemplate")
  T.Panel(win, T.c.bg)
  win:SetSize(520, 420)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  tinsert(UISpecialFrames, "RequiemLedgerReport")

  local title = T.Text(win, 16, "silver", T.TITLE_FONT)
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("Tester report")
  win.title = title
  local hint = T.Text(win, 11, "muted")
  hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  hint:SetText("The text is selected: press Ctrl+C, then paste it to Discord.")
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local box = CreateFrame("Frame", nil, win, "BackdropTemplate")
  T.Panel(box, { 0.02, 0.03, 0.07, 1 })
  box:SetPoint("TOPLEFT", 12, -56)
  box:SetPoint("BOTTOMRIGHT", -12, 44)

  local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -26, 6)

  edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFont(T.FONT, 11, "")
  edit:SetWidth(450)
  edit:SetScript("OnEscapePressed", function() win:Hide() end)
  -- Keep the text read-only: any typing puts the report back.
  edit:SetScript("OnTextChanged", function(self, user)
    if user then self:SetText(self.report or ""); self:HighlightText() end
  end)
  scroll:SetScrollChild(edit)

  local again = T.Button(win, "Select all", 110, 22, function() edit:SetFocus(); edit:HighlightText() end)
  again:SetPoint("BOTTOMLEFT", 12, 12)
  local refresh = T.Button(win, "Refresh", 110, 22, function() E:ShowText(win.title:GetText(), win.source) end)
  refresh:SetPoint("LEFT", again, "RIGHT", 8, 0)
end

-- Any copyable text: title, and a function that builds the text.
function E:ShowText(title, source)
  if not win then build() end
  win.title:SetText(title)
  win.source = source
  edit.report = source()
  edit:SetText(edit.report)
  win:Show()
  edit:SetFocus()
  edit:HighlightText()
end

function E:Show()
  self:ShowText("Tester report", lines)
end
