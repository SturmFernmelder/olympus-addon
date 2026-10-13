-- 1.2.4 is pre-launch. These exercise the real shipped policy, not the future race fixture.
-- Historical records stay intact; a later launch/date/UI/protocol is deliberately not supplied.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local function Net(w, c) return W3.M(w, c, "HonorsNet") end
local function Claim(c, level, now)
	local A = c.ns.Arena
	return table.concat({ A.GK(c.guid), A.B36(level), A.B36(now) }, "~")
end
local function Record(c, level, now)
	local A = c.ns.Arena
	return table.concat({ A.B36(level), A.GK(c.guid), c.ns.ArenaFights.Wire(c.name), A.B36(now) }, ":")
end
local function NoLevel(held)
	for _, h in ipairs(held) do assert(not h.key:match("^level%-race%-"), "a pre-launch level award: " .. h.key) end
end

test("1.2.4 pre-launch level race: shipped level-ups collect and send nothing, even after the old date and with independent game lives on", function()
	local w, cast = W3.New({ world = { compliance = "shipped", clock = 2000000000 },
		more = { { "young", "Brisa Vale", { level = 19 } } } })
	local c, net = cast.young, Net(w, cast.young)
	eq(w:Events(c, true).PLAYER_LEVEL_UP, nil, "no collection hook before launch")
	eq(c.Roles.Live(), true, "unrelated games remain live")
	w:Fire(c, "PLAYER_LEVEL_UP", 20)
	w:As(c, c.ns.HonorsNet.OnLevelUp, 40) -- a direct/manual caller must not schedule claims either
	w:Run(3700)
	eq(#w:Sent{ from = c, type = "IL" }, 0)
	eq(net.Store(), nil, "a level-up cannot allocate the historical book")
	eq(net.WatchLevels(), false)
	local ok, why = net.SendClaim(20)
	eq(ok, false); eq(why, "level-race-off")
	ok, why = c.Arena.Send("IL", "L", Claim(c, 20, w.clock))
	eq(ok, false); eq(why, "level-race-off", "raw send uses the same boundary")
	for _, t in ipairs(w:Timers(c, true)) do
		assert(not tostring(t.where):find("level", 1, true), "no deferred race timer")
	end
	eq(net.LevelRaceActive(), false)
	W3.NoErrors(w)
end)

test("1.2.4 pre-launch level race: native IL and an authenticated clerk's AB H from an older peer allocate no claims or levels; no clerk records or answers go out", function()
	local w = World.New({ compliance = "shipped", clock = 2000000000 })
	local viewer, peer, clerk = w:Role("bettor1"), w:Role("fighterA"), w:Role("councillor")
	local net = Net(w, viewer)
	eq(w:As(viewer, viewer.ns.IsHighCouncillor, clerk.name), true, "the AB sender really passes the existing authority gate")
	viewer.comm.handlers.IL("CHANNEL", peer.name, "IL~L1~" .. Claim(peer, 20, w.clock))
	eq(net.Store(), nil, "native old-peer claim is not collected")
	viewer.comm.handlers.AB("CHANNEL", clerk.name, "AB~L1~H~" .. Record(peer, 40, w.clock))
	eq(net.Store(), nil, "authenticated historical relay is not collected")
	eq(net.TakeRecords(clerk.name, "L", Record(peer, 60, w.clock)), false, "direct receiver cannot bypass it")
	local s = net.Store(true)
	s.levels[60] = { { guid = peer.guid, name = peer.name, t = w.clock - 100, place = 1 } }
	eq(net.RecordsBody(), nil); eq(net.SendRecords(), false); eq(net.Answer(peer.name), false)
	w:Run(0)
	for _, item in ipairs(w:Sent{ from = viewer, type = "AB" }) do
		assert(not item.msg:find("~H~", 1, true), "no historical level records on the wire")
	end
	eq(s.levels[60][1].name, peer.name, "relay refusal does not erase the historical book")
	W3.NoErrors(w)
end)

test("1.2.4 pre-launch level race: old saved places and claims survive census checks, refresh and reload without awarded titles or letters", function()
	local w = World.New({ compliance = "shipped", clock = 2000000000 })
	local c = w:Client("Brisa Vale", { level = 19 })
	local net = Net(w, c)
	local s = net.Store(true)
	local place = { guid = c.guid, name = c.name, t = w.clock - 2 * 86400, place = 1 }
	local claim = { gk = c.ns.Arena.GK(c.guid), name = c.name, level = 20,
		t = w.clock - 20 * 86400, heardLocal = w.clock - 20 * 86400, vouched = true }
	s.levels[60], s.claims.old, s.vouchRule = { place }, claim, 1
	-- This stale place contradicts the current native player level: even the old security
	-- maintenance must not erase history while collection is dormant.
	eq(#net.Holdings(c.name, c.guid), 0, "old records award no pre-launch title")
	eq(next(net.Inputs().levels), nil)
	eq(net.Known().level, true, "known-disabled, never an unknown relay gap")
	local m = w:As(c, c.ns.ArenaProfile.Mine, true)
	m.frame, m.title = "rank", "level-race-60"
	m.seen = { ["level-60"] = { place = 1, title = "level-race-60" } }
	m.standing = { ["level-60"] = { p = 1 } }
	eq(net.Standing()["level-60"], nil, "historical standing is not an effective launch award")
	eq(m.standing["level-60"].p, 1, "saved notice history remains intact")
	eq(net.Verified(c.name, c.guid).title, nil, "old configured title is not an effective award")
	eq(#net.CheckPlaces(), 0); eq(net.RaceSoon(), false); eq(#net.RunRace(), 0)
	w:As(c, function() c.ns.Fire("DATA_CHANGED"); c.ns.HonorsNet.Refresh() end)
	eq(c.ns.ArenaProfile.Pick().title, nil, "an old derived pick is not remembered as unknown")
	eq(c.ns.ArenaProfile.Pick().seen["level-60"], nil)
	eq(net.Standing()["level-60"], nil, "the disabled race has no live award standing")
	eq(m.standing["level-60"].p, 1, "no false newly-lost place replaces the historical notice")
	w:Fire(c, "PLAYER_LEVEL_UP", 20)
	w:Run(3700)
	eq(s.levels[60][1], place); eq(s.claims.old, claim); eq(s.vouchRule, 1)
	eq(next(s.struck or {}), nil); eq(#net.QueuedLetters(), 0); eq(#net.Letters(), 0)
	eq(#w:Sent{ from = c, type = "IL" }, 0)
	w:Logout(c); w:Login(c)
	net = Net(w, c)
	w:As(c, function() c.ns.Fire("DATA_CHANGED"); c.ns.HonorsNet.Refresh() end)
	w:Run(65)
	local kept = net.Store()
	eq(kept.levels[60][1].name, place.name); eq(kept.levels[60][1].t, place.t)
	eq(kept.claims.old.t, claim.t); eq(kept.claims.old.vouched, true); eq(kept.vouchRule, 1)
	eq(net.Levels(), kept.levels, "raw history remains readable")
	NoLevel(net.Holdings(c.name, c.guid)); eq(net.Verified(c.name, c.guid).title, nil)
	eq(net.LevelRaceActive(), false); eq(w:Events(c, true).PLAYER_LEVEL_UP, nil)
	eq(#net.QueuedLetters(), 0); eq(#net.Letters(), 0)
	W3.NoErrors(w)
end)

test("1.2.4 pre-launch level race: future fixture opt-in is explicit and strict; base and shipped worlds stay off, and cached verification respects the boundary", function()
	local w = World.New()
	local c = w:Client("Brisa Vale", { level = 19 })
	eq(w:Events(c, true).PLAYER_LEVEL_UP, nil, "foundation world does not silently opt in")
	local future = W3.LevelRaceWorld()
	local f = future:Client("Corin Ash", { level = 19 })
	eq(w:Events(c, true).PLAYER_LEVEL_UP, nil)
	eq(future:Events(f, true).PLAYER_LEVEL_UP, true, "future design fixture composes the launch policy")
	local net = Net(future, f)
	local s = net.Store(true)
	s.levels[60] = { { guid = f.guid, name = f.name, t = future.clock, place = 1 } }
	local m = future:As(f, f.ns.ArenaProfile.Mine, true)
	m.frame, m.title = "rank", "level-race-60"
	eq(net.Verified(f.name, f.guid).title, "level-race-60")
	f.ns.HonorsNet.LEVEL_RACE_LAUNCHED = 1 -- truthy is not an explicit launch
	eq(net.LevelRaceActive(), false); eq(next(net.Inputs().levels), nil)
	eq(net.Verified(f.name, f.guid).title, nil, "no cached future award leaks across the boundary")
	future:Fire(f, "PLAYER_LEVEL_UP", 20); future:Run(3700)
	eq(#future:Sent{ from = f, type = "IL" }, 0, "an already hooked future client still checks the boundary")
	eq(s.levels[60][1].name, f.name)
	local shipped = W3.LevelRaceWorld({ compliance = "shipped" })
	local p = shipped:Client("Dovan Quell", { level = 19 })
	eq(shipped:Events(p, true).PLAYER_LEVEL_UP, nil)
	eq(Net(shipped, p).LevelRaceActive(), false, "even the future fixture cannot open a shipped client")
	W3.NoErrors(w); W3.NoErrors(future); W3.NoErrors(shipped)
end)
