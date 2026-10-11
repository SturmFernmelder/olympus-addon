local H = ...
local test, eq = H.test, H.eq
local ns = H.ns

print("Data.lua: the census keeps a bounded number of guild reports")

local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

test("1.2.1 leaks: the census keeps MAX_GUILDS reports at most: made-up guilds let their own oldest go, never ours, the King's or a guild still reporting", function()
	local D = ns.Data
	local was, mine = ns.rdb.guilds, GetGuildInfo("player")
	local clock = 2000000000
	local ok, err = pcall(function()
		H.WithStub("Now", function() return clock end, function()
			ns.rdb.guilds = {
				[mine] = { total = 100, online = 10, zones = {}, t = clock - 3600, mine = true },
				-- The King's guild, its reporters quiet for an hour: older than every made-up one.
				Olympus = { total = 900, online = 90, zones = {}, t = clock - 3600 },
			}
			local function Report(guild, sender)
				return D.Receive({ guild = guild, faction = ns.faction, total = 20, online = 2, zones = {}, leader = ns.ShortName(sender), officers = {} }, sender)
			end
			eq(Report("Olympus Steady", "Steadyvoice-Realm"), true, "a real guild's report")
			-- (1.2.1's MAX_GUILDS, 300, and its count of the reports let go, read with a fallback: the
			-- same flood shows a store without a cap.)
			local cap = D.MAX_GUILDS or 300
			local before = D.Trimmed and D.Trimmed() or 0
			local flood = cap + 50
			for k = 1, flood do
				clock = clock + 1
				eq(Report("Olympus Phantom " .. k, "Phantomcaller" .. k .. "-Realm"), true, "each made-up guild is a report like any other")
				-- The real guild's reporter speaks every few minutes, as ours do.
				if k % 40 == 0 then Report("Olympus Steady", "Steadyvoice-Realm") end
			end
			eq(Count(ns.rdb.guilds), cap, "never more than MAX_GUILDS")
			assert(ns.rdb.guilds[mine] and ns.rdb.guilds[mine].mine, "ours stays")
			assert(ns.rdb.guilds.Olympus, "the King's guild stays")
			assert(ns.rdb.guilds["Olympus Steady"], "a guild still reporting stays")
			eq(ns.rdb.guilds["Olympus Phantom 1"], nil, "the oldest made-up one went")
			assert(ns.rdb.guilds["Olympus Phantom " .. flood], "the newest is in")
			eq(D.Trimmed() - before, flood + 3 - cap, "each one let go is counted (/oly status)")
			assert(ns.StatusText():find(("cached guilds=%d (at most %d,"):format(cap, cap), 1, true), "and shown")
			-- A guild already kept reporting again takes no room.
			local n = Count(ns.rdb.guilds)
			clock = clock + 1
			eq(Report("Olympus Steady", "Steadyvoice-Realm"), true)
			eq(Count(ns.rdb.guilds), n); eq(D.Trimmed() - before, flood + 3 - cap, "nothing let go for it")
		end)
	end)
	ns.rdb.guilds = was
	if not ok then error(err, 0) end
end)

test("1.2.1 leaks: a census store an older version saved past MAX_GUILDS is cut to it at login, the oldest reports first, ours kept", function()
	-- Data.lua in a namespace of its own (nothing registered on the harness's), its saved variables
	-- as an older version left them.
	local inits = {}
	local now = ns.Now()
	local guilds = { ["Olympus Home"] = { total = 5, online = 1, zones = {}, t = now - 6 * 86400, mine = true } }
	for k = 1, 420 do guilds["Olympus Saved " .. k] = { total = 5, online = 1, zones = {}, t = now - 86400 + k } end
	local dns = setmetatable({ rdb = { guilds = guilds, seen = {} }, Who = { Listen = function() end },
		On = function(name, fn) if name == "INIT" then inits[#inits + 1] = fn end end }, { __index = ns })
	assert(loadfile(H.ADDON_DIR .. "Data.lua"))("Olympus", dns)
	for _, fn in ipairs(inits) do fn() end
	eq(Count(dns.rdb.guilds), dns.Data.MAX_GUILDS)
	assert(dns.rdb.guilds["Olympus Home"], "ours, the oldest, stays")
	eq(dns.rdb.guilds["Olympus Saved 1"], nil, "the oldest other went")
	assert(dns.rdb.guilds["Olympus Saved 420"], "the newest stays")
	eq(dns.Data.Trimmed(), 421 - dns.Data.MAX_GUILDS)
end)
