gdebug.log_info("Civilian Variety: initializing...")

local mod = game.mod_runtime[game.current_mod]
local storage = game.mod_storage[game.current_mod]
local faction_civ_id = MonsterFactionId.new("civilians"):int_id()
-- The store owner sits in his own faction so that killing him in self-defence
-- does not turn every bystander hostile (FRIEND_ATTACKED propagates by faction
-- identity - see faction.json).  He is still a civilian for every purpose this
-- file cares about, so both ids go into the proximity queries below.
local faction_shop_id = MonsterFactionId.new("cv_shopkeeper"):int_id()
local CIVILIAN_FACTIONS = { faction_civ_id, faction_shop_id }

--- Returns true if a mod with this id is loaded in the current world.
--- game.active_mods is a read-only array of every loaded mod id, populated
--- before any mapgen runs (src/catalua.cpp:315-317, 335).
local function is_mod_loaded(id)
  for _, m in ipairs(game.active_mods) do
    if m == id then return true end
  end
  return false
end

local CIVILIANS_PRESENT = is_mod_loaded("civilians")

--- Overlay stored per-save settings onto the defaults, ignoring unknown keys.
local function merge_config(default_config, stored_config)
  if not stored_config then return default_config end
  local merged = {}
  for key, default_value in pairs(default_config) do
    local stored = stored_config[key]
    if stored ~= nil then
      merged[key] = stored
    else
      merged[key] = default_value
    end
  end
  return merged
end

-- ============================================================================
-- Configuration.  Override per-save via game.mod_storage["civilian_variety"].
-- ============================================================================

