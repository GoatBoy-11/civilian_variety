# Civilian Variety

A content mod for **Cataclysm: Bright Nights** that repopulates the collapse with
ordinary people.

The world of the Cataclysm was inhabited by individuals before it ended, and this
mod tries to make that visible: 37 monster types across 24 living archetypes and
5 zombies, spread across the places those people would actually have been. A
priest in a church. Two old people on a park bench who cannot outrun anything. A
clown, in full paint, doing a bit for nobody. A shopkeeper who has worked out
that nobody is coming to enforce anything ever again.

It works **standalone or alongside the bundled `civilians` mod**, with no hard
dependency on it in either direction.

---

## Requirements

- **Cataclysm: Bright Nights** with **Lua support** — the mod declares
  `lua_api_version: 2` and will not load on a build without it.
- The **UNDEAD_PEOPLE tileset** for the sprites. Without it the mod still works;
  the new archetypes just fall back to the default `@` glyph.

The only hard dependency is `bn` itself.

## Installing

1. Download this repository — green **Code** button → **Download ZIP**, or clone.
2. Inside it you will find a **`civilian_variety`** folder. Drop *that folder* into
   your game's `mods/` directory, so you end up with
   `mods/civilian_variety/modinfo.json`.
3. Enable **Civilian Variety** in the mod list when creating a world.

The mod is deliberately kept in its own folder here so the thing you copy is
already the right shape — nothing to rename, nothing to unpack twice.

---

## What it adds

**24 living archetypes.** Bystanders (ordinary, heavyset, panicked, elderly,
geeky), trades (mechanic, construction worker, farmer), emergency services
(firefighter, doctor, nurse, police, SWAT), white collar (businessman,
businesswoman, office worker), clergy (priest, nun), and the odder end — clown,
sex worker, store owner. Plus biker bandits, the mod's one hostile faction.

**Five zombies of its own.** Clowns, nerds, priests and nuns leave behind their
own kind of corpse rather than a generic one, so a costume that dies stays a
costume.

**People are somewhere for a reason.** 50 location rules put archetypes where
they belong: mechanics in garages, geeks in libraries and LAN centres, clergy in
churches, the elderly in parks and cemeteries, store owners in pawn shops and
jewellers.

**You can talk to them.** 20 archetypes have dialogue — some of it spoken, some
of it described, because a mime in full paint is not going to answer you.

**Some of them will help you, once.** Doctors treat wounds. Nurses hand over
supplies. Firefighters give you water and farmers give you food. Clergy bless
you, and it is worth considerably more if your character is Spiritual. Store
owners will accept protection money.

**Three ways to behave.** Most civilians are friendly. Biker bandits are hostile.
Store owners are *territorial* — perfectly civil until you are inside the shop,
and they do not calm down on their own.

**21 items**, including keepsakes with snippet-driven descriptions so no two
finds read the same, and a small collection of nerd paraphernalia that also turns
up in bookshops, toy shops and bedrooms.

---

## Compatibility

Designed so that it never references an id owned by another mod. It declares the
`civilians` monster faction itself, which merges cleanly if that mod is also
loaded, and it detects the bundled mod at runtime and thins its own generic
spawns so the two together do not double civilian density.

It injects a deliberately small share into the vanilla `GROUP_ZOMBIE` — a
self-imposed cap of 80 per-mille, currently using 70 — so vanilla zombie spawns
are not starved. It never sets `"override": true` on a monstergroup.

## Credits and licence

Sprites by **GoatBoy-11**.

Licensed under [CC BY-SA 4.0](LICENSE). Cataclysm: Bright Nights is its own
project with its own licensing; this mod is an independent addition to it.
