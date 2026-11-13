-- Slash commands: /rq and /requiem

local _, RL = ...
local Compat = RL.Compat

local HELP = {
  "/rq — open or close the window",
  "/rq hud — show the HUD again (after a snooze or if it was hidden)",
  "/rq hud reset — move the HUD back to its default place",
  "/rq buffs — list your buffs with spell IDs",
  "/rq learn food|flask|elixir — teach the addon the buff you just got",
  "/rq learn on|off|show|clear — learn mode for testers",
  "/rq death — preview a death phrase (not counted)",
  "/rq report — tester report to copy (Ctrl+C) and send",
  "/rq diag — short technical info in chat",
  "/rq guild — the Guild tab",
  "/rq recipes [name] — search guild recipes",
  "/rq feats — the Feats tab",
  "/rq boards — leaderboards and recent guild deaths",
  "/rq week — weekly guild report to copy into Discord",
  "/rq loot [player or item] — the loot log (from Gargul / RCLootCouncil)",
  "/rq ignore <shift-click item> — never count it as an elixir/flask; /rq ignore lists; /rq unignore <item>",
  "/rq track — show the recipe tracker; /rq track clear — stop tracking",
}

local function diag()
  RL:Print("Version %s · client %s · interface %s", RL.version, (GetBuildInfo()), select(4, GetBuildInfo()) or "?")
  RL:Print("Mode: %s · combat: %s · resting: %s · max level: %s",
    RL.Context.mode, tostring(RL.Context.inCombat), tostring(RL.Context.resting), tostring(RL.Context:IsMaxLevel()))
  RL:Print("Buffs readable: %s · auras secret now: %s", tostring(not RL.Readiness.restricted), tostring(Compat.AurasRestricted()))
  local apis = { "C_UnitAuras.GetAuraDataByIndex", "C_Item.GetItemSpell", "C_Item.GetItemCount", "C_Container.GetItemCooldown",
    "GetWeaponEnchantInfo", "C_Secrets.ShouldAurasBeSecret", "issecretvalue", "C_ChatInfo.SendAddonMessage" }
  local missing = {}
  for _, a in ipairs(apis) do if not Compat.Has(a) then missing[#missing + 1] = a end end
  RL:Print("Missing APIs: %s", #missing == 0 and "none" or table.concat(missing, ", "))
  local bag = RL.Readiness.results.sleepingbag
  RL:Print("Sleeping Bag: %s", bag and bag.status or "?")
  local _, sid = Compat.ItemSpell(RL.Data.SLEEPING_BAG_ITEM)
  RL:Print("Sleeping Bag item spell: %s", tostring(sid))
end

SLASH_REQUIEMLEDGER1 = "/rq"
SLASH_REQUIEMLEDGER2 = "/requiem"
SlashCmdList.REQUIEMLEDGER = function(msg)
  local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "" then
    RL.UI:Toggle()
  elseif cmd == "help" or cmd == "?" then
    for _, line in ipairs(HELP) do RL:Print(line) end
  elseif cmd == "hud" then
    if rest == "reset" then
      RL.HUD:ResetPosition()
      RL:Print("HUD moved back to its default place.")
    else
      if RL.charDB.hud.style == "off" then RL.charDB.hud.style = "text" end
      RL.HUD:Unsnooze()
      RL.Readiness:Evaluate()
      RL:Print("HUD is on. It only appears when something needs your attention.")
    end
  elseif cmd == "buffs" then
    RL.Learn:ListBuffs()
  elseif cmd == "learn" then
    if rest == "on" then RL.Learn:SetEnabled(true)
    elseif rest == "off" then RL.Learn:SetEnabled(false)
    elseif rest == "show" then RL.Learn:Show()
    elseif rest == "clear" then RL.Learn:Clear()
    else RL.Learn:Mark(rest) end
  elseif cmd == "death" then
    RL.Deaths:Preview()
  elseif cmd == "report" or cmd == "export" then
    RL.Export:Show()
  elseif cmd == "guild" then
    RL.UI:Show("guild")
  elseif cmd == "recipes" or cmd == "recipe" or cmd == "craft" then
    RL.UI:ShowRecipes(rest)
  elseif cmd == "ignore" or cmd == "unignore" then
    local id = tonumber(rest:match("item:(%d+)") or rest:match("^(%d+)$"))
    if id then
      RL.Readiness:Ignore(id, cmd == "ignore")
      RL:Print("%s %s.", Compat.ItemName(id) or ("Item " .. id), cmd == "ignore" and "is ignored now" or "counts again")
    else
      local names = {}
      for itemID, name in pairs(RL.db.ignoreItems or {}) do names[#names + 1] = (type(name) == "string" and name or "Item") .. " (" .. itemID .. ")" end
      RL:Print("Ignored by you: %s. Built in: Noggenfogger, Water Breathing/Walking, Detect elixirs, Giant Growth, Catseye, Poison Resistance.",
        #names > 0 and table.concat(names, ", ") or "nothing")
      RL:Print("To ignore an item: /rq ignore then shift-click it.")
    end
  elseif cmd == "loot" then
    RL.UI:ShowLoot(rest)
  elseif cmd == "week" or cmd == "weekly" then
    RL.Export:ShowText("Weekly report", function() return RL.Weekly:FullText() end)
  elseif cmd == "track" then
    if rest == "clear" then RL.Tracker:Clear(); RL:Print("Tracking stopped.") else RL.Tracker:Show() end
  elseif cmd == "boards" or cmd == "top" then
    RL.UI:Show("boards")
  elseif cmd == "feats" or cmd == "feat" then
    RL.UI:Show("feats")
  elseif cmd == "diag" then
    diag()
  elseif cmd == "debug" then
    RL.charDB.debug = not RL.charDB.debug
    RL:Print("Debug messages %s.", RL.charDB.debug and "on" or "off")
  else
    RL:Print("Unknown command. Type /rq help.")
  end
end
