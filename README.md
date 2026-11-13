<p align="center">
  <img src="assets/nemux-ledger-logo-512.png" width="160" alt="Nemux Ledger emblem">
</p>

<h1 align="center">Nemux Ledger</h1>

<p align="center">
  A guild companion addon for <b>World of Warcraft: Forever</b>.<br>
  Readiness HUD · deaths · recipe search · feats · leaderboards · weekly report · loot log
</p>

<p align="center">
  <a href="https://www.curseforge.com/wow/addons/nemux-ledger">CurseForge</a> ·
  <a href="LICENSE">MIT License</a>
</p>

---

## What it does

- **Readiness HUD.** A small panel that shows up only when something is missing or about to run out: food buff, flask, elixir, weapon oil, potions, Well-Rested. You choose the checks for solo, party and raid.
- **Guild roster and recipe search.** "Who can craft Silver Rod?" Recipes are shared when a member opens their profession window, so offline crafters are found too. Hover a recipe to see its reagents, what you have in bags and bank, and an approximate cost (with Auctionator).
- **Recipe tracker.** A shopping list on screen that updates as you loot and buy.
- **Leaderboards.** Deaths (all time and this week) and honorable kills, a guild death feed, and a weekly report ready for Discord.
- **Feats.** 33 small achievements plus guild goals with progress bars.
- **Level-up alerts** for the whole guild (can be turned off).
- **Loot log.** Reads awards from **Gargul** and **RCLootCouncil**. Nemux Ledger never hands out loot itself.

Everything that involves other players works between guild mates who also run the addon. The UI is in English.

## Install

- **CurseForge app:** search for *Nemux Ledger*.
- **Manually:** download the zip from [Releases](../../releases) or CurseForge and extract the `RequiemLedger` folder into
  `Interface\AddOns\` inside your WoW: Forever game folder.

> The folder, SavedVariables and addon-message prefix are still named `RequiemLedger` / `RQLedger`, so data from early builds is kept.

Type `/rq` to open the window, or `/rq help` to list the commands.

## Privacy: what is sent to the guild

Hidden addon messages on the guild channel and in whispers, only to guild mates who run Nemux Ledger:
addon version, death count and death location type, profession skill levels, known recipe IDs, feats, honorable kill count.

It never sends chat text, gold, items or anything from other addons. Incoming data is checked against strict formats and only ever displayed as text. Nothing received is ever run as code.

## Repository layout

```
RequiemLedger/     the addon itself (this folder goes into Interface\AddOns)
  Core/            init, DB, API compatibility layer, slash commands
  Data/            consumable tables, death phrases
  Modules/         readiness, deaths, guild sync, recipes, feats, boards, weekly, tracker, loot
  UI/              main window, HUD, minimap button, theme, export
tests/             mock WoW client (fengari) and unit tests
docs/              CurseForge description, research notes, tester guide
assets/            logo and emblem sources
```

## Development

Tests run the addon in a fake WoW client inside [fengari](https://github.com/fengari-lua/fengari) (Lua 5.3 in JavaScript):

```sh
cd tests
npm install
npm test
```

Passing mock tests do not prove the addon works in game; every feature is also checked in the live client.

Targets: WoW: Forever 1.60.x, `## Interface: 16001` (Mainline 12.x API).

## License

[MIT](LICENSE) © 2026 Nemux
