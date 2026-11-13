# Nemux Ledger

**A guild companion for WoW: Forever.** Nemux Ledger shows what you are missing before a pull, keeps your guild's history (deaths, feats, recipes, loot) and turns it into leaderboards and a weekly report. Install it and play; there is nothing to set up.

Solo, party or raid: the addon adjusts to where you are. Everything that involves other players works between guild mates who also run Nemux Ledger.

## Features

**Readiness HUD**
- A small panel that only appears when something is missing or about to run out: food buff, flask, elixir, weapon oil, potions, and the Sleeping Bag's Well-Rested.
- You choose which checks run when solo, in a party and in a raid, and how many minutes before the end it reminds you.
- Any elixir or flask in your bags is recognised by item type. Utility elixirs such as Noggenfogger are ignored, and `/rq ignore` lets you ignore more.

**Guild**
- The roster with level, zone and rank, and the real profession skill of members who run the addon.
- **Recipe search:** "who can craft Silver Rod?" Recipes are shared when a member opens their profession window, and offline crafters are found too.
- **Reagents:** hover a recipe to see its reagents, what is in your bags and bank, and an approximate cost (needs Auctionator or another addon that provides its price API).
- **Recipe tracker:** click a recipe to put a shopping list on screen. It updates as you loot and buy, and shift-clicking a reagent links it in chat.
- **Level-up alerts:** "X reached level 40". This works for the whole guild, including members without the addon, and can be turned off or limited to every 10 levels.

**Boards**
- Leaderboards for deaths (all time and this week) and honorable kills.
- A feed of recent guild deaths, with zone or boss.
- **Weekly report:** deaths, levels, honor kills, feats and loot of the week, as text ready to paste into Discord.

**Feats**
- 33 small achievements (levels, professions, honor kills, raid bosses, deaths, and a few silly ones), shared with your guild.
- Guild goals with progress bars: 10 members at max level, 1000 honor kills together, and more.

**Deaths**
- Every death is counted, with zone and boss, plus a random phrase in chat. Guild mates can see your deaths in their chat too; this can be turned off.

**Loot log**
- Who got which item, from which boss, main spec or off spec. Read from **Gargul** (and **RCLootCouncil** where it runs). Nemux Ledger never hands out loot.

## Commands
`/rq` opens the window. `/rq help` lists everything. Commands worth knowing:
- `/rq recipes <name>`: search recipes;
- `/rq loot <player>`: the loot log;
- `/rq week`: the weekly report;
- `/rq track`: the recipe tracker;
- `/rq hud`: brings the HUD back.

## What the addon sends to your guild
Nemux Ledger talks only to guild mates who run it, through hidden addon messages on the guild channel and whispers. It sends:
- the addon version;
- your death count and where you died (world, dungeon, raid or PvP);
- your profession skill levels;
- the IDs of your known recipes;
- your feats;
- your honorable kill count.

It never sends chat text, gold, items or anything from other addons. Everything it receives is checked against strict formats and only ever shown as text; nothing received is ever run as code.

## Notes
- Built for **WoW: Forever** (Interface 16001).
- The UI is in English.
- Prices are approximate and come from your price addon. Without one, no prices are shown.
- Loot log integrations read other addons' data. If a loot addon changes its internals, only the loot log stops updating; the rest keeps working.

## License
MIT
