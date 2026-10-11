local H = ...
local test, eq = H.test, H.eq
local ns = H.ns

print("The copies for Discord: other players' words as written, never as Discord's markup")

-- What a hostile name, guild, note or line carries: a fence that would end the copy's table, bold,
-- a masked link, a ping, a heading at a line's start.
local FENCE, BOLD, LINK = "```", "**loud**", "[free gold](http://example.invalid)"
local HOSTILE = FENCE .. " " .. BOLD .. " " .. LINK .. " @everyone"

local function Count(text, plain)
	local n, at = 0, 1
	while true do
		local a, b = text:find(plain, at, true)
		if not a then return n end
		n, at = n + 1, b + 1
	end
end

-- The copy's fences are its own (`fences` of them), no markup of the hostile text survives outside
-- its code block (inside one markup means nothing), and nobody is pinged anywhere.
local function Inert(text, fences, what)
	eq(Count(text, FENCE), fences, what .. ": only the copy's own fences\n" .. text)
	local outside = text:gsub("```.-```", "")
	assert(not outside:find(BOLD, 1, true), what .. ": no bold\n" .. text)
	assert(not outside:find("[free gold](", 1, true), what .. ": no masked link\n" .. text)
	assert(not text:find("@everyone", 1, true), what .. ": no ping\n" .. text)
end

-- One of the harness's saved tables swapped for fn's call, put back after.
local function WithRdb(key, value, fn)
	local was = ns.rdb[key]
	ns.rdb[key] = value
	local ok, err = pcall(fn)
	ns.rdb[key] = was
	if not ok then error(err, 0) end
end

test("1.2.1 leaks: Codec.Discord: markup characters escaped outside a code block, a backtick an apostrophe inside one, nobody pinged", function()
	local D = ns.Codec.Discord
	eq(D("Cap7-Realm"), "Cap7-Realm", "a realm's dash stays")
	eq(D("a note (with words)"), "a note (with words)", "parentheses stay")
	eq(D(BOLD), "\\*\\*loud\\*\\*")
	eq(D("_it_ ~~s~~ `c` \\"), "\\_it\\_ \\~\\~s\\~\\~ \\`c\\` \\\\")
	eq(D(LINK), "\\[free gold\\](http://example.invalid)")
	eq(D("<t:1:R>"), "\\<t:1:R>")
	eq(D("# heading"), "\\# heading"); eq(D("> quote"), "\\> quote"); eq(D("- list"), "\\- list"); eq(D("-# small"), "\\-# small")
	eq(D("one\ntwo|three"), "one twothree", "one line, no escape codes")
	eq(D(FENCE .. "x" .. FENCE, true), "'''x'''", "in a code block")
	eq(D(BOLD, true), BOLD, "markup means nothing inside a code block")
	eq(D("x", 3), "x", "a gsub's count passed along is no code block")
	eq(D("@everyone"), ns.Codec.NoMentions("@everyone")); eq(D("@here", true), ns.Codec.NoMentions("@here"))
	eq(D(nil), "")
end)

test("1.2.1 leaks: the census copy: a reported guild, its leader and a zone named as text never end the table or show as markup", function()
	local now = ns.Now()
	WithRdb("guilds", {
		["Olympus " .. HOSTILE] = { total = 50, online = 5, zones = { ["t" .. HOSTILE] = 5 }, t = now, leader = "Lead" .. FENCE .. BOLD },
		["Olympus Quiet"] = { total = 40, online = 4, zones = {}, t = now, leader = "Calm" },
	}, function()
		local text = ns.Data.DiscordText()
		Inert(text, 2, "census")
		assert(text:find("Olympus ''' " .. BOLD, 1, true), "the guild as written, in the table\n" .. text)
		assert(text:find("Lead'''", 1, true), "its leader too")
		assert(text:find("\\[free gold\\]", 1, true), "the zone, outside the table, escaped\n" .. text)
		assert(text:find("Olympus Quiet", 1, true) and text:find("Calm", 1, true), "the rest as before")
	end)
end)

test("1.2.1 leaks: the tabard inspection copy: names, guilds and notes never end the table, a marked guild never shows as markup", function()
	local now = ns.Now()
	WithRdb("inspect", { players = {
			Rogue = { name = "Rogue", guild = "Olympus" .. FENCE, status = "NONE", t = now, note = HOSTILE },
		}, guildMarks = { ["Olympus " .. BOLD .. " " .. LINK] = true } }, function()
		local text = ns.Inspect.DiscordText()
		Inert(text, 2, "inspection")
		assert(text:find("\\*\\*loud\\*\\*", 1, true), "the marked guild, escaped\n" .. text)
		assert(text:find("<Olympus'''>", 1, true), "the player's guild in the table\n" .. text)
	end)
end)

