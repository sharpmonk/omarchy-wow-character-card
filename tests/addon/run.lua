-- Runs the addon's pure logic under plain Lua 5.1, the version the game uses.
--   lua5.1 tests/addon/run.lua
local ns = {}
local root = "addon/WoWCharacterCard/"
for _, file in ipairs({ "Json.lua", "Base64.lua", "Core.lua" }) do
  assert(loadfile(root .. file))("WoWCharacterCard", ns)
end
local Json, Base64, Core = ns.Json, ns.Base64, ns.Core

local passed, failed = 0, 0

local function eq(name, got, want)
  if got == want then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL " .. name .. "\n  want: " .. tostring(want) .. "\n  got:  " .. tostring(got))
  end
end

-- Json ------------------------------------------------------------------
eq("json string", Json.Encode("abc"), '"abc"')
eq("json quote and backslash", Json.Encode('a"b\\c'), '"a\\"b\\\\c"')
eq("json newline", Json.Encode("a\nb"), '"a\\nb"')
eq("json control char", Json.Encode("a\1b"), '"a\\u0001b"')
eq("json utf8 passes through", Json.Encode("Thrâll"), '"Thrâll"')
eq("json apostrophe", Json.Encode("Pozzo dell'Eternità"), '"Pozzo dell\'Eternità"')
eq("json integer", Json.Encode(42), "42")
eq("json negative", Json.Encode(-7), "-7")
eq("json gold cap has no exponent", Json.Encode(99999999999), "99999999999")
eq("json fraction", Json.Encode(1.5), "1.5")
eq("json nan", Json.Encode(0 / 0), "null")
eq("json boolean", Json.Encode(true), "true")
eq("json empty table is object", Json.Encode({}), "{}")
eq("json array", Json.Encode({ 1, 2, 3 }), "[1,2,3]")
eq("json object keys sorted", Json.Encode({ b = 1, a = 2 }), '{"a":2,"b":1}')
eq("json nested", Json.Encode({ a = { b = "c" } }), '{"a":{"b":"c"}}')

-- Base64 ----------------------------------------------------------------
eq("base64 empty", Base64.Encode(""), "")
eq("base64 one byte", Base64.Encode("f"), "Zg==")
eq("base64 two bytes", Base64.Encode("fo"), "Zm8=")
eq("base64 three bytes", Base64.Encode("foo"), "Zm9v")
eq("base64 longer", Base64.Encode("foobar"), "Zm9vYmFy")
eq("base64 high bytes", Base64.Encode("\255\254\253"), "//79")

-- Core: keys and db -----------------------------------------------------
eq("key", Core.Key("Sharpmonk", "PvE 2"), "Sharpmonk-PvE 2")
eq("key without name", Core.Key(nil, "PvE 2"), nil)
eq("initdb from nil", Core.InitDB(nil).schema, 1)
eq("initdb repairs characters", type(Core.InitDB({ characters = "bad" }).characters), "table")

-- Core: xp delta --------------------------------------------------------
eq("xp same level", Core.XpDelta({ level = 5, xp = 100, xpMax = 1000 }, { level = 5, xp = 250 }), 150)
eq("xp across level-up",
  Core.XpDelta({ level = 41, xp = 900, xpMax = 1000 }, { level = 42, xp = 200 }), 300)
eq("xp never negative", Core.XpDelta({ level = 5, xp = 300, xpMax = 1000 }, { level = 5, xp = 100 }), 0)
eq("xp reaching max level",
  Core.XpDelta({ level = 69, xp = 900, xpMax = 1000 }, { level = 70 }), 100)
eq("xp with no previous record", Core.XpDelta(nil, { level = 5, xp = 100 }), 0)

-- Core: sessions --------------------------------------------------------
local db = Core.InitDB(nil)
local key = "Sharpmonk-PvE 2"
local r = Core.BeginSession(db, key, { level = 41, xp = 900, xpMax = 1000, money = 5000 }, 1000, false)
eq("fresh login starts session", r.session.startedAt, 1000)
eq("fresh login records start level", r.session.startLevel, 41)

r = Core.Update(db, key, { level = 42, xp = 200, xpMax = 1200, money = 4000 }, 1100)
eq("update counts xp across level-up", r.session.xpGained, 300)
eq("update counts money spent", r.session.moneyDelta, -1000)
eq("update keeps session start", r.session.startedAt, 1000)
eq("update stamps time", r.updatedAt, 1100)

r = Core.BeginSession(db, key, { level = 42, xp = 250, xpMax = 1200, money = 4500 }, 1200, true)
eq("reload continues session", r.session.startedAt, 1000)
eq("reload keeps counting xp", r.session.xpGained, 350)
eq("reload keeps counting money", r.session.moneyDelta, -500)

r = Core.BeginSession(db, key, { level = 42, xp = 250, xpMax = 1200, money = 4500 }, 9000, false)
eq("login starts new session", r.session.startedAt, 9000)
eq("new session resets xp", r.session.xpGained, 0)
eq("new session resets money", r.session.moneyDelta, 0)

r = Core.BeginSession(db, key, { level = 42, xp = 300, xpMax = 1200, money = 4500 }, 9100, nil)
eq("unknown login within gap continues", r.session.startedAt, 9000)
r = Core.BeginSession(db, key, { level = 42, xp = 300, xpMax = 1200, money = 4500 }, 9100 + 301, nil)
eq("unknown login after gap starts new", r.session.startedAt, 9401)

-- A character that reaches max level stops reporting xp; the old values must
-- not linger in the record.
r = Core.Update(db, key, { level = 70, atMaxLevel = true, money = 4500 }, 9500)
eq("max level drops xp", r.xp, nil)
eq("max level drops xpMax", r.xpMax, nil)

-- Update before any login still produces a record.
local db2 = Core.InitDB(nil)
r = Core.Update(db2, "Alt-Realm", { level = 3, xp = 10, xpMax = 100, money = 1 }, 50)
eq("update without login starts session", r.session.startedAt, 50)

-- Core: serialize -------------------------------------------------------
local db3 = Core.InitDB(nil)
Core.BeginSession(db3, "Thrâll-Pozzo dell'Eternità", { name = "Thrâll", level = 10, money = 99999999999 }, 100, false)
local data = Core.Serialize(db3, "1.0.0")
eq("serialize stores data", db3.data, data)
eq("serialize is base64 only", data:match("^[A-Za-z0-9+/=]+$") ~= nil, true)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
