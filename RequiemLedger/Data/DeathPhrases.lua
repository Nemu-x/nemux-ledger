-- Death phrases. Placeholders: {name}, {zone}, {boss}, {count}.
-- A phrase is only picked when every placeholder it uses has a value.
-- Add new lines freely: the picker avoids repeats on its own.

local _, RL = ...
RL.Data = RL.Data or {}

RL.Data.DEATH_PHRASES = {
  -- Fits any death
  any = {
    "{name} kissed the floor.",
    "{name} is inspecting the floor. Again.",
    "{name} has joined the Floor Inspectors Guild.",
    "{name} found the floor. It was right where they left it.",
    "{name} is lying down for a better view.",
    "{name} tested the floor's durability. The floor won.",
    "{name} made a strategic horizontal retreat.",
    "{name} died doing what they loved: standing in it.",
    "{name}'s health bar went on vacation.",
    "A moment of silence for {name}. Okay, that's enough.",
    "{name} became one with the dirt.",
    "Another entry for the Ledger: {name}.",
    "{name} is resting. Not the XP kind.",
    "{name} hugged the ground a little too hard.",
    "{name}: 0 health, 100% commitment.",
    "{name} missed the Spirit Healer and went to visit.",
    "{name} asked the floor for a dance. The floor said yes.",
    "{guild} mourns {name}. Briefly.",
    "{name} is now a ghost. Spooky.",
    "{name} paid the repair bill in advance.",
    "{name} has fallen and can't get up.",
    "{name} is taking the scenic route through the graveyard.",
    "{name} forgot which end of the sword goes into the enemy.",
    "{name} contributed to the guild statistics. Thank you for your service.",
    "{name} pressed the wrong button. Probably.",
    "Gravity: 1. {name}: 0.",
    "{name} will be right back. Corpse run in progress.",
  },
  -- Open world
  world = {
    "{name} lost a fight with the local wildlife in {zone}.",
    "{zone} claims another victim: {name}.",
    "{name} took a nap in {zone}. Forever.",
    "The murlocs of {zone} send their regards to {name}.",
  },
  -- 5-player dungeons
  party = {
    "{name} died in {zone}. The tank saw nothing.",
    "{name} pulled the next pack. Personally. With their face.",
    "{name} is checking the floor tiles of {zone}.",
    "The healer would like a word with {name}.",
  },
  -- Raids
  raid = {
    "{name} fell in {zone}. The raid leader is typing...",
    "{name} volunteered as the raid's floor tester.",
    "{name} is now spectating {zone}.",
  },
  -- During a boss fight
  boss = {
    "{name} lost a staring contest with {boss}.",
    "{boss} sends {name} back to the graveyard.",
    "{name} tried to tank {boss}. Nobody asked.",
    "{boss}: 1. {name}: 0.",
    "{name} went to check what {boss} keeps under the floor.",
  },
  -- Battlegrounds and other PvP
  pvp = {
    "{name} met the Horde welcoming committee.",
    "{name} was escorted to the graveyard by the Horde.",
    "{name} is guarding the graveyard. From the inside.",
  },
}

-- Special lines for round numbers; these always win.
RL.Data.DEATH_MILESTONES = {
  [1]   = "{name}'s first death. Welcome to the club.",
  [10]  = "Death number 10. {name} is getting the hang of it.",
  [25]  = "25 deaths. {name} now gets a discount at the Spirit Healer.",
  [50]  = "Fifty deaths! {name} has a loyalty card at the graveyard.",
  [100] = "100 deaths. {name} is now a Professional Floor Inspector.",
  [200] = "200 deaths. The floor of Azeroth knows {name} by name.",
  [500] = "500 deaths. {name}, are you okay?",
}
