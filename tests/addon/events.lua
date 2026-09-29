-- Drives Events.lua with stand-in game functions, under plain Lua 5.1.
--   lua5.1 tests/addon/events.lua
local passed, failed = 0, 0

local function eq(name, got, want)
  if got == want then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL " .. name .. "\n  want: " .. tostring(want) .. "\n  got:  " .. tostring(got))
  end
end

local gameGlobals = {
  "CreateFrame", "UnitName", "GetRealmName", "UnitClass", "UnitRace", "UnitFactionGroup",
  "GetBuildInfo", "WOW_PROJECT_ID", "UnitLevel", "GetMaxLevelForPlayerExpansion",
  "GetMaxPlayerLevel", "MAX_PLAYER_LEVEL", "IsXPUserDisabled", "UnitXP", "UnitXPMax",
  "GetXPExhaustion", "GetMoney", "C_Container", "GetContainerNumSlots",
  "GetContainerNumFreeSlots", "NUM_BAG_SLOTS", "C_Timer", "time", "WoWCharacterCardDB",
}

-- Loads the addon into a fresh fake game and returns a handle for firing
-- events. `game` holds the values the fake game reports; change them between
-- events to play out a session.
local function boot(game, saved)
  for _, name in ipairs(gameGlobals) do _G[name] = nil end
  local world = { registered = {}, refused = {}, timers = {} }

  function CreateFrame()
    local frame = {}
    function frame:SetScript(_, fn) world.onEvent = fn end
    function frame:RegisterEvent(event)
      if game.unknownEvents and game.unknownEvents[event] then
        world.refused[event] = true
        error("unknown event " .. event)
      end
      world.registered[event] = true
    end
    return frame
  end

  time = function() return game.now end
  UnitName = function() return game.name end
  GetRealmName = function() return game.realm end
  UnitClass = function() return game.class, game.classFile end
  UnitRace = function() return game.race end
  UnitFactionGroup = function() return game.faction end
  UnitLevel = function() return game.level end
  UnitXP = function() return game.xp end
  UnitXPMax = function() return game.xpMax end
  GetMoney = function() return game.money end
  if game.modern then
    GetBuildInfo = function() return "12.1.0", "69933", "Jan 1 2026", 120100 end
    GetMaxLevelForPlayerExpansion = function() return game.cap end
    GetXPExhaustion = function() return game.rested end
    IsXPUserDisabled = function() return false end
    WOW_PROJECT_ID = 1
    NUM_BAG_SLOTS = 4
    C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 16 or 20 end,
      GetContainerNumFreeSlots = function(bag) return bag == 0 and 5 or 0 end,
    }
    C_Timer = { After = function(_, fn) world.timers[#world.timers + 1] = fn end }
  end

  WoWCharacterCardDB = saved

  local ns = {}
  local root = "addon/WoWCharacterCard/"
  for _, file in ipairs({ "Json.lua", "Base64.lua", "Core.lua", "Events.lua" }) do
    assert(loadfile(root .. file))("WoWCharacterCard", ns)
  end

  function world.fire(event, ...) world.onEvent(nil, event, ...) end
  function world.runTimers()
    local timers = world.timers
    world.timers = {}
    for _, fn in ipairs(timers) do fn() end
  end
  function world.character() return WoWCharacterCardDB.characters[game.name .. "-" .. game.realm] end
  return world
end

local function modernGame()
  return {
    modern = true, now = 1000, name = "Sharpmonk", realm = "PvE 2",
    class = "Monk", classFile = "MONK", race = "Pandaren", faction = "Alliance",
    level = 41, cap = 70, xp = 900, xpMax = 1000, rested = 180, money = 5000,
  }
end

-- Login on a current game version ------------------------------------------
do
  local game = modernGame()
  local world = boot(game, nil)
  eq("registers login event", world.registered.PLAYER_ENTERING_WORLD, true)
  eq("registers logout event", world.registered.PLAYER_LOGOUT, true)

  world.fire("ADDON_LOADED", "SomeOtherAddon")
  eq("ignores other addons loading", WoWCharacterCardDB, nil)

  world.fire("ADDON_LOADED", "WoWCharacterCard")
  world.fire("PLAYER_ENTERING_WORLD", true, false)
  local c = world.character()
  eq("name", c.name, "Sharpmonk")
  eq("realm", c.realm, "PvE 2")
  eq("class", c.class, "Monk")
  eq("class file", c.classFile, "MONK")
  eq("race", c.race, "Pandaren")
  eq("faction", c.faction, "Alliance")
  eq("build", c.build, "12.1.0")
  eq("interface", c.interface, 120100)
  eq("level", c.level, 41)
  eq("xp", c.xp, 900)
  eq("xp max", c.xpMax, 1000)
  eq("rested", c.rested, 180)
  eq("not at max level", c.atMaxLevel, false)
  eq("money", c.money, 5000)
  eq("bags total", c.bagsTotal, 96)
  eq("bags used", c.bagsUsed, 91)
  eq("session started", c.session.startedAt, 1000)
  eq("data written", WoWCharacterCardDB.data:match("^[A-Za-z0-9+/=]+$") ~= nil, true)

  -- Earning XP and spending gold.
  game.now, game.xp, game.money = 1100, 950, 4000
  world.fire("PLAYER_XP_UPDATE")
  world.fire("PLAYER_MONEY")
  c = world.character()
  eq("xp gained", c.session.xpGained, 50)
  eq("money spent", c.session.moneyDelta, -1000)

  -- Level-up: the event arrives while the game still reports the old level
  -- and the old XP.
  world.fire("PLAYER_LEVEL_UP", 42)
  eq("level-up alone records nothing", world.character().session.xpGained, 50)
  game.now, game.level, game.xp, game.xpMax = 1200, 42, 200, 1200
  world.fire("PLAYER_XP_UPDATE")
  c = world.character()
  eq("level after level-up", c.level, 42)
  eq("xp counted across level-up", c.session.xpGained, 300)
  world.runTimers()
  eq("delayed update adds nothing extra", world.character().session.xpGained, 300)

  -- Changing zone fires the login event again; the session must carry on.
  game.now = 1300
  world.fire("PLAYER_ENTERING_WORLD", false, false)
  eq("zoning keeps session", world.character().session.startedAt, 1000)

  game.now = 1400
  world.fire("PLAYER_LOGOUT")
  eq("logout stamps time", world.character().updatedAt, 1400)
end

-- Reload, then a later fresh login -----------------------------------------
do
  local game = modernGame()
  local world = boot(game, nil)
  world.fire("ADDON_LOADED", "WoWCharacterCard")
  world.fire("PLAYER_ENTERING_WORLD", true, false)
  game.now, game.xp = 1100, 950
  world.fire("PLAYER_XP_UPDATE")
  local saved = WoWCharacterCardDB

  game.now = 1150
  world = boot(game, saved)
  world.fire("ADDON_LOADED", "WoWCharacterCard")
  world.fire("PLAYER_ENTERING_WORLD", false, true)
  eq("reload keeps session start", world.character().session.startedAt, 1000)
  eq("reload keeps xp gained", world.character().session.xpGained, 50)

  saved = WoWCharacterCardDB
  game.now = 90000
  world = boot(game, saved)
  world.fire("ADDON_LOADED", "WoWCharacterCard")
  world.fire("PLAYER_ENTERING_WORLD", true, false)
  eq("fresh login starts new session", world.character().session.startedAt, 90000)
  eq("fresh login resets xp gained", world.character().session.xpGained, 0)
end

-- A second character on the same account is kept alongside the first -------
do
  local game = modernGame()
  local world = boot(game, nil)
  world.fire("ADDON_LOADED", "WoWCharacterCard")
  world.fire("PLAYER_ENTERING_WORLD", true, false)
  local saved = WoWCharacterCardDB

  game.name, game.level, game.now = "Bankalt", 5, 2000
  world = boot(game, saved)
  world.fire("ADDON_LOADED", "WoWCharacterCard")
  world.fire("PLAYER_ENTERING_WORLD", true, false)
  eq("new character recorded", world.character().level, 5)
  eq("first character kept", WoWCharacterCardDB.characters["Sharpmonk-PvE 2"].level, 41)
end

-- Max level ----------------------------------------------------------------
do
  local game = modernGame()
  game.level, game.cap = 70, 70
  local world = boot(game, nil)
  world.fire("ADDON_LOADED", "WoWCharacterCard")
  world.fire("PLAYER_ENTERING_WORLD", true, false)
  local c = world.character()
  eq("at max level", c.atMaxLevel, true)
  eq("no xp at max level", c.xp, nil)
  eq("no rested at max level", c.rested, nil)
end

-- An old game version with most newer functions missing --------------------
do
  local game = modernGame()
  game.modern = false
  game.unknownEvents = { BAG_UPDATE_DELAYED = true, UPDATE_EXHAUSTION = true }
  local ok, world = pcall(boot, game, nil)
  eq("loads without the newer functions", ok, true)
  eq("unknown event refused quietly", world.refused.BAG_UPDATE_DELAYED, true)
  world.fire("ADDON_LOADED", "WoWCharacterCard")
  world.fire("PLAYER_ENTERING_WORLD")
  local c = world.character()
  eq("old game: level", c.level, 41)
  eq("old game: xp", c.xp, 900)
  eq("old game: rested defaults to zero", c.rested, 0)
  eq("old game: no bag data", c.bagsTotal, nil)
  eq("old game: no build", c.build, nil)
  eq("old game: session started", c.session.startedAt, 1000)
  world.fire("PLAYER_LEVEL_UP", 42)
  eq("old game: level-up without timers is safe", world.character().level, 41)
end

-- Saved data damaged by hand -----------------------------------------------
do
  local game = modernGame()
  local world = boot(game, { characters = "broken", schema = "x" })
  world.fire("ADDON_LOADED", "WoWCharacterCard")
  world.fire("PLAYER_ENTERING_WORLD", true, false)
  eq("recovers from damaged saved data", world.character().level, 41)
end

-- The game has not told us who the player is yet ---------------------------
do
  local game = modernGame()
  game.name = nil
  local world = boot(game, nil)
  world.fire("ADDON_LOADED", "WoWCharacterCard")
  local ok = pcall(world.fire, "PLAYER_ENTERING_WORLD", true, false)
  eq("no name does not raise", ok, true)
  local count = 0
  for _ in pairs(WoWCharacterCardDB.characters) do count = count + 1 end
  eq("no name records nothing", count, 0)
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
