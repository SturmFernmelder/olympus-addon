-- 1.2.1 (the security review's High 8): the level race's places were won with one forged census
-- row (any report of anyone else's listing the claimant at that level vouched for him, and after
-- CONFIRM_AFTER the place was his forever). A claim is a verified member's now (HonorsNet.Vouched:
-- our own guild's roster, the server's; another guild's census, two of its senders other than him),
-- and a place the server's word shows false goes (HonorsNet.CheckPlaces). On the test world. Every
-- name is invented.
local H = ...
local test, eq = H.test, H.eq
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local function HN(w, c) return W3.M(w, c, "HonorsNet") end

-- An IL of c's for milestone m, as its client sends it (the claim's level is his word; gk: the
-- GUID it gives, his own by default).
local function Claim(w, c, m, gk)
	w:As(c, function()
		local A = c.ns.Arena
		A.Send("IL", "L", table.concat({ gk or A.GK(c.guid), A.B36(m), A.B36(w.clock) }, "~"), {})
	end)
	w:Run(0)
end
-- The game's GetPlayerInfoByGUID on the viewer: the world's characters by their GUID (a guildmate's
-- resolves, Roster.lua reads his race so; a GUID no character has gives nothing).
local function Info(w, viewer)
	viewer.globals.GetPlayerInfoByGUID = function(guid)
		for _, o in ipairs(w.clients) do
			if o.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, o.short, o.realm end
		end
		return nil
	end
end
-- A census report heard on the viewer, then what the census's arrival does there.
local function Report(w, viewer, guild, reporter, name, level)
	W3.Report(viewer, guild, reporter, { { name = name, level = level, class = "WA" } })
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
end
local function Place(viewer, m)
	local s = viewer.ns.HonorsNet.Store()
	local list = s and s.levels and s.levels[m]
	return list and list[1] and list[1].name or nil