local DEFAULT_CONFIG = {
  -- Chance per qualifying piece of furniture that a civilian is placed.
  SPAWN_CHANCE = 15,

  -- Scaling applied when the Civilians mod is also loaded, since it scans the
  -- same furniture at its own 15% and the two would otherwise stack.  Two
  -- thirds rather than a half: the combined world should be a little busier
  -- than either mod alone, which is the point of running both.
  -- Applies to the GENERIC pool only.  Occupational archetypes are untouched -
  -- the Civilians mod has no nurses or mechanics, so there is nothing to double
  -- up with, and thinning them would just make professions rarer for no reason.
  CIVILIANS_PRESENT_SCALE = 2 / 3,

  -- Odds, per mille, that an indoor spawn draws from the generic pool rather
  -- than the occupational one: 78% ordinary bystanders, 22% professions.
  -- This is a free-standing dial.  It once mirrored the weights the two groups
  -- were split out of, but they are separate monstergroups now and each
  -- normalises to 1000 independently, so nothing inside either pool affects this
  -- ratio.  Adding or reweighting a monster in either group needs no change
  -- here; change this only to shift how often professions turn up at all.
  GENERIC_SHARE = 782,

  -- Attempts to find a free tile next to the furniture before giving up.
  TRY_TRIES = 5,

  -- Living civilians thin out as the world ages:
  --   survival_chance = VANISH_BASE_RATE ^ (days_elapsed / VANISH_PERIOD_DAYS)
  -- At the defaults below that is 100% on day 0, 50% on day 14, 25% on day 28.
  -- Set VANISH_BASE_RATE to 1.0 to disable decay entirely.
  VANISH_PERIOD_DAYS = 14.0,
  VANISH_BASE_RATE = 0.5,

  -- Ambulances.  Vehicles are invisible to the mapgen hook: mapgen_constructor
  -- returns raw vehicle pointers with no Lua type, while only the live map hands
  -- back WrappedVehicle with pos() and type().  So this runs on a slow timer
  -- instead, and is the mod's only periodic work.
  AMBULANCE_ENABLED = true,
  AMBULANCE_CHANCE = 25,
  AMBULANCE_CLEAR_RADIUS = 6,
  AMBULANCE_PLACE_RADIUS = 3,

  -- Ambient dread.  Rare, context-aware flavour lines describing what the player
  -- can hear.  There is NO in-world sound involved: Lua has no binding for
  -- sounds::sound(), only the SDL playback helpers, so this can never propagate
  -- through the map or attract monsters.  Keep it that way - a flavour message
  -- that pulls a horde onto the player would be a nasty surprise.
  -- The hook fires every 600 turns and rolls AMBIENT_CHANCE inside the handler,
  -- so ~94% of wake-ups cost three comparisons and stop.  6% of a 10-minute tick
  -- averages one message per ~2.8 hours.
  AMBIENT_ENABLED = true,
  AMBIENT_CHANCE = 6,
  -- Hard floor between messages, in minutes.  Without it random rolls will
  -- occasionally land two in quick succession, which breaks the mood instantly.
  AMBIENT_COOLDOWN_MINUTES = 90,
  AMBIENT_CIVILIAN_RADIUS = 8,

  -- How much a doctor's treatment restores, per body part, via Character:healall.
  -- Deliberately modest.  Vanilla has NO instant healing at all - bandages apply
  -- the `bandaged` effect and heal slowly over time - so an instant restore has
  -- no consumable equivalent and is inherently strong.  This should read as
  -- proper field treatment that saves you a day of resting, not a full recovery.
  -- healall clamps per part (src/character.cpp:9864), so a lightly hurt player
  -- gets correspondingly little and nobody ever exceeds their maximum.
  DOCTOR_HEAL_MIN = 6,
  DOCTOR_HEAL_MAX = 12,

  -- A blessing, in morale.  The plain figure is deliberately modest - about what
  -- a hot meal is worth - because it costs nothing and carries no risk.  The
  -- SPIRITUAL figure is the one that matters: that trait costs a point at
  -- character creation and otherwise only pays out for holy texts, so this gives
  -- it something to do out in the world.
  BLESS_BONUS = 10,
  BLESS_MAX = 20,
  BLESS_BONUS_SPIRITUAL = 25,
  BLESS_MAX_SPIRITUAL = 40,

  -- What the store owner wants to let you browse.  Two bundles rather than one:
  -- it should sting slightly, and money is otherwise close to worthless.
  APPEASE_COST = "money_bundle",
  APPEASE_COUNT = 2,

  -- Furniture a civilian might plausibly be found at.
  TARGET_FURNITURE = {
    ["f_armchair"] = true,
    ["f_bed"] = true,
    ["f_bench"] = true,
    ["f_chair"] = true,
    ["f_chair_folding"] = true,
    ["f_locker"] = true,
    ["f_sofa"] = true,
    ["f_stool"] = true,
    ["f_wardrobe"] = true,
  },

  -- Themed locations.  The first fragment found in the overmap terrain id wins,
  -- and anywhere unmatched falls through to GROUP_CV_INDOOR.  These groups bias
  -- rather than replace: each one still carries ordinary bystanders, so a
  -- construction site is mostly workers but not exclusively.
  -- Checked only after EXCLUDED_TERRAINS, so "bandit_garage" stays excluded even
  -- though a "garage" theme would otherwise match it.
  -- An entry with `count` is an open work site rather than a domestic interior:
  -- people there are standing around the lot, not sitting on the furniture, so
  -- it spawns that many anywhere walkable and skips the furniture scan entirely.
  -- Furniture-gating is a house heuristic; a construction site has one or two
  -- chairs on the whole lot, which at a 15% roll means most sites came up empty.
  -- Garages use open-site mode for the same reason work sites do: house_garage
  -- has no furniture whatsoever and garage_gas has a single chair, so interior
  -- anchoring would find nothing.  Mechanics stand at the vehicle, not on a sofa.
  -- Fragments are deliberately specific rather than a bare "garage", so that
  -- bandit_garage (a faction location) can never match.
  LOCATION_GROUPS = {
    { match = "construction_site", group = "GROUP_CV_CONSTRUCTION", count = { 2, 5 } },
    { match = "open_sewer", group = "GROUP_CV_CONSTRUCTION", count = { 1, 3 } },
    -- Held at one apiece until the mechanic has more than a single sprite;
    -- two side by side would visibly be the same person twice.
    { match = "garage_gas", group = "GROUP_CV_GARAGE", count = { 1, 1 } },
    { match = "car_dealership", group = "GROUP_CV_GARAGE", count = { 1, 1 } },
    -- Open-site: a fire station's only interior-target furniture is one sofa,
    -- and the crew would be in the apparatus bay regardless.
    { match = "fire_station", group = "GROUP_CV_FIRE_STATION", count = { 1, 2 } },

    -- Business districts and money.  Interior mode for the ones full of desks and
    -- chairs; golf courses are open ground and get a count instead.
    -- Never match a bare "office": that also catches post_office (postal workers)
    -- and office_doctor (a clinic, which belongs to a hospital theme later).
    -- Workplaces get the clerical pool; the wealthy tier keeps the places wealth
    -- actually lives.  post_office is claimed here too -- it was previously
    -- matched by nothing, since a bare "office" fragment was always avoided.
    { match = "office_tower", group = "GROUP_CV_OFFICE" },
    { match = "office_cubical", group = "GROUP_CV_OFFICE" },
    { match = "small_office", group = "GROUP_CV_OFFICE" },
    { match = "post_office", group = "GROUP_CV_OFFICE" },
    { match = "bank", group = "GROUP_CV_OFFICE" },
    { match = "mansion", group = "GROUP_CV_MANSION" },
    { match = "golfcourse", group = "GROUP_CV_BUSINESS", count = { 1, 2 } },

    -- Nightlife.  Both bars and motels are furniture-rich, so interior mode.
    -- "bar" uses prefix matching to avoid barn_aban1 and desolatebarn.
    { match = "bar", group = "GROUP_CV_NIGHTLIFE", prefix = true },
    { match = "2fmotel", group = "GROUP_CV_NIGHTLIFE" },
    { match = "hotel_tower", group = "GROUP_CV_NIGHTLIFE" },

    -- Shops with staff in them.  All eleven were unclaimed before this.
    -- Interior mode throughout: TARGET_FURNITURE is chairs, beds, sofas, stools,
    -- lockers and wardrobes, and a shop floor has few of those, so even the
    -- 19-tile megastore stays sparse rather than filling with employees.
    -- Deliberately kept off the food venues (s_restaurant*, s_teashop): waiting
    -- tables is its own archetype, not this one.
    -- The two big formats first: location_entry_for returns the FIRST match, so
    -- these must precede the GROUP_CV_RETAIL entries below or they never fire.
    -- Security guards belong in a supermarket and a megastore, and would be
    -- absurd in a bike shop, so only these two get the mall cop.
    { match = "megastore", group = "GROUP_CV_BIGSTORE" },
    { match = "s_grocery", group = "GROUP_CV_BIGSTORE" },
    { match = "s_clothes", group = "GROUP_CV_RETAIL" },
    { match = "s_hardware", group = "GROUP_CV_RETAIL" },
    { match = "dollarstore", group = "GROUP_CV_RETAIL" },
    { match = "s_butcher", group = "GROUP_CV_RETAIL" },
    { match = "s_thrift", group = "GROUP_CV_RETAIL" },
    { match = "s_sports", group = "GROUP_CV_RETAIL" },
    { match = "s_petstore", group = "GROUP_CV_RETAIL" },
    { match = "s_gardening", group = "GROUP_CV_RETAIL" },
    { match = "s_bike_shop", group = "GROUP_CV_RETAIL" },

    -- Shops with something behind the counter worth guarding.  All six were
    -- unclaimed before this.  Interior mode: every one of them is a small
    -- furniture-rich room, which is also why the owner reaches you so fast.
    { match = "pawn", group = "GROUP_CV_SHOP" },
    { match = "s_jewelry", group = "GROUP_CV_SHOP" },
    { match = "s_antique", group = "GROUP_CV_SHOP" },
    { match = "s_gun", group = "GROUP_CV_SHOP" },
    { match = "s_hunting", group = "GROUP_CV_SHOP" },
    { match = "s_liquor", group = "GROUP_CV_SHOP" },

    -- Quiet places, for the elderly.  This block sits ABOVE the geek haunts on
    -- purpose: the matcher returns the first entry that matches (the loop around
    -- overmapbuffer.check_ot returns immediately), so s_library has to be claimed
    -- before the "library" fragment below would swallow it.
    --
    -- "park" needs PREFIX, not the default CONTAINS.  is_ot_prefix
    -- (src/overmap.cpp:752-771) accepts a full match or a partial one whose next
    -- character is an underscore, so it matches park and park_roof but never
    -- parking_garage_0_0, trailerparksmall0 or luna_park - all three of which a
    -- CONTAINS match would have caught.
    --
    -- Cemetery is listed twice because the two mapgen families disagree on case:
    -- cemetery_small and cemetery_4square_* are lowercase, Cemetery_1a and
    -- Cemetery_1b are not, and CONTAINS is a plain strstr.
    --
    -- Churches and libraries are interior mode: the church palette carries
    -- f_bench, f_armchair, f_chair, f_bed and f_wardrobe, and library_palette
    -- carries f_armchair, f_chair, f_sofa, f_stool and f_locker, so both have
    -- plenty for the furniture scan to anchor to.  Parks, cemeteries and gardens
    -- are open ground with almost no furniture, so they take a count instead -
    -- the same distinction that made the first construction-site build spawn
    -- nothing (3.1).
    { match = "s_library", group = "GROUP_CV_LIBRARY" },
    { match = "church", group = "GROUP_CV_CHURCH" },
    { match = "park", group = "GROUP_CV_ELDERLY", prefix = true, count = { 1, 3 } },
    { match = "cemetery", group = "GROUP_CV_ELDERLY", count = { 1, 2 } },
    { match = "Cemetery", group = "GROUP_CV_ELDERLY", count = { 1, 2 } },
    { match = "communitygarden", group = "GROUP_CV_ELDERLY", count = { 1, 2 } },

    -- Geek haunts.  "library" now only reaches house_library, the private study;
    -- the public library is claimed above.
    { match = "library", group = "GROUP_CV_GEEK" },
    { match = "s_bookstore", group = "GROUP_CV_GEEK" },
    { match = "s_electronics", group = "GROUP_CV_GEEK" },
    { match = "s_games", group = "GROUP_CV_GEEK" },
    { match = "s_arcade", group = "GROUP_CV_GEEK" },
    { match = "museum", group = "GROUP_CV_GEEK" },
    -- lancenter is literally named "LAN center" and cs_internet_cafe "internet
    -- cafe".  Both are small - four and three overmap tiles including roofs -
    -- and both carry chairs the furniture scan can anchor to (lan_center.json
    -- has f_armchair, f_chair and f_sofa; cs_internet_cafe.json has f_chair and
    -- f_locker), so interior mode is right for them.
    --
    -- No new pool: GROUP_CV_GEEK is already geek 50 / bystander 41 / zombie nerd
    -- 8, which is the correct mix for a room full of machines.  A near-identical
    -- second group would only drift out of step with this one.
    { match = "lancenter", group = "GROUP_CV_GEEK" },
    { match = "cs_internet_cafe", group = "GROUP_CV_GEEK" },

    -- Farmland.  "farm_" rather than "farm" so solar_farm (a power plant) never
    -- matches; house_farm needs its own entry because it has no trailing part.
    -- No "silo" entry: that resolves to missile_silo, a military site.
    -- farm_isherwood_* is already handled by the isherwood exclusion.
    { match = "farm_", group = "GROUP_CV_FARM" },
    { match = "house_farm", group = "GROUP_CV_FARM" },
    { match = "barn", group = "GROUP_CV_FARM" },
    { match = "orchard", group = "GROUP_CV_FARM" },

    -- Clowns.  BN has no circus terrain; luna parks and pizza parlours are the
    -- venues that actually exist.  Malls carry them through GROUP_CV_MALL.
    { match = "luna_park", group = "GROUP_CV_CLOWN" },
    { match = "s_pizza_parlor", group = "GROUP_CV_CLOWN" },

    -- Law and order.  "police" catches police, police_1/2 and the state variants;
    -- bank already draws the office pool, which now carries a security presence.
    { match = "police", group = "GROUP_CV_POLICE" },
    { match = "mall_a", group = "GROUP_CV_MALL" },

    -- Biker bandits: the mod's only hostile faction.  Open-site so they appear on
    -- forecourts and yards rather than indoors, and deliberately absent from
    -- GROUP_CV_INDOOR -- an armed hostile in a random house with no warning is
    -- exactly the unfairness this archetype is designed around.
    { match = "roadstop", group = "GROUP_CV_BIKER", count = { 2, 3 } },
    { match = "s_gas", group = "GROUP_CV_BIKER", count = { 2, 3 } },
    { match = "junkyard", group = "GROUP_CV_BIKER", count = { 2, 3 } },
    { match = "dump", group = "GROUP_CV_BIKER", count = { 2, 3 } },

    -- Medical.  The hospital palette is furniture-rich (f_bed, f_bench, f_chair,
    -- f_locker, f_sofa), so interior mode anchors people to beds and waiting
    -- rooms properly.  office_doctor is claimed here rather than by the business
    -- theme, which is why the office fragments above are deliberately specific.
    { match = "hospital", group = "GROUP_CV_HOSPITAL" },
    { match = "office_doctor", group = "GROUP_CV_HOSPITAL" },
    { match = "s_pharm", group = "GROUP_CV_HOSPITAL" },
  },

  -- Overmap terrain name fragments where wild civilians should not appear:
  -- faction bases, labs and other places that belong to NPCs or are sealed.
  EXCLUDED_TERRAINS = {
    "refctr",
    "evac_center",
    "robofachq",
    "isherwood",
    "_ocu",
    "cabin_strange",
    "cabin_lapin",
    "lab",
    "microlab",
    "necropolis",
    "mil_base",
    "bunker",
    "outpost",
    "prison",
    "aircraft_carrier",
    "bandit",
    "ranch_camp",
    "solar_farm",
  },
}

