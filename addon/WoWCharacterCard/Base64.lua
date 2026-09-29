-- Base64 writer. The JSON is stored base64-encoded so the saved file holds no
-- quotes or backslashes for the game to escape, and the desktop side can read
-- it without understanding Lua string rules.
local _, ns = ...
local Base64 = {}
ns.Base64 = Base64

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function char(index)
  return alphabet:sub(index + 1, index + 1)
end

function Base64.Encode(s)
  local out = {}
  local len = #s
  for i = 1, len, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = char(c1) .. char(c2)
      .. (b and char(c3) or "=")
      .. (c and char(c4) or "=")
  end
  return table.concat(out)
end
