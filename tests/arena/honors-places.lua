-- 1.2.4 (the owner's calls, after the honours audit of 10-11): the frames the King's letters already
-- named are worn now (the month's donors' koi, the best guild's owl), three families more are honours
-- (the Church's top 3 Apostles' cross, the last month's top 3 of Bone Throw's lucky charm, the signed
-- Slayers top 3's skeletal horse, which respects the player's pick now), the King's letter comes the
-- first time a member reaches each place of each list per cycle (a month's list: once a month; for
-- life: once), and every later move is a small notice of Olympus's own: a strip at the top of the
-- screen and a line in chat, never a pop-up, never a burst. On the test world, the frames Honors.lua
-- ships worn. Every name is invented.
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
local function Names(list)
	local out = {}
	for i, x in ipairs(list) do out[i] = Short(type(x) == "table" and x.name or x) end
	return #out > 0 and table.concat(out, ",") or "-"
end

-- The real Church.lua and ChurchCount.lua over client c's namespace (as tests/arena/honors-crook.lua).
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
	c.rdb.church = c.rdb.church or {}
	c.rdb.church.pub = { on = true, at = w.clock - 3600 }
	return c
end
-- A logout and a login (the save came back), the frames Honors.lua ships worn, the Church loaded.
local function Ready(w, c)
	w:Logout(c)
	w:Login(c)
	W3.Rules(w, c)
	c.ns.Honors.FRAMES_SHIPPED = SHIPPED
	return LoadChurch(w, c)
end
-- The Church's top 3 (the King's word, NR~1~t): its Apostles, then its missionaries, as each client
-- of `to` takes it.
local function Top(w, to, apostles, missionaries, at)
	for _, c in ipairs(to) do
		local text = ("NR~1~t~%s~%s~%s"):format(c.ns.Arena.B36(at or w.clock), Names(apostles or {}), Names(missionaries or {}))
		eq(w:As(c, c.ns.ChurchCount.Receive, "NR", "CHANNEL", N.king, text), true, "the King's top 3 taken")
	end
end
-- The Treasurer's donors word (ID): all time's top 3, and the month closed's (names, or nil).
local function Donors(w, c, t, all, month)
	local B36 = c.ns.Arena.B36
	local body = table.concat({ B36(t), B36(c.ns.Honors.MonthOf(w.clock) - 1), month and Names(month) or "-", Names(all) }, "~")
	eq(w:As(c, c.ns.HonorsNet.TakeDonors, N.treasurer, body), true, "the Treasurer's word taken")
end
-- A month on: the clock and every timer moved together (nothing due in between).
local function NextMonth(w, c)
	local Hs = c.ns.Honors
	local m, from = Hs.MonthOf(w.clock), w.clock
	while Hs.MonthOf(w.clock) == m do w.clock = w.clock + 3600 end
	for _, x in ipairs(w.timers) do x.at = x.at + (w.clock - from) end
end
local function Pick(c) return c.ns.ArenaProfile.Pick() end
local function Letters(c) return c.ns.HonorsNet.Letters() end
local function Later(w, c) w:Run(c.ns.ArenaProfile.RATE_CHANGED + 1) end

-- The game's unit frames on client c and Borders.lua loaded into it (as tests/arena/honors-crook.lua):
-- what the player's and the target's portraits show (and, second, its texture's size).
local function Frames(w, c)
	local rec = { textures = {} }
	local function Texture(owner, sublevel)
		local t = { owner = owner, sublevel = sublevel, shown = true }
		t.SetTexture = function(self, file) self.file, self.atlas = file, nil return true end
		t.SetAtlas = function(self, a) self.atlas, self.file = a, nil end
		t.SetSize = function(self, x, y) self.size = x .. "x" .. y end
		t.SetPoint, t.ClearAllPoints = function() end, function() end
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
	function rec.Shown(owner)
		rec.B.Refresh(owner, true)
		local found
		for _, t in ipairs(rec.textures) do
			if t.owner == owner and t.sublevel ~= 2 and t.shown and (t.file or t.atlas) then
				assert(not found, "two at once on " .. owner)
				found = t
			end
		end
		return found and (found.file or found.atlas) or nil, found and found.size or nil
	end
	return rec
end

-- The notices' strips on client c as the game would make them: UIParent a frame of the game's, and
-- each strip's mouse and keyboard as it set them.
local function Strips(c)
	c.globals.UIParent = World.NewFrame("Frame", "UIParent")
	local base = c.globals.CreateFrame
	c.globals.CreateFrame = function(kind, name, parent, ...)
		local f = base(kind, name, parent, ...)
		if type(name) == "string" and name:find("^OlympusHonourNotice") then
			f.made = { kind = kind, parent = parent }
			rawset(f, "EnableMouse", function(self, on) self.mouse = on end)
			rawset(f, "EnableKeyboard", function(self, on) self.keyboard = on end)
		end
		return f
	end
end
local function ShownStrips(c)
	local n = 0
	for _, f in pairs(c.ns.HonorsNet.NoticeFrames()) do if f:IsShown() then n = n + 1 end end
	return n
end
local function Said(c)
	local out = {}
	for i, x in ipairs(c.ns.HonorsNet.Notices()) do out[i] = x.text end
	return out
end

print("HonorsNet: the places told, the koi, the owl, the cross, the charm, the skeletal horse (1.2.4)")

-- The owner (1.2.4): "Se for uma coisa que tiver ciclo, os rankings mensais, é a primeira vez do mês,
-- não a primeira vez da vida". 1.2.3 told the koi's place once a month only when a refresh fell
-- between the month's turn and the Treasurer's first word of it: the same place two months running
-- (the common case) got no second letter.
test("1.2.4 the koi: the month's top 3 donors hold it through the next month, worn (it switches on by itself over the cornucopia; picked back, the cornucopia stays); the same place two months running is a King's letter each month (1.2.3: the second month's never came), never two in one month", function()
	local w, cast = W3.New()
	local A = Ready(w, cast.A)
	local r = Frames(w, A)
	local HN = A.ns.HonorsNet
	local t = w.clock
	local function Word(month) t = t + 1 Donors(w, A, t, { A }, month) w:Run(3) end
	Word()
	eq(Pick(A).frame, "donor-top-1")
	w:As(A, HN.CloseLetter, false)
	-- The closed month's 1st: the koi, worn now, switches on by itself, with its letter.
	Later(w, A)
	Word({ A })
	eq(Pick(A).frame, "donor-month-1", "the koi is worn now: switched on")
	eq(r.Shown("player"), MEDIA .. "koi-gold", "round his own portrait")
	eq(#Letters(A), 2) eq(Letters(A)[2].key, "donor-month-1")
	w:As(A, HN.CloseLetter, false)
	-- He picks the cornucopia back: it stays.
	Later(w, A)
	eq(w:As(A, A.ns.ProfileEdit.PickFrame, "donor-top-1"), true)
	Word({ A })
	eq(Pick(A).frame, "donor-top-1", "his pick sticks")
	eq(#Letters(A), 2, "the same month: no second letter")
	-- The next month: the new closed month's 1st again, the same place: its letter, once.
	NextMonth(w, A)
	t = w.clock
	Word({ A })
	eq(#Letters(A), 3, "a new month at the same place: its letter")
	eq(Letters(A)[3].key, "donor-month-1")
	eq(A.ns.ArenaProfile.Mine().lettered["donor-month-1@" .. (A.ns.Honors.MonthOf(w.clock) - 1)], true, "told for that month")
	eq(Pick(A).frame, "donor-top-1", "the same place is no new honour: his pick stays")
	Word({ A })
	eq(#Letters(A), 3, "once that month")
	W3.NoErrors(w)
end)

-- The month's turn as the field has it: the clock runs through it, so the look HonorsNet asks at the
-- next month's first minute (Tell's LookAt) comes before the Treasurer's first word of the new month.
-- (The test above moves every timer with the clock, so that look never fell in between: before this
-- fix it ended the koi as lost there, and the new month's word made it new again, switched on by
-- itself over the cornucopia or "none" picked: "expected donor-top-1, got donor-month-1".)
test("1.2.4 the koi over the month's turn: the look at the next month's first minute ends it in silence; the new month's list naming him at the same place is its King's letter, and his pick stays (the cornucopia picked, or none; 1.2.4's first cut switched the koi back on every month); the koi he wore stands in for the cornucopia meanwhile and comes back", function()
	local w, cast = W3.New()
	-- (An hour before this month's end, the clock and every timer moved together.)
	local Hs = cast.A.ns.Honors
	local m = Hs.MonthOf(w.clock)
	local turn = w.clock - w.clock % 86400
	while Hs.MonthOf(turn) == m do turn = turn + 86400 end
	local from = w.clock
	w.clock = turn - 3600
	for _, x in ipairs(w.timers) do x.at = x.at + (w.clock - from) end
	local A, B, C = Ready(w, cast.A), Ready(w, cast.B), Ready(w, cast.spectator)
	local all = { A, B, C }
	local t = w.clock
	-- The Treasurer's word to each: all time's top 3 (A, B, C) and the month closed's (names).
	local function Word(month)
		t = math.max(t + 1, w.clock)
		for _, c in ipairs(all) do Donors(w, c, t, { A, B, C }, month) end
		w:Run(3)
	end
	local function Read() for _, c in ipairs(all) do w:As(c, c.ns.HonorsNet.CloseLetter, false) end end
	Word()
	Read()
	Later(w, A)
	-- The month closed: A 1st, B 2nd, C 3rd; each koi switches on with its letter.
	Word({ A, B, C })
	for i, c in ipairs(all) do eq(Pick(c).frame, "donor-month-" .. i, c.short .. ": the koi switched on") end
	Read()
	Later(w, A)
	-- A picks his cornucopia back, B none; C keeps the koi on.
	eq(w:As(A, A.ns.ProfileEdit.PickFrame, "donor-top-1"), true)
	eq(w:As(B, B.ns.ProfileEdit.PickFrame, "none"), true)
	-- Through the month's turn, the Treasurer's word not in yet: each client's own look ends the koi.
	w:Run(turn - w.clock + 120)
	for _, c in ipairs(all) do
		for _, h in ipairs(c.ns.HonorsNet.Holdings(c.name)) do assert(h.family ~= "donor-month", c.short .. ": the month held is over") end
	end
	eq(Pick(A).frame, "donor-top-1") eq(Pick(B).frame, "none")
	eq(Pick(C).frame, "donor-top-3", "the koi he wore over: his cornucopia stands in")
	-- The Treasurer's first word of the new month: the same places.
	Word({ A, B, C })
	eq(Pick(A).frame, "donor-top-1", "the cornucopia he picked stays")
	eq(Pick(B).frame, "none", "none stays")
	eq(Pick(C).frame, "donor-month-3", "the koi he wore, back")
	local month = Hs.MonthOf(w.clock) - 1
	for i, c in ipairs(all) do
		eq(#Letters(c), 3, c.short .. ": the new month's letter") eq(Letters(c)[3].key, "donor-month-" .. i)
		eq(c.ns.ArenaProfile.Mine().lettered["donor-month-" .. i .. "@" .. month], true, c.short .. ": told for the new month")
	end
	-- Again that month (a later word, and the looks after it): nothing more.
	Read()
	Later(w, A)
	Word({ A, B, C })
	w:Run(A.ns.HonorsNet.NOTICE_GAP + 5)
	eq(Pick(A).frame, "donor-top-1") eq(Pick(B).frame, "none") eq(Pick(C).frame, "donor-month-3")
	for _, c in ipairs(all) do eq(#Letters(c), 3, c.short .. ": once that month") end
	W3.NoErrors(w)
end)

-- 1.2.4's first cut opened the King's letter by itself wherever the player stood: at the month's
-- turn (the look at 00:01 UTC, 21:01 in Brazil: raid time) for the crook, the cross and the charm,
-- or at a new Slayers word, over a dungeon or a raid between pulls (only combat lockdown and the
-- gamepad UI made it wait). Olympus's popups wait in an instance or Busy (ns.Alert): so does it now.
test("1.2.4 the King's letter in an instance or Busy: one that would open by itself waits (his honour switched on all the same; a chat line; one line on the Decrees tab's held list for every letter waiting), opens by itself once he is out and not Busy, and at once on his own click (the Olympus window, the held line); the month's turn in a raid the same", function()
	local w, cast = W3.New()
	-- (An hour before this month's end, the clock and every timer moved together.)
	local Hs = cast.A.ns.Honors
	local m = Hs.MonthOf(w.clock)
	local turn = w.clock - w.clock % 86400
	while Hs.MonthOf(turn) == m do turn = turn + 86400 end
	local from = w.clock
	w.clock = turn - 3600
	for _, x in ipairs(w.timers) do x.at = x.at + (w.clock - from) end
	local A, B, C, D = Ready(w, cast.A), Ready(w, cast.B), Ready(w, cast.spectator), Ready(w, cast.arbiter)
	local all = { A, B, C, D }
	local function Shown(c) local f = c.ns.HonorsNet.LetterFrame() return f ~= nil and f:IsShown() == true end
	local function Held(c)
		local out = {}
		for _, h in ipairs(w:As(c, c.ns.Held)) do out[#out + 1] = h.what end
		return table.concat(out, " | ")
	end
	C.globals.UnitIsDND = function() return C.dnd == true end
	A.instance, B.instance, D.instance, C.dnd = true, true, true, true
	local printed = #A.printed
	for _, c in ipairs(all) do Donors(w, c, w.clock, { A, B, C }) end
	w:Run(3)
	for _, c in ipairs({ A, B, C }) do
		eq(Pick(c).frame:find("^donor%-top%-") ~= nil, true, c.short .. ": his honour switched on all the same")
		eq(#Letters(c), 1, c.short .. ": kept to read")
		eq(Shown(c), false, c.short .. ": no letter over his game")
		eq(Held(c), "a letter from the King", c.short .. ": on the Decrees tab's held list")
	end
	assert(table.concat(A.printed, "\n", printed + 1):find("A letter from the King awaits you", 1, true), "its chat line")
	-- A second letter meanwhile (the koi): still one held line.
	Later(w, A)
	for _, c in ipairs(all) do Donors(w, c, w.clock, { A, B, C }, { A }) end
	w:Run(3)
	eq(#Letters(A), 2) eq(Shown(A), false) eq(Held(A), "a letter from the King", "one line for both")
	-- B opens the Olympus window himself, in the instance: his letter at once. D, Busy nowhere, none.
	eq(w:As(B, B.ns.HonorsNet.WindowShown), true) eq(Shown(B), true, "his own click")
	eq(Held(D), "", "no letter: nothing held")
	-- Out of the instance, and C no longer Busy: each opens by itself within seconds, A's second after his first.
	A.instance, C.dnd = false, false
	w:Run(12)
	eq(Shown(A), true, "out: it opens") eq(A.ns.HonorsNet.LetterFrame().key, "donor-top-1")
	eq(Shown(C), true, "not Busy: it opens")
	eq(w:As(A, A.ns.HonorsNet.CloseLetter, false), true)
	eq(Shown(A), true) eq(A.ns.HonorsNet.LetterFrame().key, "donor-month-1", "the next one after his click")
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	-- The month's turn in a raid: the Apostles' cross, told per calendar month, comes again at the
	-- next month's first minute (his own look). It waits until he is out.
	Top(w, { A }, { A })
	w:Run(3)
	eq(Shown(A), true) eq(A.ns.HonorsNet.LetterFrame().key, "apostle-1")
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	A.instance = true
	w:Run(turn - w.clock + 120)
	eq(#Letters(A), 4, "the new month's cross") eq(Letters(A)[4].key, "apostle-1")
	eq(Shown(A), false, "not over his raid") eq(Held(A), "a letter from the King")
	-- The held line clicked in the raid (his own click): it opens.
	local line
	for _, l in ipairs(w:As(A, A.ns.HeldLines)) do if l.onClick then line = l end end
	assert(line, "a line to click")
	w:As(A, line.onClick)
	eq(Shown(A), true, "his click on the held line")
	W3.NoErrors(w)
end)

-- The owner (1.2.4): "... uns avisos menores ... menos intrusiva, tipo um aviso na tela, não um
-- pop-up, falando que ele caiu de posição para segundo, que ele perdeu porque ele saiu da lista, que
-- ele voltou para a lista, que ele recuperou".
test("1.2.4 notices: after the King's first letter for a place, a drop, leaving the list, coming back and a place won back are each a strip of Olympus's own at the top of the screen (no button, no mouse, no keyboard, gone in seconds) and a line in chat, once the move held two minutes, one family's 15 minutes apart; a swap back within them says nothing; dropping to 2nd is no letter", function()
	local w, cast = W3.New()
	local A, B = Ready(w, cast.A), cast.B
	Strips(A)
	local HN = A.ns.HonorsNet
	local t = w.clock
	local function Word(names) t = t + 1 Donors(w, A, t, names) w:Run(3) end
	Word({ A })
	eq(#Letters(A), 1, "1st: its letter")
	w:As(A, HN.CloseLetter, false)
	-- Down to 2nd and back to 1st inside two minutes: nothing at all.
	Word({ B, A })
	eq(#Said(A), 0, "not at once")
	w:Run(60)
	Word({ A, B })
	w:Run(HN.NOTICE_SETTLE + 5)
	eq(#Said(A), 0, "a swap back says nothing")
	-- Down to 2nd, and it holds: the notice, no letter.
	Word({ B, A })
	w:Run(HN.NOTICE_SETTLE + 5)
	eq(table.concat(Said(A), " | "), "Top donors: you dropped to 2nd place.")
	eq(#Letters(A), 1, "dropping to 2nd is no letter")
	assert(A.printed[#A.printed]:find("Top donors: you dropped to 2nd place.", 1, true), "its line in chat")
	local f = HN.NoticeFrames()[1]
	assert(f and f:IsShown(), "its strip on screen")
	eq(f:GetName(), "OlympusHonourNotice1") eq(f.made.kind, "Frame") eq(f.made.parent, A.globals.UIParent, "a frame of Olympus's own on UIParent")
	eq(f.mouse, false, "no mouse") eq(f.keyboard, false, "no keyboard")
	eq(f.text:GetText(), "Top donors: you dropped to 2nd place.") eq(f.icon.texture, MEDIA .. "cornucopia-silver-mark", "the honour's mark")
	for _, x in ipairs(A.frames) do assert(x.frame.kind ~= "Button" or x.frame.parent ~= f, "no button on it") end
	w:Run(HN.NOTICE_SHOW + 1)
	eq(f:IsShown(), false, "gone after a few seconds")
	-- 1st again: a place won back, 15 minutes after the family's last notice.
	Word({ A, B })
	w:Run(HN.NOTICE_SETTLE + 5)
	eq(#Said(A), 1, "one family's notices 15 minutes apart")
	w:Run(HN.NOTICE_GAP)
	eq(Said(A)[2], "Top donors: you regained 1st place.")
	-- Off the list, then back on it.
	Word({ B })
	w:Run(HN.NOTICE_GAP + 5)
	eq(Said(A)[3], "Top donors: you are off the list, and its frame is no longer yours.")
	Word({ A })
	w:Run(HN.NOTICE_GAP + 5)
	eq(Said(A)[4], "Top donors: you are back on the list, in 1st place.")
	eq(#Letters(A), 1, "never a second letter for a place told")
	W3.NoErrors(w)
end)

test("1.2.4 notices: never a burst at login or when a list first loads: a list first seen tells its letter alone; what moved while he was away is one strip, 'since your last visit', two minutes after his first look; in an instance or Busy the chat line alone; three strips at once at most, one every 2 seconds, ten a session, the rest in chat alone", function()
	local w, cast = W3.New()
	local A, B, C = Ready(w, cast.A), cast.B, cast.spectator
	Strips(A)
	local HN = A.ns.HonorsNet
	Donors(w, A, w.clock, { A })
	w:Run(3)
	-- The Church's first word naming him: a first look of the Apostles' list, its letter alone.
	Top(w, { A }, { B, A })
	w:Run(3)
	eq(#Letters(A), 2) eq(Letters(A)[2].key, "apostle-2")
	w:Run(HN.NOTICE_SETTLE + 5)
	eq(#Said(A), 0, "a list first loaded: no notice")
	-- Away (a logout and a login); what the realm's words say when he comes back: he dropped on both.
	w:Logout(A)
	w:Login(A)
	W3.Rules(w, A)
	A.ns.Honors.FRAMES_SHIPPED = SHIPPED
	LoadChurch(w, A)
	Strips(A)
	HN = A.ns.HonorsNet
	Donors(w, A, w.clock + 1, { B, A })
	Top(w, { A }, { B, C, A }, nil, w.clock + 1)
	w:Run(3)
	eq(#Said(A), 0, "nothing at login")
	w:Run(HN.NOTICE_SETTLE - 10)
	eq(#Said(A), 0, "nothing before the move held two minutes")
	w:Run(15)
	local since = "Since your last visit: Top donors, 2nd place; Apostles, 3rd place."
	eq(table.concat(Said(A), " | "), since, "one notice for both")
	eq(ShownStrips(A), 1, "one strip")
	eq(HN.NoticeFrames()[1].text:GetText(), since)
	w:Run(HN.REFRESH_DELAY + HN.NOTICE_SHOW + 1)
	eq(#Said(A), 1, "and nothing more at the login's own look")
	-- In an instance (the alerts held, ns.Quiet): the chat line alone.
	A.instance = true
	local printed = #A.printed
	eq(w:As(A, HN.Notice, "In a dungeon", "donor-top-2"), false, "no strip")
	eq(#A.printed, printed + 1, "its chat line")
	eq(ShownStrips(A), 0)
	A.instance = false
	-- Twelve at once: three strips at most, one every 2 seconds; ten a session (one shown already).
	local strips = 0
	for i = 1, 12 do if w:As(A, HN.Notice, "Notice " .. i, "donor-top-2") then strips = strips + 1 end end
	eq(strips, 9, "ten strips a session, the rest in chat alone")
	eq(#A.printed, printed + 13, "every one in chat")
	eq(ShownStrips(A), 1, "one at once")
	local most = 0
	for _ = 1, 60 do
		w:Run(1)
		most = math.max(most, ShownStrips(A))
	end
	eq(most, HN.NOTICE_STACK, "three at once at most")
	eq(ShownStrips(A), 0, "all gone")
	W3.NoErrors(w)
end)

test("1.2.4 the Apostles' cross: the Church's top 3 Apostles (the same word as the missionaries') hold the cross in gold, silver and bronze and its title, worn: switched on by itself with the King's letter, round his own portrait and as others see him; the 4th nothing; told once per place per calendar month", function()
	local w, cast = W3.New({ more = { { "m4", "Wenna Crale" } } })
	local a1, a2, a3, a4, viewer = cast.A, cast.B, cast.spectator, cast.m4, cast.arbiter
	local all = { a1, a2, a3, a4, viewer }
	for _, c in ipairs(all) do Ready(w, c) end
	Top(w, all, { a1, a2, a3 })
	w:Run(3)
	local want = { { a1, "apostle-1", "cross-gold", "Light of Olympus" }, { a2, "apostle-2", "cross-silver", "Voice of Olympus" },
		{ a3, "apostle-3", "cross-bronze", "Herald of Olympus" } }
	for _, x in ipairs(want) do
		local c, key, art, title = x[1], x[2], x[3], x[4]
		local where = c.short .. " " .. key
		eq(Pick(c).frame, key, where .. ": worn, switched on") eq(Pick(c).title, key)
		eq(c.ns.HonorsNet.TitleText(key), title, where)
		eq(#Letters(c), 1, where .. ": its letter") eq(Letters(c)[1].key, key)
		local text = w:As(c, c.ns.HonorsNet.LetterText, key)
		assert(text and text:find(title, 1, true) and text:find("cross", 1, true), where .. ": the Apostles' letter")
		local file, size = Frames(w, c).Shown("player")
		eq(file, MEDIA .. art, where .. ": round his own portrait")
		-- (1.2.4, the author's ask of the cross, "um pouco maior": 110 across, a plain honour's 100
		-- drawn 10% bigger about the portrait's centre: tests/arena/honors-own-look.lua.)
		eq(size, "110x110", where .. ": the cross a little bigger")
		w:As(c, c.ns.HonorsNet.CloseLetter, false)
	end
	Later(w, a1)
	local rv = Frames(w, viewer)
	viewer.target = a1.name
	local seen, seenSize = rv.Shown("target")
	eq(seen, MEDIA .. "cross-gold", "others see the gold cross on the 1st")
	eq(seenSize, "110x110", "as big on their target frame")
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, a3.name, a3.guid).art, "cross-bronze")
	for _, h in ipairs(a4.ns.HonorsNet.Holdings(a4.name)) do assert(h.family ~= "apostle", "the 4th holds no cross") end
	-- Another order the same month: no letter for a place told; a place first reached, its letter.
	Top(w, all, { a2, a1, a3 }, nil, w.clock + 1)
	w:Run(3)
	eq(#Letters(a1), 1, "a1 2nd: down, no letter")
	eq(#Letters(a2), 2, "a2 1st for the first time this month: its letter") eq(Letters(a2)[2].key, "apostle-1")
	-- The next calendar month, the same places: each its letter again (a rolling list, told per month).
	NextMonth(w, a1)
	Top(w, all, { a2, a1, a3 })
	w:Run(3)
	eq(#Letters(a1), 2) eq(Letters(a1)[2].key, "apostle-2")
	eq(#Letters(a3), 2, "the same place, a new month")
	eq(Pick(a3).frame, "apostle-3")
	W3.NoErrors(w)
end)

-- The Slayers' signed top 3 as Wanted.GlobalSnapshot gives it (tests/wanted.lua holds its signatures
-- and roles): the source stood in on client c; WANTED_CHANGED as Wanted fires it when its word changes.
local function Slayers(w, c, get)
	rawset(c.ns, "Wanted", { GLOBAL_BORDERS_ACTIVE = true, GlobalSnapshot = function() return get() end,
		GlobalBorder = function() return nil end })
	w:As(c, c.ns.Fire, "WANTED_CHANGED")
end

test("1.2.4 the slayers' frame: the signed Slayers top 3 hold the skeletal horse in gold, silver and bronze by GUID (its title, its King's letter once in his life), switched on by itself; his pick decides it as any frame's (1.2.3: the horse went over it): none shows none and the cornucopia he picked shows, round his own portrait and as others see him; a newer word without him is a notice; an expired one changes nothing", function()
	local w, cast = W3.New()
	local A, B, viewer = Ready(w, cast.A), Ready(w, cast.B), Ready(w, cast.arbiter)
	local snap = { issuer = N.king, epoch = 1, seq = 1, issued = w.clock, rows = { { guid = A.guid, points = 9 }, { guid = B.guid, points = 7 } } }
	local current = snap
	for _, c in ipairs({ A, B, viewer }) do Slayers(w, c, function() return current end) end
	w:Run(3)
	local rA, rv = Frames(w, A), Frames(w, viewer)
	viewer.target = A.name
	eq(Pick(A).frame, "wanted-slayer-1", "switched on by itself") eq(Pick(A).title, "wanted-slayer-1")
	eq(A.ns.HonorsNet.TitleText("wanted-slayer-1"), "Bane of the Horde")
	eq(rA.Shown("player"), MEDIA .. "skeletal-horse-gold", "the skeletal horse, not the orc's wolf")
	eq(#Letters(A), 1) eq(Letters(A)[1].key, "wanted-slayer-1")
	assert(w:As(A, A.ns.HonorsNet.LetterText, "wanted-slayer-1"):find("skeletal horse", 1, true), "the slayers' letter")
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	eq(Pick(B).frame, "wanted-slayer-2") eq(B.ns.HonorsNet.TitleText("wanted-slayer-2"), "Horde Hunter")
	Later(w, A)
	eq(rv.Shown("target"), MEDIA .. "skeletal-horse-gold", "others see it by his GUID")
	-- His pick: none, as he and others see him.
	eq(w:As(A, A.ns.ProfileEdit.PickFrame, "none"), true)
	eq(rA.Shown("player"), nil, "none: no frame round his own portrait")
	Later(w, A)
	eq(rv.Shown("target"), nil, "nor as others see him")
	-- The cornucopia, then picked: it shows over the horse.
	Donors(w, A, w.clock, { A })
	Donors(w, viewer, w.clock, { A })
	w:Run(3)
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	Later(w, A)
	eq(w:As(A, A.ns.ProfileEdit.PickFrame, "donor-top-1"), true)
	eq(rA.Shown("player"), MEDIA .. "cornucopia-gold", "his other frame")
	Later(w, A)
	eq(rv.Shown("target"), MEDIA .. "cornucopia-gold", "as others see him")
	-- A newer word without him: a notice, two minutes on; his pick as it is; no second letter.
	Strips(A)
	current = { issuer = N.king, epoch = 1, seq = 2, issued = w.clock, rows = { { guid = B.guid, points = 9 } } }
	for _, c in ipairs({ A, B, viewer }) do w:As(c, c.ns.Fire, "WANTED_CHANGED") end
	w:Run(A.ns.HonorsNet.NOTICE_SETTLE + 5)
	eq(table.concat(Said(A), " | "), "Slayers: you are off the list, and its frame is no longer yours.")
	eq(Pick(A).frame, "donor-top-1")
	-- The word expired (none shown): unknown is not lost; back in a word, no second letter.
	current = nil
	w:As(A, A.ns.Fire, "WANTED_CHANGED")
	w:Run(A.ns.HonorsNet.NOTICE_GAP + 5)
	eq(#Said(A), 1, "nothing for a word gone")
	current = snap
	w:As(A, A.ns.Fire, "WANTED_CHANGED")
	w:Run(A.ns.HonorsNet.NOTICE_GAP + 5)
	eq(Said(A)[2], "Slayers: you are back on the list, in 1st place.")
	eq(#Letters(A), 2, "the horse's letter once in his life (and the cornucopia's)")
	W3.NoErrors(w)
end)

-- The census as client c holds it: a guild's report (its leader, size and average level), its leader
-- vouched as the census vouches for him (Data.KnownRank's two senders: stood in, the census's own
-- tests hold it), and DATA_CHANGED as the census fires it.
local function Census(w, c, guild, leader, avg)
	W3.Report(c, guild, { short = "Rhea Teller", name = "Rhea Teller-" .. c.realm }, { { name = leader.short, level = 60, class = "WA" } },
		{ leader = leader.short, total = 40, avgLevel = avg })
	rawset(c.ns, "Data", setmetatable({ KnownRank = function() return 0, 2 end }, { __index = c.ns.Data }))
	w:As(c, c.ns.Fire, "DATA_CHANGED")
end

test("1.2.4 the owl: the guild master of the Olympus guild with the highest average level holds it, worn (switched on with its letter); his client looks again when the census changes its first, so another guild going first is a notice, and his own first again another (no second letter)", function()
	local w, cast = W3.New({ more = { { "gm", "Bryn Halloway", { guild = "Olympus Vale", rank = 0 } } } })
	local gm = Ready(w, cast.gm)
	Strips(gm)
	local r = Frames(w, gm)
	local HN = gm.ns.HonorsNet
	Census(w, gm, "Olympus Vale", gm, 45)
	w:Run(HN.BEST_SOON + 5)
	eq(Pick(gm).frame, "guild-top-leader", "the owl, worn now: switched on")
	eq(r.Shown("player"), MEDIA .. "owl-gold")
	eq(#Letters(gm), 1) eq(Letters(gm)[1].key, "guild-top-leader")
	w:As(gm, HN.CloseLetter, false)
	-- Another guild first: off the list, a notice.
	Census(w, gm, "Olympus Ash", { short = "Corin Ash" }, 50)
	w:Run(HN.BEST_SOON + HN.NOTICE_SETTLE + 10)
	eq(table.concat(Said(gm), " | "), "Best guild: your guild is no longer first, and the owl is no longer yours.")
	eq(r.Shown("player") ~= MEDIA .. "owl-gold", true, "the owl gone")
	-- His own first again: a notice, no second letter.
	Census(w, gm, "Olympus Vale", gm, 55)
	w:Run(HN.BEST_SOON + HN.NOTICE_GAP + 10)
	eq(Said(gm)[2], "Best guild: your guild is first again, and the owl is yours again.")
	eq(#Letters(gm), 1, "no second letter")
	eq(Pick(gm).frame, "guild-top-leader", "his owl back")
	W3.NoErrors(w)
end)

-- Bone Throw as members play it (tests/arena/bones-ranking.lua's PlayConceded): a table at the
-- default settings, played 20 s, then the host concedes: the guest wins. Each player's client keeps
-- both signed halves, and every member who heard them on the channel counts the game too.
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local function Bones(w, c, fn, ...) return w:As(c, c.ns.FarkleTable[fn], ...) end
local function PlayConceded(w, host, guest)
	local id = assert(Bones(w, host, "Create", { guest = guest.name, target = 2000 }))
	w:Run(0)
	assert(Bones(w, guest, "Answer", id, true, nil, {}))
	w:Run(0)
	w:QueueRoll(host.name, 90); w:QueueRoll(guest.name, 10)
	Bones(w, host, "Roll", id); Bones(w, guest, "Roll", id)
	w:Run(20)
	assert(Bones(w, host, "Concede", id))
	w:Run(0)
	return id
end

test("1.2.4 the Bones' charm: the last month's top 3 of Bone Throw (the games both players' halves agree on, a win at least) hold the lucky charm in gold, silver and bronze through the month after, worn (switched on with its letter) and seen by others; at the month's turn the player's client looks by itself (no word comes); that month over, it ends in silence", function()
	local w = FW.New({ compliance = "shipped" })
	local a, b, c, d = w:Player(N.fighterA), w:Player(N.fighterB), w:Player(N.bettor3), w:Player(N.bettor1)
	w:Group({ a, b })
	local Hs, HN = a.ns.Honors, a.ns.HonorsNet
	-- (An hour before this month's end, the clock and every timer moved together.)
	local m = Hs.MonthOf(w.clock)
	local turn = w.clock - w.clock % 86400
	while Hs.MonthOf(turn) == m do turn = turn + 86400 end
	local from = w.clock
	w.clock = turn - 3600
	for _, x in ipairs(w.timers) do x.at = x.at + (w.clock - from) end
	-- This month: b hosts a and concedes (a wins); then b hosts c and concedes (c wins, later).
	PlayConceded(w, b, a)
	w:Group({ b, c })
	PlayConceded(w, b, c)
	eq(#Bones(w, d, "Best", "L"), 3, "this month's list as a member counts it")
	for _, x in ipairs({ a, b, c, d }) do w:As(x, x.ns.HonorsNet.Refresh) end
	eq(Pick(a).frame, "rank", "this month's list gives no charm yet")
	-- The month's turn: each player looks by himself, the month just closed his charm's.
	w:Run(turn - w.clock + 120)
	eq(Pick(a).frame, "bones-1", "worn: switched on") eq(Pick(a).title, "bones-1")
	eq(HN.TitleText("bones-1"), "Master of Bones")
	eq(#Letters(a), 1) eq(Letters(a)[1].key, "bones-1")
	eq(a.ns.ArenaProfile.Mine().lettered["bones-1@" .. m], true, "told for the month it ranks")
	local text = w:As(a, HN.LetterText, "bones-1")
	assert(text:find("Master of Bones", 1, true) and text:find("lucky charm", 1, true), "the Bones' letter")
	eq(Pick(c).frame, "bones-2") eq(c.ns.HonorsNet.TitleText("bones-2"), "Luck's Favourite")
	for _, h in ipairs(b.ns.HonorsNet.Holdings(b.name)) do assert(h.family ~= "bones", "no win: no charm") end
	local r = Frames(w, a)
	eq(r.Shown("player"), MEDIA .. "charm-gold", "round his own portrait")
	Later(w, a)
	eq(w:As(d, d.ns.HonorsNet.Verified, a.name, a.guid).art, "charm-gold", "as others see him")
	-- The month after over (no game of his in the month closed then): the charm ends, said nothing.
	Strips(a)
	NextMonth(w, a)
	w:As(a, HN.Refresh)
	w:Run(HN.NOTICE_SETTLE + 5)
	for _, h in ipairs(HN.Holdings(a.name)) do assert(h.family ~= "bones", "over") end
	eq(#Said(a), 0, "a closed month's end: no notice")
	eq(#Letters(a), 1)
	eq(tostring(r.Shown("player")):find("charm", 1, true), nil, "the charm no longer shows")
	W3.NoErrors(w)
end)

-- FarkleTable keeps HALVES_MAX games (2000), the oldest going first past it, and the oldest are the
-- closed month's: 1.2.4's first cut recounted the charm from what was left, so on a busy realm its
-- top 3 changed partway through the month it is held in (its holder "out", the 4th lettered for a
-- place he never held), each client at its own prune. (The cap lowered here: the same code, fewer
-- games.)
test("1.2.4 the Bones' charm through the month after: this client's games past FarkleTable's cap (HALVES_MAX) prune the closed month's oldest, and its top 3 stays as it stood when that month closed: the holders keep their charms, round their portraits and as others see them, no notice, no letter", function()
	local w = FW.New({ compliance = "shipped" })
	local a, b, c, d = w:Player(N.fighterA), w:Player(N.fighterB), w:Player(N.bettor3), w:Player(N.bettor1)
	local everyone = { a, b, c, d }
	w:Group({ a, b })
	local Hs, HN = a.ns.Honors, a.ns.HonorsNet
	-- (An hour before this month's end, the clock and every timer moved together.)
	local m = Hs.MonthOf(w.clock)
	local turn = w.clock - w.clock % 86400
	while Hs.MonthOf(turn) == m do turn = turn + 86400 end
	local from = w.clock
	w.clock = turn - 3600
	for _, x in ipairs(w.timers) do x.at = x.at + (w.clock - from) end
	-- This month: a beats b, then c beats b.
	PlayConceded(w, b, a)
	w:Group({ b, c })
	PlayConceded(w, b, c)
	for _, x in ipairs(everyone) do w:As(x, x.ns.HonorsNet.Refresh) end
	-- The month's turn: a holds the gold charm, c the silver.
	w:Run(turn - w.clock + 120)
	eq(Pick(a).frame, "bones-1") eq(Pick(c).frame, "bones-2")
	eq(#Letters(a), 1) eq(#Letters(c), 1)
	eq(w:As(d, d.ns.HonorsNet.Verified, a.name, a.guid).art, "charm-gold", "as others see him")
	Strips(a)
	Strips(c)
	-- This month's games (d beats c, then d beats b) take every client's store over its cap (3 here:
	-- down to 2 when pruned, FarkleTable.Prune as at a login and while involved): the oldest go, last
	-- month's.
	w:Run(3600)
	w:Group({ c, d })
	PlayConceded(w, c, d)
	-- (Two hosts' invitations within FarkleTable.INVITES_WINDOW ask d whether to stop them: later.)
	w:Run(d.ns.FarkleTable.INVITES_WINDOW + 1)
	w:Group({ b, d })
	PlayConceded(w, b, d)
	local closed = Hs.MonthOf(w.clock) - 1
	for _, x in ipairs(everyone) do
		eq(#Bones(w, x, "Best", "L", { month = closed }), 3, x.short .. ": last month's list as it closed")
		x.ns.FarkleTable.HALVES_MAX = 3
		Bones(w, x, "Prune")
		eq(#Bones(w, x, "Best", "L", { month = closed }), 0, x.short .. ": last month's games pruned here")
		eq(#Bones(w, x, "Best", "L"), 3, x.short .. ": this month's kept")
	end
	for _, x in ipairs(everyone) do w:As(x, x.ns.HonorsNet.Refresh) end
	w:Run(HN.NOTICE_SETTLE + HN.NOTICE_GAP + 10)
	eq(Pick(a).frame, "bones-1", "his charm stays") eq(Pick(c).frame, "bones-2")
	for _, x in ipairs(everyone) do
		local holders = {}
		for _, p in ipairs({ a, c }) do
			for _, h in ipairs(w:As(x, x.ns.HonorsNet.Holdings, p.name)) do if h.family == "bones" then holders[#holders + 1] = h.key end end
		end
		eq(table.concat(holders, ","), "bones-1,bones-2", x.short .. ": the closed month's top 3 as it stood")
	end
	eq(w:As(d, d.ns.HonorsNet.Verified, a.name, a.guid).art, "charm-gold", "others still see it")
	for _, x in ipairs({ a, c }) do
		eq(#Said(x), 0, x.short .. ": no notice") eq(#Letters(x), 1, x.short .. ": no letter")
	end
	for _, h in ipairs(w:As(d, d.ns.HonorsNet.Holdings, d.name)) do assert(h.family ~= "bones", "this month's winner holds nothing of last month") end
	W3.NoErrors(w)
end)
