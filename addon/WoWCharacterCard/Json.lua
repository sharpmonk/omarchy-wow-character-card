-- Minimal JSON writer. The desktop plugin reads this addon's data as JSON, and
-- not every game version ships an encoder, so the addon carries its own.
local _, ns = ...
local Json = {}
ns.Json = Json

local escapes = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function escapeChar(c)
  return escapes[c] or string.format("\\u%04x", string.byte(c))
end

local function encodeString(s)
  return '"' .. (s:gsub('[%c"\\]', escapeChar)) .. '"'
end

local function encodeNumber(n)
  if n ~= n or n == math.huge or n == -math.huge then return "null" end
  -- %.0f keeps large copper totals out of exponent notation.
  if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%.0f", n) end
  return string.format("%.14g", n)
end

local function isArray(t)
  local n = #t
  if n == 0 then return false end
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count == n
end

local encode

local function encodeTable(t)
  local parts = {}
  if isArray(t) then
    for i = 1, #t do parts[i] = encode(t[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(t) do
    if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = tostring(k) end
  end
  -- Sorted so the same data always produces the same text.
  table.sort(keys)
  for i = 1, #keys do
    local k = keys[i]
    local v = t[k]
    if v == nil then v = t[tonumber(k)] end
    parts[i] = encodeString(k) .. ":" .. encode(v)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

encode = function(v)
  local kind = type(v)
  if kind == "string" then return encodeString(v) end
  if kind == "number" then return encodeNumber(v) end
  if kind == "boolean" then return v and "true" or "false" end
  if kind == "table" then return encodeTable(v) end
  return "null"
end

Json.Encode = encode
