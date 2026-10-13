-- 1.2.3, the author's measure on his game with 1.2.2 (a profiler of his reading collectgarbage("count")
-- around every ns.SafeCall, for 50 minutes): each redraw of the Chat tab made about 2.5 MB of garbage,
-- one every second or two while it showed a busy channel, and each redraw of the window (UI.Refresh)
-- about 0.5 MB; the Lua heap's peaks were his worry ("the addon must not hurt the game"). Here the
-- Lua heap itself counts what they allocate (collectgarbage("count"), the collector stopped), the
-- widget toolkit's stand-ins left out: in the game a frame's methods are the client's, in C, and
-- make no Lua garbage. LuaJIT's sizes are not Lua 5.1's: the tests compare redraws with each other.
local ns, test, eq, h = ...

-- KB allocated while fn runs by everything but the widget toolkit's stand-in methods (each line
-- charged to the function it runs in: a stand-in's own lines, and what they call, are left out).
local function Allocated(fn)
	local standIn = {}
	for _, f in pairs(h.Widget) do if type(f) == "function" then standIn[f] = true end end
	local meta = UIParent and getmetatable(UIParent)
	if meta and type(meta.__index) == "function" then standIn[meta.__index] = true end
	if type(CreateFrame) == "function" then standIn[CreateFrame] = true end
	local count, getinfo = collectgarbage, debug.getinfo
	local kb, last, inStandIn = 0, nil, false
	local function Hook(event)
		local now = count("count")
		if last and not inStandIn then kb = kb + now - last end
		local info = getinfo(event == "return" and 3 or 2, "f")
		inStandIn = info ~= nil and standIn[info.func] == true
		last = count("count")
	end
	local jitWas = jit and jit.status and jit.status()
	if jit then jit.off(); jit.flush() end
	collectgarbage("collect"); collectgarbage("stop")
	debug.sethook(Hook, "lr")
	local ok, err = pcall(fn)
	debug.sethook()
	local now = count("count")
	if last and not inStandIn then kb = kb + now - last end
	collectgarbage("restart")
	if jit and jitWas then jit.on() end
	if not ok then error(err, 0) end
	return kb
end

local T0 = h.T0
local LINK = "|cff1eff00|Hitem:14342::::::::60:::::|h[Mooncloth]|h|r"
local WORDS = { "hello", "anyone", "selling", "Mooncloth", "LFG", "Scholomance", "need", "healer", "tank", "for", "the", "raid",
	"tonight", "Olympus", "guild", "join", "please", "thanks", "price", "Orgrimmar", "Stormwind", "quest", "help", "spam" }
local GUILDS = { "Olympus II", "Olympus", "Olympus III" }
local CLASSES = { "WA", "PA", "MA", "PR", "RO", "DR", "HU", "WL", "SH" }

local function Line(t, sender, guild, class, text, extra)
	local e = { t = t, sender = sender, guild = guild, class = class, text = text }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

