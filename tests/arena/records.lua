-- Original signed KN halves exercise Records and its actual Bones adapter. No private source key.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = H.World.NAMES
local function Do(w, c, f, ...) return w:As(c, c.ns.Records[f], ...) end
local function Setup()
	local w = FW.New({ compliance = "shipped" })
	return w, w:Player(N.fighterA), w:Player(N.fighterB), w:Player(N.bettor3)
end
local function Pair(w, a, b, id, winner, t)
	local out = {}
	for seat, c in ipairs({ a, b }) do
		out[seat] = w:As(c, function()
			local B = c.ns.Arena.B36
			local time = t or w.clock
			local core = ("%s~%s~%s~-~2~-~e~%s~%s~%s~t~%s~0a1b2c3d~%s~%s~%d"):format(id, a.name, b.name, winner or "1", B(2000), B(300), B(40), B(time), B(time - 300), seat)
			local D = c.ns.Debts local _, pk = D.MyKey()
			return core .. "~" .. D.B64(pk) .. "~" .. D.B64(D.Sign("OLYB1|" .. core))
		end)
	end
	return out[1] .. "^" .. out[2]
end
local function Keys(w, a, b)
	for _, c in ipairs({ a, b }) do assert(Do(w, c, "SendKey")) end
	w:Run(3)
end
local function Take(w, c, body) Do(w, c, "Take", "b", body, N.bettor1, "relay") w:Run(3) end
local function Errors(w)
	for _, c in ipairs(w.clients) do for _, err in ipairs(c.errors) do error(c.name .. ": " .. err) end end
end

