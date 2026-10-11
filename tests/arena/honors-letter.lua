-- 1.2.1, the King's letter when an honour is earned (HonorsNet.lua): who gets it, how often, and
-- its window. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local function Short(name) return (name:gsub("%-.*$", "")) end
-- The Treasurer's donors word (ID) as client c takes it: all time's top 3, `names` in order.
local function Donors(w, c, t, names, month)
	local B36 = c.ns.Arena.B36
	local list = {}
	for i, x in ipairs(names) do list[i] = Short(type(x) == "table" and x.name or x) end
	local body = table.concat({ B36(t), B36(c.ns.Honors.MonthOf(w.clock) - 1), month or "-", #list > 0 and table.concat(list, ",") or "-" }, "~")
	eq(w:As(c, c.ns.HonorsNet.TakeDonors, N.treasurer, body), true, "the Treasurer's word taken")
end
local function Shown(c)
	local f = c.ns.HonorsNet.LetterFrame()
	return f ~= nil and f:IsShown() == true
end

print("HonorsNet: the King's letter (1.2.1)")

-- The owner after Asmon's stream (1.2.1): the King got the King's letter about a frame he holds.
test("1.2.1 the King's letter: never to the King himself: his honour switches on, no letter shows, none is kept or opens on a click; where no King is pinned, the guild master of the King's guild the same; everyone else gets his", function()
	local w, cast = W3.New({ more = { { "gm", "Bryn Halloway", { guild = World.KING_GUILD, rank = 0 } } } })
	local king, A, gm = cast.king, cast.A, cast.gm
	-- (gm's realm group has no King pinned by name: there the guild master of his guild is the King.)
	rawset(gm.ns, "KingCharacter", function() return nil end)
	eq(w:As(gm, gm.ns.King.IsKing), true, "gm is the King where no King is pinned")
	eq(w:As(king, king.ns.IsKingCharacter, king.name), true)
	for _, c in ipairs({ king, A, gm }) do Donors(w, c, w.clock, { king, A, gm }) end
	w:Run(3)
	-- The King: the cornucopia on, no letter from himself.
	eq(king.ns.ArenaProfile.Pick().frame, "donor-top-1", "his honour switched on")
	eq(Shown(king), false, "no letter from himself")
	eq(#king.ns.HonorsNet.QueuedLetters(), 0); eq(#king.ns.HonorsNet.Letters(), 0, "none kept to read again")
	eq(w:As(king, king.ns.HonorsNet.ShowLetter, "donor-top-1"), false, "nor on a click")
	w:As(king, king.ns.HonorsNet.QueueLetter, "arena-champion")
	eq(Shown(king), false); eq(#king.ns.HonorsNet.QueuedLetters(), 0, "whatever asks for one")
	eq(w:As(king, king.ns.HonorsNet.WindowShown), false, "the Olympus window opens none")
	-- The guild master of the King's guild where none is pinned: the same.
	eq(gm.ns.ArenaProfile.Pick().frame, "donor-top-3")
	eq(Shown(gm), false); eq(#gm.ns.HonorsNet.Letters(), 0)
	-- Anyone else: his letter.
	eq(Shown(A), true, "the second donor's letter")
	eq(A.ns.HonorsNet.LetterFrame().key, "donor-top-2")
	eq(#A.ns.HonorsNet.Letters(), 1)
	W3.NoErrors(w)
end)

-- The owner (1.2.1): the letter must not come back for anyone with every update. Each honour's
-- letter shows once per character, kept in his saved profile.
test("1.2.1 the King's letter: once per honour per character: never again when the honour comes back after a gap in its source, a place lost and won back, Escape, a relog; a new honour still gets its own, once", function()
	local w, cast = W3.New()
	local A, B = cast.A, cast.B
	local t = w.clock
	local function Word(names, month) t = t + 1 Donors(w, A, t, names, month) w:Run(3) end
	Word({ A })
	eq(Shown(A), true, "the first donor's letter")
	eq(A.ns.HonorsNet.LetterFrame().key, "donor-top-1")
	eq(w:As(A, A.ns.HonorsNet.CloseLetter, false), true)
	-- Out of the three (a later word), then back in: the same honour, no second letter.
	Word({ B })
	eq(A.ns.ArenaProfile.Pick().seen["donor-top"], nil, "forgotten: its source is here and names someone else")
	Word({ A })
	eq(Shown(A), false, "no second letter when it comes back")
	eq(#A.ns.HonorsNet.QueuedLetters(), 0)
	-- Second, then first again: a place won back is no new letter either.
	Word({ B, A })
	Word({ A, B })
	eq(A.ns.ArenaProfile.Pick().frame, "donor-top-1")
	eq(Shown(A), false, "no second letter for the place won back")
	eq(#A.ns.HonorsNet.Letters(), 1, "one letter kept to read again")
	-- A new honour: its own letter. Escape (or the game's window sweep) is Later: the Olympus
	-- window's open never brings it back.
	Word({ A, B }, Short(A.name))
	eq(Shown(A), true, "the month's donor: a new honour, its letter")
	local letter = A.ns.HonorsNet.LetterFrame()
	eq(letter.key, "donor-month-1")
	letter:Hide()
	local onHide = letter:GetScript("OnHide")
	assert(type(onHide) == "function", "the letter answers its own hide")
	w:As(A, onHide, letter)
	eq(#A.ns.HonorsNet.QueuedLetters(), 0, "Escape: as Later")
	eq(w:As(A, A.ns.HonorsNet.WindowShown), false)
	eq(Shown(A), false, "not with the Olympus window")
	-- A relog (the saved profile kept): nothing again; the honours told are in it.
	w:Logout(A)
	w:Login(A)
	W3.Rules(w, A)
	w:Run(A.ns.HonorsNet.REFRESH_DELAY + 5)
	eq(A.ns.ArenaProfile.Pick().frame ~= nil, true)
	eq(Shown(A), false, "nothing after a relog")
	eq(#A.ns.HonorsNet.QueuedLetters(), 0)
	local told = A.ns.ArenaProfile.Mine().lettered
	eq(told["donor-top-1"], true); eq(told["donor-month-1"], true)
	W3.NoErrors(w)
end)

-- What 1.2.0 kept tells the letters it gave: the account's profiles from before 1.2.1 (their
-- letters and seen) never show again a letter they queued, nor one for an honour held at that
-- character's first look under 1.2.1 (the safe side: its letter may have left the list of 20).
-- The update as the game does it: 1.2.0's saved data, then a login with this version.
local function Updated(w, c, profile)
	w:Logout(c)
	c.saved.db.arenaProfile = { [c.name] = profile }
	c.saved.db.honorLetters = nil
	w:Login(c)
	W3.Rules(w, c)
end

test("1.2.1 the King's letter: after the update, a letter 1.2.0 gave (read or not) never shows again, nor one for an honour held at the first look; a new honour after it gets its letter; a profile 1.2.1 made is never taken for 1.2.0's", function()
	local w, cast = W3.New({ more = { { "C", "Corin Ash" }, { "D", "Dovan Quell" }, { "E", "Elsa Brook" } } })
	local C, D, E = cast.C, cast.D, cast.E
	local now = w.clock
	-- C: the cornucopia's letter read under 1.2.0, then its family forgotten in a gap of its source.
	Updated(w, C, { seen = {}, letters = { { key = "donor-top-1", t = now - 86400, read = true } }, at = now - 86400 })
	-- D: under 1.2.0 the belt's honour remembered, its letter long gone from the list.
	Updated(w, D, { seen = { ["belt-A"] = { place = 1, frame = "arena-champion", title = "arena-champion" } }, at = now - 86400 })
	-- The first look under 1.2.1: C holds nothing yet; D the third place of all time already.
	w:As(C, C.ns.HonorsNet.Refresh)
	Donors(w, D, now, { cast.A, cast.B, D })
	w:Run(3)
	eq(Shown(C), false); eq(Shown(D), false, "held at the first look: told already (the safe side)")
	eq(D.ns.ArenaProfile.Pick().frame, "donor-top-3", "his honour still switched on")
	-- C's cornucopia back: no letter, 1.2.0 gave it.
	Donors(w, C, now + 1, { C })
	w:Run(3)
	eq(C.ns.ArenaProfile.Pick().frame, "donor-top-1")
	eq(Shown(C), false, "the letter 1.2.0 gave, not again")
	-- A new honour after the first look: its letter.
	Donors(w, D, now + 2, { cast.A, cast.B, D }, Short(D.name))
	w:Run(3)
	eq(Shown(D), true, "the month's donor, earned after the update: its letter")
	eq(D.ns.HonorsNet.LetterFrame().key, "donor-month-1")
	-- E, new under 1.2.1: his pick set before any honour makes his profile (seen, no letters);
	-- after a relog his first honour still gets its letter (that profile is 1.2.1's, not 1.2.0's).
	eq(w:As(E, E.ns.ArenaProfile.SetPick, "none"), true)
	eq(type(E.ns.ArenaProfile.Mine().seen), "table", "his profile kept")
	w:Logout(E)
	w:Login(E)
	W3.Rules(w, E)
	Donors(w, E, now + 3, { E })
	w:Run(3)
	eq(Shown(E), true, "his first honour after the relog: its letter")
	eq(E.ns.HonorsNet.LetterFrame().key, "donor-top-1")
	W3.NoErrors(w)
end)

-- The owner on Asmon's stream (1.2.1): the letter had no window round it, its words ran off the
-- paper in a small font and its two buttons sat under it. On the harness's widget toolkit (its
-- templates and anchors, a 1366 x 768 screen), every letter in English and pt-BR: the window is
-- Olympus's (ns.Window: the bronze metal, its plain corner, no portrait ring or logo), the head in
-- its title bar, the parchment inside it; the words at the letter font's 15 px (the client's
-- GetFont and SetFont, as it answers them) wrapped inside the paper, clear of the art; the seal,
-- the signature and both buttons inside the window and apart.
test("1.2.1 the King's letter: its window is Olympus's own metal with the parchment inside; the words at 15 px wrapped inside the paper, the seal, signature and both buttons inside the window, every letter in English and pt-BR", function()
	local w, cast = W3.New()
	-- (One client a language: the letter's window is made once a session, in the game's language.)
	local CLIENTS = { enUS = cast.A, ptBR = cast.B }
	local L = cast.A.ns.L
	local KEYS = { "arena-champion", "arena-class-mage-2", "arena-race-orc-3", "donor-top-1", "donor-month-2", "level-race-40", "oracle-1", "guild-top-leader" }
	local WORDS = { "HONOR_LETTER", "HONOR_LETTER_HEAD", "HONOR_LETTER_SIGN", "HONOR_LETTER_WEAR", "HONOR_LETTER_LATER", "HONOR_TITLES",
		"HONOR_CLASS_TITLE", "HONOR_RACE_TITLE", "HONOR_CLASS_NAMES", "HONOR_RACE_NAMES", "HONOR_METAL_GOLD", "HONOR_METAL_SILVER", "HONOR_METAL_BRONZE" }
	local pt = {}
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local okPt, errPt = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales/ArenaFightsText.lua"))("Olympus", { L = pt }) end)
	GetLocale = savedLocale
	assert(okPt, errPt)
	local saved = {}
	for _, k in ipairs(WORDS) do saved[k] = rawget(L, k) end
	H.WithUI(function()
		-- The client's font API on the letter's words: the font it was made with at 12 px.
		local create = CreateFrame
		local function Create(...)
			local f = create(...)
			local make = f.CreateFontString
			rawset(f, "CreateFontString", function(self, ...)
				local fs = make(self, ...)
				rawset(fs, "GetFont", function(s) return "Fonts\\FRIZQT__.TTF", s.px or 12, "" end)
				rawset(fs, "SetFont", function(s, _, px) s.px = px end)
				return fs
			end)
			return f
		end
		for _, c in pairs(CLIENTS) do c.globals.CreateFrame = Create end
		local ok, err = pcall(function()
			for _, lang in ipairs({ "enUS", "ptBR" }) do
				if lang == "ptBR" then for _, k in ipairs(WORDS) do rawset(L, k, assert(pt[k], "pt-BR " .. k)) end end
				local A = CLIENTS[lang]
				local HN = A.ns.HonorsNet
				for _, key in ipairs(KEYS) do
					local where = lang .. " " .. key
					eq(w:As(A, HN.ShowLetter, key), true, where)
					local f = HN.LetterFrame()
					eq(f.template, "DefaultPanelTemplate", where .. ": the Olympus window's metal")
					eq(f.metal, true); eq(f.NineSlice.layoutType, "ButtonFrameTemplateNoPortrait", where .. ": its plain corner, no ring")
					eq(f.PortraitContainer, nil, where .. ": no portrait of the window's own")
					eq(f.TitleContainer.TitleText:GetText(), L.HONOR_LETTER_HEAD, where .. ": the head in its title bar")
					local fl, fb, fw, fh = f:GetRect()
					local fr, ft = fl + fw, fb + fh
					assert(fb >= 0 and ft <= 768, where .. ": on the screen")
					-- The parchment: inside the metal, under the title bar; the game's QuestBG, its paper alone.
					local paper = f.bg
					local pl, pb, pw, ph = paper:GetRect()
					local pr, pt_ = pl + pw, pb + ph
					assert(pl > fl and pr < fr and pb >= fb and pt_ <= ft - H.ns.Dialog.BAR, where .. ": the parchment inside the window")
					if paper.texture and tostring(paper.texture):find("QuestBG", 1, true) then eq(paper.texCoord, "0 " .. 296 / 512 .. " 0 " .. 331 / 512, where) end
					local function Inside(region, name)
						local l, b, rw, rh = region:GetRect()
						assert(l and b, where .. ": " .. name .. " placed")
						assert(l >= pl and l + rw <= pr and b >= pb and b + rh <= pt_, ("%s: %s inside the parchment (%d %d %d %d in %d %d %d %d)"):format(where, name,
							l, b, l + rw, b + rh, pl, pb, pr, pt_))
						return l, b, l + rw, b + rh
					end
					-- The words: the letter font, 15 px, wrapped at their width; every line inside their box.
					local body = f.body
					eq(body:GetText(), (HN.LetterText(key)), where)
					eq(body.px, 15, where .. ": the words at 15 px"); eq(f.sign.px, 15, where .. ": the signature too")
					eq(body.wrap, true, where .. ": wrapped")
					local bl, bb, br, bt = Inside(body, "the words")
					local lines = 0
					for line in (body:GetText() .. "\n"):gmatch("([^\n]*)\n") do
						body.text = line
						lines = lines + math.max(1, math.ceil(body:GetUnboundedStringWidth() / (br - bl)))
					end
					body.text = HN.LetterText(key)
					assert(bt - bb >= lines * 15, ("%s: %d lines in %d px"):format(where, lines, bt - bb))
					-- Clear of the art: the portrait's slot and its reach left of the words, inside the paper.
					local rig = f.rig
					local sl, sb, sr, st = Inside(rig.slot, "the portrait")
					assert(sl - rig.reach.left >= pl and st + rig.reach.top <= pt_, where .. ": the art inside the paper")
					assert(sr + rig.reach.right <= bl, where .. ": the words right of the art")
					-- The seal and the signature under the words and the art; the buttons under them.
					local _, _, _, sealTop = Inside(f.seal, "the seal")
					local sealBottom = select(2, f.seal:GetRect())
					assert(sealTop <= bb and sealTop <= sb - rig.reach.bottom, where .. ": the seal under the words and the art")
					local sign = f.sign
					local sgr, sgt = sign:GetRight(), sign:GetTop()
					assert(sgr <= pr and sgr - sign:GetUnboundedStringWidth() >= bl - 1 and sgt <= bb, where .. ": the signature under the words, inside the paper")
					local wl, wb, wr, wt = Inside(f.wear, "Wear it")
					local ll, lb, lr, lt = Inside(f.later, "Later")
					assert(wr <= ll, where .. ": the buttons apart")
					assert(wt <= sealBottom and lt <= sealBottom, where .. ": the buttons under the seal")
					eq(wb, lb)
					for _, b in ipairs({ f.wear, f.later }) do
						assert(b:GetText() and b:GetText() ~= "", where .. ": a label")
					end
					eq(w:As(A, HN.CloseLetter, false), true)
					eq(f:IsShown(), false)
				end
			end
		end)
		for _, k in ipairs(WORDS) do rawset(L, k, saved[k]) end
		if not ok then error(err, 0) end
	end)
	W3.NoErrors(w)
end)
