-- 1.2.4, Most Wanted's notices on the real windows: the Slayer letter in the King's letter's own
-- window (HonorsNet.lua: its "wanted@" family, its words and title Wanted.lua's, from its key), the
-- death's toast (Olympus's own window) and the avenged notice (Olympus's own dialog, Dialog.lua).
-- Every name is invented. Each of these fails on release/1.2.3 (no such letter, toast or dialog).
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local function Shown(c)
	local f = c.ns.HonorsNet.LetterFrame()
	return f ~= nil and f:IsShown() == true
end
-- A logout and a login: the release client, its save came back (Arena.Persists).
local function Kept(w, c)
	w:Logout(c)
	w:Login(c)
	W3.Rules(w, c)
	return c
end
-- Wanted.lua in a client of the test world, as its own: the TOC loads it before the arena's files,
-- which are all the world loads. Its dialogs stay off the harness's table.
local function WithWanted(w, c)
	local saved = {}
	for k, v in pairs(StaticPopupDialogs) do saved[k] = v end
	w:As(c, function() assert(loadfile(H.ADDON_DIR .. "Wanted.lua"))("Olympus", c.ns) end)
	for k in pairs(StaticPopupDialogs) do if saved[k] == nil then StaticPopupDialogs[k] = nil end end
	return c.ns.Wanted
end
-- A Slayer letter's key as a kill makes it (Bounty.LetterKey): two of ours slain, his bounty 90,
-- his level 60 (120 points), 210 in all; the Horde player of the client c's realm.
local function Key(W, c, digest)
	return W.Bounty.LetterKey({ digest = digest or "00000000000a1b2c", points = 210, level = 60, hl = 60 },
		{ victims = { {}, {} }, bounty = 90 }, "Grimtooth Gorefang-" .. c.realm)
end

print("Most Wanted: the Slayer letter and the notices (1.2.4)")

test("1.2.4 the Slayer letter is the King's letter: its window, with Wanted's words (whom he slew, how many of ours, the bounty, the level's points, the total) and its title in the profile Edit's list; once a kill; kept to read again after a relog, never opening by itself again; Wear it changes nothing; never to the King", function()
	local w, cast = W3.New()
	local A, king = Kept(w, cast.A), Kept(w, cast.king)
	local WA = WithWanted(w, A)
	local L = A.ns.L
	local key = Key(WA, A)
	eq(key:sub(1, 7), "wanted@")
	local HN = A.ns.HonorsNet
	local pick = A.ns.ArenaProfile.Pick().frame
	w:As(A, HN.QueueLetter, key)
	eq(Shown(A), true, "the King's letter's window")
	local f = HN.LetterFrame()
	eq(f.key, key)
	local text, title = w:As(A, WA.LetterText, key)
	eq(text, L.WANTED_LETTER:format("Grimtooth Gorefang", "60", 2, 90, L.WANTED_LETTER_LEVEL:format(120), 210))
	eq(f.body:GetText(), text, "Wanted's words in the King's letter")
	eq(w:As(A, HN.LetterText, key), text, "through HonorsNet's own entry point")
	eq(title, L.WANTED_LETTER_TITLE:format("Grimtooth Gorefang"))
	eq(w:As(A, HN.TitleText, key), title, "its title, as the profile Edit's list shows it")
	local list = HN.Letters()
	eq(#list, 1); eq(list[1].key, key)
	-- "Wear it": no honour is the letter's; the pick stays, and the letter closes.
	eq(w:As(A, HN.CloseLetter, true), true)
	eq(Shown(A), false); eq(A.ns.ArenaProfile.Pick().frame, pick, "nothing to wear")
	-- Once a kill: the same key again shows nothing; another kill's key, its own letter.
	w:As(A, HN.QueueLetter, key)
	eq(Shown(A), false, "told already"); eq(#HN.Letters(), 1)
	local other = Key(WA, A, "00000000000a1b2d")
	w:As(A, HN.QueueLetter, other)
	eq(Shown(A), true); eq(HN.LetterFrame().key, other); eq(#HN.Letters(), 2)
	w:As(A, HN.CloseLetter, false)
	-- A relog: nothing by itself; read again from the list (the Edit's click), the same words.
	Kept(w, A)
	WA = WithWanted(w, A)
	HN = A.ns.HonorsNet
	w:Run(HN.REFRESH_DELAY + 5)
	eq(Shown(A), false, "never again by itself"); eq(#HN.QueuedLetters(), 0)
	eq(#HN.Letters(), 2, "kept to read again")
	eq(w:As(A, HN.ShowLetter, key), true)
	eq(HN.LetterFrame().body:GetText(), text, "the same words after the relog: they are its key's")
	w:As(A, HN.CloseLetter, false)
	-- The King: no letter from himself, none kept.
	local WK = WithWanted(w, king)
	w:As(king, king.ns.HonorsNet.QueueLetter, Key(WK, king))
	eq(Shown(king), false); eq(#king.ns.HonorsNet.Letters(), 0)
	W3.NoErrors(w)
end)

-- Wanted.lua in a table of its own over the harness's namespace, its registrations kept off the
-- harness's (events, listeners, the privacy page's lines, the channel's handlers).
local function OwnWanted()
	local cns = setmetatable({}, { __index = H.ns })
	local quiet = function() end
	rawset(cns, "RegisterEvent", quiet)
	rawset(cns, "On", quiet)
	rawset(cns, "Consent", {})
	rawset(cns, "Comm", {})
	rawset(cns, "UI", {})
	local saved = {}
	for k, v in pairs(StaticPopupDialogs) do saved[k] = v end
	assert(loadfile(H.ADDON_DIR .. "Wanted.lua"))("Olympus", cns)
	local def = StaticPopupDialogs.OLYMPUS_WANTED_AVENGED
	return cns, def, function()
		for k in pairs(StaticPopupDialogs) do if saved[k] == nil then StaticPopupDialogs[k] = nil end end
	end
end

test("1.2.4 Most Wanted's notices on the real windows: the death's toast is Olympus's own metal window at the bottom centre, off the escape list, gone after its seconds; the avenged notice is Olympus's own dialog (Thank, Close, Whisper and See, See keeping it), in both input modes; never a game popup", function()
	H.WithUI(function()
		local savedPopup = StaticPopup_Show
		StaticPopup_Show = function(which) error("the game's popup: " .. tostring(which)) end
		local cns, def, Restore = OwnWanted()
		local ok, err = pcall(function()
			local timers = {}
			rawset(cns, "After", function(seconds, label, fn) timers[#timers + 1] = { seconds = seconds, label = label, fn = fn } end)
			local W = cns.Wanted
			-- The toast.
			local f = assert(W.Bounty.Toast("A death's words."), "the toast")
			eq(f.template, "DefaultPanelTemplate", "Olympus's own metal window")
			eq(f.TitleContainer.TitleText:GetText(), cns.L.TAB_WANTED, "Wanted in its title bar")
			eq(f:IsShown(), true); eq(f.text:GetText(), "A death's words.")
			local point, rel, relPoint, x, y = f:GetPoint(1)
			eq(point, "BOTTOM"); eq(rel, UIParent); eq(relPoint, "BOTTOM"); eq(x, 0); eq(y, W.Bounty.TOAST_Y, "the bottom centre")
			for _, name in ipairs(UISpecialFrames) do assert(name ~= f:GetName(), "off the escape list") end
			eq(f.CloseButton, nil, "no button")
			eq(timers[#timers].label, "wanted toast"); eq(timers[#timers].seconds, W.Bounty.TOAST_SECONDS)
			timers[#timers].fn()
			eq(f:IsShown(), false, "gone after its seconds")
			-- The avenged notice, in both input modes.
			local r = { name = "Valen Ashcroft-Realm", guild = "Olympus II", horde = "Grimtooth Gorefang-Realm", times = 2, who = "n:x" }
			for _, pad in ipairs({ false, true }) do
				GamepadStyle(pad)
				local mode = pad and "the gamepad UI" or "mouse and keyboard"
				local whispers, people = {}, {}
				cns.UI.WhisperText = function(name, text) whispers[#whispers + 1] = { name, text } return true end
				cns.UI.ShowPerson = function(p) people[#people + 1] = p return true end
				local d = assert(H.ns.Dialog.Show("OLYMPUS_WANTED_AVENGED", W.Bounty.AvengedText(r), nil, r), mode)
				eq(d.text:GetText(), cns.L.WANTED_AVENGED:format("Valen Ashcroft", "Olympus II", "Grimtooth Gorefang", cns.L.WANTED_AVENGED_TIMES:format(2)))
				eq(d.buttons[1]:GetText(), cns.L.WANTED_AVENGED_THANK); eq(d.buttons[2]:GetText(), cns.L.WANTED_AVENGED_CLOSE)
				eq(d.buttons[3]:GetText(), cns.L.WANTED_AVENGED_WHISPER); eq(d.extraButton:GetText(), cns.L.WANTED_AVENGED_SEE)
				eq(d.extraButton:IsShown(), true); eq(d.editBox:IsShown(), false, mode .. ": no edit box")
				-- See: his profile, the dialog stays.
				d.extraButton:Click()
				eq(#people, 1); eq(people[1].name, "Valen Ashcroft"); eq(people[1].guild, "Olympus II"); eq(people[1].source, "addon")
				eq(d:IsShown(), true, mode .. ": See keeps it")
				-- Thank: the thanks in Olympus's whisper window (nothing sent); the notice closes.
				d.buttons[1]:Click()
				eq(#whispers, 1); eq(whispers[1][2], cns.L.WANTED_THANK_TEXT)
				eq(d:IsShown(), false, mode .. ": answered")
				H.ns.Dialog.Reset()
			end
			GamepadStyle(false)
			eq(def.hasEditBox, nil)
		end)
		Restore()
		StaticPopup_Show = savedPopup
		if not ok then error(err, 0) end
	end)
end)
