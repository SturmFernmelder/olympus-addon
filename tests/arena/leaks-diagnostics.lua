local H = ...
local test, eq = H.test, H.eq
local ns = H.ns

print("Diagnostics.lua: what /oly status, /oly bug and the error log never keep")

-- The saved tables and stand-ins these tests change, put back after, even when one fails.
local function Saved(fn)
	local db, rdb, C = ns.db, ns.rdb, ns.Comm
	local was = { errors = db.errors, log = db.log, realmKey = rdb.realmKey, joined = C.JoinedName(), setKey = C.SetRealmKey,
		list = GetChannelList, chat = C_ChatInfo }
	db.errors, db.log = {}, {}
	local ok, err = pcall(fn)
	db.errors, db.log, rdb.realmKey = was.errors, was.log, was.realmKey
	C.SetJoinedForTest(was.joined)
	C.SetRealmKey = was.setKey
	GetChannelList, C_ChatInfo = was.list, was.chat
	if not ok then error(err, 0) end
end

-- Everything a player could paste or send: /oly status, /oly bug, the log and the saved errors.
local function Everything()
	local text = table.concat({ ns.StatusText(), ns.BuildBugReport(), table.concat(ns.db.log, "\n") }, "\n")
	for _, e in ipairs(ns.db.errors) do text = text .. "\n" .. e.key .. "\n" .. e.where .. "\n" .. e.msg .. "\n" .. (e.stack or "") end
	return text
end

test("1.2.1 leaks: a failure inside /oly key <secret> keeps the command, never the key, in the errors, the log and /oly bug", function()
	Saved(function()
		local secret = "Hidden Grove 4417"
		ns.Comm.SetRealmKey = function(s) error("on purpose, with " .. tostring(s)) end
		SlashCmdList.OLYMPUS("key " .. secret)
		eq(#ns.db.errors, 1, "the failure was kept")
		eq(ns.db.errors[1].where, "slash key", "the command alone")
		eq(ns.db.errors[1].msg:find("on purpose", 1, true) ~= nil, true, "and what went wrong")
		local text = Everything()
		assert(not text:find(secret, 1, true), "the key is nowhere")
		assert(not text:lower():find("hidden grove", 1, true), "in no case")
		assert(ns.BuildBugReport():find("slash key", 1, true), "the report names the command")
		-- "/oly key rotate" names no key: kept as typed; other commands as before.
		ns.CaptureError("slash key rotate", "rotation failed")
		ns.CaptureError("slash helpme where is the bank", "boom")
		eq(ns.db.errors[2].where, "slash key rotate")
		eq(ns.db.errors[3].where, "slash helpme where is the bank")
	end)
end)

test("1.2.1 leaks: a key older versions kept with a failure leaves the saved errors and log at login", function()
	-- Diagnostics.lua in a namespace of its own, its saved variables as an older version left them.
	local inits = {}
	local dns = setmetatable({ Gate = false, RegisterEvent = function() end, allErrors = {} }, { __index = ns })
	dns.On = function(name, fn) if name == "INIT" then inits[#inits + 1] = fn end end
	dns.db = { errors = {
			{ key = "slash key Mossy Lantern 81|Comm.lua:1: boom Mossy Lantern 81", where = "slash key Mossy Lantern 81",
				msg = "Comm.lua:1: boom Mossy Lantern 81", stack = "in Mossy Lantern 81", count = 1, version = "1.2.0" },
			{ key = "slash key rotate|x", where = "slash key rotate", msg = "x", stack = "", count = 1, version = "1.2.0" },
		}, log = {
			"10-01 12:00:00 ERROR in slash key Mossy Lantern 81: Comm.lua:1: boom",
			"10-01 12:00:01 ERROR in slash key rotate: x",
			"10-01 12:00:02 ERROR in slash key: kept as this version keeps it",
		} }
	assert(loadfile(H.ADDON_DIR .. "Diagnostics.lua"))("Olympus", dns)
	eq(#inits > 0, true, "an INIT handler")
	for _, fn in ipairs(inits) do fn() end
	local e = dns.db.errors[1]
	eq(e.where, "slash key"); eq(e.key, "slash key|Comm.lua:1: boom (key)")
	eq(e.msg, "Comm.lua:1: boom (key)"); eq(e.stack, "in (key)")
	eq(dns.db.errors[2].where, "slash key rotate", "rotate is no key")
	eq(dns.db.log[1], "10-01 12:00:00 ERROR in slash key (not kept)")
	eq(dns.db.log[2], "10-01 12:00:01 ERROR in slash key rotate: x")
	eq(dns.db.log[3], "10-01 12:00:02 ERROR in slash key: kept as this version keeps it")
end)

test("1.2.1 leaks: /oly status and /oly bug never name the sealed channel nor the player's own channels", function()
	Saved(function()
		ns.rdb.realmKey = "Quiet Harbor 2291"
		local sealed = (ns.Comm.ChannelSpec())
		assert(sealed:find("^Oly"), sealed)
		ns.Comm.SetJoinedForTest(sealed)
		GetChannelList = function() return 1, "General", false, 2, "Trade", false, 3, "dawnwatchers", false, 4, sealed, false end
		local base = C_ChatInfo or {}
		C_ChatInfo = setmetatable({ GetChannelInfoFromIdentifier = function(name)
			if name == "General" or name == "Trade" then return { zoneChannelID = name == "General" and 1 or 2 } end
			return { zoneChannelID = 0 }
		end }, { __index = base })
		-- As Comm.lua logs it, and an older key's channel too.
		ns.db.log = { "10-11 12:00:00 channel " .. sealed .. " is #4", "10-11 12:00:01 joining channel Oly0abc1xyz (sealed)" }
		local status, bug = ns.StatusText(), ns.BuildBugReport()
		for _, text in ipairs({ status, bug }) do
			assert(not text:lower():find(sealed:lower(), 1, true), "the sealed channel is not named")
			assert(not text:find("Oly0abc1xyz", 1, true), "nor an older one")
			assert(not text:find("dawnwatchers", 1, true), "nor the player's own channel")
		end
		assert(status:find("channel (sealed channel) = #", 1, true), status)
		assert(status:find("chat channels: 1 General, 2 Trade, 3 other, 4 Olympus", 1, true), status)
		assert(bug:find("channel (sealed channel) is #4", 1, true), "the log line stays, without the name")
		assert(bug:find("joining channel (sealed channel) (sealed)", 1, true))
		-- The public channel's name is no secret: shown as before.
		ns.rdb.realmKey = nil
		ns.Comm.SetJoinedForTest(ns.CHANNEL)
		assert(ns.StatusText():find("channel '" .. ns.CHANNEL .. "' = #", 1, true))
	end)
end)
