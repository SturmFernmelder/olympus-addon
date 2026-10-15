-- 1.2.4 (the author's ask): a guild's average level in the Census, a column of its own sorted by
-- its title; in the Realm, in parentheses after its Lord's online or offline, the Realm's guilds
-- following the Census's title clicked; after the free slots of Recruiting and in the copy for
-- Discord; and one of the first tie-breaks of every order of guilds. Loaded by tests/run.lua with
-- the harness's WithUI and LoadUI.
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]census%-avg%-level%.lua$")) or "./"
local WithUI, LoadUI = extra.WithUI, extra.LoadUI
local L, V, D = ns.L, ns.Views, ns.Data
local Grey, Green = V.Grey, V.Green

-- What a row shows, its colours and icons taken out.
local function Bare(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- fn with these reports as the census (every one of our own client's look: no census mark), the
-- default order, nothing typed in a search; all of it as it was afterwards.
-- (1.2.4's review: the Realm's own order too, Views.realmSort, its default.)
local function WithGuilds(guilds, fn)
	local saved = { guilds = ns.rdb.guilds, seen = ns.rdb.seen, sort = V.sort, ui = ns.UI, key = ns.rdb.realmKey,
		census = V.Filter("census"), realm = V.Filter("realm"), realmSort = V.realmSort }
	ns.rdb.guilds, ns.rdb.seen, ns.rdb.realmKey = guilds, {}, "sealed"
	V.sort, V.realmSort = { key = "members", desc = true }, "members"
	V.SetFilter("census", ""); V.SetFilter("realm", "")
	ns.UI = ns.UI or { StatusLine = function() return "status" end, Refresh = function() end }
	local ok, err = pcall(fn)
	ns.rdb.guilds, ns.rdb.seen, V.sort, ns.UI, ns.rdb.realmKey = saved.guilds, saved.seen, saved.sort, saved.ui, saved.key
	V.realmSort = saved.realmSort
	V.SetFilter("census", saved.census or ""); V.SetFilter("realm", saved.realm or "")
	if not ok then error(err, 0) end
end

local function Report(total, avgLevel, more)
	local r = { total = total, online = 10, zones = {}, t = os.time(), leader = "Lead", leaderOnline = true, officers = {}, mine = true, avgLevel = avgLevel }
	for k, v in pairs(more or {}) do r[k] = v end
	return r
end

-- The Census's guild rows (the cells as shown), and the Realm's guilds in its order.
local function CensusRows()
	local out = {}
	for _, line in ipairs(V.Build("census")) do if line.cols then out[#out + 1] = line end end
	return out
end
local function CensusNames()
	local out = {}
	for _, line in ipairs(CensusRows()) do out[#out + 1] = Bare(line.cols[1]) end
	return table.concat(out, ",")
end
local function RealmHeaders()
	local out, byName = {}, {}
	for _, line in ipairs(V.Build("realm")) do
		local name = type(line.id) == "string" and line.id:match("^guild:(.+)$")
		if name then out[#out + 1] = name; byName[name] = line end
	end
	return table.concat(out, ","), byName
end

-- The words of the client in language `code` (1.2.4's review: each of the addon's five): Locales.lua,
-- then the language's own file where it has one (ptBR's words are in Locales.lua).
local function Words(code)
	local t = {}
	local savedLocale = GetLocale
	GetLocale = function() return code end
	local ok, err = pcall(function()
		assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", t)
		if code == "deDE" or code == "esES" or code == "frFR" then assert(loadfile(ROOT .. "Olympus/Locales/" .. code .. ".lua"))("Olympus", t) end
	end)
	GetLocale = savedLocale
	if not ok then error(err, 0) end
	return t.L
end
local function Portuguese() return Words("ptBR") end

-- The Realm's line that orders its guilds (1.2.4's review), nil where it has none; and a choice of it taken.
local function OrderLine()
	for _, line in ipairs(V.Build("realm")) do if line.id == "realm-order" then return line end end
end
local function Choose(text)
	local line = assert(OrderLine(), "the Realm's order line")
	for _, o in ipairs(line.filters[1].options) do
		if o.text == text then
			assert(o.onClick, text .. ": not the order already")
			return o.onClick()
		end
	end
	error("no choice " .. text)
end

-- How much of its row a line's right text keeps, rendered in a row `width` wide (6 px a letter, as
-- the offline fonts measure), and that text's whole width.
local function Kept(line, width)
	local content = CreateFrame("Frame", nil, UIParent)
	content:SetWidth(width or 300)
	content.style = "old"
	V.Render(content, { line })
	local r = content.rows[1]
	local whole = r.right:GetUnboundedStringWidth()
	local a = r.right:Anchor("LEFT")
	return a and -(a[4] + 2) or whole, whole -- (RIGHT_INSET aside; no anchor: nothing cut, all of it kept)
end

test("1.2.4 average level: to the tenth as the census carries it, our own guild's unrounded one cut the same way; none for 0, a missing one or one no guild can have", function()
	-- Our own guild's from our roster, unrounded, and the same guild's report as another client hears it.
	local heard = assert(ns.Codec.DecodeReport(ns.Codec.EncodeReport({ guild = "Olympus Test", total = 100, online = 10, avgLevel = 47.96 })))
	eq(heard.avgLevel, 47.9, "the wire cuts it down")
	eq(D.AvgTenths({ avgLevel = 47.96 }), 479, "ours, cut the same way")
	eq(D.AvgTenths(heard), 479, "theirs")
	eq(D.AvgLevelText({ avgLevel = 47.96 }), "47.9"); eq(D.AvgLevelText(heard), "47.9")
	eq(D.AvgTenths({ avgLevel = 60 }), 600); eq(D.AvgTenths({ avgLevel = 1 }), 10); eq(D.AvgLevelText({ avgLevel = 1 }), "1.0")
	for _, v in ipairs({ 0, 0.95, 60.1, 75, 1000, -3, "abc" }) do eq(D.AvgTenths({ avgLevel = v }), nil, tostring(v)) end
	eq(D.AvgTenths({ avgLevel = 0 / 0 }), nil, "NaN"); eq(D.AvgTenths({ avgLevel = math.huge }), nil, "infinite")
	eq(D.AvgTenths({}), nil, "an older version's report"); eq(D.AvgTenths(nil), nil); eq(D.AvgLevelText({ avgLevel = 0 }), nil)
	-- In the language's own decimal mark.
	local mark = rawget(L, "DECIMAL_MARK")
	L.DECIMAL_MARK = ","
	local ok, err = pcall(function() eq(D.AvgLevelText(heard), "47,9") end)
	L.DECIMAL_MARK = mark
	if not ok then error(err, 0) end
	-- A guild by its name, from the census kept: 0 for none, so it sorts as the lowest.
	WithGuilds({ ["Olympus A"] = Report(10, 33.3) }, function()
		eq(D.AvgTenthsOf("Olympus A"), 333); eq(D.AvgTenthsOf("OLYMPUS A"), 333, "whatever the case"); eq(D.AvgTenthsOf("Olympus Z"), 0)
	end)
end)

test("1.2.4 the Census: a column for the average level between Online and the Lord, its title short in English and Portuguese, a value to the tenth, '-' for none", function()
	local cols = V.COLUMNS.census
	eq(#cols, 5)
	local keys = {}
	for i, c in ipairs(cols) do keys[i] = c.key .. ":" .. tostring(c.sort) end
	eq(table.concat(keys, ","), "COL_GUILD:name,COL_MEMBERS:members,COL_ONLINE:online,COL_AVG_LEVEL:level,COL_LORD:lord")
	eq(cols[4].justify, "RIGHT", "a number, as Members and Online")
	-- Side by side, the whole width, no column on another.
	local x = 0
	for i, c in ipairs(cols) do
		assert(math.abs(c.x - x) < 1e-9, "column " .. i .. " starts where the one before ends")
		x = c.x + c.w
	end
	assert(math.abs(x - 1) < 1e-9, "the whole width")
	assert(cols[3].w < cols[2].w, "Online narrower than Members (the smaller numbers)")
	eq(L.COL_AVG_LEVEL, "Avg lvl"); eq(L.AVG_LEVEL_TAG, "(avg lvl %s)"); eq(L.DECIMAL_MARK, ".")
	local pt = Portuguese()
	eq(pt.COL_AVG_LEVEL, "Nv. méd."); eq(pt.AVG_LEVEL_TAG:format("47,9"), "(nv. méd. 47,9)"); eq(pt.DECIMAL_MARK, ",")
	-- The rows: our own guild's unrounded one as every client has it, none as "-", the Lord after it.
	WithGuilds({
		["Olympus Own"] = Report(300, 47.96, { leader = "Ownlord" }),
		["Olympus Old"] = Report(200, 0, { leader = "Oldlord" }), -- (a version that sent none)
		["Olympus Forged"] = Report(100, 1000, { leader = "Fakelord" }), -- (the field reads up to 1000.0)
	}, function()
		local rows = CensusRows()
		eq(#rows, 3)
		eq(Bare(rows[1].cols[1]), "Olympus Own"); eq(rows[1].cols[4], "47.9"); eq(Bare(rows[1].cols[5]), "Ownlord")
		eq(rows[2].cols[4], Grey("-")); eq(rows[3].cols[4], Grey("-"), "what no guild can have is none")
		-- The hover says the same number (it said 48.0 for our own 47.96: "%.1f" of the unrounded one).
		local tip = {}
		rows[1].tooltip({ AddLine = function() end, AddDoubleLine = function(_, a, b) tip[a] = b end })
		eq(tip[L.AVG_LEVEL], "47.9")
		tip = {}
		rows[2].tooltip({ AddLine = function() end, AddDoubleLine = function(_, a, b) tip[a] = b end })
		eq(tip[L.AVG_LEVEL], nil, "none: no line, as before")
		-- The copy for Discord: the same column.
		local copy = D.DiscordText()
		assert(copy:find("Members  *Online  *Avg lvl  *Leader"), copy)
		assert(copy:find("Olympus Own%s+300%s+10%s+47%.9%s+Ownlord"), copy)
		assert(copy:find("Olympus Old%s+200%s+10%s+%-%s+Oldlord"), copy)
	end)
end)

test("1.2.4 the Census: a click on Avg lvl sorts by it, the highest first, again the lowest first; a guild without one last both ways, a tie the larger guild first", function()
	WithGuilds({
		["Olympus A"] = Report(100, 40),
		["Olympus B"] = Report(300, 55.5),
		["Olympus C"] = Report(200, 40),
		["Olympus D"] = Report(900, nil), -- (none: the largest guild)
		["Olympus E"] = Report(50, 20.04),
		["Olympus F"] = Report(800, 0),
		["Olympus Stale"] = Report(950, 60, { t = os.time() - D.FRESH - 1 }),
	}, function()
		-- By default: fresh first, the larger first.
		eq(CensusNames(), "Olympus D,Olympus F,Olympus B,Olympus C,Olympus A,Olympus E,Olympus Stale")
		V.SortBy("level")
		eq(V.sort.key, "level"); eq(V.sort.desc, true, "a first click: the highest first")
		eq(CensusNames(), "Olympus B,Olympus C,Olympus A,Olympus E,Olympus D,Olympus F,Olympus Stale",
			"55.5, then 40 twice (200 members before 100), 20.0; none last; an old report after every current one")
		V.SortBy("level")
		eq(V.sort.desc, false)
		eq(CensusNames(), "Olympus E,Olympus C,Olympus A,Olympus B,Olympus D,Olympus F,Olympus Stale",
			"the lowest first; none still last, a tie still the larger guild first")
		-- Another title, back to the highest first for a count, A to Z for a name.
		V.SortBy("members"); eq(V.sort.desc, true)
		V.SortBy("name"); eq(V.sort.desc, false)
	end)
end)

test("1.2.4 tie-breaks: the higher average level first in every column's tie, whichever way it runs; the default order keeps the exact <OLYMPUS> first at the same size", function()
	WithGuilds({
		["OLYMPUS"] = Report(500, 10, { online = 50, leader = "King" }),
		["Olympus Hi"] = Report(500, 58, { online = 50, leader = "Same" }),
		["Olympus Lo"] = Report(500, 30, { online = 50, leader = "same" }),
		["Olympus None"] = Report(500, nil, { online = 50, leader = "Same" }),
		["Olympus Few"] = Report(100, 59, { online = 5, leader = "Zed" }),
	}, function()
		-- The shared order (1.1.5): the standard-bearer at the same size, then the higher average level.
		eq(CensusNames(), "OLYMPUS,Olympus Hi,Olympus Lo,Olympus None,Olympus Few")
		eq((RealmHeaders()), "OLYMPUS,Olympus Hi,Olympus Lo,Olympus None,Olympus Few", "the Realm in the same order")
		local names = {}
		for i, e in ipairs(D.Summary().guilds) do names[i] = e.name end
		eq(table.concat(names, ","), "OLYMPUS,Olympus Hi,Olympus Lo,Olympus None,Olympus Few", "Data.Summary's")
		-- Members the other way: the smallest first; as many, the higher average level first.
		V.SortBy("members")
		eq(V.sort.desc, false)
		eq(CensusNames(), "Olympus Few,Olympus Hi,Olympus Lo,OLYMPUS,Olympus None")
		-- Online, both ways: as many online, the higher average level first.
		V.sort = { key = "online", desc = true }
		eq(CensusNames(), "Olympus Hi,Olympus Lo,OLYMPUS,Olympus None,Olympus Few")
		V.sort = { key = "online", desc = false }
		eq(CensusNames(), "Olympus Few,Olympus Hi,Olympus Lo,OLYMPUS,Olympus None")
		-- The Lord: the same name (any case), the higher average level first.
		V.sort = { key = "lord", desc = false }
		eq(CensusNames(), "OLYMPUS,Olympus Hi,Olympus Lo,Olympus None,Olympus Few")
	end)
end)

test("1.2.4 the Realm: its guilds' average level in parentheses after their Lord's online or offline, kept whole; its guilds in its own order, chosen on its line, the average level's among them", function()
	WithGuilds({
		["Olympus Big"] = Report(900, 31.25, { leader = "Bigboss", leaderOnline = true }),
		["Olympus Mid"] = Report(500, 52, { leader = "Midboss", leaderOnline = false, leaderDays = 0 }),
		["Olympus Small"] = Report(100, nil, { leader = "Smallboss", leaderOnline = false, leaderDays = 5 }),
		["Olympus Grey"] = Report(50, 44, { leader = "Greyboss", leaderOnline = false, leaderDays = 0, t = os.time() - D.FRESH - 1 }),
	}, function()
		local order, header = RealmHeaders()
		eq(order, "Olympus Big,Olympus Mid,Olympus Small,Olympus Grey", "by default the shared order, as before")
		eq(header["Olympus Big"].right, Green(L.ONLINE_NOW) .. "  " .. Grey("(avg lvl ") .. "31.2" .. Grey(")"),
			"its Lord online, then the average level: the number white, its words grey")
		eq(Bare(header["Olympus Mid"].right), L.OFFLINE_TODAY .. "  (avg lvl 52.0)")
		eq(Bare(header["Olympus Small"].right), L.OFFLINE_DAYS:format(5) .. " !", "none: nothing after it")
		eq(header["Olympus Grey"].right, Grey(L.OFFLINE_TODAY) .. "  " .. Grey("(avg lvl 44.0)"), "an old report: all grey")
		for name, line in pairs(header) do eq(line.rightWide, true, name) end
		-- The hover as ever (the same number).
		local tip = {}
		header["Olympus Big"].tooltip({ AddLine = function() end, AddDoubleLine = function(_, a, b) tip[a] = b end })
		eq(tip[L.AVG_LEVEL], "31.2")
		-- (Changed on purpose, 1.2.4's review: the Realm's guilds followed the title last clicked in the
		-- Census, unseen on the Realm, and only the Census could put them back. The Realm has its own
		-- order now, on its own line, and a title clicked in the Census leaves it as it was.)
		V.SortBy("level")
		eq((RealmHeaders()), "Olympus Big,Olympus Mid,Olympus Small,Olympus Grey", "the Census's title clicked: the Realm as it was")
		V.SortBy("name")
		eq((RealmHeaders()), "Olympus Big,Olympus Mid,Olympus Small,Olympus Grey")
		V.sort = { key = "members", desc = true }
		-- Its line, above its guilds: the shared order by default; its choices the Census's five columns.
		local line = OrderLine()
		assert(line, "the order line")
		local lines, at, first = V.Build("realm"), nil, nil
		for i, l in ipairs(lines) do
			if l.id == "realm-order" then at = i end
			if not first and type(l.id) == "string" and l.id:match("^guild:") then first = i end
		end
		eq(at, first - 1, "right above the first guild")
		local f = line.filters[1]
		eq(f.label, L.REALM_ORDER); eq(f.value, L.COL_MEMBERS); eq(f.understated, true)
		local choices = {}
		for i, o in ipairs(f.options) do choices[i] = o.text .. (o.selected and "*" or "") .. (o.onClick and "" or "-") end
		eq(table.concat(choices, ","), table.concat({ L.COL_MEMBERS .. "*-", L.COL_ONLINE, L.AVG_LEVEL, L.COL_GUILD, L.COL_LORD }, ","),
			"the order in use chosen, nothing to do on it")
		-- The average level chosen: the highest first, none last, an old report after every current one;
		-- the Census's own order as it was.
		local refreshed = 0
		ns.UI = { StatusLine = function() return "status" end, Refresh = function() refreshed = refreshed + 1 end }
		Choose(L.AVG_LEVEL)
		eq(refreshed, 1, "redrawn")
		eq(V.realmSort, "level")
		eq((RealmHeaders()), "Olympus Mid,Olympus Big,Olympus Small,Olympus Grey")
		eq(OrderLine().filters[1].value, L.AVG_LEVEL, "the line says it")
		eq(V.sort.key, "members"); eq(CensusNames(), "Olympus Big,Olympus Mid,Olympus Small,Olympus Grey", "the Census as it was")
		-- A search's guilds in it too (no line over them).
		V.SetFilter("realm", "olympus")
		eq((RealmHeaders()), "Olympus Mid,Olympus Big,Olympus Small,Olympus Grey"); eq(OrderLine(), nil, "no line over a search")
		V.SetFilter("realm", "")
		-- By the Lord, A to Z; then back to the shared order.
		Choose(L.COL_LORD)
		eq((RealmHeaders()), "Olympus Big,Olympus Mid,Olympus Small,Olympus Grey")
		Choose(L.COL_MEMBERS)
		eq(V.realmSort, "members"); eq((RealmHeaders()), "Olympus Big,Olympus Mid,Olympus Small,Olympus Grey")
	end)
	-- One guild: nothing to order, no line.
	WithGuilds({ ["Olympus Alone"] = Report(100, 30) }, function() eq(OrderLine(), nil) end)
end)

test("1.2.4 the Realm's guild header: a long guild and Lord give way to its online and average level, kept whole up to half the row (a third for other rows)", function()
	WithUI(function()
		WithGuilds({
			["Olympus Brotherhood Of Ages"] = Report(900, 47.9, { leader = "Longestlordname", leaderOnline = false, leaderDays = 0 }),
		}, function()
			local _, header = RealmHeaders()
			local line = header["Olympus Brotherhood Of Ages"]
			assert(line, "its header")
			local function Kept(l)
				local content = CreateFrame("Frame", nil, UIParent)
				content:SetWidth(300)
				content.style = "old"
				V.Render(content, { l })
				local a = content.rows[1].right:Anchor("LEFT")
				return a and -(a[4] + 2) or nil -- (how much of the row its right text keeps, RIGHT_INSET aside)
			end
			-- (6 px a letter, as the offline fonts measure: "offline today  (avg lvl 47.9)", 174 px;
			-- the row's room 288 px, its left text far wider.)
			local room = 300 - 4 - 6 - 2
			eq(Kept(line), math.floor(room / 2), "half the row")
			local plain = {}
			for k, v in pairs(line) do plain[k] = v end
			plain.rightWide = nil
			eq(Kept(plain), math.floor(room / 3), "another row: a third, as before")
		end)
	end)
end)

test("1.2.4 Recruiting and the zones: as many free slots, or soldiers in a zone, the higher average level first; its average level after its free slots", function()
	local zones = { m1453 = 20 }
	WithGuilds({
		["Olympus Q"] = Report(600, 25, { zones = zones }),
		["Olympus R"] = Report(600, 45, { zones = zones }),
		["Olympus S"] = Report(600, nil, { zones = zones }),
		["Olympus T"] = Report(100, 10, { zones = { m1453 = 30 } }),
	}, function()
		local open = V.OpenGuilds(D.Summary())
		local names = {}
		for i, o in ipairs(open) do names[i] = o.name .. "=" .. o.free end
		eq(table.concat(names, ","), "Olympus T=900,Olympus R=400,Olympus Q=400,Olympus S=400")
		-- Who recruits are sent to (Recruit.lua's route answer) goes by it too.
		names = {}
		for i, o in ipairs(ns.Recruit.OpenGuilds()) do names[i] = o.name end
		eq(table.concat(names, ","), "Olympus T,Olympus R,Olympus Q,Olympus S")
		-- The Realm's Recruiting: the free slots, then the average level (none: nothing).
		local rows = {}
		for _, line in ipairs(V.Build("realm")) do
			local name = line.text and Bare(line.text):match("^<(Olympus %a)>$")
			if name and line.right and Bare(line.right):find(L.FREE_SLOTS:format(""), 1, true) then rows[#rows + 1] = name .. ": " .. Bare(line.right) end
		end
		eq(table.concat(rows, " | "), "Olympus T: 900 free  (avg lvl 10.0) | Olympus R: 400 free  (avg lvl 45.0) | Olympus Q: 400 free  (avg lvl 25.0) | Olympus S: 400 free")
		-- The Census's search for a zone: its guilds by their soldiers there, then the average level.
		V.SetFilter("census", "stormwind")
		local lines, at = V.Build("census"), nil
		for i, line in ipairs(lines) do if line.header and Bare(line.text):find("Stormwind City", 1, true) then at = i end end
		assert(at, "the zone's header")
		-- (Changed on purpose, 1.2.4's review: its average level after its count, so that the order is
		-- seen, kept whole up to half the row; before, the count alone.)
		local found = {}
		for i = at + 1, at + 4 do
			found[#found + 1] = Bare(lines[i].text) .. " " .. Bare(lines[i].right)
			eq(lines[i].rightWide, true, Bare(lines[i].text))
		end
		eq(table.concat(found, ","), "<Olympus T> 30  (avg lvl 10.0),<Olympus R> 20  (avg lvl 45.0),<Olympus Q> 20  (avg lvl 25.0),<Olympus S> 20")
		-- The Census's "recruiting": the same order, the same words after the free slots.
		V.SetFilter("census", "recruiting")
		found = {}
		for _, line in ipairs(V.Build("census")) do
			if line.indent == 1 and line.right then found[#found + 1] = Bare(line.text) .. " " .. Bare(line.right) end
		end
		eq(table.concat(found, ","), "<Olympus T> 900 free  (avg lvl 10.0),<Olympus R> 400 free  (avg lvl 45.0),<Olympus Q> 400 free  (avg lvl 25.0),<Olympus S> 400 free")
	end)
end)

-- 1.2.4's review: Recruiting's rows (the Realm's and the Census's "recruiting" search) and a zone's
-- guilds carry their average level after their count, so their right text grew; at a third of the
-- row, as other rows keep theirs, a long guild name cut the average level off.
test("1.2.4's review: a long guild name gives way to Recruiting's free slots and average level, and a zone's count and average level, kept whole up to half the row", function()
	WithUI(function()
		WithGuilds({
			["Olympus Brotherhood Ages"] = Report(600, 45, { zones = { m1453 = 20 } }), -- (24 letters, the longest a guild's name)
		}, function()
			local function Find(lines, pred) for _, l in ipairs(lines) do if pred(l) then return l end end end
			local function Free(l) return l.right and Bare(l.right):find(L.FREE_SLOTS:format(""), 1, true) and Bare(l.text):find("Brotherhood", 1, true) end
			local realm = assert(Find(V.Build("realm"), Free), "the Realm's Recruiting row")
			eq(Bare(realm.right), "400 free  (avg lvl 45.0)")
			local kept, whole = Kept(realm)
			eq(kept, whole, "the Realm's Recruiting: its free slots and average level whole")
			-- The Census's search, its rows a step in: more of it kept than a third held. (Not all of it
			-- here: 6 px a letter make it 144 px, more than half of that row's 276; the client's font
			-- draws it narrower, an in-game check.)
			V.SetFilter("census", "recruiting")
			local census = assert(Find(V.Build("census"), Free), "the Census's recruiting row")
			eq(census.rightWide, true)
			kept, whole = Kept(census)
			local narrow = {}
			for k, v in pairs(census) do narrow[k] = v end
			narrow.rightWide = nil
			assert(kept > (Kept(narrow)), "more kept than a third: " .. kept)
			V.SetFilter("census", "stormwind")
			local zone = assert(Find(V.Build("census"), function(l) return l.indent == 1 and Bare(l.text) == "<Olympus Brotherhood Ages>" end), "the zone's row")
			eq(Bare(zone.right), "20  (avg lvl 45.0)")
			kept, whole = Kept(zone)
			eq(kept, whole, "a zone's guild: whole")
			-- (A third of the row would not hold it: the room 288 less the name's 156 leaves 132.)
			local plain = {}
			for k, v in pairs(realm) do plain[k] = v end
			plain.rightWide = nil
			kept, whole = Kept(plain)
			assert(kept < whole, "without it, the average level cut: " .. kept .. " of " .. whole)
		end)
	end)
end)

-- 1.2.4's review: the Royal Inspection's guilds broke their ties by the average level unseen, and no
-- test held that order (one guild only in the Throne's test): as many inspected, the higher average
-- level first, said after its count, kept whole up to half the row.
test("1.2.4's review: the Royal Inspection's guilds, as many inspected, the higher average level first, said after their count", function()
	local K = ns.King
	local saved = { dev = ns.devThrone, member = ns.IsMember, rank = ns.Roster.RankOf, after = ns.After, enforced = ns.Authority and ns.Authority.Enforced }
	local ok, err = pcall(function()
		WithGuilds({
			["Olympus Alpha"] = Report(100, 20), ["Olympus Beta"] = Report(100, 50), ["Olympus Many"] = Report(100, 10),
		}, function()
			K.Reset()
			ns.devThrone = true -- (the Throne's preview: the King's own page, nothing sent)
			ns.IsMember = function() return false end -- (no patrol of our own)
			ns.After = function() end
			if ns.Authority then ns.Authority.Enforced = function() return false end end
			ns.Roster.RankOf = function() return 1 end -- (each reporter one we can place in his guild)
			eq(K.CanCall(), true)
			K.Inspect()
			K.ReceiveReport("Scouta-Realm", "T3~0~Olympus Alpha~6~4~0~")
			K.ReceiveReport("Scoutb-Realm", "T3~0~Olympus Beta~3~7~0~")
			K.ReceiveReport("Scoutc-Realm", "T3~0~Olympus Many~20~0~0~")
			K.ReceiveReport("Scoutd-Realm", "T3~0~Olympus Abyss~5~5~0~") -- (no census of it: no average)
			local rows = {}
			for _, l in ipairs(K.InspectionLines()) do
				if l.indent == 2 and Bare(l.text):match("^<Olympus") then
					rows[#rows + 1] = Bare(l.text) .. " " .. Bare(l.right)
					eq(l.rightWide, true, Bare(l.text))
				end
			end
			eq(table.concat(rows, ","), "<Olympus Many> 100%  (20/20)  (avg lvl 10.0),<Olympus Beta> 30%  (3/10)  (avg lvl 50.0),"
				.. "<Olympus Alpha> 60%  (6/10)  (avg lvl 20.0),<Olympus Abyss> 50%  (5/10)", "20 first; then 10 each: 50.0, 20.0, none (by name: Abyss first)")
		end)
	end)
	ns.devThrone, ns.IsMember, ns.Roster.RankOf, ns.After = saved.dev, saved.member, saved.rank, saved.after
	if ns.Authority then ns.Authority.Enforced = saved.enforced end
	K.Reset()
	if not ok then error(err, 0) end
end)

test("1.2.4 Data.SortGuildCounts: the larger first by each count in turn, then the higher average level, then the name; a row's own census entry read first", function()
	WithGuilds({
		["Olympus A"] = Report(10, 20), ["Olympus B"] = Report(10, 50), ["Olympus C"] = Report(10, nil),
	}, function()
		local rows = { { name = "Olympus C", n = 3 }, { name = "Olympus A", n = 3 }, { name = "Olympus B", n = 3 }, { name = "Olympus Z", n = 3 },
			{ name = "Olympus Y", n = 7 } }
		D.SortGuildCounts(rows, "n")
		local names = {}
		for i, r in ipairs(rows) do names[i] = r.name .. ":" .. r.avg end
		eq(table.concat(names, ","), "Olympus Y:0,Olympus B:500,Olympus A:200,Olympus C:0,Olympus Z:0",
			"7 first; then 50.0, 20.0; none and unknown by name")
		-- Two counts (the dues: gold paid, then members), then the average level.
		rows = { { name = "Olympus A", copper = 5, members = 10 }, { name = "Olympus B", copper = 5, members = 10 },
			{ name = "Olympus C", copper = 5, members = 12 }, { name = "Olympus Z", copper = 9 } }
		D.SortGuildCounts(rows, "copper", "members")
		names = {}
		for i, r in ipairs(rows) do names[i] = r.name end
		eq(table.concat(names, ","), "Olympus Z,Olympus C,Olympus B,Olympus A")
		-- A row with its census entry (Data.Summary's, as Views.OpenGuilds keeps it): read from it.
		rows = { { name = "Olympus A", n = 1, e = { g = { avgLevel = 59 } } }, { name = "Olympus B", n = 1 } }
		D.SortGuildCounts(rows, "n")
		eq(rows[1].name .. ":" .. rows[1].avg, "Olympus A:590")
	end)
end)

-- (1.2.4's review: this test checked the titles' and cells' places with UI.Layout's and LayoutColumns'
-- own sums; now with what a player sees: the titles side by side across the list, each title's
-- words inside its own header, each number under its own title.)
-- Where the headers' templates draw their title, from their left edge (Forever 1.60.1's
-- SharedUIPanelTemplates.xml, ColumnDisplayButtonNoScriptsTemplate: <Anchor point="LEFT" x="8"/>,
-- as the old Who window's titles).
local TEXT_X = 8

-- The window's Census titles, each { left, right, text, drawn (its words' width as drawn), b }, in
-- the header row's own units.
local function Titles(main)
	local out = {}
	for i, b in ipairs(main.colHeader.buttons) do
		if b:IsShown() then
			local left = b:Anchor("TOPLEFT")[4]
			out[i] = { left = left, right = left + b:GetWidth(), text = b:GetText(), drawn = b:GetFontString():GetStringWidth(), b = b }
		end
	end
	return out
end

-- Five titles side by side over the list, the next starting where one ends (within its last 2 px,
-- the templates' shared edge), the five across the list; each title's words ending before the next
-- title starts (the last: before its own edge). Returns them.
local function SideBySide(main, why)
	local t = Titles(main)
	eq(#t, 5, why)
	eq(t[1].left, 0, why .. ": the first at the list's left")
	for i = 2, 5 do
		assert(t[i].left > t[i - 1].left and t[i].left <= t[i - 1].right and t[i - 1].right - t[i].left <= 2,
			why .. ": title " .. i .. " where title " .. (i - 1) .. " ends")
	end
	local listW = main.views.census:GetWidth()
	assert(t[5].right <= listW + 4 and t[5].right >= listW - 8, why .. ": across the list (" .. t[5].right .. " of " .. listW .. ")")
	for i = 1, 5 do
		local limit = i < 5 and t[i + 1].left or t[i].right - 2
		assert(t[i].left + TEXT_X + t[i].drawn <= limit, why .. ": " .. tostring(t[i].text) .. " runs over the next title")
	end
	return t
end

-- UI.lua in the words of `Lx` (Words), the window opened on the Census, the old look or (hd) the HD one.
local function OpenIn(Lx, hd, fn)
	WithUI(function()
		local uns = setmetatable({ L = Lx }, { __index = ns })
		uns.On = function() end
		if hd then
			-- (Forever's: next to its Guild & Communities window, as wide as its Social window.)
			uns.GuildFrameHook = { IsHD = function() return true end }
			FriendsFrame = CreateFrame("Frame", "FriendsFrame", UIParent)
			FriendsFrame:SetSize(385, 424)
		end
		assert(loadfile(ROOT .. "Olympus/UI.lua"))("Olympus", uns)
		WithGuilds({
			["Olympus A"] = Report(300, 40), ["Olympus B"] = Report(200, 55), ["Olympus C"] = Report(100, nil),
		}, function()
			ns.UI = uns.UI
			uns.UI.Toggle()
			local main = hd and OlympusFrameHD or OlympusFrame
			eq(main.views.census:GetWidth(), hd and 352 or 296, "the list's width")
			eq(main.tab, "census")
			eq(main.colHeader:IsShown(), true)
			fn(main, uns.UI)
		end)
	end)
end

test("1.2.4 the Census window: five titles, Avg lvl the fourth, side by side across the list; a click on it sorts the rows; a layout of four hides the fifth cell", function()
	OpenIn(L, false, function(main)
		local t = SideBySide(main, "the old window")
		for i, col in ipairs(V.COLUMNS.census) do eq(t[i].b.sortKey, col.sort, col.key) end
		assert(t[4].text == L.COL_AVG_LEVEL or t[4].text == L.COL_AVG_LEVEL_SHORT, t[4].text)
		local function Shown()
			local out = {}
			for _, r in ipairs(main.views.census.rows or {}) do
				if r:IsShown() and r.line and r.line.cols then out[#out + 1] = Bare(r.line.cols[1]) .. "=" .. Bare(r.cols[4]:GetText()) end
			end
			return table.concat(out, ",")
		end
		eq(Shown(), "Olympus A=40.0,Olympus B=55.0,Olympus C=-")
		-- Each cell under its own title (to 3 px, the titles' shared edges), the numbers right-justified:
		-- in the window's own units, the titles from the header row's left, the cells from the list's.
		local row
		for _, r in ipairs(main.views.census.rows) do if r:IsShown() and r.line and r.line.cols then row = r break end end
		local headerX, listX = main.colHeader:Anchor("TOPLEFT")[4], main.scroll:Anchor("TOPLEFT")[4]
		for c = 1, 5 do
			local cell = row.cols[c]
			local cl, bl, br = listX + cell:Anchor("LEFT")[4], headerX + t[c].left, headerX + t[c].right
			local cr = cl + cell:GetWidth()
			assert(cl >= bl - 3 and cr <= br + 3, ("cell %d under its title: %.1f-%.1f in %d-%d"):format(c, cl, cr, bl, br))
			eq(cell.justifyH, (c >= 2 and c <= 4) and "RIGHT" or "LEFT", "cell " .. c)
		end
		t[4].b:Click()
		eq(V.sort.key, "level"); eq(V.sort.desc, true)
		eq(Shown(), "Olympus B=55.0,Olympus A=40.0,Olympus C=-", "the highest first, none last")
		t[4].b:Click()
		eq(Shown(), "Olympus A=40.0,Olympus B=55.0,Olympus C=-", "the lowest first, none still last")
		-- A table of four columns (the Church's, the Tabards'): its rows' fifth cell hidden.
		local content = CreateFrame("Frame", nil, UIParent)
		content:SetWidth(300)
		V.Render(content, { { cols = { "a", "b", "c", "d" } } }, V.COLUMNS.heraldry)
		eq(content.rows[1].cols[4]:IsShown(), true); eq(content.rows[1].cols[5]:IsShown(), false)
	end)
end)

-- 1.2.4's review: the narrower columns made room for the average level; a longer language's title
-- (German, Spanish, French) ran over the next one. Each title now fits its own header: whole where it
-- fits, else its language's short title, else cut ("...") inside its own; in every language the
-- addon has, on both windows. (Offline, a title is measured 6 px a byte in the HD template's font,
-- 7 in the old window's, whose templates are not modelled: the old window takes its short titles
-- here where the client's narrower font may keep the whole ones, an in-game check.)
test("1.2.4's review: every Census title inside its own header in all five languages, on both windows: whole, short, or cut", function()
	local seen = {}
	for _, code in ipairs({ "enUS", "ptBR", "deDE", "esES", "frFR" }) do
		local Lx = Words(code)
		for _, hd in ipairs({ false, true }) do
			OpenIn(Lx, hd, function(main, UI)
				local why = code .. (hd and " HD" or " old")
				local t = SideBySide(main, why)
				for i, col in ipairs(V.COLUMNS.census) do
					local text = t[i].text
					local full, short = Lx[col.key], col.short and Lx[col.short]
					assert(text == full or text == short, why .. ": " .. tostring(text))
					-- Short only where the whole one would have run over the next title.
					if text ~= full then
						local fs = t[i].b:GetFontString()
						t[i].b:SetText(full); fs:SetWidth(0)
						local limit = i < 5 and t[i + 1].left or t[i].right - 2
						assert(t[i].left + TEXT_X + fs:GetUnboundedStringWidth() > limit, why .. ": " .. full .. " fits, yet " .. text)
						UI.Layout()
					end
					seen[why .. " " .. col.key] = t[i].b:GetText() .. (t[i].b:GetFontString():IsTruncated() and "..." or "")
				end
			end)
		end
	end
	-- The English and Portuguese titles whole on the HD window (the client's own font there).
	for _, key in ipairs({ "COL_GUILD", "COL_MEMBERS", "COL_ONLINE", "COL_AVG_LEVEL", "COL_LORD" }) do
		eq(seen["enUS HD " .. key], L[key])
	end
	eq(seen["ptBR HD COL_AVG_LEVEL"], "Nv. méd."); eq(seen["ptBR HD COL_MEMBERS"], "Membros")
	-- German Members, wider than its column on either window: its short title.
	eq(seen["deDE old COL_MEMBERS"], "Mitgl."); eq(seen["deDE HD COL_MEMBERS"], "Mitgl.")
	-- Spanish Online on the old window, even its short title wider than the column: cut inside it.
	eq(seen["esES old COL_ONLINE"], "Conec....")
	eq(seen["esES HD COL_ONLINE"], "Conec.")
end)