test("1.2.1 leaks: the loot notes copy: a note's words, its names and the points' never show as markup", function()
	local Lt = ns.Loot
	local guild = Lt.Guild()
	assert(guild, "in a guild")
	WithRdb("loot", { [ns.Fold(guild)] = {
		notes = { n1 = { t = ns.Now(), text = HOSTILE, writer = "Scribe-Realm", via = "Relay" .. BOLD .. "-Realm", to = "Taker" .. LINK } },
		points = { ["Pointy" .. BOLD .. "-Realm"] = { v = 7 } },
	} }, function()
		local ok, err = pcall(function()
			local text = Lt.DiscordText()
			Inert(text, 0, "loot")
			assert(text:find("Scribe", 1, true), "the writer\n" .. text)
			assert(text:find(ns.L.LOOT_VIA:format("Scribe", "Relay\\*\\*loud\\*\\*"), 1, true), "the officer who passed it on, escaped\n" .. text)
			assert(text:find("Pointy\\*\\*loud\\*\\*: 7", 1, true), "the points\n" .. text)
		end)
		Lt.Reset()
		if not ok then error(err, 0) end
	end)
end)

test("1.2.1 leaks: the acts log copy: what a sender sent and his name never show as markup; the screen's line as before", function()
	local e = { kind = "court", what = HOSTILE, words = "> " .. BOLD, by = "Herald" .. BOLD .. "-Realm", t = ns.Now() }
	WithRdb("acts", { e }, function()
		local text = ns.Chronicle.Text()
		Inert(text, 0, "acts")
		assert(text:find('"\\> \\*\\*loud\\*\\*"', 1, true), "the words, escaped, in our quotes\n" .. text)
		assert(text:find("Herald\\*\\*loud\\*\\*", 1, true), "the sender\n" .. text)
		assert(ns.Chronicle.Line(e):find(HOSTILE, 1, true), "the tooltip and chat line unchanged")
	end)
end)

-- The Watch's and the Judgment's files in a namespace of their own (nothing registered on the
-- harness's), the King's stream off.
local function WithWatch(fn)
	local dialogs = {}
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	local wns = setmetatable({ db = {}, rdb = { council = { names = { ["voter" .. BOLD:lower()] = true } } },
		Comm = false, Moderation = false, PlayerMenu = false, UI = false, Watch = false, Judgment = false,
		On = function() end, Fire = function() end, CouncilMasked = function() return false end,
		IsKingCharacter = function() return false end,
		IsHighCouncillor = function(name) return ns.ShortName(name) == "Voter" .. BOLD end }, { __index = ns })
	local ok, err = pcall(function()
		assert(loadfile(H.ADDON_DIR .. "Watch.lua"))("Olympus", wns)
		assert(loadfile(H.ADDON_DIR .. "Judgment.lua"))("Olympus", wns)
		fn(wns.Watch, wns.Judgment)
	end)
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = dialogs[k] end
	if not ok then error(err, 0) end
end

test("1.2.1 leaks: a Watch case's copy: the accused, the notes and the reported lines never show as markup", function()
	WithWatch(function(W)
		local now = ns.Now()
		local text = W.CaseText({ target = "Accused" .. BOLD .. "-Realm", cats = { O = 1 }, reporters = 1, firstAt = now, lastAt = now,
			reports = { { at = now, cat = "O", note = HOSTILE, reporter = "Witness-Realm", n = 1,
				lines = { { tier = "A", at = now, text = "# " .. LINK .. " @everyone" } } } } })
		Inert(text, 0, "case")
		assert(text:find(ns.L.WATCH_CASE_TITLE:format("Accused\\*\\*loud\\*\\*"), 1, true), "the accused\n" .. text)
		assert(text:find("\\# \\[free gold\\]", 1, true), "the reported line\n" .. text)
		assert(not text:find("Witness", 1, true), "still no reporter's name")
	end)
end)

test("1.2.1 leaks: a judgment's copy: the accused, his guild, the sender and the voters never show as markup", function()
	WithWatch(function(_, J)
		local now = ns.Now()
		local text = J.Text({ target = "Accused" .. LINK .. "-Realm", guild = "Olympus" .. FENCE .. BOLD, from = "Sender" .. BOLD .. "-Realm",
			cats = { O = 1 }, reporters = 1, lines = 1, at = now, closes = now + 3600, finding = "U",
			votes = { ["Voter" .. BOLD .. "-Realm"] = { v = "U", at = now } } })
		Inert(text, 0, "judgment")
		assert(text:find("Sender\\*\\*loud\\*\\*", 1, true), "the sender\n" .. text)
		assert(text:find("Voter\\*\\*loud\\*\\*", 1, true), "the voter\n" .. text)
		assert(text:find("<Olympus\\`\\`\\`\\*\\*loud\\*\\*>", 1, true), "the guild\n" .. text)
	end)
end)
