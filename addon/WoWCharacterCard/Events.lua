-- Game glue. Reads the character from the game and hands it to Core. Every game
-- function is looked up before use, because the set differs between versions;
-- a value the game cannot give is left out of the record.
local addonName, ns = ...
local Core = ns.Core

local ADDON_VERSION = "1.0.1"

local db
local key
local sessionBegun = false
local pendingLevel = 0

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local results = { pcall(fn, ...) }
  if not results[1] then return nil end
  return unpack(results, 2, 6)
end

local function bagSlots()
  local container = type(C_Container) == "table" and C_Container or nil
  local numSlots = (container and container.GetContainerNumSlots) or GetContainerNumSlots
  local numFree = (container and container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
  if type(numSlots) ~= "function" or type(numFree) ~= "function" then return nil, nil end
  local total, free = 0, 0
  for bag = 0, (tonumber(NUM_BAG_SLOTS) or 4) do
    total = total + (tonumber((call(numSlots, bag))) or 0)
    free = free + (tonumber((call(numFree, bag))) or 0)
  end
  if total == 0 then return nil, nil end
  return total - free, total
end

local function maxLevel()
  return tonumber((call(GetMaxLevelForPlayerExpansion)))
    or tonumber((call(GetMaxPlayerLevel)))
    or tonumber(MAX_PLAYER_LEVEL)
end

local function snapshot()
  local s = {}
  s.name = call(UnitName, "player")
  s.realm = call(GetRealmName)
  s.class, s.classFile = call(UnitClass, "player")
  s.race = call(UnitRace, "player")
  s.faction = call(UnitFactionGroup, "player")

  local build, _, _, interface = call(GetBuildInfo)
  s.build = build
  s.interface = tonumber(interface)
  s.projectId = tonumber(WOW_PROJECT_ID)

  local level = tonumber((call(UnitLevel, "player"))) or 0
  if level > 0 then s.level = level end

  local cap = maxLevel()
  local xpOff = call(IsXPUserDisabled) == true
  s.atMaxLevel = (cap ~= nil and level >= cap) or xpOff
  if not s.atMaxLevel then
    s.xp = tonumber((call(UnitXP, "player")))
    s.xpMax = tonumber((call(UnitXPMax, "player")))
    s.rested = tonumber((call(GetXPExhaustion))) or 0
  end

  s.money = tonumber((call(GetMoney)))
  s.bagsUsed, s.bagsTotal = bagSlots()
  return s
end

-- `final` is the logout record: the last chance to save, so it is never
-- skipped.
local function record(begin, isReload, final)
  if not db then return end
  local s = snapshot()
  -- For a moment after a level-up the game reports the old level, and its XP
  -- figures may belong to either level. Nothing read now can be trusted.
  if not final and pendingLevel > (s.level or 0) then return end
  key = key or Core.Key(s.name, s.realm)
  if not key or not s.level then return end
  local now = tonumber((call(time))) or 0
  if begin then
    Core.BeginSession(db, key, s, now, isReload)
    sessionBegun = true
  else
    Core.Update(db, key, s, now)
  end
  Core.Serialize(db, ADDON_VERSION)
end

-- Events can arrive before the login event. Recording them would stamp the
-- record with the current time and make a new day look like a reload.
local function update()
  if sessionBegun then record(false) end
end

local handlers = {}

function handlers.ADDON_LOADED(name)
  if name ~= addonName then return end
  WoWCharacterCardDB = Core.InitDB(WoWCharacterCardDB)
  db = WoWCharacterCardDB
end

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
  if sessionBegun then
    record(false)
    return
  end
  local isReload
  if isInitialLogin ~= nil or isReloadingUi ~= nil then
    isReload = isReloadingUi == true
  end
  record(true, isReload)
end

function handlers.PLAYER_LEVEL_UP(newLevel)
  -- XP still belongs to the old level here. Remember the level and let the XP
  -- update that follows do the recording.
  pendingLevel = tonumber(newLevel) or pendingLevel
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(1, update)
  end
end

handlers.PLAYER_XP_UPDATE = update
handlers.UPDATE_EXHAUSTION = update
handlers.PLAYER_MONEY = update
handlers.BAG_UPDATE_DELAYED = update

function handlers.PLAYER_LOGOUT()
  if sessionBegun then record(false, nil, true) end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
  local handler = handlers[event]
  if handler then handler(...) end
end)
for event in pairs(handlers) do
  -- An event this game version does not know raises an error when registered.
  pcall(frame.RegisterEvent, frame, event)
end