test("1.2.4 records: both original signatures and firsthand keys admit one Bones result; repeated bodies never count twice", function()
	local w, a, b, c = Setup() local body = Pair(w, a, b, "Kr1") Keys(w, a, b)
	Take(w, c, body) eq(Do(w, c, "Count", "b"), 1)
	local rows = w:As(c, c.ns.FarkleTable.Best, "L") eq(#rows, 2) eq(rows[1].won, 1)
	Take(w, c, body) eq(Do(w, c, "Count", "b"), 1) eq(#Do(w, c, "Clashes", "b"), 0)
	Errors(w)
end)

test("1.2.4 records history: bounded digests rotate every old unsealed day without dropping the newest days or advancing on a refused send", function()
	local w, a, b, c = Setup()
	local R = c.ns.Records
	local total, days = R.DIGEST_DAYS + 10, {}
	local store = Do(w, c, "Store", "b", true)
	for i = 0, total - 1 do
		local at = w.clock - i * 86400
		local body = Pair(w, a, b, "Krpage" .. i, "1", at)
		local rec = w:As(c, R.TYPES.b.Read, body)
		assert(rec, "valid original result fixture")
		local day = math.floor(at / 86400)
		store.days[day] = { [rec.id] = body }
		days[#days + 1] = day
	end
	local seen = {}
	local send = c.ns.Arena.Send
	c.ns.Arena.Send = function() return false end
	local first = Do(w, c, "DigestBody", "b")
	eq(Do(w, c, "SendDigest", "b"), false)
	eq(Do(w, c, "DigestBody", "b"), first, "full queue keeps the same historical page")
	c.ns.Arena.Send = function(kind, mode, body)
		eq(kind, "RD"); eq(mode, "L")
		local list = body:match("^b~([^~]*)~")
		local page, count = {}, 0
		for day in list:gmatch("([0-9a-z]+)%.[0-9a-z]+%.[0-9a-z]+") do
			day = c.ns.Arena.N(day, 0, 400000)
			page[day], seen[day] = true, true
			count = count + 1
		end
		assert(count <= R.DIGEST_DAYS, "wire stays bounded")
		for i = 1, 3 do assert(page[days[i]], "newest day remains visible") end
		return true
	end
	for _ = 1, 3 do assert(Do(w, c, "SendDigest", "b")) end
	c.ns.Arena.Send = send
	for _, day in ipairs(days) do assert(seen[day], "old unsealed day reachable by a later login: " .. day) end
	Errors(w)
end)

test("1.2.4 records rotation review: equal inventories on different full pages never schedule false pushes", function()
	for _, kind in ipairs({ "days", "months" }) do
		local w, a, b, c = Setup()
		local mine, peer = Do(w, c, "Store", "b", true), Do(w, b, "Store", "b", true)
		local R = c.ns.Records
		if kind == "days" then
			for i = 0, R.DIGEST_DAYS + 9 do
				local at = w.clock - i * 86400
				local body = Pair(w, a, b, "Kreview" .. i, "1", at)
				local rec = w:As(c, R.TYPES.b.Read, body)
				local day = math.floor(at / 86400)
				mine.days[day], peer.days[day] = { [rec.id] = body }, { [rec.id] = body }
			end
		else
			local latest = Do(w, c, "MonthOf", w.clock) - 1
			for i = 0, R.DIGEST_MONTHS + 4 do
				-- Already-adopted fixtures: real RSA adoption has a separate round trip.
				mine.seals[latest - i], peer.seals[latest - i] = { r = "", h = string.rep("a", 64) }, { r = "", h = string.rep("a", 64) }
			end
		end
		c.ns.Records.random = function() return 0 end
		b.ns.Arena.Send = function() return true end
		assert(Do(w, b, "SendDigest", "b")) -- advance to a noncontiguous historical page
		local page = Do(w, b, "DigestBody", "b")
		local pushes = 0
		c.ns.Arena.Send = function(tag) if tag == "RD" then pushes = pushes + 1 end; return true end
		w:As(c, c.comm.handlers.RD, "CHANNEL", b.name, "RD~L1~" .. page)
		w:Run(12)
		eq(pushes, 0, kind .. " omitted by rotation do not prove a missing record")
		Errors(w)
	end
end)

test("1.2.4 records rotation review: genuinely newer days and sealed months still schedule recovery pushes", function()
	for _, kind in ipairs({ "days", "months" }) do
		local w, a, b, c = Setup()
		local mine, peer = Do(w, c, "Store", "b", true), Do(w, b, "Store", "b", true)
		local R = c.ns.Records
		if kind == "days" then
			for i = 0, R.DIGEST_DAYS do
				local at = w.clock - i * 86400
				local body = Pair(w, a, b, "Knewer" .. i, "1", at)
				local rec = w:As(c, R.TYPES.b.Read, body)
				local day = math.floor(at / 86400)
				mine.days[day] = { [rec.id] = body }
				if i > 0 then peer.days[day] = { [rec.id] = body } end
			end
		else
			local latest = Do(w, c, "MonthOf", w.clock) - 1
			for i = 0, R.DIGEST_MONTHS do
				mine.seals[latest - i] = { r = "", h = string.rep("a", 64) }
				if i > 0 then peer.seals[latest - i] = { r = "", h = string.rep("a", 64) } end
			end
		end
		c.ns.Records.random = function() return 0 end
		local pushes = 0
		c.ns.Arena.Send = function(tag) if tag == "RD" then pushes = pushes + 1 end; return true end
		local page = Do(w, b, "DigestBody", "b")
		w:As(c, c.comm.handlers.RD, "CHANNEL", b.name, "RD~L1~" .. page)
		w:Run(12)
		eq(pushes, 1, "newest " .. kind .. " is not a rotated omission")
		Errors(w)
	end
end)

test("1.2.4 records regression: an unsigned conflicting body cannot invalidate a legitimate record or its ranking", function()
	local w, a, b, c = Setup() local body = Pair(w, a, b, "Kr2") Keys(w, a, b) Take(w, c, body)
	local fake = Pair(w, a, b, "Kr2", "2"):gsub("~[%w%-_]+$", "~" .. string.rep("A", 86))
	Take(w, c, fake)
	eq(#Do(w, c, "Clashes", "b"), 0, "no conflict before signature verification")
	eq(Do(w, c, "Count", "b"), 1) eq(#w:As(c, c.ns.FarkleTable.Best, "L"), 2)
	Errors(w)
end)

test("1.2.4 records history: sealed monthly summaries beyond the newest twenty-four remain discoverable", function()
	local w, _, _, c = Setup()
	local R, store = c.ns.Records, Do(w, c, "Store", "b", true)
	local latest = Do(w, c, "MonthOf", w.clock) - 1
	local total = R.DIGEST_MONTHS + 5
	-- Already-adopted summary fixtures: signature/hash adoption is exercised by the separate
	-- RSA round trip. This test exercises the real bounded relay's discovery inventory.
	for i = 0, total - 1 do store.seals[latest - i] = { r = "", h = string.rep("a", 64) } end
	local original, seen = c.ns.Arena.Send, {}
	c.ns.Arena.Send = function() return false end
	local first = Do(w, c, "DigestBody", "b")
	eq(Do(w, c, "SendDigest", "b"), false)
	eq(Do(w, c, "DigestBody", "b"), first)
	c.ns.Arena.Send = function(_, _, body)
		local list = body:match("^b~[^~]*~([^~]*)$")
		local page, count = {}, 0
		for month in list:gmatch("([0-9a-z]+)%.%x+") do
			month = c.ns.Arena.N(month, 0, 100000)
			page[month], seen[month], count = true, true, count + 1
		end
		assert(count <= R.DIGEST_MONTHS)
		assert(page[latest], "newest completed month is on every page")
		return true
	end
	for _ = 1, 3 do assert(Do(w, c, "SendDigest", "b")) end
	c.ns.Arena.Send = original
	for i = 0, total - 1 do assert(seen[latest - i], "older sealed month remains reachable") end
	Errors(w)
end)

test("1.2.4 records: a signed conflicting result is excluded and retained, and changes the holder digest for relay", function()
	local w, a, b, c = Setup() Keys(w, a, b) Take(w, c, Pair(w, a, b, "Kr3"))
	local before = Do(w, c, "DigestBody", "b")
	Take(w, c, Pair(w, a, b, "Kr3", "2"))
	eq(#Do(w, c, "Clashes", "b"), 1) eq(#w:As(c, c.ns.FarkleTable.Best, "L"), 0)
	assert(Do(w, c, "DigestBody", "b") ~= before, "verified conflict is visible to anti-entropy")
	Errors(w)
end)

test("1.2.4 records: a relay cannot bootstrap identity; pending records survive reload and wait for original players' keys", function()
	local w, a, b, c = Setup() local body = Pair(w, a, b, "Kr4")
	Take(w, c, body) eq(Do(w, c, "Count", "b"), 0) eq(Do(w, c, "Pending", "b"), 1)
	w:Logout(c) w:Login(c) w:Run(15)
	eq(Do(w, c, "Pending", "b"), 1)
	Keys(w, a, b) eq(Do(w, c, "Count", "b"), 1) eq(Do(w, c, "Pending", "b"), 0)
	Errors(w)
end)

test("1.2.4 records review: one relayer cannot evict every other player's pending records", function()
	local w, a, b, c = Setup()
	local R = c.ns.Records
	for i = 1, R.PENDING_EACH do
		local _, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krpend" .. i), N.bettor1, "relay")
		eq(why, "pending")
	end
	local _, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krpendover"), N.bettor1, "relay")
	eq(why, "pending-sender", "the sender is capped before it can consume the global store")
	_, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krpendpeer"), N.bettor2, "relay")
	eq(why, "pending", "another relayer still has room")
	eq(Do(w, c, "Pending", "b"), R.PENDING_EACH + 1)
	Errors(w)
end)

test("1.2.4 records review: one relayer cannot monopolize the signature wait queue", function()
	local w, a, b, c = Setup() Keys(w, a, b)
	local R, original = c.ns.Records, c.ns.Arena.Check
	R.TYPES.b.DAY_MAX = 1000
	c.ns.Arena.Check = function() end -- keep the real Records inflight slots occupied
	for i = 1, R.CHECKS_EACH do
		local ok, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krcheck" .. i), N.bettor1, "relay")
		eq(ok, true); eq(why, "checking")
	end
	for i = 1, R.WAIT_EACH do
		local _, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krwait" .. i), N.bettor1, "relay")
		eq(why, "waiting")
	end
	local _, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krwaitover"), N.bettor1, "relay")
	eq(why, "busy-sender")
	local ok
	ok, why = Do(w, c, "Take", "b", Pair(w, a, b, "Krwaitpeer"), N.bettor2, "relay")
	eq(ok, true); eq(why, "checking", "another relayer retains an active verifier slot")
	c.ns.Arena.Check = original
	Errors(w)
end)

test("1.2.4 records: asynchronous callbacks recheck per-player capacity before storing results", function()
	local w, a, b, c = Setup() Keys(w, a, b)
	c.ns.Records.TYPES.b.DAY_MAX = 1
	local checks, original = {}, c.ns.Arena.Check
	c.ns.Arena.Check = function(key, claim, cb) checks[#checks + 1] = { key, claim, cb } end
	Do(w, c, "Take", "b", Pair(w, a, b, "Kr5"), N.bettor1, "relay")
	Do(w, c, "Take", "b", Pair(w, a, b, "Kr6"), N.bettor1, "relay")
	c.ns.Arena.Check = original
	for _, check in ipairs(checks) do w:As(c, original, unpack(check)) end
	w:Run(3) eq(Do(w, c, "Count", "b"), 1, "two inflight records cannot consume the same final slot")
	Errors(w)
end)

test("1.2.4 records: an unsealed month is never silently erased, even after the legacy Bones store prunes it", function()
	local w, a, b, c = Setup() local body = Pair(w, a, b, "Kr7") Keys(w, a, b) Take(w, c, body)
	local month = Do(w, c, "MonthOf", w.clock)
	w:Logout(a) w:Logout(b) w:Run(80 * 86400)
	w:As(c, c.ns.FarkleTable.Prune)
	eq(Do(w, c, "Count", "b"), 1)
	eq(#w:As(c, c.ns.FarkleTable.Best, "L", { month = month }), 2, "ranking reconstructs its signed records")
	w:Logout(c) w:Login(c) w:Run(15) eq(Do(w, c, "Count", "b"), 1)
	Errors(w)
end)

test("1.2.4 records: bounded verifier retries do not spin when the shared verification queue is full", function()
	local w, a, b, c = Setup() Keys(w, a, b)
	local original, calls = c.ns.Arena.Check, 0
	c.ns.Arena.Check = function(key, claim, cb) calls = calls + 1 cb(nil) end
	Do(w, c, "Take", "b", Pair(w, a, b, "Kr8"), N.bettor1, "relay")
	eq(calls, 2) w:Run(5) eq(calls, 2)
	c.ns.Arena.Check = original w:Run(35) eq(Do(w, c, "Count", "b"), 1)
	Errors(w)
end)

test("1.2.4 records: Alliance and Horde stores are separate in the same realm saved data; malformed totals are refused", function()
	local w, a, b, c = Setup() Keys(w, a, b) Take(w, c, Pair(w, a, b, "Kr9"))
	local faction = c.ns.faction c.ns.faction = "Horde"
	eq(Do(w, c, "Count", "b"), 0) c.ns.faction = faction eq(Do(w, c, "Count", "b"), 1)
	local sent = w:As(a, a.ns.Arena.Send, "RT", "L", "b~1~12345678~1~1", {})
	assert(sent) w:Run(1) Errors(w)
end)

test("1.2.4 records: any ordinary holder relays a Bones result to a late member; identity still comes from its players", function()
	local w, a, b, c = Setup() Keys(w, a, b) Take(w, c, Pair(w, a, b, "Kr10"))
	local late = w:Player(N.bettor1)
	Keys(w, a, b)
	w:Run(c.ns.Records.ANSWER_GAP + 1) -- an original result just heard suppresses redundant immediate answers
	c.ns.Records.random, late.ns.Records.random = function() return 0 end, function() return 0 end
	assert(Do(w, c, "SendDigest", "b")) w:Run(20)
	eq(Do(w, late, "Count", "b"), 1, "neither original player sent the result to this late client")
	eq(#w:As(late, late.ns.FarkleTable.Best, "L"), 2)
	Errors(w)
end)

test("1.2.4 records: the duel adapter preserves GUID identity checks and adds a verified relayed result to ordinary rankings", function()
	local w, a, b, c = Setup()
	for _, client in ipairs(w.clients) do
		client.globals.GetPlayerInfoByGUID = function(guid)
			for _, named in ipairs(w.clients) do if named.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, named.short, named.realm end end
		end
	end
	local halves = {}
	for side, client in ipairs({ a, b }) do
		halves[side] = w:As(client, function()
			local A, D = client.ns.Arena, client.ns.Debts
			local core = table.concat({ "Fr11", side == 1 and "A" or "B", A.GK(a.guid), a.name, A.GK(b.guid), b.name, "1", "A", "A", "K", "AK" .. A.B36(20), A.B36(w.clock), "-", "60", "60" }, "~")
			local _, pk = D.MyKey() return core .. "~" .. D.B64(pk) .. "~" .. D.B64(D.Sign("OLYH1|" .. core))
		end)
	end
	Keys(w, a, b)
	Do(w, c, "Take", "d", halves[1] .. "^" .. halves[2], N.bettor1, "relay") w:Run(3)
	eq(Do(w, c, "Count", "d"), 1)
	local entries = w:As(c, c.ns.ArenaLedger.Entries) eq(#entries, 1) eq(entries[1].fl, "dr")
	eq(#w:As(c, c.ns.ArenaLedger.RecordMonth, Do(w, c, "MonthOf", w.clock)), 2)
	w:Logout(c) w:Login(c) w:Run(15) eq(Do(w, c, "Count", "d"), 1)
	Errors(w)
end)
