# Nemux Ledger 0.7.0

**Guild crafters, offline too**
- Professions → Guild crafters is now the first view, and it lists offline members too. Tick **Show offline** to see them.
- Offline members show their real skill once their Nemux Ledger has shared it. Skills are now kept between sessions.
- A profession with nobody online still gets its own heading.

**Crafting requests**
- In a guild mate's recipe book, press **Request** to ask them for a craft. Press it again for one more.
- Professions → **Orders** lists your requests and the ones you can craft, with Accept, Decline, Done and Cancel buttons.
- Crafters who were offline get the request when they log in. You see each step in chat. The craft and the trade still happen in the game, by hand.

**Profession cooldowns**
- Professions → **Cooldowns** shows Mooncloth, transmutes and the Salt Shaker for all your characters and for guild mates.
- "Ready again" appears in chat when one of yours is ready.
- New cooldown recipes on Forever are picked up when the game shows them in your profession window.

**Raid Center** (new Raids tab)
- **History**: every raid you join, with kills, wipes, time and deaths. Hover a raid to see each boss.
- Guild first kills and new guild speed records are announced in chat.
- **Attendance**: raid nights per guild member over the last 30, 60 or 90 days.
- **Ready check**: members with Nemux Ledger report their food, flask, elixir, weapon buff and potions when a ready check starts.

**Guild Chronicle**
- Boards now has a **Chronicle**: guild first kills, level caps, feats, new and departed members, finished crafting requests, and guild death milestones.
- An event is listed once, however many members saw it. People who were offline catch up when they log in.

**Member profiles**
- Click a member in the Guild tab (or in raid attendance) to open their profile: deaths, this week, feats, honor kills, raid nights, professions with recipe counts, cooldowns, leaderboard titles, latest feats and recent chronicle lines.
- It works while they are offline. Click a profession to open their recipe book.

**More fun**
- 40 new feats (73 in all), including raid ones (be there for a guild first kill, kill a boss after 5 wipes), crafting requests and profession cooldowns.
- About 100 new death phrases and new milestones up to 1000 deaths.
- Five colour themes in Settings, switched instantly: Requiem, Alliance, Midnight, Emerald Dream, Blood and Iron.
- A one-time reminder to open each profession window once, so your recipes are shared. It is said once in chat; the Professions tab keeps a quiet hint.

**Fixes**
- View buttons, check boxes and footer notes no longer overlap the column headers or each other (Professions, Feats, Guild, Boards, Deaths, Settings, Loot, Me).

- `/rq demo` shows a made-up guild for screenshots. Nothing is saved or sent, and `/rq demo` again brings your guild back.

New commands: `/rq orders`, `/rq cd`, `/rq raids`, `/rq profile [name]`, `/rq demo`.

# Nemux Ledger 0.6.2

**Guild mates' recipe books**
- In Professions → Guild crafters, click a member to open **their recipe book** for that profession. It works even when they are offline.
- The book is laid out like the game's profession window: recipes grouped in collapsible categories on the left (with icons, quality colours and a green dot when your bags hold the reagents), the chosen recipe on the right with its reagents (bags, bank and how many are needed), the approximate cost, who else knows it, and a Track button.
- Categories are the game's own for professions you have (read when you open your window). For other professions they come from what the recipe makes (Parts, Explosives, Chest, Potion...) and, for enchants, from the slot.
- Hover a recipe for the game's tooltip of the item. Shift-click it to link it in chat. Search inside the book, « Back returns to the list.
- Member rows show how many recipes are known ("29 recipes »"), or "not synced" when the member hasn't shared yet: they need Nemux Ledger and to open that profession window once.
- **Shift-click** a member to try the game's own profession window. Forever doesn't always answer this, which is why the addon's own book is the default.
- Fixed: a guild mate's profession window shown by the game could be read as your own recipes.
- The secondary profession cards are wider, so "First Aid", "Fishing" and "Cooking" are no longer cut off.

# Nemux Ledger 0.6.1

**New Professions tab**
- Your professions are shown as cards: two main professions with skill bars, plus Cooking, First Aid and Fishing.
- **Click a card to open that profession window.** Click it again to close it. The card of the open window has a crimson border.
- Gathering skills (Herbalism, Skinning, Fishing) have no window to open. Professions can't be opened in combat.
- Recipe search ("who can craft...") and the guild crafters list moved here from the Guild tab. The Guild tab now shows the members list only.
- The profession bars on the Me tab can be clicked too.
- `/rq profs` opens the tab. `/rq recipes <name>` searches recipes, as before.

# Nemux Ledger 0.6.0

**RCLootCouncil integration**
- The loot log now follows RCLootCouncil live on WoW: Forever. Every raid member with RCLootCouncil sees each award as it happens, not only the master looter.
- The Response column shows RCLootCouncil's own response and colour (Mainspec, Offspec, Minor Upgrade, ...).
- The item tooltip shows council votes, the note, the boss and raid, and who handed the item out.
- Awards that are deleted or edited in RCLootCouncil's history window are updated here too.
- Personal loot and bonus rolls are left out.

**Minimap button**
- It now uses the standard LibDBIcon library. Minimap button bags pick it up as "Nemux Ledger" instead of showing a warning about a custom button.
- Your button position is kept.

**Window**
- A new header with the emblem inside the frame and a flat close button.
- Tabs now look like tabs.
- Selected buttons are highlighted in crimson instead of fading the others.
- Flat search fields with placeholder text.
- The background is more opaque, so other UI no longer shows through.
- The Boards tab is tidied up: the "Remind on reset" option no longer sticks out of the window, and names in the guild death feed are no longer cut off.
