local ns, test, eq, WithRooms, RoomMessage = ...
local function Ids(list)
	local out = {}
	for _, e in ipairs(list) do out[#out + 1] = e.id end
	return table.concat(out, ",")
end

test("role chat navigation: one dropdown follows actual restricted audiences", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me], w.stewards[me], w.departments[me] = true, true, "War"
		assert(R.RegisterAudience("church", { label = "Church", CanAccess = function() return w.church == true end, Recipients = function() return {} end }))
		w.church = true
		local tabs = R.Tabs()
		-- (1.2.3: Guild, then Roles; the Race and Class tabs are gone.)
		eq(#tabs, 2); eq(tabs[2].kind, "role"); eq(tabs[2].dropdown, true)
		-- (1.2.4, the author's rule: the High Council are the King's centurions, so a councillor is in All
		-- Centurions too, wherever his own guild is; Guild Centurions is the King's guild's own, by its
		-- roster: tests/king-centurions.lua. Was "council,secretariat,dept:war,departments,church".)
		eq(Ids(R.Options("role")), "council,secretariat,dept:war,departments,allcenturions,church")
		w.church, w.stewards[me] = false, nil
		eq(Ids(R.Options("role")), "council,dept:war,departments,allcenturions", "audience removals reflected immediately")
		w.council[me] = nil
		eq(#R.Options("role"), 0); eq(#R.Tabs(), 1)
	end)
end)

test("role chat navigation: preview changes destinations but never authority or private data", function()
	WithRooms(function(w, R, c)
		local role = "member"
		c.ViewAs = { Previewing = function() return role ~= "my" end, Role = function() return role end }
		assert(R.RegisterAudience("church", { label = "Church", CanAccess = function() return false end, Recipients = function() return {} end }))
		eq(#R.Options("role"), 0)
		role = "king"
		eq(Ids(R.Options("role")), "council,secretariat,dept:treasury,dept:war,dept:citizenry,dept:heritage,dept:justice,dept:church,departments,church")
		for _, option in ipairs(R.Options("role")) do
			eq(option.disabled, true, "preview destinations are inert")
			eq(R.CanAccess(option.id), false); eq(R.Select(option.id), false)
			eq(R.Send(option.id, "not authorized"), false)
			eq(#R.History(option.id), 0)
		end
		eq(#w.jobs, 0); eq(w.attempts, 0, "no restricted transport attempted")
		eq(R.Receive("WHISPER", "Aldric Vane-Realm", RoomMessage("council", 1, "private")), false)
		role = "councillor"
		eq(Ids(R.Options("role")), "council,dept:treasury,dept:war,dept:citizenry,dept:heritage,dept:justice,dept:church,departments,church")
		role = "treasurer"; eq(Ids(R.Options("role")), "council,dept:treasury,treasurers")
		role = "gm"; eq(Ids(R.Options("role")), "masters")
		role = "officer"; eq(Ids(R.Options("role")), "centurions,allcenturions")
		role = "correspondent"; eq(Ids(R.Options("role")), "dept:treasury,dept:war,dept:citizenry,dept:heritage,dept:justice,dept:church,departments")
		for _, r in ipairs({ "member", "outsider", "my" }) do
			role = r; eq(#R.Options("role"), 0, r .. " is not federal authority")
		end
		w.council[c.me:lower()] = true
		role = "king"
		eq(R.Options("role")[1].disabled, true, "even an authorized reader cannot open real lines under a preview")
		eq(R.PreviewOnly("council"), true); eq(R.PreviewOnly("guild"), false)
		role = "my"; eq(R.Options("role")[1].disabled, false); eq(R.PreviewOnly("council"), false)
	end)
end)

-- 1.2.3 (the author's measure: each redraw of the Chat tab made 2.5 MB of garbage on his game): the
-- role rooms' access read the census's every guild again for each department, the treasurers', the
-- masters' and the centurions' rooms, and asked Data.AuthorizedRank a name's rank in every guild for
-- each of the masters' and the centurions' rooms. One listing (Rooms.Options, Rooms.Tabs, the Chat
-- page's destinations: Rooms.Listing) reads the guilds once, a name's nominations once and a name's
-- rank in a guild once; and the rooms are just those each room's own check (Rooms.CanAccess, outside
-- any listing) gives, for every kind of reader.
test("role chat navigation (1.2.3): one listing reads the census's guilds once and a name's rank in each guild once; its rooms are each room's own check's, for masters, officers, correspondents, a treasury clerk and, enforced, another guild's signed master", function()
	WithRooms(function(w, R, c)
		c.rdb.guilds = {}
		for i = 1, 30 do c.rdb.guilds["Olympus " .. i] = { t = w.epoch } end
		local ranks = { ["Master-Realm"] = 0, ["Officer-Realm"] = 1, ["Member-Realm"] = 3, ["Scribe-Realm"] = 3, ["Clerk-Realm"] = 3 }
		local signed = { ["Olympus 7"] = { ["Abroad-Realm"] = 0, ["Lead7-Realm"] = 0 } }
		local asked = {}
		c.Data = setmetatable({ AuthorizedRank = function(name, guild)
			asked[name .. " in " .. guild] = (asked[name .. " in " .. guild] or 0) + 1
			if guild == w.guild then return ranks[name], ranks[name] ~= nil and "roster" or nil end
			if w.enforced then
				local r = signed[guild] and signed[guild][name]
				return r, r ~= nil and "signed" or "enforced"
			end
			return 2, "census" -- (what the census says of anyone: never counted here)
		end }, { __index = ns.Data })
		c.Authority = { Enforced = function() return w.enforced == true end }
		c.Roster.Fresh = function() return c.Roster end
		c.Roster.RankOf = function(name) return ranks[c.FullName(name)] end
		local lists = {
			[w.guild] = { by = "Master-Realm", names = { ["Scribe-Realm"] = { "correspondent", "Department of War" },
				["Clerk-Realm"] = { "correspondent", "Federal Treasury" } } },
			["Olympus 7"] = { by = "Lead7-Realm", names = { ["Abroad-Realm"] = { "correspondent", "Department of War" } } },
		}
		c.Nominees = {
			ListOf = function(guild) return lists[guild] end,
			RoleOf = function(name, guild)
				local e = lists[guild] and lists[guild].names[c.FullName(name)]
				if e then return e[1], e[2] end
			end,
			Proven = function() return true end,
		}
		local federation, isFederation = 0, c.IsFederation
		c.IsFederation = function(guild) federation = federation + 1; return isFederation(guild) end
		local IDS = { "council", "secretariat", "dept:treasury", "dept:war", "dept:citizenry", "dept:heritage", "dept:justice", "dept:church",
			"masters", "treasurers", "departments", "centurions", "allcenturions" }
		local function Check(me, want)
			c.me = me
			local each = {}
			for _, id in ipairs(IDS) do if R.CanAccess(id) then each[#each + 1] = id end end
			for k in pairs(asked) do asked[k] = nil end
			federation = 0
			local listed = Ids(R.Options("role"))
			eq(listed, table.concat(each, ","), me .. ": each room's own check")
			eq(listed, want, me)
			for which, n in pairs(asked) do eq(n, 1, me .. ": " .. which .. ", asked once a listing") end
			assert(federation <= 30 + 4, me .. ": the census's guilds read once a listing, not once a room (" .. federation .. ")")
		end
		Check("Member-Realm", "")
		Check("Master-Realm", "masters")
		Check("Officer-Realm", "centurions,allcenturions")
		Check("Scribe-Realm", "dept:war,departments")
		Check("Clerk-Realm", "dept:treasury,treasurers,departments")
		w.enforced = true
		Check("Abroad-Realm", "dept:war,masters,departments")
		Check("Member-Realm", "")
		-- The Tabs and every kind's rooms in one listing: the guilds still read once.
		c.me, w.enforced = "Scribe-Realm", nil
		federation = 0
		local tabs = R.Listing(function()
			local t = R.Tabs()
			R.Options("role"); R.Options("race")
			return t
		end)
		eq(tabs[#tabs].kind, "role")
		assert(federation <= 30 + 4, "one listing, the guilds read once (" .. federation .. ")")
	end)
end)
