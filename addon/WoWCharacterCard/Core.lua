-- Recording logic. Nothing in this file calls the game, so it runs the same
-- under plain Lua in the tests as it does in any game version.
local _, ns = ...
local Core = {}
ns.Core = Core

Core.SCHEMA = 1
-- A login this soon after the last update is treated as a reload when the game
-- does not say which it was.
Core.RELOAD_GAP = 300

function Core.InitDB(db)
  if type(db) ~= "table" then db = {} end
  if type(db.characters) ~= "table" then db.characters = {} end
  db.schema = Core.SCHEMA
  if type(db.data) ~= "string" then db.data = "" end
  return db
end

function Core.Key(name, realm)
  if not name or name == "" then return nil end
  return name .. "-" .. (realm or "")
end

local function copy(snapshot)
  local record = {}
  for k, v in pairs(snapshot) do record[k] = v end
  return record
end

local function newSession(snapshot, now)
  return {
    startedAt = now,
    startLevel = snapshot.level,
    xpGained = 0,
    moneyDelta = 0,
  }
end

-- XP earned between two snapshots, counting the rest of the old level when a
-- level-up happened in between.
function Core.XpDelta(prev, snapshot)
  if not prev or not prev.level or not snapshot.level then return 0 end
  if snapshot.level == prev.level then
    if not prev.xp or not snapshot.xp then return 0 end
    return math.max(0, snapshot.xp - prev.xp)
  end
  if snapshot.level > prev.level then
    local rest = 0
    if prev.xp and prev.xpMax then rest = math.max(0, prev.xpMax - prev.xp) end
    return rest + (snapshot.xp or 0)
  end
  return 0
end

-- A record that is not a table was damaged by hand; treat it as absent.
local function previous(db, key)
  local prev = db.characters[key]
  if type(prev) ~= "table" then return nil end
  return prev
end

function Core.BeginSession(db, key, snapshot, now, isReload)
  local prev = previous(db, key)
  local continuing = false
  if prev and type(prev.session) == "table" then
    if isReload == nil then
      continuing = (now - (prev.updatedAt or 0)) < Core.RELOAD_GAP
    else
      continuing = isReload == true
    end
  end

  local record = copy(snapshot)
  if continuing then
    record.session = prev.session
    record.session.xpGained = (record.session.xpGained or 0) + Core.XpDelta(prev, snapshot)
    if prev.money and snapshot.money then
      record.session.moneyDelta = (record.session.moneyDelta or 0) + (snapshot.money - prev.money)
    end
  else
    record.session = newSession(snapshot, now)
  end
  record.updatedAt = now
  db.characters[key] = record
  return record
end

function Core.Update(db, key, snapshot, now)
  local prev = previous(db, key)
  if not prev or type(prev.session) ~= "table" then
    return Core.BeginSession(db, key, snapshot, now, false)
  end

  -- A level cannot change its XP ceiling. When it seems to, the game is half
  -- way through a level-up: new XP figures, old level. Wait for the rest.
  if snapshot.level == prev.level and snapshot.xpMax and prev.xpMax
    and snapshot.xpMax ~= prev.xpMax then
    return prev
  end

  local record = copy(snapshot)
  record.session = prev.session
  record.session.xpGained = (record.session.xpGained or 0) + Core.XpDelta(prev, snapshot)
  if prev.money and snapshot.money then
    record.session.moneyDelta = (record.session.moneyDelta or 0) + (snapshot.money - prev.money)
  end
  record.updatedAt = now
  db.characters[key] = record
  return record
end

function Core.Serialize(db, addonVersion)
  local json = ns.Json.Encode({
    schema = Core.SCHEMA,
    addonVersion = addonVersion or "",
    characters = db.characters,
  })
  db.data = ns.Base64.Encode(json)
  return db.data
end