local CONFIG = merge_config(DEFAULT_CONFIG, storage.config)

if CIVILIANS_PRESENT then
  gdebug.log_info(
    string.format(
      "Civilian Variety: Civilians mod detected, generic bystanders scaled to %d%% (professions unchanged).",
      math.floor(CONFIG.CIVILIANS_PRESENT_SCALE * 100 + 0.5)
    )
  )
end


-- ============================================================================
-- Spawning
-- ============================================================================

-- Sentinel for "no themed location matched"; resolved to one of the two indoor
-- pools at placement time.
local GENERIC_POOL = "<indoor>"

local function is_walkable(map, p)
  local ter = map:get_ter_at(p)
  return ter:obj():get_movecost() > 0
end

--- Look for an open tile within 2 squares of the furniture, so the civilian
--- does not end up standing inside the sofa they were sitting on.
local function find_nearby_free_tile(map, center)
  local map_size = map:get_map_size()
  for _ = 1, CONFIG.TRY_TRIES do
    local x = center.x + gapi.rng(-2, 2)
    local y = center.y + gapi.rng(-2, 2)
    if x >= 0 and x < map_size and y >= 0 and y < map_size then
      local p = PointOmtMs.new(x, y)
      if is_walkable(map, p) then return p end
    end
  end
  return nil
end

--- Fewer and fewer of them are still alive as the weeks pass.
local function survives_the_calendar()
  if CONFIG.VANISH_BASE_RATE >= 1.0 then return true end
  local days = (gapi.current_turn() - gapi.turn_zero()):to_days()
  local survival_chance = CONFIG.VANISH_BASE_RATE ^ (days / CONFIG.VANISH_PERIOD_DAYS)
  return gapi.rng(1, 10000) <= (survival_chance * 10000)
end

local function is_excluded_location(omt_pos)
  if not omt_pos then return false end
  for _, fragment in ipairs(CONFIG.EXCLUDED_TERRAINS) do
    if overmapbuffer.check_ot(fragment, OtMatchType.CONTAINS, omt_pos) then return true end
  end
  return false
end

--- Which pool this chunk draws from.  Resolved once per generated chunk rather
--- than once per furniture tile, so the cost is a short loop per map, not per
--- square.  Roof layers are skipped: "hospital_1_roof" contains "hospital", and
--- nobody should be found sitting on the roof.
local function location_entry_for(omt_pos)
  if omt_pos and not overmapbuffer.check_ot("_roof", OtMatchType.CONTAINS, omt_pos) then
    for _, entry in ipairs(CONFIG.LOCATION_GROUPS) do
      -- Default CONTAINS is fine for distinctive fragments.  Short words need
      -- PREFIX, which requires underscore-delimited parts: "bar" then matches
      -- bar / bar_1 / bar_roof but never barn_aban1 or desolatebarn.
      local how = entry.prefix and OtMatchType.PREFIX or OtMatchType.CONTAINS
      if overmapbuffer.check_ot(entry.match, how, omt_pos) then return entry end
    end
  end
  return nil
end

--- Any walkable tile in the chunk, for open sites with nothing to sit on.
local function find_any_free_tile(map)
  local map_size = map:get_map_size()
  for _ = 1, CONFIG.TRY_TRIES * 4 do
    local p = PointOmtMs.new(gapi.rng(0, map_size - 1), gapi.rng(0, map_size - 1))
    if is_walkable(map, p) then return p end
  end
  return nil
end

