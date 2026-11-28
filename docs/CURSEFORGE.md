# Nemux Ledger

**Your guild. Your history. Your legacy.** The guild companion for WoW: Forever.

Nemux Ledger tells you what you are missing before a pull. It shows who in the guild can craft what, even while they are offline, and takes crafting requests. It tracks profession cooldowns and keeps your raid history and attendance. It also writes the guild's story: first kills, feats, deaths and new members. Install it and play. There is nothing to set up.

It is useful on its own and gets better with every guild mate who installs it. Everything that involves other players works between guild mates who run Nemux Ledger.

## Features

**Readiness HUD**
- A small panel that appears only when something is missing or about to run out: food buff, flask, elixir, weapon oil, potions, and the Sleeping Bag's Well-Rested.
- You choose which checks run when solo, in a party and in a raid, and how many minutes before the end it reminds you.
- Any elixir or flask in your bags is recognised. Utility elixirs such as Noggenfogger are ignored, and `/rq ignore` lets you ignore more.

**Professions and crafting**
- **Guild crafters:** every profession in the guild with its members, offline ones included, with their real skill.
- **Recipe books:** click a crafter to browse their recipes, laid out like the game's profession window, even while they are offline. Each recipe shows its reagents, what is in your bags and bank, and an approximate cost (with Auctionator or another addon that provides its price API).
- **Crafting requests:** press **Request** on a recipe. The crafter gets it, even if they log in later, and can accept, decline or mark it done. You see each step in chat. The craft and the trade still happen in the game, by hand.
- **Profession cooldowns:** Mooncloth, transmutes and the Salt Shaker for all your characters and your guild mates, with a "ready again" note in chat.
- **Recipe search:** "who can craft Silver Rod?"
- **Recipe tracker:** a shopping list on screen that updates as you loot and buy.

**Raid Center**
- **History:** every raid with kills, wipes, time and deaths, boss by boss.
- **Guild first kills and speed records**, announced in chat.
- **Attendance:** raid nights per guild member over the last 30, 60 or 90 days.
- **Ready check:** members with Nemux Ledger report their food, flask, elixir, weapon buff and potions when a ready check starts.

**Guild**
- The roster with level, zone and rank.
- **Member profiles:** click anyone to see their deaths, feats, honor kills, raid attendance, professions, cooldowns, leaderboard titles and recent history.
- **Level-up alerts:** "X reached level 40". This works for the whole guild, including members without the addon.

**Boards and Chronicle**
- Leaderboards for deaths (all time and this week) and honorable kills, with titles for the leaders.
- **Guild Chronicle:** first kills, level caps, feats, new and departed members, finished crafting requests and death milestones, listed once however many members saw them.
- **Weekly report:** deaths, levels, honor kills, feats and loot of the week, ready to paste into Discord.

**Feats**
- 73 small achievements for levels, professions, raids, crafting, honor kills and deaths, plus a few silly ones. They are shared with your guild.
- Guild goals with progress bars.

**Deaths**
- Every death is counted with zone and boss, and you get one of 150+ phrases in chat. Guild mates can see your deaths in their chat too. This can be turned off.

**Loot log**
- Who got which item, from which boss and with which response. It follows **RCLootCouncil** live and also reads **Gargul**. Nemux Ledger never hands out loot.

**Looks**
- Five colour themes in Settings: Requiem, Alliance, Midnight, Emerald Dream, Blood and Iron.

## Getting started
1. Install and log in.
2. **Open each of your profession windows once.** The game only gives an addon your recipes after the window has been opened. The addon reminds you once.
3. Type `/rq` to open the window.

## Commands
`/rq` opens the window and `/rq help` lists everything. The most useful ones:
- `/rq profs`: professions and guild crafters
- `/rq orders`: crafting requests
- `/rq cd`: profession cooldowns
- `/rq raids`: raid history, attendance and the ready check
- `/rq profile <name>`: a guild member's profile
- `/rq recipes <name>`: search recipes
- `/rq loot <player>`: the loot log
- `/rq week`: the weekly report
- `/rq hud`: bring the HUD back

## What the addon sends
Nemux Ledger talks only to guild mates who run it. It uses hidden addon messages on the guild channel and in whispers. It sends:
- the addon version;
- your death count and where you died (world, dungeon, raid or PvP);
- your profession skill levels and the IDs of your known recipes;
- your profession cooldown timers;
- your feats and your honorable kill count;
- crafting requests you make or answer;
- guild chronicle events your client saw (for example a guild first kill).

During a ready check it sends your own consumable status (food, flask, elixir, weapon buff, potions) to your group. Only guild mates' reports are shown.

It never sends chat text, gold, items or anything from other addons. Everything it receives is checked against strict formats and only ever shown as text. Nothing received is run as code.

## Notes
- Built for **WoW: Forever** (Interface 16001).
- The UI is in English.
- Raid features read only what the game gives every addon on Forever: boss kills and wipes, the group roster, and what guild mates' addons report. There is no combat log for addons on Forever.
- Prices are approximate and come from your price addon. Without one, no prices are shown.

## License
MIT
