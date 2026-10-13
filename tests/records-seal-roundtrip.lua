local root, public, signed = arg[1], arg[2], arg[3]
local f = assert(io.open(public)) local key = f:read("*a") f:close()
f = assert(io.open(signed)) local seal = f:read("*a"):match("^%s*(.-)%s*$") f:close()
local ns = {}
assert(loadfile(root .. "/Olympus/Sign.lua"))("Olympus", ns)
local text, sig = seal:match("^(.-)~(%x+)$")
local n, mu, k = key:match("N = (%x+)") , key:match("MU = (%x+)"), tonumber(key:match("K = (%d+)"))
ns.Sign.WithKey(n, mu, k, function()
  assert(ns.Sign.Verify(text, sig), "the actual monthly seal signature")
  assert(not ns.Sign.Verify(text:gsub("Alliance", "Horde"), sig), "a seal cannot move factions")
  assert(not ns.Sign.Verify(text:gsub("~b~", "~d~"), sig), "a seal cannot move record types")
  -- The real Records functions, with the minimal non-UI clock/transport needed to load them.
  local handlers = {}
  ns.L, ns.rdb, ns.realm, ns.group, ns.faction = {}, {}, "Emberfall", "Emberfall+Emberfall2", "Alliance"
  ns.FullName = function(name) return name end
  ns.Arena = { Now = function() return 1790000000 end, Sim = function() return false end,
    Slash = function() end, Handle = function(_, fn) return fn end, Send = function() return true end,
    After = function() end, B36 = function(v) return tostring(v) end,
    N = function(v) return tonumber(v) end, Fields = function(body)
      local out = {} for field in (body .. "~"):gmatch("([^~]*)~") do out[#out + 1] = field end return unpack(out)
    end }
  ns.Comm = { Handle = function(kind, fn) handlers[kind] = fn end }
  ns.On, ns.Every, ns.Fire = function() end, function() return {} end, function() end
  ns.SafeCall = function(_, fn, ...) return fn(...) end
  StaticPopupDialogs, date = {}, os.date
  assert(loadfile(root .. "/Olympus/Records.lua"))("Olympus", ns)
  local R = ns.Records
  R.Register("b", { Read = function() end, Totals = function() return {} end })
  local store = R.Store("b", true)
  local day = math.floor(R.MonthStart(24318) / 86400) + 1
  store.days[day] = { original = "kept record" }
  assert(R.TakeSeal(seal, "Anyone-Emberfall", "relay"))
  assert(store.days[day], "a valid seal without matching totals cannot compact records")
  assert(R.Sealed("b", 24318) == nil)
  handlers.RT("CHANNEL", "Anyone-Emberfall", "L", "b~24318~" .. text:match("(%x+)$"):sub(1, 8) .. "~1~1~Test Person-Emberfall,1,1,0")
  assert(store.days[day] == nil, "only adopted authenticated totals permit old record compaction")
  assert(R.Sealed("b", 24318)[1].won == 1, "monthly totals remain after compaction")
end)
print("Records monthly seal: real RSA round trip and scope tampering passed")