--- Open work sites: scatter people across the lot instead of anchoring them to
--- furniture that mostly is not there.
local function populate_open_site(map, entry)
  local how_many = gapi.rng(entry.count[1], entry.count[2])
  for _ = 1, how_many do
    if survives_the_calendar() then
      local spawn_at = find_any_free_tile(map)
      if spawn_at then map:place_spawns(entry.group, 1, spawn_at, spawn_at, 1.0, true) end
    end
  end
end

mod.on_mapgen_postprocess = function(params)
  local map = params.map
  if not map then return end
  if is_excluded_location(params.omt) then return end

  local location = location_entry_for(params.omt)

  -- Open work sites are populated by area and skip the furniture scan.
  if location and location.count then
    populate_open_site(map, location)
    return
  end

  local spawn_group = location and location.group or GENERIC_POOL
  local size = map:get_map_size()
  for x = 0, size - 1 do
    for y = 0, size - 1 do
      local p = PointOmtMs.new(x, y)
      local furn = map:get_furn_at(p)
      if furn and furn:is_valid() and CONFIG.TARGET_FURNITURE[furn:str_id():str()] then
        if gapi.rng(1, 100) <= CONFIG.SPAWN_CHANCE and survives_the_calendar() then
          local group = spawn_group
          local place = true
          if group == GENERIC_POOL then
            -- Split the untyped indoor pool in two so the Civilians guard can
            -- thin the generic half without touching the occupational half.
            if gapi.rng(1, 1000) <= CONFIG.GENERIC_SHARE then
              group = "GROUP_CV_INDOOR_GENERIC"
              place = not CIVILIANS_PRESENT
                or gapi.rng(1, 1000) <= CONFIG.CIVILIANS_PRESENT_SCALE * 1000
            else
              group = "GROUP_CV_INDOOR_SPECIAL"
            end
          end
          if place then
            local spawn_at = find_nearby_free_tile(map, p)
            if spawn_at then map:place_spawns(group, 1, spawn_at, spawn_at, 1.0, true) end
          end
        end
      end
    end
  end
end

gdebug.log_info("Civilian Variety: ready.")

-- ============================================================================
-- Ambulance crews
-- ============================================================================

--- Is one of ours already standing near this spot?  Used instead of remembering
--- which ambulances have been handled: pos() is a local map coordinate that
--- shifts as the map re-centres, so anything based on stored coordinates would
--- drift.  "Is somebody already there?" cannot drift.
local function civilian_near(civilians, pos, radius)
  if not civilians then return false end
  for _, mon in ipairs(civilians) do
    if mon and not mon:is_dead() then
      local d = coords.rl_dist(mon:get_pos_ms(), pos)
      if d and d <= radius then return true end
    end
  end
  return false
end

