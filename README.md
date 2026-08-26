# Civilian Variety

A content mod for **Cataclysm: Bright Nights**. Repopulates the world with
ordinary people — the ones who were simply *there* when it happened.

---

## Up front: this mod is mostly AI-written

Nearly all of it — the JSON, the Lua, the balance, the monster and item design,
and every line of dialogue and description — was written by Claude, with me
directing it, testing in-game and making the calls.

**The art is the exception: most of the sprites are hand-drawn by me.**

I wouldn't have finished this without the help, and it's a real mod that works.
But if AI-generated content is a dealbreaker for you, better to know that now
than after you've downloaded it.

---

## Requirements

- **Cataclysm: Bright Nights with Lua support** (declares `lua_api_version: 2`;
  it won't load on a build without it)
- **UNDEAD_PEOPLE tileset** for the sprites — optional, you just get `@` glyphs
  without it

Only hard dependency is `bn`.

## Install

1. Green **Code** button → **Download ZIP**
2. Copy the `civilian_variety` folder into your game's `mods/` folder
3. Enable **Civilian Variety** when you create a world

## Features

- **40 monsters** — 34 civilian archetypes and 6 zombies
- **Archetypes**: bystanders (ordinary, heavyset, panicked, elderly, geeky),
  retail workers, clergy, doctors, nurses, firefighters, police and SWAT,
  mechanics, construction workers, farmers, office workers, business people,
  clown, sex worker, store owner, and biker bandits
- **61 location rules** — people show up where they'd actually be: mechanics in
  garages, geeks in libraries and LAN centres, clergy in churches, the elderly in
  parks and cemeteries, staff in shops
- **Six zombie counterparts** — clowns, nerds, clergy, firefighters and retail
  staff keep their uniform after they turn
- **Talk to people** — 22 archetypes have dialogue
- **One-shot favours** — doctors treat wounds, nurses hand over supplies,
  firefighters give water, farmers give food, clergy bless you (worth more with
  the Spiritual trait), store owners take protection money
- **Three behaviours** — most civilians are friendly, biker bandits are hostile,
  store owners are territorial and turn on you once you're inside the shop
- **27 items** — keepsakes with 79 randomised descriptions, a nerd collection,
  and findable dead bodies you can loot like containers
- **114 ambient barks**
- Works **with or without** the bundled `civilians` mod

## Compatibility

Never references an id owned by another mod. It declares the `civilians` monster
faction itself, which merges cleanly if that mod is loaded, and thins its own
spawns at runtime so the two don't double civilian density.

Adds only a small share to vanilla `GROUP_ZOMBIE` (74 of a self-imposed 80
per-mille cap), so vanilla zombie spawns aren't starved. Never sets
`"override": true` on a monstergroup.

## Credits and licence

Sprites by **GoatBoy-11**. Code and design by Claude (Anthropic), directed and
tested by GoatBoy-11.

[CC BY-SA 4.0](LICENSE). Cataclysm: Bright Nights is its own project with its own
licensing; this is an independent addition to it.
