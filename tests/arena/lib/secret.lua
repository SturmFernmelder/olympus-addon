-- 1.2.6: a strict stand-in for the values Forever's client keeps secret from addons (UnitHealth,
-- UnitPower, UnitCastingInfo's values, UnitGUID of a restricted unit...). On the client a secret
-- errors on every comparison (with anything, nil included), on arithmetic, concatenation,
-- tostring, length and indexing; it may only be handed to the few widget setters that accept one.
-- A table can't play that part here: LuaJIT never calls a table's __eq against a string, a number
-- or nil, so `secret == guid` would quietly be false. An FFI object's metatype is asked for every
-- comparison, so these raise as the client's do.
--
--   local Secret = assert(loadfile(ROOT .. "tests/arena/lib/secret.lua"))()
--   local v = Secret.New()       -- a new secret value (each one a distinct object)
--   Secret.Is(v)                 -- the test's issecretvalue
--   Secret.Any(t)                -- a secret anywhere in a table (keys and values, deep)?
--
-- Limits (stated where it matters): a truth test (`if v`) and a secret used as a table key cannot
-- be trapped, and type(v) is "cdata" here where the client says "number" or "string".
local cached = package.loaded["olympus-test-secret"]
if cached then return cached end

local ffi = require("ffi")
ffi.cdef("typedef struct { int olympus_secret; } olympus_secret_t;")
local function Boom() error("a secret value was used (compared, computed, joined or indexed)", 2) end
local T = ffi.metatype("olympus_secret_t", {
	__eq = Boom, __lt = Boom, __le = Boom, __concat = Boom, __tostring = Boom, __len = Boom, __unm = Boom,
	__add = Boom, __sub = Boom, __mul = Boom, __div = Boom, __mod = Boom, __pow = Boom,
	__index = Boom, __newindex = Boom, __call = Boom,
})

local M = {}
function M.New() return T() end
function M.Is(v) return type(v) == "cdata" and ffi.istype(T, v) end
function M.Any(t, seen)
	if M.Is(t) then return true end
	if type(t) ~= "table" then return false end
	seen = seen or {}
	if seen[t] then return false end
	seen[t] = true
	for k, v in pairs(t) do
		if M.Any(k, seen) or M.Any(v, seen) then return true end
	end
	return false
end
package.loaded["olympus-test-secret"] = M
return M
