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
