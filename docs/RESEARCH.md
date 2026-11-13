# Requiem Ledger — Stage 0: Research & Feasibility

> Status: draft for discussion · Date: 2026-11-10 · Client: WoW: Forever 1.60.1 (build 70790, Interface 16001)
>
> Status labels used throughout the document:
> - **[CONF]** — confirmed by a source (Blizzard, warcraft.wiki.gg, or the client API dump).
> - **[INF]** — inference from Midnight-era rules or indirect data.
> - **[UNV]** — from a single third-party source or from beta material.
> - **[TEST]** — must be checked in the live client.
>
> Nothing here has been tested in a live client yet. I have no access to the game. The API dump shows that a function or event **exists**. It does not show **how it behaves** or whether its values are secret.

Your additions to the brief, recorded as requirements:
1. **English only.** No localization layer is planned. All UI strings still live in one module: it costs nothing and makes the code cleaner.
2. **Works solo first.** Extra features turn on when you are in a party or raid.
3. **Priority:** tracking food, flasks and **XP buffs from food** for Forever.

---

## 1. WoW: Forever as an addon platform

### 1.1 Key facts

| Fact | Status | Source |
|---|---|---|
| Launched 2026-11-04. Based on 2004 Azeroth, level 60 cap, Legacy System (account-wide perks) | [CONF] | [Blizzard News](https://news.blizzard.com/en-us/article/24315820/world-of-warcraft-forever-now-live), [Wiki](https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever) |
| Client 1.60.1, `## Interface: 16001` | [CONF] | [TOC format](https://warcraft.wiki.gg/wiki/TOC_format), [atraeau API dump](https://atraeau.github.io/WoW-Addons/api.json) (build 70790, Nov 3 2026) |
| TOC suffix `_Forever.toc` (alias `_Camelot.toc`). Part of the **Mainline** family, so `_Mainline.toc` loads too. `_Classic.toc` does **not** load | [CONF] | [TOC format](https://warcraft.wiki.gg/wiki/TOC_format) |
| `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT (18)` | [CONF] | [WOW_PROJECT_ID](https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID) |
| **"WoW Forever shares Mainline WoW's UI architecture, including the vast majority of APIs available in 12.1.5"** | [CONF] | [Patch 1.60.1 API notes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes) |
| **"The addon disarmament changes introduced in Midnight, including secrets, will also be active in Forever"** | [CONF] | same |
| Trial and veteran accounts **cannot send** addon messages | [CONF] | same |
| Characters have a **first name and a surname**. Rulesets (Normal/PvP/RP/RP-PvP) work as "mega-realms" instead of realms. Ace3, Gargul and Details! all had to fix name parsing | [CONF] | [Ace3 commits](https://github.com/WoWUIDev/Ace3/commits), [Icy Veins: surnames](https://www.icy-veins.com/wow-forever/surnames) |
| Lua `require` was renamed to `import`. `GetSpellInfo` and `GetItemInfo` globals are gone, use `C_Spell` / `C_Item` | [CONF] | 1.60.1 notes, dump |
| Raids open on Dec 9: **Barrow Deeps (10)**, **Hyjal Summit (20)**, **Onyxia's Lair (40)**. Nine new dungeons for levels 13–60 | [CONF] | [Wiki](https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever) |
| Hardcore ruleset is planned "after launch" (Winter 2026/27) | [CONF] | same |
| Warcraft Logs supports Forever (forever.warcraftlogs.com) | [UNV] (from WCL posts on X, quoted in search results) | [X post](https://x.com/WarcraftLogs/status/2117767961482318221) |

### 1.2 Main conclusion: this is the Midnight API, not Classic

Forever **is not** Classic Era 1.15 from an addon's point of view. It is the modern Mainline API (12.1.5) with every Midnight restriction. That has three consequences:

1. Classic addons and the Classic API do not port. We write against `C_*` namespaces, and our references are Midnight addons.
2. **`COMBAT_LOG_EVENT_UNFILTERED` is unavailable.** In the dump, `CombatLogGetCurrentEventInfo` is absent. On Midnight, registering CLEU throws `ADDON_ACTION_FORBIDDEN` ([CLEU](https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT_UNFILTERED)) [CONF for Midnight / INF for Forever]. **Combat analytics inside the addon in the classic sense is impossible.**
3. **Secret values.** Under combat, encounter, M+/PvP restrictions, and in "communication-restricted maps such as dungeons and raids", many fields (auras, unit identity, chat messages) become *secret*. The addon can pass them to Blizzard widgets, but it cannot read, compare or store them ([Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values)) [CONF for Midnight / INF for Forever].

The dump contains the whole toolkit for working with this: `C_Secrets.*` (`ShouldAurasBeSecret`, `GetSpellAuraSecrecy`, `ShouldUnitIdentityBeSecret`…), `issecretvalue()`, `C_RestrictedActions.IsAddOnRestrictionActive/GetAddOnRestrictionState`, the event `ADDON_RESTRICTION_STATE_CHANGED`, and `C_ChatInfo.InChatMessagingLockdown()` [CONF, present in the dump].

**Architecture principle that follows:** *"Collect outside restrictions, defer during restrictions, never guess."* Every collector checks the restriction state. Any secret value gets status `Unknown`, never 0 or `Missing`.

### 1.3 Data available outside and during combat

| Data | Outside combat / open world | In combat / encounter / instance |
|---|---|---|
| Your own auras (`C_UnitAuras.GetPlayerAuraBySpellID`, `GetUnitAuras("player")`) | Yes [CONF API] | Probably secret [INF]. Some spells may be non-secret, check with `C_Secrets.GetSpellAuraSecrecy` [TEST] |
| Party/raid members' auras | Probably readable [INF][TEST] | Secret [INF] |
| Bag contents (`C_Item.GetItemCount`) | Yes [CONF API] | Probably yes, it is not combat data [TEST] |
| Rested (`GetXPExhaustion`, `IsResting`, `UPDATE_EXHAUSTION`) | Yes [CONF API] | Yes [INF] |
| Your own death (`PLAYER_DEAD`) | Yes [CONF API] | Yes, the event has no payload [CONF API] |
| Other players' deaths (`UNIT_DIED(unitGUID)`) | Yes [CONF API] | GUID is secret under `SecretWhenUnitIdentityRestricted` [CONF wiki for Midnight] |
| ENCOUNTER_START/END, BOSS_KILL | Yes, with encounterID, success, groupSize [CONF API] | Not secret is assumed [TEST] |
| Loot: `ENCOUNTER_LOOT_RECEIVED`, `C_LootHistory.*`, `CHAT_MSG_LOOT` | Yes [CONF API] | Chat messages in instances may be secret [INF][TEST] |
| Damage/healing | No (no CLEU). There is `C_DamageMeter` (Blizzard's built-in meter) | Data is secret during combat. Available after combat is [TEST] |

### 1.4 SavedVariables

- `## SavedVariables` (account-wide) and `## SavedVariablesPerCharacter` (per character) in `WTF\Account\…` [CONF] ([SavedVariables](https://warcraft.wiki.gg/wiki/SavedVariables)).
- They are written on logout or `/reload`. **A client crash loses the session's data.** This is unavoidable, so design for it.
- I found no Forever-specific size limit. In practice, files over a few MB slow down load time and logout. Cap the history (§8).
- There was a bug on the beta where SV were not restored. It was reportedly fixed in build 70009 [UNV].

### 1.5 Addon messages

| Parameter | Value | Status |
|---|---|---|
| API | `C_ChatInfo.RegisterAddonMessagePrefix`, `SendAddonMessage`, `SendAddonMessageLogged`, event `CHAT_MSG_ADDON` | [CONF dump] |
| Channels | PARTY, RAID, INSTANCE_CHAT, GUILD, OFFICER, WHISPER, CHANNEL | [CONF wiki] |
| Prefix ≤ 16 chars, message ≤ **255 bytes** | | [CONF wiki] |
| Throttle: **10 messages per prefix, regenerating at 1/s** (whispers outside instances are exempt) | | [CONF wiki] |
| `Enum.SendAddonMessageResult`: 11 = AddOnMessageLockdown, 12 = TargetOffline | | [CONF wiki] |
| Lockdown during encounters and other restricted content, lifted at ENCOUNTER_END | | [INF] (Midnight community docs; Blizzard has not stated the exact Forever rules) |
| Trial accounts cannot send | | [CONF] |
| Native compression/serialization: `C_EncodingUtil.CompressString`, `SerializeCBOR` | | [CONF dump] |

### 1.6 APIs that may change

The most likely to change:
- The rules for secrets and lockdowns. Blizzard has already relaxed them several times on Midnight.
- The list of non-secret spells.
- Names, realms and rulesets: the surname layer is new and is still being patched.
- Loot APIs: the loot model for Forever raids is undocumented.
- Legacy System: the dump has no `C_LegacySystem*`, so the API is not public or is named differently [TEST].

How we protect against this: every API call goes through a thin `Compat` layer with feature detection (`if C_X and C_X.Fn`), plus a "capabilities" list shown in Settings → Diagnostics.

---

## 2. Feasibility matrix

Legend: ✅ confirmed and feasible · 🟡 probably feasible, needs a client test · 🟠 partially feasible · 🔵 needs an external tool · ⛔ impossible with the current API

### 2.1 Readiness (food, flasks, XP) — **your priority**

| Feature | API / events | Limitations | Sync | Storage | Complexity | Reliability | Class |
|---|---|---|---|---|---|---|---|
| My Well Fed / food buff | `C_UnitAuras.GetPlayerAuraBySpellID`, `UNIT_AURA(player)` | Secret in combat. Check before pull | No | Config (spell list) | Low | High outside combat | ✅/🟡 |
| My food **XP buff** (+5% XP from kills) | Same | The aura ID and whether the bonus is a separate aura are unknown [UNV] | No | — | Low | Unknown until a test | 🟡 |
| My flask / elixirs / weapon oil | Auras + `GetWeaponEnchantInfo` [TEST] | Flask/elixir stacking rules conflict between sources | No | Config | Medium | High | 🟡 |
| My consumables in bags (potions: 12) | `C_Item.GetItemCount`, `BAG_UPDATE_DELAYED` | — | No | — | Low | High | ✅ |
| Rested XP | `GetXPExhaustion`, `IsResting`, `UPDATE_EXHAUSTION`, `PLAYER_UPDATE_RESTING` | — | No | — | Low | High | ✅ |
| Sleeping Bag: in bags / ready / active | `GetItemCount(211527)`, `C_Item.GetItemCooldown` [TEST], aura | Aura ID 429959 is from SoD [UNV]. Cooldown is 1h or 2h40m (sources disagree) | No | — | Low | Medium until a test | 🟡 |
| Camping buffs | Auras | Mutually exclusive with class buffs [CONF]. IDs unknown | No | — | Low | — | 🟡 |
| Party/raid members' buffs (no addon) | `GetUnitAuras("partyN"/"raidN")` outside combat | Readability out of combat is [INF][TEST]. Bags are unreachable | No | Not stored (live only) | Medium | Medium | 🟡 |
| Party/raid members' buffs and bags (with addon) | Self-report over PARTY/RAID | Lockdown in instances. Send before pull and at READY_CHECK | Yes | Short-lived cache + TTL | Medium | High while fresh | 🟡 |
| Ready Check integration | `READY_CHECK`, `READY_CHECK_CONFIRM` | No automatic clicking (protected) | Report | — | Low | High | ✅ |

### 2.2 Other modules

| Feature | Key API | Limitations | Sync | Class |
|---|---|---|---|---|
| Guild roster, online, ranks, level, class | `C_GuildInfo.GuildRoster`, `GetGuildRosterInfo`, `GUILD_ROSTER_UPDATE` | Name+surname+ruleset, so we need our own identity key | No | ✅ |
| Profiles: main/alts | Manual linking + self-report from the alt ("I am an alt of X") | No reliable automatic way. We do not touch Battle.net | Yes | ✅ (manual) |
| Professions (mine) | `GetProfessions`, `GetProfessionInfo`, `C_TradeSkillUI` | — | Self-report | ✅ |
| Professions (others) | Self-report only | Players without the addon: unknown | Yes | 🟠 |
| Role | Manual + `UnitGroupRolesAssigned` in a group | No role specs in vanilla | Yes | ✅ |
| **Death: my own** total, per session, world/dungeon/raid | `PLAYER_DEAD` + `GetInstanceInfo` + zone | — | Self-report | ✅ |
| Death: during an active encounter | `ENCOUNTER_START` → stored context → `PLAYER_DEAD` | The context is ours, the event is reliable | Self-report | ✅/🟡 |
| Death: PvP vs PvE | Duel/BG flags, `UnitIsPVP`, instanceType=pvp | **Killer and cause unknown** (no CLEU). Can only say "died in PvP context" | — | 🟠 |
| Deaths of others without the addon | `UNIT_DIED` outside restrictions. In raids the GUID is secret | In a raid only via the self-report of players with the addon | — | 🟠 |
| Cause of death, damage, "who killed" | — | No CLEU. The Death Recap API exists but its content is probably secret [TEST] | — | ⛔ in-addon / 🔵 via logs |
| **Loot** with boss link | `ENCOUNTER_LOOT_RECEIVED(encounterID,itemID,itemLink,…)`, `C_LootHistory.GetAllEncounterInfos/GetSortedInfoForDrop`, `LOOT_HISTORY_UPDATE_DROP` | Raid loot model unknown. The winner field and secrecy need a test | Yes (dedup) | 🟡 |
| Loot (fallback) | `CHAT_MSG_LOOT` + parsing via GlobalStrings | May be secret in an instance. Boss link only by time window, so "probable" | Yes | 🟠 |
| Guild achievements (custom) | Built from our own events (deaths, kills, loot, level-up `PLAYER_LEVEL_UP`, professions) | Reliability equals the reliability of the source event | Yes | ✅/🟡 |
| Blizzard achievements and statistics | `ACHIEVEMENT_EARNED`, `GetStatistic` exist in the API | Unknown whether Forever has achievements [TEST] | — | 🟡 |
| Raid Planner (own events) | Addon messages over GUILD | No server. Peer-to-peer propagation | Yes | ✅ |
| Built-in calendar | `C_Calendar.*` present | Reading guild events: yes. Creating/inviting from the addon: possibly needs a hardware event [TEST] | — | 🟡 |
| Raid history: pulls, wipes, kills, duration, roster | `ENCOUNTER_START/END(success)`, `BOSS_KILL`, group roster | Reliable | Yes | ✅ |
| Deaths per pull (by player) | Self-report from players with the addon | Without the addon: unknown | Yes | 🟠 |
| DPS/HPS, damage taken, debuffs | `C_DamageMeter` (after combat [TEST]) or logs | Data secret during combat | — | 🟠/🔵 |
| Duels: win/loss | `DUEL_REQUESTED`, `DUEL_FINISHED` (no payload) + `CHAT_MSG_SYSTEM` (`DUEL_WINNER_KNOCKOUT` pattern) | Is the system text secret? [TEST]. Fallback: both participants self-report | Yes | 🟡 |
| PvP: lifetime HKs, rank | `GetPVPLifetimeStats` | Battleground stats (`C_PvP`) are secret during the match [INF] | — | 🟡 |
| Tournaments | Manual brackets + duel results | — | Yes | ✅ (manual) |

---

## 3. Competitor analysis

| Addon | What it does well | Forever | Our conclusion |
|---|---|---|---|
| **Guild Muster – Revenant** | Calendar, sign-ups, attendance, loot history (reads Gargul), officer tools. P2P | ✅ 0.31.21 (11-09) | **The closest competitor.** Small (~1.2K downloads), launched alongside Forever. Worth a hands-on look ([CF](https://www.curseforge.com/wow/addons/guild-muster)) |
| **Gargul** | Loot master, soft-reserve/TMB, GDKP, auto-loot | ✅ ([GitHub](https://github.com/papa-smurf/Gargul)) | **We do not replace loot distribution.** We read its award history |
| **Details!** | Meter, death log, plugin API | ✅ `Details_Camelot.toc` ([GitHub](https://github.com/Tercioo/Details-Damage-Meter)) | **We do not build a meter.** Optional integration |
| **GuildDeathLog / Guild Chronicle** | Guild deaths, memorials, 46 "survival achievements", Hall of Fame | ✅ v10.2.0 ([CF](https://www.curseforge.com/wow/addons/guild-death-log)) | A direct competitor for Deaths and Achievements. We set ourselves apart with the raid context (deaths per encounter/pull) and a reliability marker |
| **GRM** | Deepest roster tracking, alts, joins/leaves | ✅ ([CF](https://www.curseforge.com/wow/addons/guild-roster-manager)) | We do not duplicate an officer audit log. We keep a light roster |
| **NovaRaidCompanion** | Buffs, consumables, raid logs | ✅ v1.97 ([CF](https://www.curseforge.com/wow/addons/nova-raid-companion)) | Our Readiness competitor. Our differences: solo-first, XP buffs, Sleeping Bag, honest statuses |
| **Method Raid Tools** | Raid checks, notes | ✅ | We do not make notes or cooldown planners |
| **Guilded** | Attendance, EPGP, loot council, Discord bot | ✅ 9.1.3 | Heavy and tied to an external service |
| **Altoholic** | Data for all your own characters | ✅ | The model for personal alt data |
| RCLootCouncil, CLM, CEPGP, Deathlog, Recount, WeakAuras | — | ❌ no Forever build | An import from their exports is optional |
| Warcraft Logs | Analysis of the combat log file | ✅ [UNV] | **The basis for Extended Analytics** instead of our own parser |

**Where Requiem Ledger is stronger:** one ledger instead of 4–5 addons. It is aware of name+surname+ruleset. It is built from scratch for secrets/lockdown (queue + deferred sync). It works solo. It is honest about data reliability. It is the only one with personal XP-readiness (food XP, Sleeping Bag, rested, camping). It covers PvP and duels, where we found no living Forever addon.

---

## 4. Data synchronization

### 4.1 Model: event log (event sourcing), not table sync

Every fact is an **immutable event** created by its **author** (whoever observed it):

```
{ id = "<originKey>:<seq>", t = <type>, ts = GetServerTime(), o = <originKey>,
  v = <schema version>, d = { ...payload... } }
```

- `originKey` is a stable key of the author's character. It is built from the player GUID (`UnitGUID("player")`), which is stable for a character and not tied to the name or surname. The name is stored separately as a mutable attribute.
- `seq` is a monotonic counter per character (stored in SV).
- **Deduplication** comes from the ID: an event cannot be counted twice. Loot and kills that several witnesses see are deduplicated with a **natural key** (`encounterID + raid-session + itemLink + recipientKey`), which merges the copies into one fact with several witnesses. More witnesses means higher reliability.
- **Corrections** are separate events (`correction`, `void`) that point to the original. History is never overwritten, which fulfils "manual correction with an edit history".
- **Trust:** an author can only report facts **about themselves** (my death, my buffs, my professions). Facts about others (loot, kills) count as "witnessed". Officer actions are accepted only from ranks listed in a policy config. Rank is checked against our local guild roster, not against what the message claims.

### 4.2 Transport

| Situation | Channel | Behaviour |
|---|---|---|
| Solo / outside the guild | — | Fully local. Sync is optional |
| Guild, open world, city | GUILD | Delta sync on login and periodically (rare) |
| Party / raid outside restrictions | PARTY / RAID | Readiness snapshots, raid-session events |
| Encounter / lockdown (`InChatMessagingLockdown()` = true, result 11) | — | **Outbound queue.** Flushed after `ADDON_RESTRICTION_STATE_CHANGED` / `ENCOUNTER_END` |
| Trial account | — | Receive only |

**Delta sync protocol** (inspired by vector clocks):
1. `HELLO`: protocol version + a digest of `{originKey → maxSeq}`, compressed. It is sent at most once per N minutes, with random jitter.
2. A peer compares and asks for what is missing (`REQ origin from..to`).
3. **One** responder answers (the lowest GUID among those who have the data, plus a random delay), so ten people do not all reply.
4. The payload is CBOR (`C_EncodingUtil.SerializeCBOR`) → `CompressString` → base64 → chunks ≤ 240 bytes → ChatThrottleLib/AceComm with priority `BULK`.

**Message validation:** check the prefix, protocol version, size limits, field types and ranges against a schema, and that the sender equals `originKey` for self-report events. Unknown types are ignored. **No `loadstring`, no code from the network.** Rate-limit incoming messages per sender.

**Version compatibility:** a protocol version (major/minor). A different major means "no sync, show a warning". A newer minor is fine: unknown fields are ignored.

### 4.3 What does not need sync
Live readiness of party members is an ephemeral snapshot with a TTL (for example 10 minutes). It is not written into the shared history, only a summary at the moment of the pull. A snapshot older than its TTL shows as **Outdated**.

---

## 5. Raid Analytics and combat log limits

### Tier 1 — In-game (built into the addon)
Data that is reliably available:
- **Raid session:** instanceID, start and end, roster (snapshots on `GROUP_ROSTER_UPDATE`).
- **Pull:** `ENCOUNTER_START` → `ENCOUNTER_END(success)`, duration, groupSize, attempt number. **Kill or wipe is reliable.**
- **Deaths in a pull:** self-reports from players with the addon (a `PLAYER_DEAD` while an encounter context is active). Coverage = `reports / roster`, and it is shown next to the number ("Deaths: 7 (coverage 14/20)").
- **Loot per encounter:** `ENCOUNTER_LOOT_RECEIVED` / `C_LootHistory` [TEST].
- **Damage/healing:** optional, via `C_DamageMeter` after combat, if it is not secret [TEST].

**Not available in Tier 1:** cause of death, killing ability, damage taken, avoidable damage, debuffs, consumable use during combat.

### Tier 2 — Extended (optional, external)
- Advanced Combat Logging (`LoggingCombat`, CVar `advancedCombatLogging`) writes `Logs\WoWCombatLog*.txt` [CONF API; the file format on Forever is INF].
- **Recommendation: Warcraft Logs, not our own parser.** WCL already parses Forever logs [UNV]. The addon stores a **link to the WCL report** in the raid session (an officer pastes it). Our own log parser (CLI/desktop) is a separate project for later, only if WCL misses something critical, such as guild-only stats across many reports.
- An addon **cannot read files**. Data can get back into the game only through a hand-pasted import string. That is possible, but it is not part of the MVP.

The base addon never depends on Tier 2.

---

## 6. Readiness: food, flasks, XP buffs, Sleeping Bag

### 6.1 What we know about Forever mechanics

| Item | Data | Status |
|---|---|---|
| **Well Fed gives +5% XP from kills** | "Being Well Fed gives you 5% increased experience from kills" | [UNV] — [Warcraft Tavern](https://www.warcrafttavern.com/forever/news/cooked-food-provides-an-xp-buff-in-world-of-warcraft-forever), [Method](https://www.method.gg/wow-forever/list-of-all-consumables-and-enchants-in-wow-forever). Quests unclear |
| New food, item IDs 249869–250075 (Savory Turtle Stew 250068, Steaming Stag Steak 250071, Swiftstrike Steak 250072, Prehistoric Pulled Raptor 250075, Wicked Smoothie 249876, Sage's Tea 249870, Sunny Tea 249869) + vanilla (Nightfin Soup 13931, Mightfish Steak 13934, Grilled Squid 13928) | Beta data | [UNV] |
| Well Fed aura **spell ID** and duration | **Not found** | [TEST] |
| Legacy perk "Gourmand": +33% food buff duration (3 ranks) | | [UNV] |
| New "Natural" flasks 274273–274276 (+60 Stam + a stat). **They only work in Mount Hyjal, Hyjal Summit, Barrow Deeps** | Beta data | [UNV] |
| Vanilla flasks (Titans 13510, Distilled Wisdom 13511, Supreme Power 13512…), new elixirs 250xxx | | [UNV] |
| Flask + elixir stacking | **Sources disagree** | [TEST], so the rules must be configurable |
| **Cozy Sleeping Bag, item 211527.** Added in 1.60.1. Reward for the quest "This Must Be The Place" (from level 14, Westfall/Barrens). +1% XP per minute rested, up to 3%. Cannot be used in a rested zone. Sold by Rix Xizzix (Booty Bay) | | **[CONF]** — [Wiki](https://warcraft.wiki.gg/wiki/Cozy_Sleeping_Bag) |
| Sleeping Bag buff "Well-Rested" spell 429959 | This is the SoD ID | [UNV] — [Warcraft Tavern](https://www.warcrafttavern.com/forever/guides/cozy-sleeping-bag/) |
| Sleeping Bag cooldown | 1h (WT) vs 2h40m (Wiki) | [TEST] |
| Camping: campsite buffs, mutually exclusive with class buffs | | [CONF] Blizzard |
| Legacy perk "Well Rested": +4% rest accrual rate and cap per rank (5 ranks) | | [UNV] |
| World buffs exist but are removed inside dungeons and raids. The exact list is unknown | | [UNV] |

**Conclusion:** the mechanics are confirmed, but **almost none of the aura IDs are confirmed for live**. So:
1. All IDs live in a separate **data file** (`Data/Consumables.lua`), not in logic code.
2. Matching uses **spell ID first, then aura name as a fallback** (`GetAuraDataBySpellName`). English-only makes this acceptable.
3. A **"Learn mode"** in Settings → Diagnostics: the player eats or drinks and the addon logs new auras (spellId, name, duration). This lets us collect real IDs in the very first test session. This is a diagnostic tool, not a gameplay automation.

### 6.2 Statuses (as you specified)
- `Active` — the aura is present and its remaining time > threshold.
- `Expiring` (sub-status of Active) — less than N minutes remain.
- `Missing` — data is readable and the aura is absent.
- `Available` — no aura, but the item is in the bags (food, flask, Sleeping Bag off cooldown).
- `Unknown` — the value is secret / cannot be read right now.
- `Not Reported` — the player has no addon or did not respond.
- `Outdated` — the snapshot is older than its TTL.

### 6.3 Modes: solo → party → raid
| Mode | What it does |
|---|---|
| **Solo (always)** | A compact Readiness panel: Food / XP Food / Flask / Elixirs / Weapon / Rested % / Sleeping Bag / Camping / Potions xN. Reminders: "Well Fed expired" (out of combat, on a cooldown, without spam), "Sleeping Bag is ready" when outside a rested zone and leveling. A per-session XP log (XP/h, share of rested XP) — [TEST] whether the bonus can be separated out |
| **Party** | Members' table: auras out of combat (from the API) + self-reports from players with the addon. "Party Ready 3/5". A "Check" button that sends a request to the party |
| **Raid** | Same plus role/class profiles (who needs a flask and which one), a summary at READY_CHECK and on ENCOUNTER_START (a snapshot of the last readable values), shown in the raid session report. **Only after restrictions lift.** No automatic actions |

Requirement profiles are **configurable** per role and class (e.g. "Healer: Mana food + Distilled Wisdom/Natural …"), and per raid (Natural flasks only count in Hyjal/Barrow Deeps).

**Not allowed and not planned:** auto-using items, auto-clicking Ready Check, auto-messaging into chat without the player's action.

---

## 7. Preliminary architecture

```
RequiemLedger/
  RequiemLedger_Forever.toc      ## Interface: 16001
  Libs/                          Ace3 (current, with Forever fixes), LibDBIcon, LibSharedMedia (optional)
  Core/
    Init.lua                     namespace, versions, module loader
    Events.lua                   single event bus (one frame, dispatch to subscribers)
    Compat.lua                   feature detection, secret/lockdown wrappers (SafeRead → value|UNKNOWN)
    Identity.lua                 originKey from GUID, name+surname+ruleset, main/alt links
    Context.lua                  Solo/Party/Raid, instance, active encounter, restriction state
    Strings.lua                  all UI strings in one place (English)
  Data/                          static data: consumables, encounters, instances (IDs here only)
  Storage/
    DB.lua                       SV schema, versions, migrations, validation, caps
    Ledger.lua                   append-only event log + materialized indexes (projections)
  Sync/
    Protocol.lua                 message schemas, validation, CBOR+compress+chunk
    Transport.lua                AceComm/ChatThrottleLib, outbound queue during lockdown
    Reconcile.lua                digests, delta sync, responder election
  Modules/                       each module: collectors (events→ledger) + projections + UI views
    Readiness/  Deaths/  Raids/  Loot/  Members/  Achievements/  PvP/  Planner/
  UI/
    Theme.lua                    palette (navy/gold), fonts, scaling
    Widgets/                     table (virtual scrolling), filters, tabs, tooltips, empty states
    MainFrame.lua                window, tabs, position memory
    Dashboard.lua                configurable widgets
```

Key decisions and why:
- **Modules do not talk to each other directly.** They communicate only through the ledger and the event bus. This lets Achievements subscribe to Deaths and Loot events without coupling.
- **Projections** (counters, rankings, per-boss tables) are rebuilt from the ledger. That makes migrations and corrections safe: rebuild the projection and you are done. They are rebuilt lazily when a tab is opened, never per frame.
- **Ace3**: proven, already patched for Forever (AceDB keyed on surnames), and provides AceComm + ChatThrottleLib (correct throttling). We do not need AceGUI, because our own widgets look better and are lighter.
- **Native `C_EncodingUtil`** instead of LibDeflate/LibSerialize: fewer dependencies [TEST it works].

---

## 8. Data storage

| SV | Contents |
|---|---|
| `RequiemLedgerDB` (account-wide) | `schemaVersion`, ledger (events from every author, keyed by originKey), projections (cache, can be rebuilt), guild profiles, settings shared across characters |
| `RequiemLedgerCharDB` (per character) | UI and position, `seq` counter, personal Readiness settings, outbound queue |

- **Versioning:** `schemaVersion` + a chain of `migrations[n] → n+1`. Before a migration, a copy of the critical tables goes into `backup` (one generation).
- **Validation on load:** every event is checked against its type's schema. Corrupted events are moved to `quarantine` (and shown in Diagnostics), never deleted silently.
- **Size:** caps per type (e.g. readiness snapshots: 30 days; raw deaths outside raids: 1 year, then aggregates only). Officers can configure an "archive" (compacting old events into aggregates).
- **Multiple guilds:** the data is partitioned by guild key (guild name + ruleset), so we stay ready for public release.
- **Export/Import:** a string (CBOR → compress → base64) in a copy window. Plus CSV export of tables (loot, attendance, deaths) for spreadsheets and Discord.

---

## 9. Main technical risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | Party members' auras are secret even out of combat in instances | Medium | High for party/raid Readiness | Self-report from players with the addon. Snapshot before entering the instance |
| 2 | Well Fed / XP / Sleeping Bag aura IDs differ from the beta | High | Medium | Data file + match by name + Learn mode |
| 3 | `CHAT_MSG_LOOT`/`SYSTEM` text is secret in instances | Medium | Medium (loot fallback, duels) | `ENCOUNTER_LOOT_RECEIVED`/`C_LootHistory` as the primary source. Duels outside instances |
| 4 | Addon messages locked in all instances (not only during encounters) | Medium | Medium | Queue and flush on exit. Readiness snapshots before entering |
| 5 | Blizzard changes the restrictions in a patch | High | Varies | Compat layer, capability diagnostics, quick releases |
| 6 | Unreliable identity (surname, name changes, ruleset transfers) | Medium | High for history | originKey = GUID. Name is an attribute. Manual merge of profiles by officers |
| 7 | Sync storm in a 40-player raid | Medium | Medium | Responder election, jitter, BULK priority, digests instead of full data |
| 8 | Fake data from a modified client | Low | Medium | Trust policy: self-report only about yourself, officer ranks, multiple witnesses. Officer data is marked "verified" |
| 9 | SV bloat → slow load | Medium | Medium | Caps, aggregation, archive |
| 10 | Competitors (Guild Muster, GuildDeathLog, NRC) | Certain | Medium | Unified UX, raid context, honest reliability, integrations |
| 11 | **I cannot test in the client** | Certain | High | We need a tester in the guild (ideally 2–3 people for sync) and a test checklist per stage |

---

## 10. MVP proposal

**MVP = "Personal Ledger + Party/Raid Readiness".** It is valuable from day one, even if only one person has the addon installed:

1. **Foundation:** TOC, Core (events, compat, identity, context), Storage with schema versions, the ledger with event IDs, a sync protocol skeleton (schemas and versioning, without full reconcile), main window, `/rq` and `/requiem`, minimap button.
2. **Readiness (solo):** food / XP food / flask / elixirs / weapon / rested / Sleeping Bag / camping / potions, statuses, reminders, Learn mode.
3. **Deaths (personal):** total, per session, world/dungeon/raid/PvP context, per encounter (via ENCOUNTER_START context), history, periods.
4. **Readiness (party/raid):** live auras via the API + self-reports over PARTY/RAID, Ready Check summary.

Not in the MVP: loot, achievements, planner, PvP, guild sync. The *formats* are still laid down in Foundation.

---

## 11. Preliminary roadmap

| Stage | Contents | Depends on | Key risk | Done when |
|---|---|---|---|---|
| **0. Research** | This document + **a client test session**: Learn mode and secrets checklist (items TEST) | — | No tester | All critical [TEST] items closed |
| **1. Foundation** | Core, Compat, Identity, Context, Storage+migrations, Ledger (IDs, schemas), Protocol v1 (schemas only), UI skeleton (window, tabs, table, theme), slash commands, Diagnostics | 0 | — | Loads without errors, SV survive /reload, migration test passes, window works at 1280×720 and at UI scale 0.64 |
| **2. Readiness — solo** | Readiness panel, statuses, reminders, consumables data | 1 | Aura IDs | Food, flask and Sleeping Bag correctly detected in the client by 2 testers |
| **3. Deaths — personal + encounter context** | Death collector, projections, Deaths tab | 1 | — | Deaths counted correctly in world, dungeon and boss pulls |
| **4. Party/Raid Readiness + Sync v1 (PARTY/RAID)** | Self-report, live auras of members, Ready Check summary, lockdown queue | 2, 1 | Secrets in groups | 5-player party: correct statuses, no spam, no Lua errors in the dungeon |
| **5. Raid sessions** | Pull/wipe/kill, roster, deaths per pull (coverage), raid history | 3, 4 | — | One real raid gives a correct report |
| **6. Guild & Members + Sync v2 (GUILD, delta)** | Roster, profiles, alts, professions (self-report), Dashboard | 1, sync | Sync storm | 10+ users, consistent data after relogs |
| **7. Loot** | ENCOUNTER_LOOT_RECEIVED/LootHistory, dedup by witnesses, corrections, Gargul import | 5, 6 | Unknown loot model | One raid's loot matches the actual drops |
| **8. Achievements** | Rules engine on top of the ledger, points, rarity, Hall of Fame, officer verification | 3, 5, 7 | False triggers | Every rule has a test on synthetic events + a check in the client |
| **9. Raid Planner** | Events, sign-ups, roles, bench, attendance, reading the WoW calendar | 6 | Offline propagation | A plan reaches people who log in 24h later |
| **10. PvP & Duels** | Duels, lifetime HKs, rankings, tournaments | 6 | Secret chat text | Duels counted on both sides without duplicates |
| **11. Public release** | Multi-guild, documentation, CurseForge/Wago, imports/exports | everything | — | Works in a guild that is not Requiem |

Each stage ends with a report in the format you asked for (done / tested / not tested / limitations / decisions / next).

**Testing:**
- Offline: a Lua 5.1 harness (busted or a bare runner) with mock events and mocked `C_*` APIs, covering projections, migrations, dedup and protocol validation. *These tests do not prove the addon works in the client.*
- In-client: a checklist per stage and `/rq debug` (event log, capability list, secret checks).

---

## 12. Questions that need your decision

1. **MVP priority.** The guild vote put Deaths first, and your note puts food, flask and XP buffs first. I propose **Readiness → Deaths** (both in the MVP, Readiness first). Do you agree?
2. **Testers.** I cannot run WoW. Who in the guild can install dev builds and run checklists (ideally 2–3 people for sync tests)? The first job is a ~30-minute "Learn mode" session: eat, drink a flask, use the Sleeping Bag.
3. **Loot in Requiem.** What will you use in raids: Gargul, master loot, group loot, or something else? I propose **not** distributing loot ourselves but recording it and importing from Gargul.
4. **Officer rights.** Which guild ranks can confirm achievements and correct loot or attendance records?
5. **Extended Analytics.** Is it enough to store a **Warcraft Logs link** on the raid session, with no parser of our own for now?
6. **Libraries.** Ace3 (AceDB/AceComm/ChatThrottleLib) is my recommendation. Or do you want zero dependencies (more code of our own, more risk in sync)?
7. **Distribution.** A private zip for the guild at first, or CurseForge/Wago right away (with neutral "Requiem" branding)?
8. **Hardcore.** Will Requiem play on the Hardcore ruleset when it arrives? That changes the meaning of the Death Tracker (memorials vs counters).
9. **Is a +5% kill XP aura** worth separating from regular stat food in the UI (as "XP Food"), or is a single "Food: Active (+XP)" status enough?

---

## Sources
- Blizzard: [WoW: Forever Now Live](https://news.blizzard.com/en-us/article/24315820/world-of-warcraft-forever-now-live), [Beta](https://news.blizzard.com/en-us/article/24304160/the-world-of-warcraft-forever-beta-now-live)
- warcraft.wiki.gg: [World of Warcraft: Forever](https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever), [Patch 1.60.1/API changes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes), [TOC format](https://warcraft.wiki.gg/wiki/TOC_format), [WOW_PROJECT_ID](https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID), [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values), [COMBAT_LOG_EVENT_UNFILTERED](https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT_UNFILTERED), [C_ChatInfo.SendAddonMessage](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage), [C_UnitAuras.GetAuraDataByIndex](https://warcraft.wiki.gg/wiki/API_C_UnitAuras.GetAuraDataByIndex), [SavedVariables](https://warcraft.wiki.gg/wiki/SavedVariables), [Legacy System](https://warcraft.wiki.gg/wiki/Legacy_System), [Cozy Sleeping Bag](https://warcraft.wiki.gg/wiki/Cozy_Sleeping_Bag), [ENCOUNTER_START](https://warcraft.wiki.gg/wiki/ENCOUNTER_START), [UNIT_DIED](https://warcraft.wiki.gg/wiki/UNIT_DIED), [DUEL_FINISHED](https://warcraft.wiki.gg/wiki/DUEL_FINISHED)
- API dump: [atraeau.github.io/WoW-Addons/api.json](https://atraeau.github.io/WoW-Addons/api.json) (1.60.1, build 70790)
- Mechanics (third-party): [Warcraft Tavern: food XP](https://www.warcrafttavern.com/forever/news/cooked-food-provides-an-xp-buff-in-world-of-warcraft-forever), [Warcraft Tavern: Sleeping Bag](https://www.warcrafttavern.com/forever/guides/cozy-sleeping-bag/), [Warcraft Tavern: Legacy](https://www.warcrafttavern.com/forever/guides/legacy/), [Method: consumables](https://www.method.gg/wow-forever/list-of-all-consumables-and-enchants-in-wow-forever)
- Addons: [Guild Muster](https://www.curseforge.com/wow/addons/guild-muster), [Gargul](https://github.com/papa-smurf/Gargul), [Details!](https://github.com/Tercioo/Details-Damage-Meter), [GuildDeathLog](https://www.curseforge.com/wow/addons/guild-death-log), [GRM](https://www.curseforge.com/wow/addons/guild-roster-manager), [NovaRaidCompanion](https://www.curseforge.com/wow/addons/nova-raid-companion), [Ace3](https://github.com/WoWUIDev/Ace3/commits)
- Context on restrictions: [Icy Veins: Midnight restrictions eased](https://www.icy-veins.com/wow/news/combat-addon-restrictions-eased-in-midnight/), [Icy Veins: Forever surnames](https://www.icy-veins.com/wow-forever/surnames)