local function free_tile_near(map, pos, radius)
  local candidates = map:points_in_radius(pos, radius, 0)
  if not candidates then return nil end
  for _ = 1, CONFIG.TRY_TRIES do
    local p = candidates[gapi.rng(1, #candidates)]
    if p then
      local ter = map:get_ter_at(p)
      if ter and ter:obj():get_movecost() > 0 then return p end
    end
  end
  return nil
end

mod.on_every_x_ambulance = function()
  if not CONFIG.AMBULANCE_ENABLED then return end
  local map = gapi.get_map()
  if not map then return end

  local vehicles = map:get_vehicles()
  if not vehicles or #vehicles == 0 then return end

  local civilians = gapi.get_monsters_if({ ["faction_ids"] = CIVILIAN_FACTIONS })

  for _, wrapped in ipairs(vehicles) do
    if wrapped and wrapped:type() == "ambulance" then
      local vpos = wrapped:pos()
      if vpos
        and not civilian_near(civilians, vpos, CONFIG.AMBULANCE_CLEAR_RADIUS)
        and gapi.rng(1, 100) <= CONFIG.AMBULANCE_CHANCE
        and survives_the_calendar()
      then
        local spot = free_tile_near(map, vpos, CONFIG.AMBULANCE_PLACE_RADIUS)
        if spot then map:place_spawns("GROUP_CV_HOSPITAL", 1, spot, spot, 1.0, true) end
      end
    end
  end
end

-- ============================================================================
-- Interaction: examine a civilian to talk to them
-- ============================================================================

local EFFECT_PET = EffectTypeId.new("pet")

-- Flavour for the talk option.  One line is picked at random.
local TALK = {
  ["mon_cv_bystander"] = {
    "They look at you for a while without answering.",
    "They ask whether the roads are open yet.",
    "They tell you a street name, as though that explains something.",
    "They say they are waiting for someone.  They do not say who.",
  },
  ["mon_cv_firefighter"] = {
    "\"Anyone else with you?  Anyone hurt?\"",
    "\"You doing okay?\"",
    "\"Stay low and stay behind me if you're coming.\"",
  },
  ["mon_cv_mechanic"] = {
    "\"Everything on the lot's dead.  Every single one.\"",
    "\"You need a belt, an alternator, anything, I know where it is.\"",
    "\"Whose keys are these?  Somebody's going to want these back.\"",
  },
  ["mon_cv_construction_worker"] = {
    "\"Site's not secure.  Nobody signed off on any of this.\"",
    "\"You shouldn't be out here without a hat on.\"",
    "\"We were three weeks from topping out.\"",
  },
  ["mon_cv_doctor"] = {
    "\"Are you hurt?  Actually hurt, or just walking it off?\"",
    "\"I have no blood, no theatre and no power.  Ask me again.\"",
    "\"Everyone keeps asking me what it is.  I don't know what it is.\"",
  },
  ["mon_cv_nurse"] = {
    "\"Sit down before you fall down.\"",
    "\"We ran out of most things on the first night.\"",
    "\"If you're not bleeding, you can wait.\"",
  },
  ["mon_cv_businessman"] = {
    "\"This is a correction.  A severe one, but a correction.\"",
    "\"If you're liquid right now, you are in an extraordinary position.\"",
    "\"I own four of these.  Owned.  Own.\"",
  },
  ["mon_cv_sex_worker"] = {
    "\"Rates are the same as they were.  Everything else went to hell, not me.\"",
    "\"You look like you've had a week.  I've had a month.\"",
    "\"Cash only.  Card machine's been down since the world ended.\"",
    "\"You don't happen to have anything on you?  Anything at all?\"",
    "\"I'm not going in there.  You go in there.\"",
  },
  ["mon_cv_businesswoman"] = {
    "\"Everyone panics at the bottom.  That's what the bottom is.\"",
    "\"I can still get you a very good price on that.\"",
    "\"My phone hasn't rung in a while.  That's unusual.\"",
  },
}

-- Female doctors say exactly what the men say.
TALK["mon_cv_doctor_f"] = TALK["mon_cv_doctor"]

TALK["mon_cv_office_worker"] = {
  "\"Do you know if the building's been cleared?  Officially, I mean.\"",
  "\"I only came in because nobody said not to.\"",
  "\"My badge doesn't open anything any more.\"",
}
TALK["mon_cv_office_worker_f"] = TALK["mon_cv_office_worker"]

-- Heavyset bystanders are ordinary people; they say what ordinary people say.
TALK["mon_cv_bystander_fat"] = TALK["mon_cv_bystander"]
TALK["mon_cv_bystander_fat_f"] = TALK["mon_cv_bystander"]

-- The elderly are the only civilians who answer you properly and at length, and
-- the content is always the same underneath: they have understood their odds,
-- and they are being polite about it.  A few entries are described actions
-- rather than speech, for the ones who cannot manage the sentence.
TALK["mon_cv_elderly"] = {
  "\"I'm not going to be much use to you, son.  I know that.\"",
  "\"Took me two hours to get down here.  Two hours, that stretch.\"",
  "\"You go on.  I'll only slow you down and we both know it.\"",
  "\"Doctor told me to keep walking.  Well.  I'm keeping walking.\"",
  "\"I was in Korea.  This is worse, and I'm eighty-one.\"",
  "\"Have you seen my wife?  Grey coat.  She was right behind me.\"",
  "He starts to explain something, loses the thread, and apologises for it.",
  "He shifts his weight onto the stick and asks whether you have somewhere to be.",
  "\"They don't get tired.  That's the thing about them.  They don't get tired.\"",
  "He looks at you for a moment and asks, quite steadily, whether it is bad everywhere.",
}
TALK["mon_cv_elderly_f"] = {
  "\"I'm all right, dear.  Don't fuss.\"",
  "\"I've not got my tablets.  They're in the house and the house is that way.\"",
  "\"My grandson lives out past the river.  I was going to see about him.\"",
  "\"You're very kind, but I'd only hold you up.\"",
  "\"I keep thinking somebody will come round and sort it out.\"",
  "She asks whether you have eaten, and seems genuinely troubled by the answer.",
  "She tells you to be careful, twice, and does not say of what.",
  "\"I've buried a husband and two sisters.  I'd just rather not be the last one.\"",
  "She pats your arm and tells you to run if you have to, and not to feel bad about it.",
  "She stops mid-sentence to get her breath, and waves you off while she does it.",
}

TALK["mon_cv_geek"] = {
  "\"Okay so -- okay.  Have you seen how they move?  Have you actually watched?\"",
  "\"I have a plan.  It is not a good plan.\"",
  "\"I really thought I'd be better at this.\"",
}
TALK["mon_cv_farmer"] = {
  "\"Fence is down on the east side.  Whole thing's gone.\"",
  "\"They come up out of the treeline.  Same time every night.\"",
  "\"You can stand there or you can pick something up.\"",
}
TALK["mon_cv_farmer_f"] = TALK["mon_cv_farmer"]

-- The retail worker is the mod's one joke that is also its bleakest line: they
-- are still on shift, because nobody with the authority to end the shift has
-- come back.  Written without pronouns - the sprite pool is half men, half women
-- under two ids that share this list.
TALK["mon_cv_retail"] = {
  "\"We're open.  I don't know why we're open, but we're open.\"",
  "\"Card only.  The card machine doesn't work either.  I'm aware.\"",
  "\"Everything on aisle four went first.  Everything.  In about an hour.\"",
  "\"I can't authorise that.  Only the manager can, and he isn't here.\"",
  "You are asked, entirely automatically, whether you have a loyalty card.",
  "\"Six people asked me where the bottled water was.  Then nobody asked anything.\"",
  "\"I keep tidying the shelves.  It's that or think about it.\"",
  "\"They told us to stay until close.  Nobody's said when close is.\"",
  "They straighten something on the shelf beside you without appearing to notice doing it.",
  "\"If you're taking that, just take it.  I genuinely do not care any more.\"",
}
TALK["mon_cv_retail_f"] = TALK["mon_cv_retail"]

-- The mall cop takes the job entirely seriously, and the joke is that nobody
-- has told them the job stopped existing.  Played straight rather than winking:
-- the authority is imaginary but the courage is real, which is funnier and also
-- slightly sad.  No pronouns - the sprite pool is mixed.
TALK["mon_cv_butler"] = {
  "\"The family is not receiving today.  I am very sorry.\"",
  "\"I have not been given any instruction to the contrary, so I am continuing.\"",
  "\"If sir would leave a card, I shall see that it is passed on.\"",
  "\"There has been no word from the house since Tuesday.  I have kept to the routine.\"",
  "He inclines his head very slightly, and does not move out of the doorway.",
  "\"I could not say where the family have gone.  I would not say, in any case.\"",
  "\"The silver is accounted for.  I checked it twice this morning.\"",
  "\"One does what one can, in the circumstances.  One goes on doing it.\"",
}

TALK["mon_cv_maid"] = {
  "\"I've done the upstairs twice.  I don't know what else to do with myself.\"",
  "\"Nobody's rung the bell since yesterday morning.  I keep listening for it.\"",
  "\"Mr. Ashcombe said to stay at our posts.  So I'm at my post.\"",
  "She stops, straightens something on a table that did not need straightening, and moves on.",
  "\"I'm not to go in the west wing.  I never have been.\"",
  "\"There's a room up there I've stopped cleaning.  Don't ask me why.\"",
  "\"They'll want it all in order when they come back.  If they come back.\"",
  "\"I've a bus to catch at six.  I know.  I know there isn't.\"",
}

TALK["mon_cv_mallcop"] = {
  "\"Stand back, citizen.  I'll deal with this.\"",
  "\"This is a secure site.  I'd need to see some ID.\"",
  "\"I've radioed it in.  Someone will be along.\"",
  "\"Level two clearance.  That's food court and above.\"",
  "\"You can't park there.  I appreciate the circumstances.  You still can't park there.\"",
  "They straighten up as you approach, and adjust a badge that is not a police badge.",
  "\"Shoplifting is still theft.  I don't care what's happened.\"",
  "\"Nine years, no incidents.  Well.  No incidents until recently.\"",
  "They rest a hand on the tazer, in a way clearly practised in a mirror.",
  "\"Between you and me, I've been thinking about applying to the real force.\"",
}

-- Every line is a warning wearing a sentence.  They are not frightened of you and
-- not making conversation; they are telling you where the line is while there is
-- still time to hear it.  Written without pronouns: sprite 153 is a woman.
TALK["mon_cv_shopkeeper"] = {
  "\"You can look from there.\"",
  "\"Thirty-one years.  Thirty-one.  And it's mine until somebody tells me different.\"",
  "\"You're the fourth this week.  The other three ran.\"",
  "\"I'm not being unreasonable.  I'm being clear.\"",
  "You get no answer.  They simply move, so the counter is between you and everything else.",
  "\"Money still works in here.  Try it.\"",
  "\"There's nothing back there you need.  There's things back there I need.\"",
  "They watch your hands rather than your face for the entire time you are speaking.",
  "\"Police said stay put and mind the property.  So that's what I'm doing.\"",
  "\"Buy something or step outside.  Those are both fine with me.\"",
}

-- Clergy get the longest answers of anyone in the mod, and the least certainty.
-- Both lists deliberately avoid reassurance: they are people whose job was to
-- have an answer, working without one.
TALK["mon_cv_priest"] = {
  "\"Come in if you want to.  The doors don't lock and I wouldn't lock them.\"",
  "\"People keep asking me what it means.  I've stopped pretending I know.\"",
  "\"I've said more funerals this week than in the nine years before it.\"",
  "\"If you need to sit down for a while, sit down.  Nobody's using the pews.\"",
  "\"I'm not going to tell you it's a judgement.  I don't believe that.\"",
  "He asks your name, and repeats it once, as though filing it somewhere safe.",
  "\"There were forty of us in here on the first night.  There are none now.\"",
  "He starts to say something about mercy, stops, and offers you water instead.",
  "\"You can be angry about it.  I'd think less of you if you weren't.\"",
  "He looks at the door for a moment, then back at you, and asks if you've eaten.",
}
TALK["mon_cv_nun"] = {
  "\"You'll want to be inside before dark.  I'm not going to argue about it.\"",
  "\"We took in whoever came.  It was never going to be enough.\"",
  "\"I've been praying.  I'm not going to pretend I've been answered.\"",
  "\"Sit.  You're swaying and you haven't noticed.\"",
  "She asks, quite directly, whether you have hurt anybody who was still alive.",
  "\"Forty years I've done this.  Nothing in forty years is any use this week.\"",
  "She presses something into your hand without explaining what it is for.",
  "\"If you find children out there, you bring them here.  You understand me.\"",
  "She tells you she is not frightened, and it is almost entirely convincing.",
  "\"Go on then.  I'll be here.  Somebody has to be.\"",
}

-- Panicked bystanders never manage a line.  Every entry is a description of the
-- attempt failing: they are too frightened, too winded, or too far gone to get a
-- sentence out.  The clown says nothing because he is in character; these say
-- nothing because they cannot.
TALK["mon_cv_bystander_panicked"] = {
  "They try to answer, get halfway through a word, and start again from the beginning.",
  "They are breathing far too fast to say anything, and they know it, and that makes it worse.",
  "They grab your arm, look at your face, and let go without having said anything at all.",
  "Whatever they are trying to tell you comes out as the same syllable, three times.",
  "They point behind you, urgently, at nothing you can see.",
  "They shake their head continuously while you speak, as though warding the words off.",
  "They start to cry, apologise for crying, and then manage neither.",
  "They ask you something, but they are already backing away before you can answer.",
}

-- Bikers are hostile; the examine menu deliberately does not cover them, so
-- TALK has no entry and on_try_monster_interaction leaves them to vanilla.

TALK["mon_cv_police"] = {
  "\"Stay behind me.  Don't run, they follow movement.\"",
  "\"Dispatch went quiet on the second day.  I'm still on shift.\"",
  "\"If you see anyone still breathing, you send them my way.\"",
}
TALK["mon_cv_swat"] = {
  "\"We were told to hold the block.  So I'm holding the block.\"",
  "\"Shield holds.  Everything else is negotiable.\"",
  "\"Anyone left alive in there, or is it just us?\"",
}

TALK["mon_cv_cop_pistol"] = TALK["mon_cv_police"]

-- The clown is the one archetype that never speaks.  Every line is a described
-- bit of business instead: it suits a mime in full paint, and it lets the joke
-- curdle slightly without anyone having to say anything.
TALK["mon_cv_clown"] = {
  "They honk their nose at you.  Twice.  The second one is somehow pointed.",
  "They produce a flower from their sleeve and offer it to you.  It died a long time ago.",
  "They mime walking into a wall, stagger back, and check whether you enjoyed it.",
  "They begin pulling handkerchiefs from a pocket.  There are a great many, and none are clean.",
  "They twist a balloon into an animal, consider it, and hand it over with tremendous seriousness.",
  "They pretend to trip, recover with a flourish, and bow to nobody in particular.",
  "They tap an invisible wristwatch, shrug enormously, and gesture at the empty street.",
  "They juggle three things badly, drop all of them, and stare at their hands.",
  "They mime being trapped inside a box.  They keep at it for rather longer than the joke needs.",
  "They offer a handshake.  The buzzer in their palm is out of batteries, and they seem to know it.",
}

-- ============================================================================
-- One-shot favours
-- ============================================================================
--
-- Some archetypes will help once, and only once.  The marker is an effect on
-- the monster itself rather than an entry in mod storage: it is per-individual,
-- it saves with the creature, and it cannot drift the way a stored coordinate
-- would.  A second favour means finding a different person.
--
-- `give` archetypes leave an item on the ground beside them.  Handing it over
-- directly would be neater, but dropping it is honest about the fiction - they
-- set it down and step back.

local EFFECT_HELPED = EffectTypeId.new("effect_cv_helped")
local MORALE_GOOD = MoraleTypeDataId.new("morale_feeling_good")
-- Our own morale type, declared in morale_types.json.  add_morale merges entries
-- of the same type, so sharing morale_feeling_good with the doctor and the sex
-- worker would have a blessing silently overwrite a treatment bonus.
local MORALE_BLESSED = MoraleTypeDataId.new("morale_cv_blessed")
-- trait_id is string_id<mutation_branch>, which luna exposes as MutationBranchId
-- (src/catalua_luna_doc.h:265).  Built once here rather than per call.
local TRAIT_SPIRITUAL = MutationBranchId.new("SPIRITUAL")
local FOREVER = TimeDuration.from_days(3650)

local FAVOUR = {
  -- The store owner is the only favour that UNDOES something rather than giving
  -- you a thing.  They anger on proximity and the engine never lets that anger
  -- decay, so without this they are a one-mistake permanent enemy.
  ["mon_cv_shopkeeper"] = {
    label = "Offer him money to let you browse",
    hint = "Two bundles.  No negotiation, and no calming down on their own.",
    kind = "appease",
  },

  -- Clergy bless.  The only favour that always succeeds: there is no chance roll
  -- and nothing to run out of, because a priest turning you down would be a
  -- strange thing for a priest to do.  What varies is what it is worth to you.
  ["mon_cv_priest"] = {
    label = "Ask for a blessing",
    hint = "It costs them nothing and they will not refuse.",
    kind = "bless",
  },
  ["mon_cv_nun"] = {
    label = "Ask for a blessing",
    hint = "It costs them nothing and they will not refuse.",
    kind = "bless",
  },

  -- Doctors treat; nurses supply.  Deliberately not both: the doctor is the only
  -- medical service left in the world, and the nurse is the only reliable source
  -- of supplies, so each is worth finding for its own reason.
  ["mon_cv_doctor"] = {
    label = "Ask them to treat your wounds",
    hint = "They will need a while, and you will have to stand still for it.",
    kind = "treat",
  },
  ["mon_cv_nurse"] = {
    label = "Ask them for medical supplies",
    hint = "They might have something they can spare.",
    kind = "give",
    chance = 50,
    group = "cv_favour_medical",
    yes = "%s hands over what little they can spare and sets it down beside you.",
    no = "\"There is nothing left.  I am sorry.  There is nothing I can do for you.\"",
  },
  ["mon_cv_mechanic"] = {
    label = "Ask them for a spare tool",
    hint = "They might have something rattling around the bottom of the bag.",
    kind = "give",
    chance = 50,
    group = "cv_favour_tools",
    yes = "%s digs through their bag and puts something down where you can reach it.",
    no = "\"Nothing spare.  Wish I did.\"",
  },
  ["mon_cv_firefighter"] = {
    label = "Ask them for water",
    hint = "They were carrying supplies for other people.",
    kind = "give",
    chance = 50,
    group = "cv_favour_water",
    yes = "%s passes you water without needing to be asked twice.",
    no = "\"Ran dry hours ago.  Try the hydrants on the north side.\"",
  },
  ["mon_cv_farmer"] = {
    label = "Ask them for food",
    hint = "They are likelier to have some than most.",
    kind = "give",
    chance = 50,
    group = "cv_favour_food",
    yes = "%s looks you over, decides something, and leaves food where you can take it.",
    no = "\"It is all in the ground or gone.  Come back at harvest, if there is one.\"",
  },
  ["mon_cv_sex_worker"] = {
    label = "Offer them a money bundle",
    hint = "Costs one money bundle.  Takes a while.",
    kind = "company",
    decline = 20,
    cost = "money_bundle",
  },
}
-- Gendered variants share their counterpart's entry.
FAVOUR["mon_cv_doctor_f"] = FAVOUR["mon_cv_doctor"]
FAVOUR["mon_cv_farmer_f"] = FAVOUR["mon_cv_farmer"]

--- Leave a favour beside the monster, on a walkable tile where possible.
--- Uses place_items rather than create_item_at because only an item_group can
--- declare a `container-item`: spawning water_clean bare drops a puddle on the
--- floor instead of a bottle the player can pick up.
local function leave_item_near(mon, group_id)
  local map = gapi.get_map()
  if not map then return false end
  local pos = mon:get_pos_ms()
  local spots = map:points_in_radius(pos, 1, 0)
  local target = pos
  if spots then
    for _ = 1, 6 do
      local p = spots[gapi.rng(1, #spots)]
      if p then
        local ter = map:get_ter_at(p)
        if ter and ter:obj():get_movecost() > 0 then
          target = p
          break
        end
      end
    end
  end
  -- chance 100, and topleft == bottomright so it lands on exactly one tile.
  map:place_items(group_id, 100, target, target, false)
  return true
end

--- Paid company runs as an assigned activity, exactly like reading a book: time
--- passes normally while it ticks, and a wandering zombie can interrupt it.
--- Treatment finished uninterrupted.  healall() is the right call rather than
--- mod_all_parts_hp_cur(): Character::heal clamps each part to
--- min(amount, max - current) (src/character.cpp:9864), so nobody ends up above
--- their maximum, and it raises the proper heal event and pain-morale update.
--- mod_all_parts_hp_cur does a bare `hp_cur += mod` with no clamp at all.
game.activity_functions["cv_treatment_finished"] = function(params)
  local who = params.user
  if not who then return end
  who:healall(gapi.rng(CONFIG.DOCTOR_HEAL_MIN, CONFIG.DOCTOR_HEAL_MAX))
  who:add_morale(MORALE_GOOD, 6, 12, TimeDuration.from_hours(3), TimeDuration.from_hours(1), false)
  gapi.add_msg(MsgType.good, "Your wounds have been cleaned, closed and dressed properly.")
end

game.activity_functions["cv_company_finished"] = function(params)
  local who = params.user
  if not who then return end
  who:add_morale(MORALE_GOOD, 12, 25, TimeDuration.from_hours(4), TimeDuration.from_hours(2), false)
  gapi.add_msg(MsgType.good, "You feel considerably better about the state of things.")
end

local function do_favour(mon, entry)
  local you = gapi.get_avatar()
  local name = mon:get_name()

  if entry.kind == "appease" then
    -- Second argument is mandatory: the C++ default does not survive SET_FX_T
    -- (see the company branch below).
    local paid = you:get_item_with_id(ItypeId.new(CONFIG.APPEASE_COST), false)
    if not paid or paid:is_null() then
      gapi.add_msg(MsgType.info, string.format(
        "%s looks at your empty hands and does not soften at all.", name))
      return false
    end
    you:use_charges(ItypeId.new(CONFIG.APPEASE_COST), CONFIG.APPEASE_COUNT)
    mon:add_effect(EFFECT_HELPED, FOREVER)

    -- The actual mechanism.  For a MF_FACTION_MEMORY monster, attitude() reads
    -- effective_anger toward the player from get_faction_anger("player") alone
    -- (src/monster.cpp:1818-1834), so subtracting exactly that much zeroes it.
    -- The engine has no decay path of its own - it only ever adds
    -- (src/monster.cpp:4519) - which is why this is the only way back.
    local held = mon:get_faction_anger("player")
    if held > 0 then mon:add_faction_anger("player", -held) end
    -- anger/morale are the non-faction fallback; reset them too so the same
    -- monster behaves if FACTION_MEMORY is ever taken off the base.
    mon.anger = 0
    mon.morale = 0

    if held >= 10 then
      gapi.add_msg(MsgType.good, string.format(
        "%s counts it twice, lowers the shotgun, and goes back behind the counter.", name))
    else
      gapi.add_msg(MsgType.good, string.format(
        "%s counts it twice and nods at the shelves.  Take your time.", name))
    end
    return true
  end

  if entry.kind == "bless" then
    mon:add_effect(EFFECT_HELPED, FOREVER)
    local devout = you:has_trait(TRAIT_SPIRITUAL)
    local bonus = devout and CONFIG.BLESS_BONUS_SPIRITUAL or CONFIG.BLESS_BONUS
    local cap = devout and CONFIG.BLESS_MAX_SPIRITUAL or CONFIG.BLESS_MAX
    -- Lasts a good while and decays slowly, so it reads as something you carry
    -- away with you rather than a snack.
    you:add_morale(MORALE_BLESSED, bonus, cap,
      TimeDuration.from_hours(devout and 12 or 6),
      TimeDuration.from_hours(devout and 4 or 2), false)
    gapi.add_msg(MsgType.info, string.format(
      "%s rests a hand on your head and says the words without hurrying them.", name))
    if devout then
      gapi.add_msg(MsgType.good,
        "You have not heard them in a long time, and they land exactly where you needed them to.")
    else
      gapi.add_msg(MsgType.good, "You feel a little steadier for it.")
    end
    return true
  end

  if entry.kind == "treat" then
    -- Not spending a one-shot favour on somebody who is not hurt.  The marker
    -- goes on only once treatment actually begins.
    if you:hp_percentage() >= 100 then
      gapi.add_msg(MsgType.info, string.format(
        "%s looks you over with some care, and tells you there is nothing to treat.", name))
      return false
    end
    mon:add_effect(EFFECT_HELPED, FOREVER)
    gapi.add_msg(MsgType.info, string.format(
      "%s sits you down and starts work, talking the whole time about nothing in particular.", name))
    -- Interruptible on purpose.  The healing lands in on_finish, so a zombie
    -- wandering in costs you the treatment and the favour both.
    you:assign_lua_activity({
      ["type"] = ActivityTypeId.new("ACT_WAIT"),
      ["duration"] = TimeDuration.from_minutes(gapi.rng(15, 30)),
      ["name"] = "being treated",
      ["on_finish"] = "cv_treatment_finished",
      ["interruptable"] = true,
    })
    return true
  end

  if entry.kind == "company" then
    -- The second argument is mandatory in Lua: the C++ default (need_charges =
    -- false) does not survive SET_FX_T, which binds the explicit two-argument
    -- signature (src/catalua_bindings_creature.cpp:1067).  Omitting it raises
    -- "stack index 3, expected boolean, received no value".
    local paid = you:get_item_with_id(ItypeId.new(entry.cost), false)
    if not paid or paid:is_null() then
      gapi.add_msg(MsgType.info, string.format("%s looks at your empty hands, and looks away.", name))
      return false
    end
    -- Declining costs nothing: they turn it down before any money changes hands.
    if gapi.rng(1, 100) <= entry.decline then
      gapi.add_msg(MsgType.mixed, string.format("%s looks you up and down, and declines.", name))
      return false
    end
    -- money_bundle is `"stackable": true`, so a stack of five is ONE item object
    -- carrying five charges.  remove_item removes that object and takes the lot;
    -- use_charges removes exactly the quantity asked for.
    you:use_charges(ItypeId.new(entry.cost), 1)
    mon:add_effect(EFFECT_HELPED, FOREVER)
    gapi.add_msg(MsgType.info, string.format("%s takes the money and beckons you somewhere quieter.", name))
    you:assign_lua_activity({
      ["type"] = ActivityTypeId.new("ACT_WAIT"),
      ["duration"] = TimeDuration.from_minutes(gapi.rng(10, 30)),
      ["name"] = "spending a while out of the world",
      ["on_finish"] = "cv_company_finished",
      ["interruptable"] = true,
    })
    return true
  end

  mon:add_effect(EFFECT_HELPED, FOREVER)
  if gapi.rng(1, 100) <= entry.chance then
    leave_item_near(mon, entry.group)
    gapi.add_msg(MsgType.good, string.format(entry.yes, name))
  else
    gapi.add_msg(MsgType.info, entry.no)
  end
  return true
end

-- ============================================================================
-- Ambient dread
-- ============================================================================
--
-- Occasional lines describing something heard rather than seen.  Buckets are
-- checked cheapest-first and the first match wins, so the only query with any
-- real cost - the civilian sweep - runs solely when the player is outdoors in
-- daylight, on a tick that already passed both the roll and the cooldown.

local AMBIENT = {
  night = {
    "Somewhere north of here a car alarm has been going for a while.  It stops mid-cycle.",
    "A dog is barking, a long way off.  It has been barking for hours.",
    "Something heavy moves through undergrowth nearby, unhurried, and does not come closer.",
    "There is a light on in a window across the way.  You are fairly sure there wasn't, earlier.",
    "Far off, glass breaks, and then keeps breaking, methodically, pane after pane.",
    "The wind drops, and for a moment you hear how quiet it has become.",
    "Someone is screaming, distantly.  It stops before you can decide which direction it came from.",
  },
  indoors = {
    "Upstairs, something settles.  Houses do that.  Houses have always done that.",
    "A tap is running somewhere in the building.  You cannot find it.",
    "The floor creaks in the next room, twice, as though someone shifted their weight.",
    "A phone rings somewhere in the building.  Four rings, then nothing.",
    "There is a smell of cooking from somewhere, faint and old and wrong.",
    "Something taps at a window on the other side of the wall.  A branch, probably.",
    "The pipes knock once, hard, and are quiet.",
  },
  civilians = {
    "Someone nearby is talking, quietly and continuously, to nobody you can see.",
    "Somebody close by keeps checking their watch.  You can hear the sleeve, over and over.",
    "Someone is humming.  They stop when they notice you listening, then start again.",
    "Nearby, somebody laughs - briefly, at nothing - and then apologises to the empty air.",
    "You hear a bag being packed and unpacked, packed and unpacked, a few metres away.",
    "Someone close by is reciting an address under their breath, as though afraid of forgetting it.",
  },
  day = {
    "A radio, faint and far off, is still reading out evacuation points that no longer exist.",
    "An engine starts somewhere, revs badly, and dies.  Nobody tries again.",
    "Crows go up all at once from a rooftop a few streets over.",
    "There is a column of smoke on the horizon that was not there yesterday.",
    "A church bell rings the hour.  It is not the right hour.",
    "Somewhere nearby, an unattended sprinkler is still watering a lawn.",
    "A car horn sounds twice, politely, as though the traffic might still clear.",
  },
}

mod.on_every_x_ambient = function()
  if not CONFIG.AMBIENT_ENABLED then return end
  if gapi.rng(1, 100) > CONFIG.AMBIENT_CHANCE then return end

  -- One turn is one second, so the cooldown converts straight to turns.
  local now = gapi.current_turn():to_turn()
  local last = storage.ambient_last_turn
  if last and now - last < CONFIG.AMBIENT_COOLDOWN_MINUTES * 60 then return end

  local you = gapi.get_avatar()
  if not you then return end
  local pos = you:get_pos_ms()
  local map = gapi.get_map()

  local bucket
  if gapi.current_turn():is_night() then
    bucket = "night"
  elseif map and not map:is_outside(pos) then
    bucket = "indoors"
  else
    -- get_monsters_if filters by faction engine-side, so this is one query and a
    -- short distance walk rather than a scan of every tile in radius.
    local civilians = gapi.get_monsters_if({ ["faction_ids"] = CIVILIAN_FACTIONS })
    if civilian_near(civilians, pos, CONFIG.AMBIENT_CIVILIAN_RADIUS) then
      bucket = "civilians"
    else
      bucket = "day"
    end
  end

  local lines = AMBIENT[bucket]
  if not lines or #lines == 0 then return end
  local pick = lines[gapi.rng(1, #lines)]
  -- A single reroll: enough to stop the obvious back-to-back repeat without
  -- bookkeeping a full recent-history list for something this rare.
  if #lines > 1 and pick == storage.ambient_last_line then
    pick = lines[gapi.rng(1, #lines)]
  end

  storage.ambient_last_line = pick
  storage.ambient_last_turn = now
  gapi.add_msg(MsgType.info, pick)
end


mod.on_try_monster_interaction = function(params)
  local mon = params.monster
  if not mon then return end

  local lines = TALK[mon:get_type():str()]
  if not lines then return end -- not one of ours; leave the stock behaviour alone

  -- Anything already tamed (leftovers from the old follower mechanic) falls
  -- straight through to the game's own pet menu, so it can still be managed.
  if mon:has_effect(EFFECT_PET) then return end

  local favour = FAVOUR[mon:get_type():str()]
  local spent = mon:has_effect(EFFECT_HELPED)

  local menu = UiList.new()
  menu:title(mon:get_name())
  menu:add_w_desc(1, "Talk to them", "See whether they have anything to say.")
  if favour and not spent then
    menu:add_w_desc(3, favour.label, favour.hint)
  end
  menu:add_w_desc(2, "Other", "Open the standard interaction menu.")
  menu:add(0, "Leave them alone")

  local choice = menu:query()
  if choice == 1 then
    gapi.add_msg(MsgType.info, lines[gapi.rng(1, #lines)])
  elseif choice == 3 and favour and not spent then
    do_favour(mon, favour)
  end

  -- The engine hands us params.results pre-set to allowed = true and reads it
  -- back afterwards (src/catalua.cpp:697-701); a returned table is discarded.
  -- Only "Other" lets the stock menu through.
  if params.results then params.results.allowed = (choice == 2) end
end
