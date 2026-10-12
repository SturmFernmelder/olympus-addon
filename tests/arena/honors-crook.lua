-- 1.2.3 (the owner's call, "Cajado entra na 1.2.3"): the missionaries' crook, the first honour's frame
-- worn after the cornucopia. The Church's top 3 missionaries (ChurchCount.Top3: the NR~1~t word taken
-- from the Head's, the King's or the author's client; in the game only the author's sends one, and the
-- tests hand each client the King's) hold the shepherd's crook in gold, silver and bronze and
-- its title, and see it on their own portraits; the 4th holds nothing. A frame not released yet (the
-- koi) never takes the place of the cornucopia worn; a released one may switch on by itself, and the
-- player picks back any released frame he holds, and it stays. The profile's pickers offer only the
-- released frames. On the test world, with the real Church.lua and ChurchCount.lua in each client and
-- the frames Honors.lua ships worn. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local MEDIA = "Interface\\AddOns\\Olympus\\media\\honors\\"
-- The frames worn as Honors.lua ships them (the test world wears every family's: World's Load).
local SHIPPED = (function()
	local fresh = {}
	assert(loadfile(H.ADDON_DIR .. "Honors.lua"))("Olympus", fresh)
	return fresh.Honors.FRAMES_SHIPPED
end)()

local function Short(name) return (name:gsub("%-.*$", "")) end

-- The real Church.lua and ChurchCount.lua in a namespace of their own over client c's (its saved
-- data, its roots: the world's King and author), their message handlers kept to hand messages to.
local function LoadChurch(w, c)
	local handlers = {}
	local cns = setmetatable({ Comm = { Handle = function(kind, fn) handlers[kind] = fn end, Send = function() end, Whisper = function() end },
		On = function() end, ChatRooms = false }, { __index = c.ns })
	w:As(c, function()
		assert(loadfile(H.ADDON_DIR .. "Church.lua"))("Olympus", cns)
		assert(loadfile(H.ADDON_DIR .. "ChurchCount.lua"))("Olympus", cns)
	end)
	rawset(c.ns, "Church", cns.Church)
	rawset(c.ns, "ChurchCount", cns.ChurchCount)
	c.church = handlers
	-- (The public ranking open: the author's switch, as the Church keeps it.)
	c.rdb.church = c.rdb.church or {}
	c.rdb.church.pub = { on = true, at = w.clock - 3600 }
	return c
end
-- A logout and a login (the save came back: Arena.Persists), the frames Honors.lua ships worn, the
-- Church loaded again (a login builds the client's namespace again).
local function Ready(w, c)
	w:Logout(c)
	w:Login(c)
	W3.Rules(w, c)
	c.ns.Honors.FRAMES_SHIPPED = SHIPPED
	return LoadChurch(w, c)
end
-- The Church's top 3 (last 30 days) as `from` publishes it, on CHANNEL, to each client of `to`:
-- missionaries' names in order, as the Church takes the word (ChurchCount.Receive, its NR handler's).
-- What each client's Church answered: { ok, why }.
local function Top(w, to, from, names, at)
	local list = {}
	for i, x in ipairs(names) do list[i] = Short(type(x) == "table" and x.name or x) end
	local results = {}
	for _, c in ipairs(to) do
		assert(c.church.NR, "the Church's NR handler")
		local B36 = c.ns.Arena.B36
		local text = ("NR~1~t~%s~-~%s"):format(B36(at or w.clock), #list > 0 and table.concat(list, ",") or "-")
		results[#results + 1] = { w:As(c, c.ns.ChurchCount.Receive, "NR", "CHANNEL", from, text) }
	end
	return results
end
-- The Treasurer's donors word (ID) as client c takes it: all time's top 3, and the month's.
local function Donors(w, c, t, names, month)
	local B36 = c.ns.Arena.B36
	local list = {}
	for i, x in ipairs(names) do list[i] = Short(type(x) == "table" and x.name or x) end
	local body = table.concat({ B36(t), B36(c.ns.Honors.MonthOf(w.clock) - 1), month or "-", #list > 0 and table.concat(list, ",") or "-" }, "~")
	eq(w:As(c, c.ns.HonorsNet.TakeDonors, N.treasurer, body), true, "the Treasurer's word taken")
end

-- (1.2.4) The Oracle's ravens, a frame this version still does not wear (2.0's bets): the koi of the
-- 1.2.3 tests below was that frame until 1.2.4 released it (the owner's call). A bank's IO word naming
-- `names` the last month's best predictors, as client c takes it; the world needs a bank (Banked).
local function Banked()
	local w, cast = W3.New({ more = { { "bank", N.bank } } })
	eq(cast.king.Roles.SetBanks({ N.bank }), true)
	w:Run(0)
	return w, cast
end
local function Ravens(w, c, names, t)
	local B36 = c.ns.Arena.B36
	local list = {}
	for i, x in ipairs(names) do list[i] = Short(type(x) == "table" and x.name or x) end
	local body = table.concat({ B36(c.ns.Honors.MonthOf(w.clock) - 1), B36(t or w.clock), #list > 0 and table.concat(list, ",") or "-" }, "~")
	w:As(c, function() c.ns.Arena.Inject("CHANNEL", N.bank, "IO~L1~" .. body) end)
end

-- The game's unit frames on client c (their containers, as tests/arena/honors-net.lua stands them in)
-- and Borders.lua loaded into it: what the player's and the target's portraits show.
local function Frames(w, c)
	local rec = { textures = {} }
	local function Texture(owner, sublevel)
		local t = { owner = owner, sublevel = sublevel, shown = true }
		t.SetTexture = function(self, file) self.file, self.atlas = file, nil return true end
		t.SetAtlas = function(self, a) self.atlas, self.file = a, nil end
		t.SetSize, t.SetPoint, t.ClearAllPoints = function() end, function() end, function() end
		t.SetTexCoord, t.SetDesaturated, t.SetVertexColor = function() end, function() end, function() end
		t.Show = function(self) self.shown = true end
		t.Hide = function(self) self.shown = false end
		t.IsShown = function(self) return self.shown end
		rec.textures[#rec.textures + 1] = t
		return t
	end
	local function Container(label)
		return { label = label, CreateTexture = function(_, _, _, _, sublevel) return Texture(label, sublevel) end }
	end
	local g = c.globals
	g.TargetFrame = { TargetFrameContainer = Container("target"), CheckClassification = function() end }
	g.FocusFrame = { TargetFrameContainer = Container("focus"), CheckClassification = function() end }
	g.PlayerFrame = { PlayerFrameContainer = Container("player") }
	g.hooksecurefunc = function(t, key, post)
		if type(t) ~= "table" then return end
		local original = t[key]
		t[key] = function(...) local r = { original(...) } post(...) return unpack(r) end
	end
	g.C_Texture = { GetAtlasInfo = function() return {} end }
	g.InCombatLockdown = function() return false end
	g.UnitIsUnit = function(a, b) return a == b end
	w:As(c, function()
		rawset(c.ns, "Borders", nil)
		assert(loadfile(H.ADDON_DIR .. "Borders.lua"))("Olympus", c.ns)
	end)
	rec.B = W3.M(w, c, "Borders")
	-- What a portrait shows now (worked out afresh): its foreground file (an honour's) or atlas (a
	-- rank's), or nil; never two.
	function rec.Shown(owner)
		rec.B.Refresh(owner, true)
		local found
		for _, t in ipairs(rec.textures) do
			if t.owner == owner and t.sublevel ~= 2 and t.shown and (t.file or t.atlas) then
				assert(not found, "two at once on " .. owner)
				found = t
			end
		end
		return found and (found.file or found.atlas) or nil
	end
	return rec
end

local function FrameKeys(vm)
	local out = {}
	for _, x in ipairs(vm.frames) do if not x.own then out[#out + 1] = x.key end end
	return table.concat(out, ",")
end

print("HonorsNet: the missionaries' crook (1.2.3)")

test("1.2.3 the missionaries' crook: the Church's top 3 (the King's word) hold the crook in gold, silver and bronze and its title, switched on and seen round their own portraits and by others; the 4th, and a word from anyone but a root, nothing", function()
	local w, cast = W3.New({ more = { { "m4", "Wenna Crale" } } })
	local m1, m2, m3, m4, viewer = cast.A, cast.B, cast.spectator, cast.m4, cast.arbiter
	local all = { m1, m2, m3, m4, viewer }
	for _, c in ipairs(all) do Ready(w, c) end
	-- (The released frames are the cornucopia and, now, the crook.)
	eq(m1.ns.Honors.FrameShipped({ family = "missionary" }), true, "the crook is worn in this version")
	-- A plain member's forged top 3 naming the 4th: refused; he holds nothing.
	for _, r in ipairs(Top(w, all, m4.name, { m4, m1, m2 })) do eq(r[2], "root", "only the Head's, the King's or the author's word") end
	w:Run(3)
	for _, c in ipairs(all) do eq(c.ns.HonorsNet.ChurchTop(), nil, c.short .. ": no top 3 taken") end
	-- The King's: m1, m2, m3 (the 4th, Wenna, ranked after them, is not in it).
	for _, r in ipairs(Top(w, all, N.king, { m1, m2, m3 })) do eq(r[1], true, "the King's word taken") end
	w:Run(3)
	local want = { { m1, "missionary-1", "crook-gold", "Good Shepherd" }, { m2, "missionary-2", "crook-silver", "Faithful Shepherd" },
		{ m3, "missionary-3", "crook-bronze", "Shepherd" } }
	for _, x in ipairs(want) do
		local c, key, art, title = x[1], x[2], x[3], x[4]
		local where = c.short .. " " .. key
		local held
		for _, h in ipairs(c.ns.HonorsNet.Holdings(c.name)) do if h.family == "missionary" then held = h end end
		assert(held, where .. ": held")
		eq(held.key, key, where); eq(held.art, art, where); eq(held.shape, "plain", where); eq(held.mark, art, where)
		eq(held.period, c.ns.Honors.MonthOf(w.clock), where .. ": told for this month")
		-- Switched on by itself, frame and title, and said (AP).
		local pick = c.ns.ArenaProfile.Pick()
		eq(pick.frame, key, where .. ": its frame on"); eq(pick.title, key, where .. ": its title on")
		eq(c.ns.HonorsNet.TitleText(key), title, where)
		local v = w:As(c, c.ns.HonorsNet.Verified, c.name)
		eq(v.frame, key, where); eq(v.art, art, where); eq(v.metal, art:match("%-(%a+)$"), where); eq(v.title, key, where)
		-- Round his own portrait.
		local r = Frames(w, c)
		eq(r.Shown("player"), MEDIA .. art, where .. ": round his own portrait")
		-- The King's letter: its family's words with the title; once.
		local letters = c.ns.HonorsNet.Letters()
		eq(#letters, 1, where .. ": one letter"); eq(letters[1].key, key, where)
		local text = w:As(c, c.ns.HonorsNet.LetterText, key)
		assert(text and text:find(title, 1, true) and text:find("crook", 1, true), where .. ": the missionaries' letter")
		eq(c.ns.ArenaProfile.Mine().lettered[key .. "@" .. c.ns.Honors.MonthOf(w.clock)], true, where .. ": told for this month")
		w:As(c, c.ns.HonorsNet.CloseLetter, false)
	end
	-- Another client: the 1st's crook round his portrait (his pick heard, held on the viewer's own top 3).
	local rv = Frames(w, viewer)
	viewer.target = m1.name
	eq(rv.Shown("target"), MEDIA .. "crook-gold", "others see the gold crook on the 1st")
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, m3.name, m3.guid).art, "crook-bronze", "and the bronze on the 3rd")
	-- The 4th: nothing, round his own portrait or anyone's.
	for _, h in ipairs(m4.ns.HonorsNet.Holdings(m4.name)) do assert(h.family ~= "missionary", "the 4th holds no crook") end
	eq(m4.ns.ArenaProfile.Pick().frame, "rank")
	eq(#m4.ns.HonorsNet.Letters(), 0, "no letter")
	local r4 = Frames(w, m4)
	eq(tostring(r4.Shown("player")):find("crook", 1, true), nil, "no crook round his portrait")
	viewer.target = m4.name
	eq(tostring(rv.Shown("target")):find("crook", 1, true), nil, "nor on him elsewhere")
	-- A forged pick of the crook on him (a profile word): his rank's frame there.
	w:As(viewer, function()
		viewer.ns.Arena.Inject("CHANNEL", m4.name, "AP~L1~" .. table.concat({ "-", "WA", "1", "2", "60", "0.0", "-", "0", "missionary-1", "missionary-1",
			viewer.ns.Arena.B36(w.clock) }, "~"))
	end)
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, m4.name, m4.guid).frame, "rank", "a forged pick shows his rank's frame")
	eq(tostring(rv.Shown("target")):find("crook", 1, true), nil)
	-- The public ranking closed: no crook shows, and nothing is lost (it comes back unannounced).
	for _, c in ipairs({ m1, viewer }) do c.rdb.church.pub = { on = false, at = w.clock } w:As(c, c.ns.Fire, "CHURCH_PUBLIC_CHANGED", false) end
	w:Run(3)
	viewer.target = m1.name
	eq(tostring(rv.Shown("target")):find("crook", 1, true), nil, "closed: no crook")
	eq(m1.ns.ArenaProfile.Pick().seen.missionary.place, 1, "remembered while closed: not lost")
	for _, c in ipairs({ m1, viewer }) do c.rdb.church.pub = { on = true, at = w.clock + 1 } w:As(c, c.ns.Fire, "CHURCH_PUBLIC_CHANGED", true) end
	w:Run(3)
	eq(rv.Shown("target"), MEDIA .. "crook-gold", "open again: the crook")
	eq(#m1.ns.HonorsNet.Letters(), 1, "no second letter")
	-- A word older than its own 30 days names nobody.
	w.clock = w.clock + m1.ns.Honors.CHURCH_MAX_AGE + 60
	for _, t in ipairs(w.timers) do t.at = t.at + m1.ns.Honors.CHURCH_MAX_AGE + 60 end
	w:As(viewer, viewer.ns.Fire, "CHURCH_TOP_CHANGED")
	eq(tostring(rv.Shown("target")):find("crook", 1, true), nil, "a stale top 3: no crook")
	W3.NoErrors(w)
end)

-- The owner (1.2.3): "se a pessoa tem cornucopia e ganha koi pode até mudar quando ganha mas a pessoa
-- pode escolher no perfil entre elas". 1.2.2 switched the pick to any frame newly earned: the koi, not
-- released, took the cornucopia's place and his rank's frame showed. (1.2.4: the koi is released, the
-- owner's call; the Oracle's raven, still not, stands in for it here: the same rule.)
test("1.2.3 honours: wearing the cornucopia, a frame not released yet (1.2.4: the raven) leaves it worn, and its King's letter's Wear it wears its title alone; a released one (the crook) switches on, the cornucopia can be picked back in the profile and stays picked; a pick 1.2.2 left on a frame not released wears the cornucopia again", function()
	local w, cast = Banked()
	local A, viewer = cast.A, cast.arbiter
	Ready(w, A); Ready(w, viewer)
	local t = w.clock
	local function Both(names) t = t + 1 for _, c in ipairs({ A, viewer }) do Donors(w, c, t, names) end w:Run(3) end
	local function Raven(names) t = t + 1 for _, c in ipairs({ A, viewer }) do Ravens(w, c, names, t) end w:Run(3) end
	local function Seen() return w:As(viewer, viewer.ns.HonorsNet.Verified, A.name, A.guid) end
	-- (A profile's word saying something new is taken a minute after the last: ArenaProfile.RATE_CHANGED.)
	local function Later() w:Run(A.ns.ArenaProfile.RATE_CHANGED + 1) end
	local rA, rv = Frames(w, A), Frames(w, viewer)
	viewer.target = A.name
	-- The cornucopia: switched on.
	Both({ A })
	eq(A.ns.ArenaProfile.Pick().frame, "donor-top-1")
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	eq(rA.Shown("player"), MEDIA .. "cornucopia-gold")
	-- The month's raven (not released): the cornucopia stays worn; the raven's title switches on.
	Later()
	Raven({ A })
	local pick = A.ns.ArenaProfile.Pick()
	eq(pick.frame, "donor-top-1", "the cornucopia stays: the raven is not released")
	eq(pick.title, "oracle-1", "its title switches on")
	eq(rA.Shown("player"), MEDIA .. "cornucopia-gold", "round his own portrait")
	eq(Seen().frame, "donor-top-1"); eq(rv.Shown("target"), MEDIA .. "cornucopia-gold", "and as others see him")
	-- The raven's letter, "Wear it": its title, never the frame not worn (1.2.2: the pair was refused,
	-- and nothing changed). (His title put back to none first, so the click shows.)
	eq(A.ns.HonorsNet.LetterFrame().key, "oracle-1")
	eq(w:As(A, A.ns.ProfileEdit.PickTitle, "none"), true)
	eq(A.ns.ArenaProfile.Pick().title, nil)
	w:As(A, A.ns.HonorsNet.CloseLetter, true)
	eq(A.ns.ArenaProfile.Pick().frame, "donor-top-1", "Wear it keeps the cornucopia"); eq(A.ns.ArenaProfile.Pick().title, "oracle-1")
	-- The crook (released): switches on by itself.
	Later()
	Top(w, { A, viewer }, N.king, { A })
	w:Run(3)
	eq(A.ns.ArenaProfile.Pick().frame, "missionary-1", "a released frame switches on")
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	w:Run(1)
	eq(rA.Shown("player"), MEDIA .. "crook-gold"); eq(rv.Shown("target"), MEDIA .. "crook-gold")
	-- He picks the cornucopia back in the profile: it shows, and stays through new words and a relog.
	Later()
	eq(w:As(A, A.ns.ProfileEdit.PickFrame, "donor-top-1"), true)
	eq(rA.Shown("player"), MEDIA .. "cornucopia-gold")
	w:Run(3)
	eq(rv.Shown("target"), MEDIA .. "cornucopia-gold", "others see his pick")
	Both({ A })
	Raven({ A })
	Top(w, { A, viewer }, N.king, { A }, w.clock + 10)
	w:Run(3)
	eq(A.ns.ArenaProfile.Pick().frame, "donor-top-1", "his pick sticks")
	Ready(w, A)
	Donors(w, A, t + 5, { A })
	Ravens(w, A, { A }, t + 6)
	Top(w, { A }, N.king, { A }, w.clock + 20)
	w:Run(A.ns.HonorsNet.REFRESH_DELAY + 5)
	eq(A.ns.ArenaProfile.Pick().frame, "donor-top-1", "after a relog too")
	-- A pick 1.2.2 left on a frame not released (it switched it on by itself): the cornucopia again.
	local m = A.ns.ArenaProfile.Mine(true)
	m.frame = "oracle-1"
	w:As(A, A.ns.Fire, "HONORS_CHANGED", A.name)
	eq(w:As(A, A.ns.HonorsNet.Verified, A.name).frame, "rank", "(1.2.2's case: his rank's frame showed)")
	w:As(A, A.ns.HonorsNet.Refresh)
	eq(A.ns.ArenaProfile.Pick().frame, "donor-top-1", "the first released frame he holds, by ORDER")
	eq(rA.Shown("player"), MEDIA .. "cornucopia-gold")
	W3.NoErrors(w)
end)

-- (1.2.4: the koi is released now, so it is offered; the raven, still not, is the frame never offered.)
test("1.2.3 the profile's Edit: its frame list and its icon picker offer only the released frames held (the cornucopia, the crook; 1.2.4: the koi), never one not released yet (1.2.4: the raven); its title still is; each click moves to a frame that shows", function()
	local w, cast = Banked()
	local A = cast.A
	Ready(w, A)
	Donors(w, A, w.clock, { A }, Short(A.name))
	Ravens(w, A, { A })
	Top(w, { A }, N.king, { A })
	w:Run(3)
	local held = {}
	for _, h in ipairs(A.ns.HonorsNet.Holdings(A.name)) do held[#held + 1] = h.key end
	eq(table.concat(held, ","), "donor-top-1,missionary-1,oracle-1,donor-month-1", "the cornucopia, the crook, the raven and the koi held")
	local PE = W3.M(w, A, "ProfileEdit")
	local vm = PE.ViewModel()
	eq(FrameKeys(vm), "rank,none,donor-top-1,missionary-1,donor-month-1", "the released frames alone")
	local titles = {}
	for _, x in ipairs(vm.titles) do titles[#titles + 1] = x.key end
	eq(table.concat(titles, ","), "none,donor-top-1,missionary-1,oracle-1,donor-month-1", "every title held")
	local koiMark = false
	for _, x in ipairs(PE.IconList("icon")) do
		assert(x.key ~= "raven-gold", "no mark of a frame not released")
		if x.key == "koi-gold" then koiMark = true end
	end
	eq(koiMark, true, "(1.2.4) the koi's mark, released")
	eq(PE.HonourOfMark("raven-gold"), nil)
	-- Each click on the frame picker: the next frame, and it is the one shown.
	local seen = {}
	for _ = 1, 5 do
		eq(PE.Cycle("frame", 1), true, "each click takes")
		local pick = A.ns.ArenaProfile.Pick().frame
		seen[#seen + 1] = pick
		local shown = w:As(A, A.ns.HonorsNet.Verified, A.name).frame
		eq(shown, pick, pick .. ": shown as picked")
	end
	-- (From the cornucopia, switched on first by ORDER: the crook, the koi, then round to it again.)
	eq(table.concat(seen, ","), "missionary-1,donor-month-1,rank,none,donor-top-1")
	W3.NoErrors(w)
end)

-- 1.2.3, after review. The crook is the first released frame a 30-day moving ranking gives: its holders
-- drop out of the top 3 and come back routinely. The owner's rule again: a released frame may switch
-- on by itself when earned, the player picks any released frame he holds, and his pick sticks.
-- The world as the tests above: A and a viewer (another client), the King's words of the top 3, each
-- newer than the last (ChurchCount.TakeTop keeps the newest).
local function Crook(w, cast, extra)
	local A, viewer = cast.A, cast.arbiter
	for _, c in ipairs({ A, viewer }) do Ready(w, c) end
	for _, c in ipairs(extra or {}) do Ready(w, c) end
	local x = { A = A, viewer = viewer, rA = Frames(w, A), rv = Frames(w, viewer), at = w.clock, t = w.clock }
	viewer.target = A.name
	-- (A profile's word saying something new is taken a minute after the last: ArenaProfile.RATE_CHANGED.)
	function x.Later() w:Run(A.ns.ArenaProfile.RATE_CHANGED + 1) end
	-- The King's top 3 (newer each time) to `to` (A and the viewer), then the refresh it causes.
	function x.Word(names, to)
		x.at = x.at + 1
		Top(w, to or { A, viewer }, N.king, names, x.at)
		w:Run(3)
	end
	-- The Treasurer's word: A 1st of all time (and of the month closed when month is given).
	function x.Donors(month)
		x.t = x.t + 1
		for _, c in ipairs({ A, viewer }) do Donors(w, c, x.t, { A }, month) end
		w:Run(3)
	end
	function x.Pick() return A.ns.ArenaProfile.Pick() end
	function x.Seen() return w:As(viewer, viewer.ns.HonorsNet.Verified, A.name, A.guid) end
	function x.Own() return w:As(A, A.ns.HonorsNet.Verified, A.name) end
	return x
end

-- The cornucopia held, the crook switched on by itself, then a fresh word without him: the pick
-- stayed on the crook ("a pick no longer held stays the pick"), and his own portrait, the viewer's
-- target frame and Verified showed his rank's frame with no title, the cornucopia held.
test("1.2.3 the missionaries' crook: switched on over the cornucopia, then a fresh top 3 without him: the cornucopia and its title show again round his own portrait and as another client sees him, never his rank's frame; named again the same month, the crook again with no second letter", function()
	local w, cast = W3.New()
	local x = Crook(w, cast)
	local A, others = x.A, { cast.B, cast.spectator, cast.king }
	x.Donors()
	eq(x.Pick().frame, "donor-top-1")
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	-- Named 3rd: the bronze crook switches on by itself, its letter told.
	x.Later()
	x.Word({ others[1], others[2], A })
	eq(x.Pick().frame, "missionary-3") eq(x.Pick().title, "missionary-3")
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	eq(x.rA.Shown("player"), MEDIA .. "crook-bronze")
	eq(x.rv.Shown("target"), MEDIA .. "crook-bronze", "others see it")
	-- A fresh word without him (three others): the cornucopia and its title.
	x.Later()
	x.Word(others)
	eq(x.Pick().frame, "donor-top-1", "the cornucopia he holds") eq(x.Pick().title, "donor-top-1")
	eq(x.rA.Shown("player"), MEDIA .. "cornucopia-gold", "round his own portrait")
	local own = x.Own()
	eq(own.frame, "donor-top-1") eq(own.title, "donor-top-1")
	eq(x.rv.Shown("target"), MEDIA .. "cornucopia-gold", "as another client sees him")
	local seen = x.Seen()
	eq(seen.frame, "donor-top-1") eq(seen.title, "donor-top-1", "and its title")
	-- Named 3rd again the same month: the crook back (his look before it dropped), no second letter.
	x.Later()
	x.Word({ others[1], others[2], A })
	eq(x.Pick().frame, "missionary-3", "the crook again") eq(x.Pick().title, "missionary-3")
	eq(#A.ns.HonorsNet.Letters(), 2, "the cornucopia's and the crook's letters, no other")
	eq(x.rv.Shown("target"), MEDIA .. "crook-bronze")
	W3.NoErrors(w)
end)

-- His pick back to the cornucopia stuck only while the ranking stood still: dropped to 4th and named
-- 3rd again the same month (its letter told: no letter came), or any place up, switched the crook on
-- over it, silently.
test("1.2.3 the missionaries' crook: the cornucopia picked back in the profile stays when he drops to 4th and is named 3rd again the same month (no letter, nothing switched on); a place first reached this month switches on with its letter; picked back again it stays, through moves within the top 3 and a relog", function()
	local w, cast = W3.New()
	local x = Crook(w, cast)
	local A, PE = x.A, W3.M(w, x.A, "ProfileEdit")
	local B, S, K = cast.B, cast.spectator, cast.king
	x.Donors()
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	x.Later()
	x.Word({ B, S, A })
	eq(x.Pick().frame, "missionary-3")
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	-- He picks the cornucopia back (frame and title).
	x.Later()
	eq(w:As(A, PE.PickFrame, "donor-top-1"), true) eq(w:As(A, PE.PickTitle, "donor-top-1"), true)
	w:Run(3)
	eq(x.rv.Shown("target"), MEDIA .. "cornucopia-gold")
	-- Out (4th), then 3rd again the same month: his pick stays; no letter.
	x.Word({ B, S, K })
	eq(x.Pick().frame, "donor-top-1")
	x.Word({ B, S, A })
	eq(x.Pick().frame, "donor-top-1", "his pick stays") eq(x.Pick().title, "donor-top-1")
	eq(#A.ns.HonorsNet.Letters(), 2, "no letter: 3rd was told this month")
	eq(x.rA.Shown("player"), MEDIA .. "cornucopia-gold")
	eq(x.rv.Shown("target"), MEDIA .. "cornucopia-gold", "as others see him")
	-- 2nd, first reached this month: the silver crook switches on, and its letter tells him.
	x.Later()
	x.Word({ B, A, S })
	eq(x.Pick().frame, "missionary-2") eq(x.Pick().title, "missionary-2")
	eq(#A.ns.HonorsNet.Letters(), 3, "its letter")
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	-- Picked back again: it stays through 3rd, 2nd again, out and in, and a relog.
	x.Later()
	eq(w:As(A, PE.PickFrame, "donor-top-1"), true)
	for _, names in ipairs({ { B, S, A }, { B, A, S }, { B, S, K }, { B, A, S } }) do
		x.Word(names)
		eq(x.Pick().frame, "donor-top-1", "his pick sticks")
	end
	Ready(w, A)
	Donors(w, A, x.t + 5, { A })
	x.Word({ B, A, S }, { A })
	w:Run(A.ns.HonorsNet.REFRESH_DELAY + 5)
	eq(x.Pick().frame, "donor-top-1", "after a relog too")
	eq(#A.ns.HonorsNet.Letters(), 3)
	W3.NoErrors(w)
end)

-- The King gets no letter (1.2.1), and nothing was told for him: every return switched his crook on.
test("1.2.3 the missionaries' crook: the King's honours are told without a letter, so his pick sticks as anyone's: the rank's frame picked back stays when he is named 3rd again the same month", function()
	local w, cast = W3.New()
	local K = cast.king
	Ready(w, K)
	local at = w.clock
	local function Word(names) at = at + 1 Top(w, { K }, N.king, names, at) w:Run(3) end
	Word({ cast.B, cast.spectator, K })
	eq(K.ns.ArenaProfile.Pick().frame, "missionary-3", "switched on")
	eq(#K.ns.HonorsNet.Letters(), 0, "no letter from himself")
	eq((K.ns.ArenaProfile.Mine().lettered or {})["missionary-3@" .. K.ns.Honors.MonthOf(w.clock)], true, "told all the same")
	eq(w:As(K, W3.M(w, K, "ProfileEdit").PickFrame, "rank"), true)
	Word({ cast.B, cast.spectator, cast.A })
	Word({ cast.B, cast.spectator, K })
	eq(K.ns.ArenaProfile.Pick().frame, "rank", "his pick stays")
	W3.NoErrors(w)
end)

-- 1.2.2 switched a frame not released on by itself; the first 1.2.3 mend took only one held now, on an
-- unlocked pick. And the title's click, or the King's letter's Wear it, on such a pick did nothing
-- (Choose refused the frame kept). (1.2.4: the owl and the koi are released now; the comet he never
-- won and the raven, not released, stand in for them.)
test("1.2.3 honours: a pick 1.2.2 left on a frame not released, locked or not held now (1.2.4: a comet he never won), wears the cornucopia; the Wear it of a frame not released (1.2.4: the raven) on a locked pick of it wears its title; the title's click with a crook not held now takes", function()
	local w, cast = Banked()
	local x = Crook(w, cast)
	local A, PE = x.A, W3.M(w, x.A, "ProfileEdit")
	x.Donors()
	Ravens(w, A, { A }, x.t + 1)
	w:Run(3)
	local held = {}
	for _, h in ipairs(A.ns.HonorsNet.Holdings(A.name)) do held[#held + 1] = h.key end
	eq(table.concat(held, ","), "donor-top-1,oracle-1", "the cornucopia and the raven")
	eq(#A.ns.HonorsNet.QueuedLetters(), 2, "their letters")
	-- The comet, not held (1.2.2 can't have put it there, but any frame not released is mended): the cornucopia.
	local m = A.ns.ArenaProfile.Mine(true)
	m.frame = "level-race-60"
	w:As(A, A.ns.Fire, "HONORS_CHANGED", A.name)
	eq(x.Own().frame, "rank", "(1.2.2's case: his rank's frame)")
	w:As(A, A.ns.HonorsNet.Refresh)
	eq(x.Pick().frame, "donor-top-1", "the comet not held: the cornucopia")
	-- Locked on the raven, his title none, and the raven's letter answered Wear it before any refresh.
	m.frame, m.title, m.locked = "oracle-1", nil, true
	w:As(A, A.ns.HonorsNet.CloseLetter, false) -- (the cornucopia's letter, Later)
	eq(A.ns.HonorsNet.LetterFrame().key, "oracle-1")
	w:As(A, A.ns.HonorsNet.CloseLetter, true)
	eq(x.Pick().title, "oracle-1", "Wear it wears its title")
	w:Run(3)
	eq(x.Pick().frame, "donor-top-1", "and the cornucopia shows: locked, mended") eq(x.Pick().locked, true)
	eq(x.rA.Shown("player"), MEDIA .. "cornucopia-gold")
	-- The crook locked and then lost (a fresh word without him): the title's click takes.
	x.Word({ A })
	eq(w:As(A, PE.PickFrame, "missionary-1"), true)
	eq(x.Pick().frame, "missionary-1", "locked: picked by hand")
	x.Word({ cast.B })
	eq(x.Pick().frame, "missionary-1", "locked: stays")
	eq(w:As(A, PE.PickTitle, "donor-top-1"), true, "the title's click takes")
	eq(x.Pick().title, "donor-top-1") eq(x.Pick().frame, "missionary-1")
	W3.NoErrors(w)
end)