end
-- Our own guild's roster on the viewer, as Roster.lua reads it from the server (fresh: Roster.Fresh).
local function Roster(viewer, rows)
	local R = { members = {}, byName = {}, snapshotAt = viewer.ns.Now() }
	for _, row in ipairs(rows) do
		R.members[#R.members + 1] = { full = row[1].name, level = row[2] }
		R.byName[row[1].name] = 3
	end
	function R.Fresh() return R end
	function R.RankOf(name) return type(name) == "string" and R.byName[viewer.ns.FullName(name)] or nil end
	rawset(viewer.ns, "Roster", R)
	return R
end

test("1.2.1 the level race: one forged census row no longer wins a place, nor the claimant's own, nor two senders of two guilds; two senders of his one guild do", function()
	local w, cast = W3.New({ more = { { "alt", "Fenn Rook", { level = 12 } }, { "f1", "Garric Holt" }, { "f2", "Hale Brindle" },
		{ "f3", "Ivo Marsh" } } })
	local viewer, alt = cast.spectator, cast.alt
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	Claim(w, alt, 60)
	local after = viewer.ns.Honors.CONFIRM_AFTER + 2
	-- One report of another sender (any guild named Olympus): no proof.
	Report(w, viewer, "Olympus Fakers", cast.f1, alt.name, 60)
	w:Run(after)
	eq(Place(viewer, 60), nil, "one census row")
	-- His own report beside it: never his own proof.
	Report(w, viewer, "Olympus Fakers", alt, alt.name, 60)
	w:Run(after)
	eq(Place(viewer, 60), nil, "his own report")
	-- Another sender, of another guild: one sender in each, no proof.
	Report(w, viewer, "Olympus Elsewhere", cast.f2, alt.name, 60)
	w:Run(after)
	eq(Place(viewer, 60), nil, "two guilds, one sender each")
	-- A second sender of the first guild: vouched (the census's own two-sender rule) at once; the
	-- claim is older than CONFIRM_AFTER by now, so the place as soon as the race runs (1.2.1: RACE_SOON
	-- after the census change, never inside the message's own handler).
	Report(w, viewer, "Olympus Fakers", cast.f3, alt.name, 60)
	for _, c in pairs(viewer.ns.HonorsNet.Store().claims) do eq(c.vouched, true, "vouched at once") end
	w:Run(viewer.ns.HonorsNet.RACE_SOON)
	eq(Place(viewer, 60), alt.name)
	W3.NoErrors(w)
end)

test("1.2.1 the level race: a guildmate's claim is vouched by our own roster (the server's), never by another guild's census", function()
	local w, cast = W3.New({ more = { { "mate", "Jory Pike", { level = 19 } }, { "liar", "Kell Dunmore", { level = 15 } },
		{ "f1", "Garric Holt" }, { "f2", "Hale Brindle" } } })
	local viewer = cast.spectator
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	Roster(viewer, { { cast.mate, 20 }, { cast.liar, 15 } })
	Info(w, viewer)
	local after = viewer.ns.Honors.CONFIRM_AFTER + 2
	-- His roster level is the server's: no census needed.
	Claim(w, cast.mate, 20)
	w:As(viewer, viewer.ns.HonorsNet.RunRace)
	w:Run(after)
	eq(Place(viewer, 20), cast.mate.name, "our roster at 20")
	-- A guildmate at 15 by our roster, two senders of another guild listing him at 40: nothing.
	Claim(w, cast.liar, 40)
	Report(w, viewer, "Olympus Fakers", cast.f1, cast.liar.name, 40)
	Report(w, viewer, "Olympus Fakers", cast.f2, cast.liar.name, 40)
	w:Run(after)
	eq(Place(viewer, 40), nil, "another guild's census says nothing of one of ours")
	for _, c in pairs(viewer.ns.HonorsNet.Store().claims) do
		if c.level == 40 then eq(c.vouched, false) end
	end
	W3.NoErrors(w)
end)

test("1.2.1 the level race: a place the server's word shows false goes (his unit below the milestone, or our roster an hour on), with his claim; he never takes it again here, nor does a clerk's record of him; the next proven claim takes it", function()
	local w, cast = W3.New({ more = { { "alt", "Fenn Rook", { level = 12 } }, { "real", "Lena Shaw", { level = 59 } },
		{ "f1", "Garric Holt" }, { "f2", "Hale Brindle" }, { "mate", "Jory Pike", { level = 30 } } } })
	local viewer, alt = cast.spectator, cast.alt
	local net = HN(w, viewer)
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	local after = viewer.ns.Honors.CONFIRM_AFTER + 2
	-- Two forged senders of one guild win it for the level-12 alt.
	Claim(w, alt, 60)
	Report(w, viewer, "Olympus Fakers", cast.f1, alt.name, 60)
	Report(w, viewer, "Olympus Fakers", cast.f2, alt.name, 60)
	w:Run(after)
	eq(Place(viewer, 60), alt.name)
	-- A holder seen at or above it keeps it (the game's level for his unit).
	cast.alt.level = 60
	W3.Sees(viewer, { [alt] = true })
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(Place(viewer, 60), alt.name, "seen at 60: kept")
	-- Seen at 12 (a party, a target, a nameplate): the claim was false. The place goes.
	cast.alt.level = 12
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(Place(viewer, 60), nil, "struck")
	local gk = w:As(viewer, function() return viewer.ns.Arena.GK(alt.guid) end)
	local s = net.Store()
	assert(s.struck and s.struck[60] and s.struck[60][gk], "kept as struck for 60")
	for _, c in pairs(s.claims) do assert(not (c.gk == gk and c.level == 60), "his claim gone") end
	eq(net.Stats().struck, 1)
	-- He claims it again: refused. A clerk's records naming him: refused.
	Claim(w, alt, 60)
	eq(net.Stats().refused.struck, 1)
	local A = viewer.ns.Arena
	local rest = table.concat({ A.B36(60), gk, viewer.ns.ArenaFights.Wire(alt.name), A.B36(w.clock - 100) }, ":")
	eq(net.TakeRecords(cast.arbiter.name, "L", rest), false, "a clerk's record of a struck place")
	eq(Place(viewer, 60), nil)
	-- The next proven claim takes it.
	Claim(w, cast.real, 60)
	Report(w, viewer, "Olympus Shaw", cast.f1, cast.real.name, 60)
	Report(w, viewer, "Olympus Shaw", cast.f2, cast.real.name, 60)
	w:Run(after)
	eq(Place(viewer, 60), cast.real.name, "the next one")
	-- Our roster's word: a guildmate's place at 40 with his roster level 30, read too soon after the
	-- place (the roster may not have his level-up yet): kept; an hour on: struck.
	local R = Roster(viewer, { { cast.mate, 40 } })
	Info(w, viewer)
	Claim(w, cast.mate, 40)
	w:As(viewer, net.RunRace)
	w:Run(after)
	eq(Place(viewer, 40), cast.mate.name)
	R.members[1].level = 30
	R.members = { { full = cast.mate.name, level = 30 } }
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(Place(viewer, 40), cast.mate.name, "too soon to tell")
	w:Run(viewer.ns.HonorsNet.STRIKE_AFTER)
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(Place(viewer, 40), nil, "our roster an hour on: below 40")
	W3.NoErrors(w)
end)

test("1.2.1 the level race: a claim kept vouched under the old rule (one census row) is looked at again: not proven, it takes no place", function()
	local w, cast = W3.New({ more = { { "alt", "Fenn Rook", { level = 12 } } } })
	local viewer, alt = cast.spectator, cast.alt
	local net = HN(w, viewer)
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	local s = net.Store(true)
	local gk = w:As(viewer, function() return viewer.ns.Arena.GK(alt.guid) end)
	s.claims[alt.name:lower() .. ":60"] = { gk = gk, name = alt.name, level = 60, t = w.clock - 3600, heardLocal = w.clock - 3600, vouched = true }
	w:As(viewer, net.RunRace)
	eq(Place(viewer, 60), nil)
	eq(s.claims[alt.name:lower() .. ":60"].vouched, false)
	W3.NoErrors(w)
end)

-- (The review of the fix: a forger's claim may give a GUID no character has, which the game never
-- resolves, so his unit was never found by it and the place stood; and the strikes were kept by
-- GUID alone, so another made-up one claimed again.)
test("1.2.1 the level race: a place won under a made-up GUID goes once his unit is in view by his name (another GUID, or below the milestone); he is struck by name too, so another GUID, his claim or a clerk's record, does not bring him back", function()
	local w, cast = W3.New({ more = { { "alt", "Fenn Rook", { level = 12 } }, { "high", "Ivo Marsh", { level = 60 } },
		{ "f1", "Garric Holt" }, { "f2", "Hale Brindle" } } })
	local viewer, alt = cast.spectator, cast.alt
	local net = HN(w, viewer)
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	local after = viewer.ns.Honors.CONFIRM_AFTER + 2
	local A = viewer.ns.Arena
	local fake = A.GK("Player-4099-0DEADBEEF")
	Claim(w, alt, 60, fake)
	Report(w, viewer, "Olympus Fakers", cast.f1, alt.name, 60)
	Report(w, viewer, "Olympus Fakers", cast.f2, alt.name, 60)
	w:Run(after)
	eq(Place(viewer, 60), alt.name, "two senders: the place, under the made-up GUID")
	-- Nothing of his in view (the game gives no one that GUID): kept.
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(Place(viewer, 60), alt.name, "nothing in view")
	-- His unit targeted: his own GUID, at 12. The place goes, and every claim of his name to 60.
	viewer.target = alt.name
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(Place(viewer, 60), nil, "struck")
	eq(net.Stats().struck, 1)
	local s = net.Store()
	assert(s.struck[60][fake], "struck by the GUID he gave")
	assert(s.struckNames and s.struckNames[60] and s.struckNames[60][alt.name:lower()], "struck by his name")
	for _, c in pairs(s.claims) do assert(not (c.level == 60 and c.name == alt.name), "his claim gone") end
	for _, h in ipairs(net.Holdings(alt.name)) do assert(h.key ~= "level-race-60", "held by his name") end
	-- Out of view again, he claims it under another made-up GUID: refused. A clerk's record of him
	-- under a third: refused.
	viewer.target = nil
	Claim(w, alt, 60, A.GK("Player-4099-0BADF00D"))
	eq(net.Stats().refused.struck, 1)
	local rest = table.concat({ A.B36(60), A.GK("Player-4099-0FACADE0"), viewer.ns.ArenaFights.Wire(alt.name), A.B36(w.clock - 100) }, ":")
	eq(net.TakeRecords(cast.arbiter.name, "L", rest), false, "a clerk's record of a struck name")
	eq(Place(viewer, 60), nil)
	-- A unit in view at the milestone but under another GUID than his place's: the GUID was never
	-- his, struck too.
	Claim(w, cast.high, 40, A.GK("Player-4099-0CAFEBABE"))
	Report(w, viewer, "Olympus Highs", cast.f1, cast.high.name, 40)
	Report(w, viewer, "Olympus Highs", cast.f2, cast.high.name, 40)
	w:Run(after)
	eq(Place(viewer, 40), cast.high.name)
	viewer.target = cast.high.name
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(Place(viewer, 40), nil, "his unit at 60, under another GUID")
	-- A true place: his own GUID, his unit in view at it. Kept.
	viewer.target = nil
	local real = w:Client("Lena Shaw", { level = 20 })
	W3.Rules(w, real)
	Claim(w, real, 20)
	Report(w, viewer, "Olympus Shaw", cast.f1, real.name, 20)
	Report(w, viewer, "Olympus Shaw", cast.f2, real.name, 20)
	w:Run(after)
	eq(Place(viewer, 20), real.name)
	viewer.target = real.name
	Info(w, viewer)
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(Place(viewer, 20), real.name, "his own GUID, at 20: kept")
	W3.NoErrors(w)
end)

test("1.2.1 the level race: a place whose GUID the game gives another character goes", function()
	local w, cast = W3.New({ more = { { "alt", "Fenn Rook", { level = 12 } }, { "other", "Lena Shaw", { level = 60 } },
		{ "f1", "Garric Holt" }, { "f2", "Hale Brindle" } } })
	local viewer, alt = cast.spectator, cast.alt
	local net = HN(w, viewer)
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	local after = viewer.ns.Honors.CONFIRM_AFTER + 2
	local A = viewer.ns.Arena
	-- Another character's GUID, which the game does not resolve here yet.
	Claim(w, alt, 60, A.GK(cast.other.guid))
	Report(w, viewer, "Olympus Fakers", cast.f1, alt.name, 60)
	Report(w, viewer, "Olympus Fakers", cast.f2, alt.name, 60)
	w:Run(after)
	eq(Place(viewer, 60), alt.name)
	-- The game names that GUID: Lena Shaw's, not his.
	Info(w, viewer)
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	eq(Place(viewer, 60), nil, "struck")
	eq(net.Stats().struck, 1)
	W3.NoErrors(w)
end)

test("1.2.1 the level race: a guildmate's claim our roster puts at the milestone counts only under his own GUID (the game resolves a guildmate's; a made-up one waits)", function()
	local w, cast = W3.New({ more = { { "mate", "Jory Pike", { level = 20 } }, { "mate2", "Kell Dunmore", { level = 20 } } } })
	local viewer = cast.spectator
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	Roster(viewer, { { cast.mate, 20 }, { cast.mate2, 20 } })
	Info(w, viewer)
	local after = viewer.ns.Honors.CONFIRM_AFTER + 2
	local A = viewer.ns.Arena
	-- A made-up GUID beside his roster level: no proof.
	Claim(w, cast.mate, 20, A.GK("Player-4099-0DEADBEEF"))
	w:As(viewer, viewer.ns.HonorsNet.RunRace)
	w:Run(after)
	eq(Place(viewer, 20), nil, "a made-up GUID")
	-- Another guildmate there under his own: the place.
	Claim(w, cast.mate2, 20)
	w:As(viewer, viewer.ns.HonorsNet.RunRace)
	w:Run(after)
	eq(Place(viewer, 20), cast.mate2.name, "his own GUID")
	for _, c in pairs(viewer.ns.HonorsNet.Store().claims) do
		if c.name == cast.mate.name then eq(c.vouched, false) end
	end
	W3.NoErrors(w)
end)