-- A busy channel's 100 lines: thirty writers in three guilds (the King's one), some of each a
-- link or a colour code another client sent, the block terms hiding a few, ours among them.
local function History(n)
	local list = {}
	for i = 1, n do
		local words = {}
		for k = 1, 4 + (i * 7) % 30 do words[k] = WORDS[(i * 13 + k * 5) % #WORDS + 1] end
		if i % 9 == 0 then words[#words + 1] = LINK end
		if i % 11 == 0 then words[#words + 1] = "|cffff0000fake|r" end
		local who = (i * 7) % 30 + 1
		local mine = i % 17 == 0
		list[i] = Line(T0 + i * 20, mine and ns.me or ("Writer" .. who .. "-Realm"), GUILDS[who % 3 + 1], CLASSES[who % 9 + 1],
			table.concat(words, " "), { mine = mine or nil, id = i })
	end
	return list
end

-- What the author's game has around those lines: the High Council's list naming two writers, his
-- own block terms and the shared ones, a moderator's word on someone (the history is filtered
-- then), the class colours. Undone by the function returned.
local function Realistic()
	local saved = { colours = RAID_CLASS_COLORS, words = ns.db.filterWords, shared = ns.rdb.filterShared, council = ns.rdb.council,
		netoff = ns.rdb.netoff }
	RAID_CLASS_COLORS = { WARRIOR = { colorStr = "ffc79c6e" }, PALADIN = { colorStr = "fff58cba" }, MAGE = { colorStr = "ff69ccf0" },
		PRIEST = { colorStr = "ffffffff" }, ROGUE = { colorStr = "fffff569" }, DRUID = { colorStr = "ffff7d0a" } }
	ns.db.filterWords = { spam = true }
	ns.rdb.filterShared = { slur = { on = true, at = T0, by = "Asmongold Asmongler-Realm" } }
	ns.rdb.council = { at = 1, names = { writer3 = "Writer3", writer7 = "Writer7" } }
	ns.rdb.netoff = { c = { ["zeusy-realm"] = { name = "Zeusy-Realm", off = true, at = T0, by = "Asmongold Asmongler-Realm", reason = "spam" } }, g = {} }
	ns.Fire("NETOFF_CHANGED")
	return function()
		RAID_CLASS_COLORS, ns.db.filterWords, ns.rdb.filterShared, ns.rdb.council = saved.colours, saved.words, saved.shared, saved.council
		ns.rdb.netoff = saved.netoff
		ns.Fire("NETOFF_CHANGED")
	end
end

-- The tab's lines as they show, top to bottom: each bubble's words, header (name, time, the name
-- a whisper goes to and its tooltip's), width, height, side and place, its line; each grey row's
-- words and place.
local function Drawn(f)
	local out = {}
	for _, b in ipairs(f.bubbles) do
		if b:IsShown() then
			local a = b:Anchor("TOPLEFT") or b:Anchor("TOPRIGHT")
			local head = b.header:IsShown()
			out[#out + 1] = table.concat({ "bubble", tostring(b.body:GetText()), tostring(b.body:GetWidth()), tostring(head),
				head and tostring(b.who:GetText()) or "", head and tostring(b.time:GetText()) or "",
				head and tostring(b.header.whisper) or "", head and tostring(b.header.full) or "", tostring(b:GetWidth()),
				tostring(b:GetHeight()), a[1], tostring(a[5]), tostring(b.entry and b.entry.text), tostring(b.hidden) }, " / ")
		end
	end
	for _, r in ipairs(f.rows) do
		if r:IsShown() then
			local a = r:Anchor("TOPLEFT")
			out[#out + 1] = table.concat({ "row", tostring(r.text:GetText()), tostring(a and a[5]) }, " / ")
		end
	end
	return out
end

local function SameDrawn(got, want, what)
	eq(#got, #want, what .. ": parts drawn")
	for i = 1, #want do eq(got[i], want[i], what .. ": part " .. i) end
end

-- What a redraw that works every line out again draws (every look forgotten: a new era, every
-- bubble laid out whole).
local function Fresh(w)
	w.CW.ForgetLooks()
	w.CW.Render()
	return Drawn(w.CW.Frame())
end

-- The window with the tab open on a realistic channel, its clock the test's (w.tick moves it).
local function WithChannel(fn, closed)
	h.WithWindow(function(w)
		local undo = Realistic()
		local ok, err = pcall(function()
			w.clock = 1000
			GetTime = function() return w.clock end
			w.list = History(100)
			ns.rdb.chat = { A = w.list }
			if not closed then w.f = w.CW.Open("A") end
			w.tick = function(s)
				w.clock = w.clock + s
				w.f:Fire("OnUpdate", s)
			end
			-- A line that came: the oldest goes (the channel keeps 100), the tab hears it and its
			-- throttle draws it.
			w.arrive = function(text, sender, guild, class, extra)
				table.remove(w.list, 1)
				local e = Line(w.list[#w.list].t + 20, sender or "Newcomer-Realm", guild or "Olympus II", class or "PA", text, extra)
				w.list[#w.list + 1] = e
				w.fire("CHAT_CHANGED", "A"); w.fire("CHAT_LINE", "A", e.sender, e.text)
				w.tick(0.3)
				return e
			end
			fn(w)
		end)
		undo()
		if not ok then error(err, 0) end
	end)
end

test("1.2.3 memory: the Chat tab redrawn for lines that came (its throttle) makes a twentieth of the garbage of its opening at most, and a redraw that works every line out again a tenth, on a busy channel's 100 lines (thirty writers, three guilds, links, a councillor, the block terms, a moderator's word, our own lines)", function()
	WithChannel(function(w)
		local opening = Allocated(function() w.f = w.CW.Open("A") end)
		w.arrive("first of the warm-up")
		local came = Allocated(function() w.arrive("a line that came") end)
		local five = Allocated(function() for k = 1, 5 do w.arrive("burst " .. k, "Burst" .. k .. "-Realm") end end) / 5
		local direct = Allocated(function() w.CW.Render() end)
		w.fire("DATA_CHANGED")
		local census = Allocated(function() w.tick(5.1) end) -- (DATA_GAP: the census redraws the tab at most that often)
		-- (1.2.2 here: a line 198 KB, each of five 174 KB, a direct redraw 196 KB, the census's 196 KB, the
		-- opening 1062 KB; on the author's game each redraw 2.5 MB, the census and WarSquads' leaders read
		-- for every room of the destinations: tests/squads.lua.)
		assert(came * 20 <= opening, ("a line that came %.1f KB, the opening %.1f KB"):format(came, opening))
		assert(five * 20 <= opening, ("each of five lines %.1f KB, the opening %.1f KB"):format(five, opening))
		assert(direct * 10 <= opening, ("a direct redraw %.1f KB, the opening %.1f KB"):format(direct, opening))
		assert(census * 10 <= opening, ("the census's redraw %.1f KB, the opening %.1f KB"):format(census, opening))
	end, true)
end)

test("1.2.3 memory: what the Chat tab draws for lines that came is what a redraw working every line out again draws: new writers and the same one again, ours, links, the block terms, a deletion, a moderator's word, the guild names hidden, a search, a revealed line", function()
	WithChannel(function(w)
		local CW = w.CW
		local function Same(what)
			local got = Drawn(w.f)
			SameDrawn(got, Fresh(w), what)
		end
		Same("opened")
		w.arrive("a new writer's line"); Same("a new writer")
		w.arrive("and his second", "Newcomer-Realm"); Same("his second, in his group")
		w.arrive("and a third, much later", "Newcomer-Realm"); Same("his third")
		w.arrive("ours " .. LINK, ns.me, "Olympus II", "WA", { mine = true }); Same("ours, with a link")
		w.arrive("a councillor's line", "Writer3-Realm", "Olympus", "PA"); Same("a councillor's")
		w.arrive("spam spam spam", "Spammer-Realm"); Same("a line the block terms hide")
		-- The block terms changed (their event, FILTER_CHANGED): the next throttled redraw shows it.
		ns.db.filterWords = { spam = true, healer = true }
		w.fire("FILTER_CHANGED"); w.tick(0.3); Same("the block terms changed")
		-- A line revealed by a click (its own redraw).
		local veiled
		for _, b in ipairs(w.f.bubbles) do if b:IsShown() and b.hidden then veiled = b end end
		assert(veiled, "a hidden line's bubble")
		veiled:Fire("OnMouseUp", "LeftButton"); Same("a hidden line revealed")
		-- A moderator deleted a line (WatchChat: the line marked, CHAT_CHANGED for its channel).
		local savedWC = rawget(ns, "WatchChat")
		rawset(ns, "WatchChat", { DeletedBody = function() return "|cff9d9d9d<deleted>|r" end, DeletedTip = function() end,
			StripText = function() return nil end })
		local ok, err = pcall(function()
			local e = w.list[60]
			e.del, e.delAt = true, T0
			w.fire("CHAT_CHANGED", "A"); w.tick(0.3)
			local deleted = false
			for _, b in ipairs(w.f.bubbles) do if b.entry == e then deleted = b.body:GetText() == "|cff9d9d9d<deleted>|r" end end
			assert(deleted, "the deletion shows at the next throttled redraw")
			Same("a deletion")
		end)
		rawset(ns, "WatchChat", savedWC)
		if not ok then error(err, 0) end
		w.list[60].del = nil
		w.fire("CHAT_CHANGED", "A"); w.tick(0.3); Same("the deletion's mark gone")
		-- A moderator's word on a writer (NETOFF_CHANGED): his lines leave the history.
		local before = #Drawn(w.f)
		ns.rdb.netoff = { c = { ["writer8-realm"] = { name = "Writer8-Realm", off = true, at = T0, by = "Asmongold Asmongler-Realm", reason = "spam" } }, g = {} }
		w.fire("NETOFF_CHANGED"); w.tick(0.3)
		assert(#Drawn(w.f) < before, "his lines gone")
		Same("a moderator's word")
		-- The guild names hidden and shown again (the gear: Channels.SetGuildNamesShown, and its
		-- CHAT_SETTINGS_CHANGED, given to this tab's own listeners here).
		ns.Channels.SetGuildNamesShown(false); w.fire("CHAT_SETTINGS_CHANGED"); w.tick(0.3); Same("the guild names hidden")
		ns.Channels.SetGuildNamesShown(true); w.fire("CHAT_SETTINGS_CHANGED"); w.tick(0.3); Same("shown again")
		-- A search typed in the tab's box, and emptied.
		w.f.search:SetText("healer"); w.f.search:Fire("OnTextChanged"); w.tick(0.3)
		assert(#Drawn(w.f) < before, "the search keeps fewer lines")
		Same("a search")
		w.arrive("a healer is here", "Healer-Realm"); Same("a line found by the search")
		w.f.search:SetText(""); w.f.search:Fire("OnTextChanged"); w.tick(0.3); Same("the search emptied")
	end)
end)

test("1.2.3 memory: nothing the Chat tab draws is older than ERA_MAX (the census's redraw, DATA_GAP), whatever changed without telling it; a click redraws at once", function()
	WithChannel(function(w)
		local CW = w.CW
		eq(CW.ERA_MAX, 60, "1.2.4: background census work is refreshed once a minute")
		local function Header(sender)
			for _, b in ipairs(w.f.bubbles) do
				if b:IsShown() and b.entry and b.entry.sender == sender and b.header:IsShown() then return b.who:GetText() end
			end
		end
		w.arrive("a line of a writer about to be named", "Writer5-Realm", "Olympus III", "MA")
		local plain = Header("Writer5-Realm")
		assert(plain and not plain:find(ns.HIGH_COUNCIL_COLOR, 1, true), "not a councillor yet")
		-- The council's list names him, and nothing tells the tab: within ERA_MAX of the era's
		-- start, a line that came keeps the era's names; past it, his name in the council's colour.
		ns.rdb.council.names.writer5 = "Writer5"
		w.tick(CW.ERA_MAX)
		w.arrive("one more line", "Writer5-Realm", "Olympus III", "MA")
		assert(Header("Writer5-Realm"):find(ns.HIGH_COUNCIL_COLOR, 1, true), "past ERA_MAX: the council's colour")
		SameDrawn(Drawn(w.f), Fresh(w), "as a redraw working it all out")
		-- Off the list again: a click (a direct redraw) shows it at once.
		ns.rdb.council.names.writer5 = nil
		CW.Render()
		assert(not Header("Writer5-Realm"):find(ns.HIGH_COUNCIL_COLOR, 1, true), "a direct redraw: at once")
		-- The census's redraw (DATA_CHANGED, DATA_GAP after the last) starts a new era too.
		ns.rdb.council.names.writer5 = "Writer5"
		w.fire("DATA_CHANGED"); w.tick(CW.ERA_MAX + 0.1)
		assert(Header("Writer5-Realm"):find(ns.HIGH_COUNCIL_COLOR, 1, true), "the census's redraw")
	end)
end)

test("1.2.3 memory: a moderator's word is asked about each line of the Chat tab's history once an era (Channels.History's memo), not at every redraw: a line that came is asked about alone", function()
	WithChannel(function(w)
		local M = ns.Moderation
		local real, asked = M.Hides, 0
		M.Hides = function(sender, guild, look)
			if not look then asked = asked + 1 end -- (the history's: the names' marks look with `look`)
			return real(sender, guild, look)
		end
		local ok, err = pcall(function()
			assert(M.Any(), "a word is out: the history is filtered")
			w.CW.Render()
			eq(asked, 100, "a new era (a direct redraw): every line of the history")
			asked = 0
			w.arrive("a line that came")
			eq(asked, 1, "a line that came: that line alone")
			asked = 0
			w.tick(w.CW.ERA_MAX); w.arrive("another, an era later")
			-- At the one-minute navigation deadline the ticker first redraws all 100 retained
			-- lines; the subsequent new line then needs only its own moderation lookup.
			eq(asked, 101, "scheduled navigation redraw, then only the new line")
		end)
		M.Hides = real
		if not ok then error(err, 0) end
	end)
end)

test("1.2.3 memory: the block terms fold a text once (Filter.WordsOf keeps the words of the texts asked lately: WORDS_KEPT, and as many asked before them), the same words each time, and forget them past that", function()
	local F = ns.Filter
	local text = "Hello |cff1eff00|Hitem:14342::::::::60:::::|h[Mooncloth]|h|r \195\128BC spam\226\128\166end"
	local first = F.WordsOf(text)
	eq(table.concat(first, ","), "hello,mooncloth,\195\160bc,spam,end", "a link's words, folded, the punctuation a gap")
	eq(F.WordsOf(text), first, "asked again: the list kept")
	assert(Allocated(function() for _ = 1, 100 do F.WordsOf(text) end end) < 1, "asked again: nothing made")
	for i = 1, F.WORDS_KEPT do F.WordsOf("filler " .. i) end
	eq(F.WordsOf(text), first, "still kept with WORDS_KEPT others asked since")
	for i = 1, 2 * F.WORDS_KEPT + 1 do F.WordsOf("more filler " .. i) end
	local again = F.WordsOf(text)
	assert(again ~= first, "forgotten past twice WORDS_KEPT others")
	eq(table.concat(again, ","), table.concat(first, ","), "worked out again: the same words")
	-- The verdicts, as before: a term of the player's own list, a shared one switched on, neither.
	local saved = { words = ns.db.filterWords, shared = ns.rdb.filterShared }
	ns.db.filterWords, ns.rdb.filterShared = { mooncloth = true }, { ["\195\160bc"] = { on = true } }
	local ok, err = pcall(function()
		eq(F.Hit(text), "mooncloth"); eq(F.Hit("abc \195\128BC"), "\195\160bc"); eq(F.Hit("nothing here"), nil)
		eq(F.Hit("abc \195\128BC", true), nil, "the player's own list alone")
	end)
	ns.db.filterWords, ns.rdb.filterShared = saved.words, saved.shared
	if not ok then error(err, 0) end
end)

-- A census of `n` guilds more, each with its zones (Data.Summary's tables grow with them).
local function BigCensus(n)
	local now = os.time()
	for g = 1, n do
		local zones = {}
		for z = 1, 8 do zones["m" .. (1400 + (g * 3 + z) % 60)] = (g + z) % 9 + 1 end
		ns.rdb.guilds["Olympus " .. (100 + g)] = { total = 100 + g, online = 20 + g % 30, zones = zones, t = now - g, leader = "Lead" .. g,
			leaderOnline = g % 2 == 0, officers = {}, top = {}, avgLevel = 14 }
	end
end

test("1.2.3 memory: the window's redraw (UI.Refresh) sums the census once, for its header and its tab both (Views.Build takes the header's summary); on the Chat tab it makes little more than that summary; the Census and the Realm list what they listed", function()
	h.WithWindow(function(w)
		BigCensus(60)
		local Data = ns.Data
		local real, summaries = Data.Summary, 0
		Data.Summary = function(...) summaries = summaries + 1; return real(...) end
		local ok, err = pcall(function()
			for _, tab in ipairs({ "chat", "census", "realm" }) do
				w.UI.SelectTab(tab)
				summaries = 0
				ns.Views.Build(tab)
				local tabAlone = summaries
				summaries = 0
				w.UI.Refresh()
				eq(summaries, tabAlone, tab .. ": the header sums the census for the tab too (once more before)")
				if tab ~= "realm" then eq(summaries, 1, tab .. ": once a redraw") end -- (a Realm page may read it again)
			end
			for _, tab in ipairs({ "census", "realm" }) do
				local function Texts(lines)
					local out = {}
					for _, line in ipairs(lines) do out[#out + 1] = tostring(line.text) .. "|" .. table.concat(line.cols or {}, "|") end
					return table.concat(out, "\n")
				end
				eq(Texts(ns.Views.Build(tab, real())), Texts(ns.Views.Build(tab)), tab .. ": the same lines from the header's summary")
			end
			w.UI.SelectTab("chat")
			local summary = Allocated(function() real() end)
			local refresh = Allocated(function() w.UI.Refresh() end)
			assert(refresh <= summary * 1.25 + 8, ("the Chat tab's window redraw %.1f KB, a summary %.1f KB"):format(refresh, summary))
		end)
		Data.Summary = real
		if not ok then error(err, 0) end
	end)
end)

test("1.2.3 memory: the Chat tab's ticker (OnUpdate, a look every 0.2 s while it shows) makes next to nothing while no line comes, on a channel or on a room", function()
	WithChannel(function(w)
		local channel = Allocated(function() for _ = 1, 50 do w.tick(0.3) end end)
		eq(w.CW.SelectLogical("guild"), true, "the guild's room")
		local room = Allocated(function() for _ = 1, 50 do w.tick(0.3) end end)
		-- (1.2.2 here: 9.3 KB and 56 KB; on the author's game, WarSquads' leaders read at each look, about
		-- 380 KB and 3 MB: 18 MB a minute on a room, none of it inside a ns.SafeCall his profiler counted.)
		assert(channel <= 6, ("fifty looks on a channel: %.1f KB"):format(channel))
		assert(room <= 30, ("fifty looks on a room: %.1f KB"):format(room))
	end)
end)

-- WarSquads.lua loaded beside the tab as in the game: its listeners hear what the tab hears
-- (w.fire) and what it tells reaches the tab's listeners (the game's one ns.Fire; ns.Fire is none in
-- this harness), in the King's guild with a fresh roster and the High Council's signed list naming
-- two of the writers, its squads' leaders. (Its rooms are not given to ChatRooms here, nor its
-- messages to Comm: neither outlives the test.) Returns WarSquads, what it told, and the undo.
local function WithSquads(w)
	local R = ns.Roster
	local saved = { guild = GetGuildInfo, inGuild = IsInGuild, byName = R.byName, complete = R.complete, generation = R.generation,
		guildOf = R.guild, group = R.group, faction = R.faction, at = R.snapshotAt }
	GetGuildInfo = function() return "Olympus", "Officer", 1 end
	IsInGuild = function() return true end
	ns.rdb.council.blob = "HS1~1~Alliance~Writer3-Realm,Writer7-Realm~abcdef"
	R.byName = { [ns.me] = 1 }
	for i = 1, 30 do R.byName["Writer" .. i .. "-Realm"] = 3 end
	R.complete, R.generation, R.guild, R.group, R.faction, R.snapshotAt = true, 1, "Olympus", ns.group, ns.faction, ns.Now()
	local told = {}
	local sns = setmetatable({ ChatRooms = false, Comm = { Handle = function() end, Send = function() return true end } }, { __index = ns })
	sns.On = function(name, f) w.on[name] = w.on[name] or {}; table.insert(w.on[name], f) end
	sns.Fire = function(name, ...) told[#told + 1] = name; w.fire(name, ...) end
	assert(loadfile(h.ADDON_DIR .. "WarSquads.lua"))("Olympus", sns)
	return sns.WarSquads, told, function()
		GetGuildInfo, IsInGuild, R.byName, R.complete, R.generation = saved.guild, saved.inGuild, saved.byName, saved.complete, saved.generation
		R.guild, R.group, R.faction, R.snapshotAt = saved.guildOf, saved.group, saved.faction, saved.at
	end
end

-- 1.2.3, the review of the Chat tab's eras: on the author's game the census tells DATA_CHANGED every
-- second or so (Data.NOTIFY_GAP; 891 census redraws in his 50 minutes), and WarSquads told
-- CHAT_ROOMS_CHANGED at each: the tab started a new era 0.2 s after every notice and worked every line
-- and room out again, never waiting for its DATA_GAP (the census's own redraw, at most every 5 s).
test("1.2.3 memory: a census notice WarSquads hears (DATA_CHANGED, every second or so on the author's game) that changed no squad keeps the Chat tab's era: the next line costs what a line costs and nothing is worked out again before DATA_GAP; a squad that changed is drawn at once", function()
	WithChannel(function(w)
		local CW = w.CW
		local s, told, undo = WithSquads(w)
		local real = CW.Render
		local renders = 0
		CW.Render = function(...) renders = renders + 1; return real(...) end
		local ok, err = pcall(function()
			eq(#s.Leaders(), 2, "the council's two writers lead squads")
			-- The first notice it hears tells (what the squads were it never told), and the census's
			-- redraw comes DATA_GAP after the last.
			w.fire("DATA_CHANGED"); w.tick(CW.ERA_MAX + 0.1)
			w.arrive("warm-up")
			local plain = Allocated(function() w.arrive("a plain line") end)
			local era = CW.era
			for k = 1, #told do told[k] = nil end
			w.fire("DATA_CHANGED")
			eq(#told, 0, "a notice that changed no squad tells nothing")
			local after = Allocated(function() w.arrive("a line after a census notice") end)
			eq(CW.era, era, "the line drawn in the era it came in")
			local direct = Allocated(function() CW.Render() end)
			-- (Before, here: a line after a notice 30.6 KB, a plain one 7.4, a direct redraw 26.6; with a
			-- 150-guild census and four vouches a guild, 240, 7.4 and 236.)
			assert(after <= plain * 1.5 + 1, ("a line after a notice %.1f KB, a plain line %.1f KB"):format(after, plain))
			assert(after * 2 <= direct, ("a line after a notice %.1f KB, a direct redraw %.1f KB"):format(after, direct))
			-- A notice every second and no line: no redraw before DATA_GAP from the census's last, one at it.
			w.fire("DATA_CHANGED"); w.tick(CW.ERA_MAX + 0.1)
			renders, era = 0, CW.era
			for i = 1, 299 do
				w.tick(0.2)
				if i % 5 == 0 then w.fire("DATA_CHANGED") end
			end
			eq(renders, 0, "59 census notices in 59.8 s: no redraw")
			eq(CW.era, era, "nothing worked out again")
			w.tick(0.2); w.tick(0.2)
			eq(renders, 1, "the census's own redraw, at DATA_GAP")
			assert(CW.era ~= era, "in a new era")
			-- A squad that changed (a leader off the council's list: one squad fewer) is drawn at once,
			-- in a new era: his name has the council's colour no more.
			local function Header(sender)
				for _, b in ipairs(w.f.bubbles) do
					if b:IsShown() and b.entry and b.entry.sender == sender and b.header:IsShown() then return b.who:GetText() end
				end
			end
			w.fire("DATA_CHANGED"); w.tick(CW.ERA_MAX + 0.1)
			assert(Header("Writer7-Realm"):find(ns.HIGH_COUNCIL_COLOR, 1, true), "a councillor's line")
			renders, era = 0, CW.era
			for k = 1, #told do told[k] = nil end
			ns.rdb.council.names.writer7 = nil
			w.fire("DATA_CHANGED")
			eq(table.concat(told, " "), "SQUADS_CHANGED CHAT_ROOMS_CHANGED", "told")
			w.tick(0.2)
			eq(renders, 1, "drawn at the next look"); assert(CW.era ~= era, "in a new era")
			eq(#s.Leaders(), 1)
			assert(not Header("Writer7-Realm"):find(ns.HIGH_COUNCIL_COLOR, 1, true), "his line without the council's colour")
			SameDrawn(Drawn(w.f), Fresh(w), "as a redraw working it all out")
		end)
		CW.Render = real
		undo()
		if not ok then error(err, 0) end
	end)
end)
