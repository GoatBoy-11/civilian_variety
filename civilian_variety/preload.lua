local mod = game.mod_runtime[game.current_mod]

-- Places civilians around furniture when a map chunk is generated.
game.add_hook("on_mapgen_postprocess", function(params)
  if mod.on_mapgen_postprocess then return mod.on_mapgen_postprocess(params) end
end)

-- Replaces the stock friendly-creature menu when examining one of our civilians.
-- Returning { allowed = false } suppresses the built-in menus (src/game.cpp:8494).
game.add_hook("on_try_monster_interaction", function(params)
  if mod.on_try_monster_interaction then return mod.on_try_monster_interaction(params) end
end)

-- Slow sweep for unattended ambulances.  The only periodic work this mod does.
-- The interval is fixed here rather than read from CONFIG: preload runs before
-- main.lua builds CONFIG, so there is nothing to read yet.  Set
-- AMBULANCE_ENABLED = false in mod storage to switch the sweep off.
gapi.add_on_every_x_hook(TimeDuration.from_turns(300), function()
  if mod.on_every_x_ambulance then return mod.on_every_x_ambulance() end
end)

-- Ambient flavour.  Deliberately a slower beat than the ambulance sweep: this
-- wakes at 600 turns and then rolls a low chance inside the handler, so the vast
-- majority of wake-ups do almost nothing.
gapi.add_on_every_x_hook(TimeDuration.from_turns(600), function()
  if mod.on_every_x_ambient then return mod.on_every_x_ambient() end
end)

-- The magical girl doll.  Registered here rather than in main.lua because the
-- item factory reads game.iuse_functions while finalising item definitions, and
-- that happens before main.lua is ever run - a use_action registered later would
-- not exist by the time the item referencing it loads.
-- Vanilla's DOLLCHAT says exactly one line per press (src/iuse.cpp:5510); she
-- gets two or three, so it plays as an exchange rather than a beep.
local DOLL_LINES = {
  "\"In the name of the tides, I will punish you!\"",
  "\"Mariner Moon, transform!\"",
  "\"I am not just a schoolgirl.  I am the guardian of the seventh sea!\"",
  "\"Everyone is counting on us.  Especially me.  I am counting on us a great deal.\"",
  "\"You cannot hide from the moonlight!\"",
  "\"That is my friend you are talking about!\"",
  "\"Even when it is dark, the tide still comes in.\"",
  "\"I did the homework.  I did MOST of the homework.\"",
  "\"Together, we are the storm!\"",
  "\"Do not cry.  Or do, and then let us go and win anyway.\"",
}

-- Body pillows.  The cooldown lives in mod storage rather than on an effect, so
-- it saves with the world and stays invisible - the same turn-stamp pattern the
-- ambient dread hook uses.  It is stored per PLAYER, not per pillow, so owning
-- two does not get you two hugs a day.
local storage = game.mod_storage[game.current_mod]
-- The morale id is resolved lazily inside the handler rather than here: preload
-- runs BEFORE any JSON is read, so building it now would reference a morale type
-- the game has not loaded yet.
local PILLOW_COOLDOWN_TURNS = 24 * 60 * 60  -- one turn is one second

game.iuse_functions["CV_PILLOW_HUG"] = function(params)
  local who = params.user
  if not who then return 0 end

  local now = gapi.current_turn():to_turn()
  local last = storage.pillow_last_turn
  if last and now - last < PILLOW_COOLDOWN_TURNS then
    gapi.add_msg(MsgType.info,
      "You have already taken what comfort there is in it today.")
    return 0
  end

  storage.pillow_last_turn = now
  who:add_morale(MoraleTypeDataId.new("morale_feeling_good"), 10, 18,
    TimeDuration.from_hours(4), TimeDuration.from_hours(2), false)
  gapi.add_msg(MsgType.good,
    "You embrace the body pillow.  You feel slightly less alone.")
  -- Return 0: a GENERIC item has no charges, and returning 1 would ask the game
  -- to consume one, which on a chargeless item destroys it.
  return 0
end

game.iuse_functions["CV_DOLL_CHAT"] = function(params)
  local who = params.user
  if not who then return 0 end
  -- Exactly one line per press, chosen at random - the same cadence as vanilla's
  -- DOLLCHAT.  An earlier version said two or three at once, which read as the
  -- doll emptying its whole repertoire in one go rather than answering you.
  gapi.add_msg(MsgType.neutral, "The doll says, tinnily: " ..
    DOLL_LINES[gapi.rng(1, #DOLL_LINES)])
  -- One battery charge per press, matching vanilla talking_doll.
  return 1
end

gdebug.log_info("Civilian Variety: preload complete, hooks registered.")
