-- The chat warnings (ChatStrikes.lua, the author on 2026-10-19: three warnings in 24 hours for a
-- word of Olympus's list in what a player typed): how a typed line is read against the list, and
-- what it costs. Synthetic words only (as tests/watch-chat.lua's
-- "plainword"): no real word of the list is ever written in this repository. The ladder, the report
-- to the team and every chat it covers: tests/watch-chat.lua. Every test name starts with
-- "watch: chat moderation: strikes:", so
--   OLYMPUS_TEST_WATCH_ONLY=1 luajit tests/run.lua "strikes"
-- runs them alone.
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]chat%-strikes%.lua$")) or "./"
extra = extra or {}

-- ChatWindow's own reply codec (EncodeReply, DecodeReply): the file loaded once into a namespace
-- of its own, its listeners and gamepad gate its own too (as the Chat tab's tests load it).
local codec
local function ReplyCodec()
	if codec then return codec end
	local cns = setmetatable({}, { __index = ns })
	cns.On, cns.RegisterEvent = function() end, function() end
	assert(loadfile(ROOT .. "Olympus/GamepadRegistry.lua"))("Olympus", cns)
	assert(loadfile(ROOT .. "Olympus/Gamepad.lua"))("Olympus", cns)
	assert(loadfile(ROOT .. "Olympus/ChatWindow.lua"))("Olympus", cns)
	codec = cns.ChatWindow
	return codec
end

-- ChatStrikes.lua loaded fresh into a namespace of its own over the harness's: its list holds
-- opts.words (each inserted by its real digest, S.Digest(S.Canon(w))), Sign.SHA256 counted, its
-- prints, pop-ups and saved store its own. opts.watchChat: the real WatchChat.lua too (its rooms
-- and messages kept off the harness's own).
local function Client(opts)
	opts = opts or {}
	local c = setmetatable({}, { __index = ns })
	local cl = { prints = {}, dialogs = {}, hashes = 0, clock = 1800000000 }
	c.L = ns.L
	c.me = opts.me or "Typer-Realm"
	c.rdb = { guilds = {} }
	c.On, c.Fire, c.PlayAlert = function() end, function() end, function() end
	if not opts.realLog then c.Log = function() end end
	c.Print = function(text) cl.prints[#cl.prints + 1] = tostring(text) end
	c.Now = function() return cl.clock end
	c.Data = { ServerTime = function() return cl.clock end }
	c.Comm = { Handle = function() end, Whisper = function() return true end, QueueRoom = function() return 60 end }
	c.ChatRooms = { missing = true }
	c.Sign = { SHA256 = function(m) cl.hashes = cl.hashes + 1 return ns.Sign.SHA256(m) end }
	c.ChatWindow = opts.reply and ReplyCodec() or { missing = true }
	if not opts.realDialogs then
		c.ShowDialog = function(which, a, b, data) cl.dialogs[#cl.dialogs + 1] = { which = which, a = a, data = data } return true end
	end
	if opts.watchChat then assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", c) end
	assert(loadfile(ROOT .. "Olympus/ChatStrikes.lua"))("Olympus", c)
	local S = c.ChatStrikes
	for _, w in ipairs(opts.words or {}) do
		local form = assert(S.Canon(w), w)
		S.LIST[S.Digest(form)] = #form
	end
	S.Index()
	cl.ns, cl.S = c, S
	return S, cl
end

-- StaticPopupDialogs as it was, after fn (the files loaded define their dialogs there).
local function KeepDialogs(fn)
	local saved = {}
	for k, v in pairs(StaticPopupDialogs) do saved[k] = v end
	local ok, err = pcall(fn)
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = nil end
	for k, v in pairs(saved) do StaticPopupDialogs[k] = v end
	if not ok then error(err, 0) end
end

local WORDS = { "plainword", "lowword", "pollword", "paxe", "atest" }
local LINK = "|cff1eff00|Hitem:14342::::::::60:::::|h[Plainword]|h|r"
-- Cyrillic: р а х е (all of "paxe" drawn in Cyrillic), and а alone.
local CYR_PAXE, CYR_A = "\209\128\208\176\209\133\208\181", "\208\176"

test("watch: chat moderation: strikes: matching: case, accents, digits (a 1 as i and as l), long runs, spaced or dotted letters, a zero-width character, a Cyrillic look-alike beside Latin letters and a link's text all hit", function()
	KeepDialogs(function()
		local S = Client({ words = WORDS })
		local hit = {
			["PLAINWORD"] = "plainword", ["a Plainword here"] = "plainword", ["pl\195\162inw\195\179rd"] = "pl\195\162inw\195\179rd",
			["pla1nword"] = "pla1nword", ["1owword"] = "1owword", ["pl4inw0rd"] = "pl4inw0rd", ["pl@inword"] = "plainword",
			["plaaaainword"] = "plaaaainword", ["polllword"] = "polllword", ["p l a i n w o r d"] = "p l a i n w o r d",
			["p.l.a.i.n.w.o.r.d!"] = "p l a i n w o r d", ["p-l-a-i-n-w-o-r-d"] = "p l a i n w o r d", ["p*l*a*i*n*w*o*r*d"] = "p l a i n w o r d",
			["plain\226\128\139word"] = "plainword", ["plain\194\173word"] = "plainword", ["pl" .. CYR_A .. "inword"] = "pl" .. CYR_A .. "inword",
			["pa\209\133\208\181"] = "pa\209\133\208\181", ["look " .. LINK .. " now"] = "plainword", ["pollword"] = "pollword",
		}
		for typed, word in pairs(hit) do
			local hits = S.Hits(typed)
			assert(hits, "a hit: " .. typed)
			eq(hits[1], word, "the word as typed: " .. typed)
		end
		-- Up to three words, each once.
		local many = S.Hits("plainword lowword plainword pollword paxe")
		eq(#many, 3); eq(table.concat(many, ","), "plainword,lowword,pollword")
	end)
end)

test("watch: chat moderation: strikes: matching misses: a longer word, a split in pieces of two letters, a word wholly in Cyrillic, an @mention, and a listed doubled letter typed single (never squeezed)", function()
	KeepDialogs(function()
		local S = Client({ words = WORDS })
		for _, typed in ipairs({ "plainwordy", "antiplainword", "plain word", "pl ainword", "pla inword", CYR_PAXE, "hi @test",
			"polword", "lowwordx", "p l a i n", "plainwor d", "" }) do
			eq(S.Hits(typed), nil, "no hit: " .. typed)
		end
		-- (The regression: squeezing every double made "polword" read as the listed "pollword".)
		eq(S.Hits("polword"), nil, "a single letter is another word")
		assert(S.Hits("polllword"), "three or more of a letter: squeezed to two")
		eq(S.Hits("@test"), nil, "an @mention: never an a (between two letters it is: pl@inword)")
		-- A list with nothing in it: nothing is read.
		local empty = Client()
		eq(next(empty.LIST), nil)
		eq(empty.Hits("plainword"), nil)
		eq(select(2, empty.Refuse("plainword", "A")), "plainword", "nothing refused")
	end)
end)

test("watch: chat moderation: strikes: a reply: only what he typed counts; a quote of another's line that hits is dropped and his words go alone, unwarned", function()
	KeepDialogs(function()
		local S, cl = Client({ words = WORDS, reply = true })
		local CW = ReplyCodec()
		local quoted = CW.EncodeReply({ who = "Other-Realm", text = "a plainword of theirs" }, "my clean answer")
		local why, body = S.Refuse(quoted, "A")
		eq(why, nil); eq(body, "my clean answer", "sent without the quote")
		eq(#S.Store().mine, 0, "no warning for quoting it")
		local clean = CW.EncodeReply({ who = "Other-Realm", text = "fine words" }, "my clean answer")
		eq(select(2, S.Refuse(clean, "A")), clean, "a clean reply goes as it is")
		why = S.Refuse(CW.EncodeReply({ who = "Other-Realm", text = "fine words" }, "my plainword"), "A")
		eq(why, "severe", "his own words: a warning")
		eq(#S.Store().mine, 1)
		eq(S.Store().mine[1].text, "my plainword", "the words he typed, never the quote")
		eq(cl.dialogs[#cl.dialogs].which, "OLYMPUS_WATCHCHAT_DECISION")
	end)
end)

test("watch: chat moderation: strikes: the line kept and reported is the report form, at most 140 bytes from about 40 before the word, never cut inside a character", function()
	KeepDialogs(function()
		local S = Client({ words = WORDS })
		local long = ("x\195\169y "):rep(30) .. "then a PLAINWORD said " .. ("tail words "):rep(20)
		eq(S.Refuse(long, "R:council~x"), "severe")
		local e = S.Store().mine[1]
		assert(#e.text <= 140, #e.text)
		eq(e.text:sub(1, 3), "..."); eq(e.text:sub(-3), "...")
		assert(e.text:find("then a PLAINWORD said", 1, true), e.text)
		local b = e.text:byte(4)
		assert(b < 128 or b >= 192, "starts on a character")
		eq(e.words, "plainword")
		eq(e.where, "R:R:councilx", "a room's code: letters, digits, : _ - only")
		eq(S.Refuse("|cffff0000a|r " .. WORDS[1] .. " ~ ^ |Hitem:1|h[x]|h", "A"), "severe")
		eq(S.Store().mine[2].text, "a " .. WORDS[1] .. " [x]", "no colour, link code, ~ or ^ (the report's fields)")
	end)
end)

test("watch: chat moderation: strikes: performance: a form of a length the list lacks is never hashed, and a line read again hashes nothing", function()
	KeepDialogs(function()
		local S, cl = Client({ words = { "plainword" } })
		cl.hashes = 0
		eq(S.Hits("hello there my friend, how are you"), nil)
		eq(cl.hashes, 0, "no word of nine letters: nothing hashed")
		eq(S.Hits("a sentence with ninechars inside"), nil)
		local first = cl.hashes
		assert(first > 0, "a form of the list's length is hashed")
		eq(S.Hits("a sentence with ninechars inside"), nil)
		eq(cl.hashes, first, "the same line again: nothing")
		eq(S.Hits("ninechars again, then"), nil)
		eq(cl.hashes, first, "a word already read in another line: its digest kept")
		assert(S.Hits("now a plainword"))
	end)
end)

-- (As the block terms' own check in tests/run.lua: /oly status and /oly bug never carry their words.)
test("watch: chat moderation: strikes: struck lines and their words never reach /oly status or /oly bug, refused reports neither", function()
	KeepDialogs(function()
		local S, cl = Client({ words = WORDS, watchChat = true, realLog = true })
		local secret = "zq" .. WORDS[1] .. "zq"
		eq(S.Refuse("a " .. WORDS[1] .. " " .. secret, "A"), "severe")
		cl.clock = cl.clock + 400
		eq(S.Refuse("again " .. WORDS[1] .. " " .. secret, "C"), "severe")
		-- Reports refused on a team member's client log who and why, never what they carried.
		for _, msg in ipairs({ "MS~1~L~1~1~1~3~A~" .. secret .. "~" .. secret, "MS~1~H~1~3~3~3~1~" .. secret }) do
			eq(S.Handle("WHISPER", "Sender-Realm", msg), false)
			eq(S.Handle("CHANNEL", "Sender-Realm", msg), false)
		end
		assert(#S.Store().mine == 2 and S.Store().mine[2].text:find(secret, 1, true), "kept on his own client")
		local status, bug = ns.StatusText(), ns.BuildBugReport()
		for _, word in ipairs({ WORDS[1], secret }) do
			assert(not status:find(word, 1, true), "/oly status names it: " .. word)
			assert(not bug:find(word, 1, true), "/oly bug names it: " .. word)
		end
	end)
end)

-- tests/gamepad.lua's rule for every Blizzard-facing change: under the gamepad UI each pop-up of
-- this file goes through ns.ShowDialog to Olympus's own window (Dialog.lua), never the game's.
if extra.WithUI and extra.WithGamepadUI then
	test("watch: chat moderation: strikes: under the gamepad UI the warning's pop-up and the team's dialog are Olympus's own windows, never the game's popups", function()
		KeepDialogs(function()
			extra.WithUI(function()
				extra.WithGamepadUI(true, function(game)
					local S, cl = Client({ words = WORDS, watchChat = true, realDialogs = true })
					eq(S.Refuse("a plainword", "A"), "severe")
					eq(#game.shown, 0, "no game popup")
					local f = ns.Dialog.Find("OLYMPUS_WATCHCHAT_DECISION")
					assert(f and f:IsShown(), "the warning in Olympus's window")
					assert(f.text:GetText():find(ns.L.WATCHCHAT_STRIKE_1:sub(1, 30), 1, true), f.text:GetText())
					f:Hide()
					S.Store().cases["x#1"] = { name = "Other-Realm", id = 1, n = 3, c24 = 3, c30 = 3, heard = 1,
						lines = { { at = 1, n = 3, where = "A", words = "plainword", text = "a plainword" } } }
					S.Ask("x#1")
					local d = ns.Dialog.Find("OLYMPUS_WATCHCHAT_STRIKE")
					assert(d and d:IsShown(), "the team's dialog in Olympus's window")
					eq(d.buttons[1]:GetText(), ns.L.WATCHCHAT_STRIKE_LET); eq(d.buttons[3]:GetText(), ns.L.WATCHCHAT_STRIKE_SHOW)
					eq(#game.shown, 0)
					d:Hide()
					eq(cl.ns.ChatStrikes, S)
				end)
			end)
		end)
	end)
end
