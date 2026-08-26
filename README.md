# Civilian Variety

A content mod for **Cataclysm: Bright Nights**. Adds new civilian type "monsters",
heavily inspired by the "**Civilians**" mod by NetSysFire, Kota and jeremy7986.

---

## DISCLAIMER: this mod is mostly AI-written

Most of the code, both LUA and most of the JSON was made by AI. 
Meaning this is mostly an AI slop mod, barely any talent was used in the making.

Half of the art was made by Goat_Boy11, 
the rest of it was AI generated as well but heavily edited.

---

## Requirements

- **Cataclysm: Bright Nights with Lua support** (Latest Version)
- **UNDEAD_PEOPLE tileset** for the sprites — optional, you just get `@` glyphs
  without it

## Install

1. Green **Code** button → **Download ZIP**
2. Copy the `civilian_variety` folder into your game's `mods/` folder
3. Enable **Civilian Variety** when you create a world

## Features

- New passive civilian type "monsters" with different variants
- Special occupational variants with unique interactions
- New zombie types
- New ambient barks (descriptive text of events/audio)
- New dead body types that can be found at random
- New items, mostly flavour for variety


## Compatibility

Never references an id owned by another mod. It declares the `civilians` monster
faction itself, which merges cleanly if that mod is loaded, and thins its own
spawns at runtime so the two don't double civilian density.

Adds only a small share to vanilla `GROUP_ZOMBIE` (74 of a self-imposed 80
per-mille cap), so vanilla zombie spawns aren't starved. Never sets
`"override": true` on a monstergroup.

## Credits and licence

Design and Json by **LebronJane**
Code **Claude** (Anthropic)
Sprites by **Goat_Boy11**. 


[CC BY-SA 4.0](LICENSE).
