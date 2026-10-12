-- Invented identities and proven-role fixtures; exercise the real room access and transport.
local H = ...
local test, eq = H.test, H.eq

local function WithRoles(fn)
	local oldGuild, oldTime = GetGuildInfo, GetTime
	local popups = {}; for key, value in pairs(StaticPopupDialogs) do popups[key] = value end
	local own, foreign = "Olympus II", "Olympus III"
	local w = { time = 1000, ranks = {}, lists = {}, council = {}, titles = {}, jobs = {}, role = nil, fresh = true, census = {} }
	local c = setmetatable({ L = H.ns.L, me = "Sage Owl-Realm", db = { chatRooms = true },
		rdb = { guilds = {}, council = { names = {} } }, CAPTAIN_RANK = 1 }, { __index = H.ns })
	GetGuildInfo = function() return own end
	GetTime = function() return w.time end
	c.FullName = function(name) return type(name) == "string" and (name:find("-", 1, true) and name or name .. "-Realm") or "" end
	c.ShortName = function(name) return tostring(name):match("^([^%-]+)") end
	c.Now = function() return w.time end
	c.Fire, c.On, c.Print, c.Log = function() end, function() end, function() end, function() end
	c.RealmOf = function(name) return tostring(name):match("%-([^%-]+)$") or "Realm" end
	c.IsMember, c.IsFederation = function() return true end, function(g) return g == own or g == foreign end
	c.IsKingGuild = function() return false end
	c.KingCharacter = function() return "Crown Owl-Realm" end
	c.IsKingCharacter = function(name) return c.FullName(name) == c.KingCharacter() end
	c.TREASURER = "Ledger Owl"
	c.Treasury = { TreasurerPin = function(name) return c.FullName(name) == "Ledger Owl-Realm" and 1 or nil end }
	c.IsHighCouncillor = function(name) return w.council[c.FullName(name)] == true end
	c.CouncilTitle = function(name) return w.titles[c.FullName(name)] end
	c.CouncilTitles = function() return { depts = {} } end
	c.IsSteward = function() return false end
	c.Workshop = { IsAuthor = function() return true end, Visible = function() return true end }
	c.Channels = { IsMe = function(name) return c.FullName(name) == c.me end }
	c.Roster = { members = {}, Fresh = function() return w.fresh end,
		RankOf = function(name) return (w.ranks[own] or {})[c.FullName(name)] end }
	c.Data = { Guild = function(g) return c.rdb.guilds[g] end,
		AuthorizedRank = function(name, g)
			local rank = (w.ranks[g] or {})[c.FullName(name)]
			if rank == nil then return nil end
			return rank, g == own and "roster" or (w.census[g] and "census" or "signed")
		end }
	c.Nominees = {
		ListOf = function(g) return w.lists[g] end,
		Proven = function(name, g) return c.Data.AuthorizedRank(name, g) == 0 end,
		RoleOf = function(name, g)
			for _, entry in ipairs(w.lists[g] and w.lists[g].entries or {}) do
				if c.FullName(entry.name) == c.FullName(name) then return entry.role, entry.dept end
			end
		end,
	}
	-- (1.2.4: another guild's signed ranks exist only once the author's signed leadership list counts,
	-- Data.AuthorizedRank; before, its ranks are the census's, which the rooms no longer even ask. This
	-- world's other guild is signed unless a test marks it census-only: the world before the list.)
	c.Authority = { Enforced = function() return next(w.census) == nil end }
	c.ViewAs = { Previewing = function() return w.role ~= nil end, Role = function() return w.role end }
	c.Comm = { Handle = function() end, Whisper = function(target, msg, _, _, _, _, options)
		w.jobs[#w.jobs + 1] = { target = target, msg = msg, options = options }; return true
	end }
	c.Consent, c.Moderation, c.WatchChat = false, false, false
	c.Codec = { SanitizeChat = function(s) return s end }
	local function Rank(name, guild, rank)
		w.ranks[guild] = w.ranks[guild] or {}; w.ranks[guild][c.FullName(name)] = rank
		if guild == own then c.Roster.members[#c.Roster.members + 1] = { name = name } end
	end
	local function List(guild, head, entries)
		Rank(head, guild, 0)
		w.lists[guild] = { by = c.FullName(head), entries = entries }
		c.rdb.guilds[guild] = { leader = head, officers = {} }
	end
	local ok, err = pcall(function()
		assert(loadfile(H.ADDON_DIR .. "ChatRooms.lua"))("Olympus", c)
		fn(c.ChatRooms, c, w, Rank, List, own, foreign)
	end)
	GetGuildInfo, GetTime = oldGuild, oldTime
	for key in pairs(StaticPopupDialogs) do StaticPopupDialogs[key] = nil end
	for key, value in pairs(popups) do StaticPopupDialogs[key] = value end
	if not ok then error(err, 0) end
end

test("Role audiences: council includes actual crown and federal treasurer, never the author alone", function()
	WithRoles(function(R, c, w)
		eq(R.CanAccess("council"), false, "author status is not council membership")
		eq(R.Send("council", "private"), false); eq(#w.jobs, 0)
		eq(R.CanAccess("council", c.KingCharacter()), true)
		eq(R.CanAccess("council", "Ledger Owl"), true)
		w.council[c.me], c.rdb.council.names[c.me:lower()] = true, c.me
		eq(R.CanAccess("council"), true)
		local recipients = table.concat(R.Recipients("council"), ",")
		assert(recipients:find("Crown Owl-Realm", 1, true)); assert(recipients:find("Ledger Owl-Realm", 1, true))
		w.council[c.me] = nil; eq(R.CanAccess("council"), false)
	end)
end)

test("Role audiences: real nomination messages require the current master and expire without granting claims", function()
	WithRoles(function(R, c, w, Rank, List, own, foreign)
		Rank("Sage Owl", own, 3); Rank("Head Owl", own, 0); Rank("Head Wren", foreign, 0)
		c.rdb.guilds[foreign] = { leader = "Head Wren", officers = {} }
		c.Data.KnownRank = function(name, guild) return c.Data.AuthorizedRank(name, guild), 2 end
		assert(loadfile(H.ADDON_DIR .. "Nominees.lua"))("Olympus", c)
		local N = c.Nominees
		local packet = "NM~1~" .. foreign .. "~1000~1~1~d=Department of War=Wren Thistle-Realm"
		N.Handle("CHANNEL", "Ordinary Wren-Realm", packet)
		eq(R.CanAccess("dept:war", "Wren Thistle"), false, "self-claimed nomination is not accepted")
		N.Handle("CHANNEL", "Head Wren-Realm", packet)
		eq(R.CanAccess("dept:war", "Wren Thistle"), true, "the actual master's received nomination")
		w.ranks[foreign]["Head Wren-Realm"] = 1
		eq(R.CanAccess("dept:war", "Wren Thistle"), false)
		w.ranks[foreign]["Head Wren-Realm"] = 0
		w.time = w.time + N.FRESH + 1
		eq(R.CanAccess("dept:war", "Wren Thistle"), false, "real nomination expires")
	end)
end)

-- (Changed in 1.2.4, the author's approved set of rooms, "Sobre as salas, eu concordo com todas as que
-- você colocou": the treasurers' room, the Federal Treasury's with the pinned Treasurer, is folded
-- into the Federal Treasury's own room, and the room of all the departments together is gone.)
test("Role audiences: department correspondents and heads follow current verified nominations; the Federal Treasury's room holds the pinned Treasurer", function()
	WithRoles(function(R, c, w, Rank, List, own, foreign)
		Rank("Sage Owl", own, 3)
		List(own, "Head Owl", { { name = "Sage Owl", role = "correspondent", dept = "Department of War" } })
		List(foreign, "Head Wren", { { name = "Wren Thistle", role = "correspondent", dept = "Department of War" } })
		eq(R.CanAccess("dept:war"), true)
		eq(R.CanAccess("dept:treasury"), false)
		eq(R.Info("departments"), nil, "gone"); eq(R.Info("treasurers"), nil, "gone")
		eq(R.CanAccess("dept:war", "Wren Thistle"), true)
		eq(R.CanAccess("dept:treasury", "Ledger Owl"), true, "the pinned Federal Treasurer")
		eq(R.CanAccess("dept:war", "Ledger Owl"), false, "only his own department")
		w.titles["Council Owl-Realm"] = { dept = "Department of War" }
		eq(R.CanAccess("dept:war", "Council Owl"), true)
		eq(R.CanAccess("dept:church", "Sage Owl"), false)
		w.lists[own].entries[1].dept = "The Missionary Church of Olympus"
		eq(R.CanAccess("dept:church"), true); eq(R.CanAccess("dept:war"), false)
		w.lists[own].entries[1].dept = "Federal Treasury"
		eq(R.CanAccess("dept:treasury"), true)
		eq(R.CanAccess("dept:treasury", "Head Owl"), false, "guild master is not automatically a treasurer")
		local recipients = table.concat(R.Recipients("dept:treasury"), ",")
		assert(recipients:find("Ledger Owl-Realm", 1, true), "the Treasurer hears the Federal Treasury's room: " .. recipients)
		eq(R.Send("dept:treasury", "the week's ledger"), true)
		local heard = {}
		for _, job in ipairs(w.jobs) do heard[job.target] = true end
		eq(heard["Ledger Owl-Realm"], true, "one logged whisper to him")
		w.ranks[foreign]["Head Wren-Realm"] = 1
		eq(R.CanAccess("dept:war", "Wren Thistle"), false, "revoked master cannot authorize nominees")
		w.fresh = false; eq(R.CanAccess("dept:treasury"), false)
	end)
end)

-- (Changed in 1.2.4, the author's approved set: "um com todos os guild masters e os seus, que são tipo
-- officers, os centuriões; um com o guild master e os correspondentes ... um só com centuriões" and
-- "Só que a gente precisa também de uma só dos Guild Masters": every guild's masters and centurions
-- together, each guild's master with his own centurions, and the masters' room of their own. Before,
-- one guild's centurions' room and the centurions of all guilds' room left the masters out.)
test("Role audiences (1.2.4): a guild master sits with his centurions, in his guild's room and with every guild's; the masters' room stays the masters'; previews stay inert", function()
	WithRoles(function(R, c, w, Rank, List, own, foreign)
		Rank("Sage Owl", own, 1); Rank("Ordinary Owl", own, 3)
		List(own, "Head Owl", {})
		List(foreign, "Head Wren", { { name = "Wren Thistle", role = "centurion" } })
		local mine, corr = R.GuildRoom("gcent", own), R.GuildRoom("gcorr", own)
		eq(R.CanAccess(mine), true); eq(R.CanAccess("allcenturions"), true)
		eq(R.CanAccess(corr), false, "a centurion is no correspondent")
		eq(R.CanAccess("masters"), false); eq(R.CanAccess("masters", "Head Owl"), true)
		eq(R.CanAccess(mine, "Head Owl"), true, "his guild's master")
		eq(R.CanAccess(corr, "Head Owl"), true)
		eq(R.CanAccess("allcenturions", "Head Owl"), true, "every guild's masters")
		eq(R.CanAccess("allcenturions", "Head Wren"), true)
		eq(R.CanAccess("allcenturions", c.KingCharacter()), true, "the King")
		eq(R.CanAccess(mine, "Wren Thistle"), false, "another guild's centurion")
		eq(R.CanAccess(mine, "Head Wren"), false, "another guild's master")
		eq(R.CanAccess("allcenturions", "Wren Thistle"), true)
		for _, id in ipairs({ "masters", mine, corr, "allcenturions" }) do
			eq(R.CanAccess(id, "Ordinary Owl"), false)
		end
		eq(R.Info("centurions"), nil, "gone")
		eq(R.Send("allcenturions", "role message"), true)
		local jobs = {}
		for _, job in ipairs(w.jobs) do jobs[job.target] = job end
		eq(#w.jobs, 4)
		for _, who in ipairs({ "Crown Owl-Realm", "Head Owl-Realm", "Head Wren-Realm", "Wren Thistle-Realm" }) do assert(jobs[who], who) end
		w.lists[foreign].entries = {}
		local job = jobs["Wren Thistle-Realm"]
		eq(job.options.permit(nil, nil, "WHISPER", job.target), false, "queued whisper rechecks recipient role")
		w.jobs = {}
		w.time = w.time + 2 -- (past SEND_GAP)
		eq(R.Send(mine, "our guild"), true)
		local targets = {}
		for _, j in ipairs(w.jobs) do targets[#targets + 1] = j.target end
		table.sort(targets)
		eq(table.concat(targets, ","), "Head Owl-Realm", "his guild's room: its master alone besides me")
		w.role = "officer"
		local ids = {}
		for _, option in ipairs(R.Options("role")) do
			ids[option.id] = true; eq(option.disabled, true); eq(R.Select(option.id), false)
		end
		eq(ids[mine], true); eq(ids.allcenturions, true); eq(ids.masters, nil)
		w.role = "gm"; local options = R.Options("role")
		eq(#options, 4); eq(options[1].id, "masters"); eq(R.Send("masters", "preview"), false)
		eq(#R.History("masters"), 0)
	end)
end)

test("Role audiences: a guild known only from census reports opens no private room: its 'master' and 'officers' are neither recipients nor accepted", function()
	WithRoles(function(R, c, w, Rank, List, own, foreign)
		w.census[foreign] = true
		c.rdb.guilds[foreign] = { leader = "Fake Master", officers = {} }
		Rank("Fake Master", foreign, 0); Rank("Fake Officer", foreign, 1)
		eq(R.CanAccess("masters", "Fake Master"), false, "a census guild master")
		eq(R.CanAccess("allcenturions", "Fake Officer"), false, "a census officer")
		local recipients = table.concat(R.Recipients("allcenturions"), ",")
		assert(not recipients:find("Fake", 1, true), recipients)
		-- (1.2.4: nor its own rooms, the master's with his correspondents and with his centurions.)
		local corr, cent = R.GuildRoom("gcorr", foreign), R.GuildRoom("gcent", foreign)
		eq(R.CanAccess(corr, "Fake Master"), false); eq(R.CanAccess(cent, "Fake Master"), false)
		eq(R.CanAccess(cent, "Fake Officer"), false)
		eq(#R.Recipients(cent), 0)
		w.census[foreign] = nil
		eq(R.CanAccess("masters", "Fake Master"), true, "the same rank from the signed list")
		eq(R.CanAccess(corr, "Fake Master"), true); eq(R.CanAccess(cent, "Fake Officer"), true)
	end)
end)
