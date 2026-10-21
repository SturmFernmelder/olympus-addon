-- 1.2.4: the Olympus API for other addons (Olympus/API.lua, docs/API.md) on the test world: the
-- privacy page's line for each addon, what a granted addon reads (copies of the pages' own rows,
-- field by field), its callbacks, and what never leaves. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local function Read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- Another addon the game has installed on that client: its TOC's Title, loaded.
local function Install(c, name, title)
	c.addonsBase = c.addonsBase or c.globals.C_AddOns
	c.addons = c.addons or {}
	c.addons[name:lower()] = title or name
	local base = c.addonsBase
	c.globals.C_AddOns = setmetatable({
		IsAddOnLoaded = function(n)
			if type(n) == "string" and c.addons[n:lower()] then return true end
			return base.IsAddOnLoaded(n)
		end,
		GetAddOnMetadata = function(n, field)
			if type(n) == "string" and c.addons[n:lower()] then return field == "Title" and c.addons[n:lower()] or nil end
			return base.GetAddOnMetadata(n, field)
		end,
	}, { __index = base })
end

-- API.lua (and its words) loaded into the client as the TOC loads it, after the boards it reads:
-- with Wanted.lua too (the core's board, which the world's clients do not load), its tab kept off
-- the harness's window. The global OlympusAPI is the client's (c.OlympusAPI), the host's put back.
-- The invented partner addons that exercise the reserved features (API.lua's Reserved) are
-- authorized on that client's copy of the list, as the shipped list authorizes the real one; any
-- other invented name is an ordinary addon. partners = false keeps the list as it ships.
-- (1.2.5.1: QuietTool and OtherTool drive the quiet presence, a reserved feature too.)
local PARTNERS = { "MapPins", "BountyBoard", "QuietTool", "OtherTool" }
local function LoadAPI(w, c, wanted, partners)
	local was = rawget(_G, "OlympusAPI")
	w:As(c, function()
		if wanted ~= false then
			local ui = rawget(c.ns, "UI")
			rawset(c.ns, "UI", { AddTab = function() end })
			assert(loadfile(H.ADDON_DIR .. "Wanted.lua"))("Olympus", c.ns)
			rawset(c.ns, "UI", ui)
		end
		assert(loadfile(H.ADDON_DIR .. "Locales/APIText.lua"))("Olympus", c.ns)
		assert(loadfile(H.ADDON_DIR .. "API.lua"))("Olympus", c.ns)
	end)
	c.OlympusAPI = rawget(_G, "OlympusAPI")
	rawset(_G, "OlympusAPI", was)
	assert(c.OlympusAPI and c.OlympusAPI ~= was, "the client's own OlympusAPI")
	local API = c.ns.API
	if partners ~= false and type(API.AuthorizedKey) == "function" then
		for _, name in ipairs(PARTNERS) do API.AUTHORIZED[w:As(c, API.AuthorizedKey, name)] = true end
	end
	return API
end

-- A handle's method, run as its client.
local function Do(w, c, handle, method, ...)
	return w:As(c, handle[method], handle, ...)
end

-- The UI-side contract, kept deliberately generic here: it records the opaque owner slot API.lua
-- routes and behaves like the window host without creating a frame in these API tests.
local function SurfaceHost(c)
	c.ns.UI = c.ns.UI or {}
	c.ns.UI.API_SURFACE_LIMIT = 1
	local state = { calls = {}, surfaces = {}, open = {}, count = 0 }
	local function Called(op, owner, spec)
		state.calls[#state.calls + 1] = { op = op, owner = owner, spec = spec }
	end
	function c.ns.UI.RegisterAPISurface(owner, spec)
		Called("register", owner, spec)
		if state.surfaces[owner] then return false, "registered" end
		if state.count >= c.ns.UI.API_SURFACE_LIMIT then return false, "surface-full" end
		if type(spec) ~= "table" then return false, "invalid-spec" end
		if type(spec.label) ~= "string" or spec.label == "" or #spec.label > 96 then return false, "invalid-label" end
		local icon = spec.icon
		if not ((type(icon) == "string" and icon ~= "") or (type(icon) == "number" and icon > 0)) then
			return false, "invalid-icon"
		end
		if type(spec.build) ~= "function" then return false, "invalid-build" end
		state.surfaces[owner] = spec
		state.count = state.count + 1
		return true
	end
	function c.ns.UI.OpenAPISurface(owner)
		Called("open", owner)
		if not state.surfaces[owner] then return false, "unregistered" end
		state.open[owner] = true
		return true
	end
	function c.ns.UI.ToggleAPISurface(owner)
		Called("toggle", owner)
		if not state.surfaces[owner] then return false, "unregistered" end
		state.open[owner] = not state.open[owner]
		return true
	end
	function c.ns.UI.RefreshAPISurface(owner)
		Called("refresh", owner)
		if not state.surfaces[owner] then return false, "unregistered" end
		return true
	end
	function c.ns.UI.IsAPISurfaceOpen(owner)
		Called("shown", owner)
		if not state.surfaces[owner] then return false, "unregistered" end
		return state.open[owner] == true
	end
	return state
end

-- The transport-side contract behind the public adapter.  It intentionally keeps fields the API
-- must never forward, and returns numeric internal ids, so these tests exercise the adapter rather
-- than duplicating its public shape in the fixture.
local function SightingHost(c)
	local host = { nextID = 7, starts = {}, areaStarts = {}, areaScopes = {}, cancels = {}, sessions = {}, reads = 0,
		AREA_SCOPES = { hostile = true, outsiders = true } }
	function host.Start(target)
		host.starts[#host.starts + 1] = target
		local id = host.nextID
		host.nextID = id + 1
		host.sessions[tostring(id)] = {
			id = id, target = target, phase = "waiting", createdAt = 100 + id, expiresAt = 700 + id,
			rawSecret = "transport-only-state", targetGUID = "Player-4002-TARGET",
			results = {
				{ target = target, reporter = "Scout One-Emberfall", guild = "Olympus", at = 110 + id,
					mapID = 1415, x = 401, y = 522, layer = 3, guid = "Player-4001-OBSERVER", rawSecret = "row-only-state" },
				{ target = target, observer = "Scout One-Emberfall", observerGuild = "Olympus", seenAt = 111 + id,
					receivedAt = 115 + id, expiresAt = 1011 + id,
					mapID = 1415, x = 402, y = 523, layer = 3, kind = "exact-unit", accuracyYards = 0 },
				{ target = target, observer = "Scout Two-Emberfall", observerGuild = "Olympus", seenAt = 112 + id,
					receivedAt = "invalid-time", expiresAt = math.huge,
					mapID = 1415, x = 403, y = 524, layer = 4, kind = "exact-group", accuracyYards = 0 },
				-- Invalid coordinates are discarded rather than clamped into an apparently valid report.
				{ target = target, observer = "Bad Row-Emberfall", observerGuild = "Olympus", seenAt = 113 + id,
					mapID = 1415, x = 1001, y = 524, layer = 4, rawSecret = "invalid-row-secret" },
				{ target = target, observer = "False Precision-Emberfall", observerGuild = "Olympus", seenAt = 114 + id,
					mapID = 1415, x = 404, y = 525, layer = 4, kind = "exact-group", accuracyYards = 5 },
			},
		}
		return true, id
	end
	function host.Session(id)
		host.reads = host.reads + 1
		return host.sessions[tostring(id)]
	end
	function host.StartArea(mapID, scope)
		host.areaStarts[#host.areaStarts + 1] = mapID
		host.areaScopes[#host.areaStarts] = scope or "(none)"
		local id = host.nextID
		host.nextID = id + 1
		host.sessions[tostring(id)] = {
			id = id, mode = "area", scope = scope or "hostile", mapID = mapID, phase = "waiting",
			createdAt = 100 + id, expiresAt = 700 + id, rawSecret = "area-transport-secret",
			results = {
				{ target = "Enemy One-Emberfall", observer = "Hidden Scout-Emberfall", observerGuild = "Olympus",
					seenAt = 110 + id, receivedAt = 112 + id, expiresAt = 900 + id,
					mapID = mapID, x = 410, y = 520, layer = 3, kind = "nearby", rawSecret = "area-row-secret" },
				{ target = "Enemy Exact-Emberfall", reporter = "Hidden Scout Two-Emberfall", observerGuild = "Olympus",
					seenAt = 111 + id, receivedAt = 113 + id, expiresAt = 901 + id,
					mapID = mapID, x = 411, y = 521, layer = 4, kind = "exact-unit", accuracyYards = 0 },
				{ target = "Wrong Map-Emberfall", observer = "Hidden Scout-Emberfall", observerGuild = "Olympus",
					seenAt = 112 + id, expiresAt = 902 + id, mapID = mapID + 1, x = 412, y = 522, layer = 3 },
				-- A not-hostile row: only an "outsiders" session may show it.
				{ target = "Passing Stranger-Emberfall", observer = "Hidden Scout-Emberfall", observerGuild = "Olympus",
					seenAt = 113 + id, receivedAt = 114 + id, expiresAt = 903 + id, mapID = mapID, x = 413, y = 523,
					layer = 3, kind = "nearby", hostile = false },
			}
		}
		return true, id
	end
	function host.AreaSession(id)
		host.reads = host.reads + 1
		local state = host.sessions[tostring(id)]
		return state and state.mode == "area" and state or nil
	end
	function host.Cancel(id, why)
		local key = tostring(id)
		local state = host.sessions[key]
		host.cancels[#host.cancels + 1] = { id = key, why = why }
		if not state then return false, "unknown" end
		host.sessions[key] = nil
		return true
	end
	function host.CancelArea(id, why)
		local state = host.sessions[tostring(id)]
		if not state or state.mode ~= "area" then return false, "not-found" end
		return host.Cancel(id, why)
	end
	rawset(c.ns, "PlayerSightings", host)
	return host
end

-- The host-owned profile-presentation contract behind the public adapter. Its internal state
-- deliberately includes fields the API must never copy.
local function ProfileEffectsHost(c)
	local host = { calls = {}, session = nil, effect = nil }
	local function Called(op, owner, style, enabled, caption)
		host.calls[#host.calls + 1] = { op = op, owner = owner, style = style, enabled = enabled, caption = caption }
	end
	function host.OpenSession(owner, style)
		Called("open", owner, style)
		if host.session and host.session.owner ~= owner then return false, "busy" end
		host.session = { owner = owner, style = style, issuer = "Internal Issuer-Emberfall", grantID = 991, expiresIn = 31.5 }
		c.ns.Fire("PROFILE_EFFECT_SESSION_CHANGED")
		return true
	end
	function host.CloseSession(owner)
		Called("close", owner)
		if host.session and host.session.owner ~= owner then return false, "owner" end
		host.session = nil
		c.ns.Fire("PROFILE_EFFECT_SESSION_CHANGED")
		return true
	end
	function host.Set(owner, style, enabled, caption)
		Called("set", owner, style, enabled, caption)
		if enabled then
			if not host.session then return false, "session" end
			if host.effect and host.effect.owner ~= owner then return false, "busy" end
			host.effect = { owner = owner, style = style, caption = caption }
			return true
		end
		if host.effect and host.effect.owner ~= owner then return false, "owner" end
		host.effect = nil
		return true
	end
	function host.DisableOwner(owner)
		Called("disable", owner)
		if not host.effect or host.effect.owner ~= owner then return false end
		host.effect = nil
		return true
	end
	function host.Session() return host.session end
	rawset(c.ns, "ProfileEffects", host)
	return host
end

local function Keys(t)
	local out = {}
	for k in pairs(t or {}) do out[#out + 1] = tostring(k) end
	table.sort(out)
	return table.concat(out, ",")
end

-- The Wanted store as Wanted.lua keeps it (ns.rdb.wanted): one Horde player with an open bounty,
-- the deaths that made it (a member's name and where he died), a claim, a sighting, who added
-- him; one taken off; two Slayers, one with a GUID.
local SECRET = { victim = "Orla Weft-Emberfall", zone = "Lakeshire Docks", sighting = "Redridge Canyons", by = "Hidden Reviewer-Emberfall",
	slayerGuid = "Player-4001-0BADF00D", source = "evidence-source-x" }
local HORDE = { name = "Grashk Bloodfen-Emberfall", guid = "Player-4002-00C0FFEE" }
local function PlantWanted(w, c)
	local W = c.ns.Wanted
	local month = w:As(c, W.MonthNow)
	local at = w.clock - 600
	c.rdb.wanted = {
		version = W.VERSION, scoreVersion = W.SCORE_VERSION, group = c.ns.group, faction = c.ns.faction, seq = 3, aliases = {}, slayerAliases = {}, baseSlayers = {},
		evidence = {}, seen = {}, seenOrder = {}, recent = {}, audit = {}, voids = {},
		targets = {
			["g:" .. HORDE.guid] = { key = "g:" .. HORDE.guid, name = HORDE.name, realm = "Emberfall", guid = HORDE.guid, active = true,
				addedAt = at, addedBy = SECRET.by, source = SECRET.source, current = 42, lifetimeKills = 3, cycle = 2, openSince = at, lastDeath = at,
				lastSighting = { zone = SECRET.sighting, at = at, precision = "consented", evidence = "SELF_DEATH" }, victimOverflow = 0,
				victims = { { id = "v1", name = SECRET.victim, zone = SECRET.zone, at = at, evidence = "SELF_DEATH", precision = "approximate", points = 42 } },
				claims = { { id = "c1", slayer = N.fighterA, points = 70, cycle = 1, at = at, evidence = "PARTY_KILL", level = 60 } } },
			["g:Player-4002-00000BAD"] = { key = "g:Player-4002-00000BAD", name = "Morka Gutrend-Emberfall", guid = "Player-4002-00000BAD",
				active = false, removedBy = SECRET.by, removedAt = at, current = 0, lifetimeKills = 0, cycle = 1, victims = {}, claims = {} },
		},
		slayers = {
			["g:" .. SECRET.slayerGuid] = { key = "g:" .. SECRET.slayerGuid, name = N.fighterA, guid = SECRET.slayerGuid, total = 70, claims = 1,
				reachedAt = at, lastAt = at, months = { [month] = 70 }, monthAt = { [month] = at }, monthClaims = { [month] = 1 } },
			["n:selka drummond-emberfall"] = { key = "n:selka drummond-emberfall", name = N.fighterB, total = 20, claims = 1,
				reachedAt = at, lastAt = at, months = { [month - 1] = 20 }, monthAt = { [month - 1] = at }, monthClaims = { [month - 1] = 1 } },
		},
	}
end

-- A world with the King, the Treasurer, two fighters and a member (Lida Fenn, the viewer) whose
-- client has the API; the Treasurer's word names the donors (Lida third, all time).
local function Setup(opts)
	opts = opts or {}
	local w, cast = W3.New({ world = opts.world, more = { { "treasurer", N.treasurer, { guild = World.KING_GUILD } } } })
	local viewer = cast.spectator
	viewer.mapID = opts.mapID or 1453
	viewer.globals.C_Map = { GetBestMapForUnit = function(unit)
		return unit == "player" and not viewer.instance and viewer.mapID or nil
	end }
	local now = w.clock
	-- Only donor presentation is synthetic. Keep the real Treasury behind this overlay:
	-- the client's live Dues ticker still reads its DevView, Book and native pin methods.
	local treasury = cast.treasurer.ns.Treasury
	rawset(cast.treasurer.ns, "Treasury", setmetatable({ DonationRecords = function()
		return { { name = "Torvin Hale", money = 500000, t = now - 40 * 86400 }, { name = "Selka Drummond", money = 300000, t = now - 40 * 86400 },
			{ name = "Lida Fenn", money = 100000, t = now - 40 * 86400 } }
	end, RankingShown = function() return false end }, { __index = treasury }))
	eq(W3.M(w, cast.treasurer, "HonorsNet").SendDonors(true), true)
	w:Run(0)
	local API = LoadAPI(w, viewer, opts.wanted)
	if opts.wanted ~= false then PlantWanted(w, viewer) end
	return w, cast, viewer, API
end

-- The client's privacy page line for an addon key.
local function Line(w, c, key)
	for _, item in ipairs(w:As(c, c.ns.Consent.Items)) do if item.key == key then return item end end
	return nil
end

print("The Olympus API (1.2.4)")

test("1.2.4 the API: donor fixture overrides preserve the actual Treasury and native Dues tickers", function()
	local w, cast = Setup()
	w:Run(61)
	W3.NoErrors(w)
	w:As(cast.treasurer, function()
		local T = cast.treasurer.ns.Treasury
		eq(T.DonationRecords()[3].name, "Lida Fenn", "only the intended donor presentation is synthetic")
		eq(T.RankingShown(), false)
		local book = T.Book()
		assert(book and book.duesNativeTracking, "the actual pinned character's ticker starts its native tracker")
		eq(book.duesNativeTracking.issuer, cast.treasurer.name)
		eq(book.duesNativeTracking.pin, T.TreasurerPin(cast.treasurer.name))
	end)
end)

test("1.2.4 the API: VERSION and Has; Register only for an installed addon, once a session, never Olympus's own name; an unregistered addon has no way in", function()
	local w, cast, viewer, API = Setup()
	SurfaceHost(viewer)
	local O = viewer.OlympusAPI
	eq(O.VERSION, 1)
	eq(O.SURFACE_LIMIT, 1)
	eq(API.VERSION, 1)
	eq(API.SURFACE_LIMIT, O.SURFACE_LIMIT)
	for _, f in ipairs({ "wanted", "rankings", "rankings.slayers", "rankings.donors", "rankings.church", "rankings.games", "profile", "callbacks",
		"ui.surface", "WANTED_CHANGED", "RANKINGS_CHANGED", "PROFILE_CHANGED", "PERMISSION_CHANGED" }) do
		eq(w:As(viewer, O.Has, f), true, f)
	end
	eq(w:As(viewer, O.Has, "census"), false, "no census feature"); eq(w:As(viewer, O.Has, nil), false)
	-- The global itself is read-only: an addon cannot replace Register for the others.
	local ok = pcall(function() O.Register = function() end end)
	eq(ok, false, "OlympusAPI is read-only")
	eq(getmetatable(O), false, "its metatable is locked")
	-- Nothing but Register gives a way in: no data function on the global.
	eq(O.GetWanted, nil); eq(O.GetRankings, nil); eq(O.GetProfile, nil); eq(O.On, nil); eq(O.RegisterSurface, nil); eq(O.UI, nil)
	eq(w:As(viewer, function() return rawget(_G, "OlympusUI") end), nil, "no second UI global")
	local h, why = w:As(viewer, O.Register, "MissingAddon")
	eq(h, nil); eq(why, "unknown", "a name the game has not installed")
	eq(select(2, w:As(viewer, O.Register, "Olympus")), "self")
	eq(select(2, w:As(viewer, O.Register, "olympus_arena")), "self")
	eq(select(2, w:As(viewer, O.Register, 42)), "name")
	eq(select(2, w:As(viewer, O.Register, "")), "name")
	eq(select(2, w:As(viewer, O.Register, "Bad|cffName")), "name")
	Install(viewer, "MapPins", "|cff33ff99Map|r Pins |TInterface\\Icons\\X:0|t")
	local api = w:As(viewer, O.Register, "MapPins")
	assert(type(api) == "table", "the installed addon's handle")
	eq(Do(w, viewer, api, "Name"), "MapPins")
	-- Its handle is its own and read-only; dot calls work as colon calls.
	eq(pcall(function() api.GetWanted = function() return {} end end), false, "the handle is read-only")
	eq(pcall(function() api.RegisterSurface = function() return true end end), false, "the surface methods are read-only too")
	eq(w:As(viewer, api.Status), "pending")
	h, why = w:As(viewer, O.Register, "mappins")
	eq(h, nil); eq(why, "taken", "a second Register of that name this session gets nothing")
	-- The privacy page's line: the addon's title, plain (its colour and texture codes gone).
	local item = Line(w, viewer, "api:mappins")
	assert(item, "its line on the privacy page")
	eq(item.explicit, true, "its own line is explicit, while the clearly labelled Authorize all may answer it")
	eq(item.label(), viewer.ns.L.API_CONSENT_LABEL:format("Map Pins"))
	eq(item.text, "API_CONSENT_TEXT")
	-- MAX_ADDONS a session.
	for i = 1, API.MAX_ADDONS - 1 do Install(viewer, "Extra" .. i) eq(type(w:As(viewer, O.Register, "Extra" .. i)), "table") end
	Install(viewer, "OneTooMany")
	eq(select(2, w:As(viewer, O.Register, "OneTooMany")), "full")
	W3.NoErrors(w)
end)

test("1.2.5 the API sightings: capability detection, explicit permission, sanitized copies, owner isolation, callbacks, cancellation and revocation", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	rawset(viewer.ns, "PlayerSightings", nil)
	eq(w:As(viewer, O.Has, "network.sightings"), false, "no transport: no advertised capability")
	local host = SightingHost(viewer)
	eq(w:As(viewer, O.Has, "network.sightings"), true, "the complete transport is feature-detected")
	eq(w:As(viewer, O.Has, "SIGHTING_CHANGED"), true, "the public event is feature-detected")

	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	local state, why = Do(w, viewer, a, "StartPlayerSearch", "Tracked Name-Emberfall")
	eq(state, nil); eq(why, "pending"); eq(#host.starts, 0, "pending permission sends no request")
	state, why = Do(w, viewer, a, "GetPlayerSearches")
	eq(state, nil); eq(why, "pending", "pending permission reads no searches")
	w:As(viewer, C.Choose, "api:mappins", false)
	state, why = Do(w, viewer, a, "StartPlayerSearch", "Tracked Name-Emberfall")
	eq(state, nil); eq(why, "refused"); eq(#host.starts, 0, "a No sends no request")
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)

	state = assert(Do(w, viewer, a, "StartPlayerSearch", "Tracked Name-Emberfall"))
	eq(state.id, "7", "the transport's numeric id is an opaque public string")
	eq(state.target, "Tracked Name-Emberfall"); eq(state.status, "searching")
	eq(state.createdAt, 107); eq(state.expiresAt, 707)
	eq(state.observers, 2, "duplicate reports by one observer count once")
	eq(state.confirmed, true, "two distinct observers confirm the nearby sighting")
	eq(#state.sightings, 3, "the out-of-range row is discarded")
	eq(Keys(state), "confirmed,createdAt,expiresAt,id,mode,observers,sightings,status,target")
	eq(state.mode, "player")
	eq(Keys(state.sightings[1]), "kind,layer,mapID,observer,observerGuild,seenAt,target,x,y")
	eq(state.sightings[1].kind, "nearby"); eq(state.sightings[1].observer, "Scout One-Emberfall")
	eq(state.sightings[1].observerGuild, "Olympus"); eq(state.sightings[1].mapID, 1415)
	eq(state.sightings[1].x, 401); eq(state.sightings[1].y, 522); eq(state.sightings[1].layer, 3)
	eq(state.sightings[2].kind, "exact-unit"); eq(state.sightings[2].accuracyYards, 0)
	eq(state.sightings[2].receivedAt, 122); eq(state.sightings[2].expiresAt, 1018)
	eq(state.sightings[3].kind, "exact-group"); eq(state.sightings[3].accuracyYards, 0)
	eq(Keys(state.sightings[2]), "accuracyYards,expiresAt,kind,layer,mapID,observer,observerGuild,receivedAt,seenAt,target,x,y")
	eq(state.sightings[3].receivedAt, nil); eq(state.sightings[3].expiresAt, nil,
		"malformed transport times are not exposed as an apparently durable result")
	local returned = {}
	local function Walk(v, depth)
		assert(depth < 10, "no cycle")
		if type(v) == "table" then
			for k, x in pairs(v) do Walk(k, depth + 1) Walk(x, depth + 1) end
		elseif type(v) == "string" then returned[#returned + 1] = v end
	end
	Walk(state, 0)
	local exported = table.concat(returned, "\n")
	for _, secret in ipairs({ "transport-only-state", "row-only-state", "invalid-row-secret", "Player-4002-TARGET", "Player-4001-OBSERVER" }) do
		eq(exported:find(secret, 1, true), nil, "transport-only data stays internal: " .. secret)
	end
	state.sightings[1].observer = "changed by consumer"
	eq(Do(w, viewer, a, "GetPlayerSearch", "7").sightings[1].observer, "Scout One-Emberfall", "every read is a fresh copy")

	local other = assert(Do(w, viewer, b, "StartPlayerSearch", "Other Target-Emberfall"))
	eq(other.id, "8")
	state, why = Do(w, viewer, a, "GetPlayerSearch", "8")
	eq(state, nil); eq(why, "unknown", "one handle cannot read another handle's search")
	state, why = Do(w, viewer, b, "GetPlayerSearch", "7")
	eq(state, nil); eq(why, "unknown", "ownership isolation works both ways")
	local allA, allB = Do(w, viewer, a, "GetPlayerSearches"), Do(w, viewer, b, "GetPlayerSearches")
	eq(#allA, 1); eq(allA[1].id, "7"); eq(#allB, 1); eq(allB[1].id, "8")
	eq(select(2, Do(w, viewer, a, "CancelPlayerSearch", "8")), "unknown", "another handle cannot cancel it")

	local toldA, toldB = {}, {}
	eq(Do(w, viewer, a, "On", "SIGHTING_CHANGED", function(_, row) toldA[#toldA + 1] = row end), true)
	eq(Do(w, viewer, b, "On", "SIGHTING_CHANGED", function(_, row) toldB[#toldB + 1] = row end), true)
	host.sessions["7"].results[#host.sessions["7"].results + 1] = {
		target = "Tracked Name-Emberfall", observer = "Scout Three-Emberfall", observerGuild = "Olympus",
		seenAt = 200, mapID = 1415, x = 405, y = 526, layer = 5,
	}
	w:As(viewer, function() viewer.ns.Fire("PLAYER_SIGHTINGS_CHANGED", 7) end)
	w:Run(API.DISPATCH_DELAY)
	eq(#toldA, 1); eq(toldA[1].id, "7"); eq(toldA[1].observers, 3)
	eq(#toldB, 0, "the other addon is not told about a search it does not own")
	host.sessions["8"].phase = "complete"
	w:As(viewer, function() viewer.ns.Fire("PLAYER_SIGHTINGS_CHANGED", "8") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#toldA, 1); eq(#toldB, 1); eq(toldB[1].id, "8"); eq(toldB[1].status, "complete")

	eq(Do(w, viewer, b, "CancelPlayerSearch", "8"), true)
	eq(host.cancels[#host.cancels].id, "8"); eq(host.cancels[#host.cancels].why, "api")
	w:Run(API.DISPATCH_DELAY)
	eq(#toldB, 2); eq(toldB[2].id, "8"); eq(toldB[2].status, "cancelled")
	-- Transport ids are intentionally small and reusable. Cancelling must discard the old
	-- handle's ownership, and the target+creation fingerprint is a second backstop: reusing id 8
	-- for the other handle must not let B read, cancel or receive callbacks for A's new request.
	host.nextID = 8
	local reused = assert(Do(w, viewer, a, "StartPlayerSearch", "Reused Target-Emberfall"))
	eq(reused.id, "8")
	state, why = Do(w, viewer, b, "GetPlayerSearch", "8")
	eq(state, nil); eq(why, "unknown")
	local beforeReuseCancel = #host.cancels
	local cancelled
	cancelled, why = Do(w, viewer, b, "CancelPlayerSearch", "8")
	eq(cancelled, false); eq(why, "unknown"); eq(#host.cancels, beforeReuseCancel)
	host.sessions["8"].phase = "complete"
	w:As(viewer, function() viewer.ns.Fire("PLAYER_SIGHTINGS_CHANGED", "8") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#toldA, 2); eq(toldA[2].id, "8"); eq(toldA[2].target, "Reused Target-Emberfall")
	eq(#toldB, 2, "the old owner receives no state or callback for a reused id")
	eq(Do(w, viewer, a, "CancelPlayerSearch", "8"), true)
	w:Run(API.DISPATCH_DELAY)

	-- Even without callbacks or GetPlayerSearches, a later successful start prunes ownership of a
	-- transport session that disappeared. Reusing that old id must not produce a spurious terminal
	-- callback for the stale handle.
	host.nextID = 9
	eq(assert(Do(w, viewer, b, "StartPlayerSearch", "Gone Before Poll-Emberfall")).id, "9")
	host.sessions["9"] = nil
	eq(assert(Do(w, viewer, b, "StartPlayerSearch", "Still Live-Emberfall")).id, "10")
	host.nextID = 9
	eq(assert(Do(w, viewer, a, "StartPlayerSearch", "Replacement After Prune-Emberfall")).id, "9")
	local toldBBeforeReuse = #toldB
	host.sessions["9"].phase = "complete"
	w:As(viewer, function() viewer.ns.Fire("PLAYER_SIGHTINGS_CHANGED", "9") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#toldB, toldBBeforeReuse, "a successful start prunes the handle's gone ownership")
	eq(Do(w, viewer, a, "CancelPlayerSearch", "9"), true)
	w:Run(API.DISPATCH_DELAY)

	-- B still owns id 10 when its transport entry disappears. If the transport reuses 10 for A,
	-- revoking B must compare the session fingerprint instead of cancelling by stale id alone.
	host.sessions["10"] = nil
	host.nextID = 10
	eq(assert(Do(w, viewer, a, "StartPlayerSearch", "Replacement Before Revoke-Emberfall")).id, "10")
	local beforeStaleRevoke = #host.cancels
	w:As(viewer, C.Choose, "api:bountyboard", false)
	eq(#host.cancels, beforeStaleRevoke, "revoking a stale handle does not cancel a reused id")
	eq(host.sessions["10"].target, "Replacement Before Revoke-Emberfall")
	eq(Do(w, viewer, a, "CancelPlayerSearch", "10"), true)
	w:Run(API.DISPATCH_DELAY)

	w:As(viewer, C.Choose, "api:mappins", false)
	eq(host.cancels[#host.cancels].id, "7"); eq(host.cancels[#host.cancels].why, "permission", "revocation stops every owned request")
	state, why = Do(w, viewer, a, "GetPlayerSearch", "7")
	eq(state, nil); eq(why, "refused", "revocation closes the read path")
	local starts = #host.starts
	state, why = Do(w, viewer, a, "StartPlayerSearch", "Never Sent-Emberfall")
	eq(state, nil); eq(why, "refused"); eq(#host.starts, starts)
	local cancels = #host.cancels
	cancelled, why = Do(w, viewer, a, "CancelPlayerSearch", "7")
	eq(cancelled, false); eq(why, "unknown", "a No already cancelled and forgot the owned request")
	eq(#host.cancels, cancels, "a stale post-revocation id never reaches a later transport session")
	W3.NoErrors(w)
end)

test("1.2.5 the API profile presentation: bounded owners, sanitized session events and active revoke cleanup", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	rawset(viewer.ns, "ProfileEffects", nil)
	eq(w:As(viewer, O.Has, "network.profile-effects"), false, "no host module: no advertised capability")
	local host = ProfileEffectsHost(viewer)
	eq(w:As(viewer, O.Has, "network.profile-effects"), true)
	eq(w:As(viewer, O.Has, "PROFILE_EFFECT_SESSION_CHANGED"), true)

	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	local told = {}
	eq(Do(w, viewer, a, "On", "PROFILE_EFFECT_SESSION_CHANGED", function(_, state)
		told[#told + 1] = { state = state }
	end), true)

	local ok, why = Do(w, viewer, a, "StartProfileSession", "shadow")
	eq(ok, false); eq(why, "pending"); eq(#host.calls, 0, "pending permission sends no session word")
	eq(Do(w, viewer, a, "StopProfileSession"), true, "a release remains available before consent")
	eq(host.calls[1].op, "close"); eq(host.calls[1].owner, "api-profile:1")
	local state
	state, why = Do(w, viewer, a, "GetProfileSession")
	eq(state, nil); eq(why, "pending")

	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)
	state, why = Do(w, viewer, a, "GetProfileSession")
	eq(state, nil); eq(why, "none")
	eq(Do(w, viewer, a, "StartProfileSession", "shadow"), true)
	eq(host.calls[#host.calls].op, "open"); eq(host.calls[#host.calls].owner, "api-profile:1")
	w:Run(API.DISPATCH_DELAY)
	eq(#told, 1); eq(Keys(told[1].state), "expiresIn,style")
	eq(told[1].state.style, "shadow"); eq(told[1].state.expiresIn, 31.5)
	eq(told[1].state.issuer, nil); eq(told[1].state.grantID, nil, "internal grant identity never leaves")
	state = assert(Do(w, viewer, a, "GetProfileSession"))
	eq(Keys(state), "expiresIn,style"); eq(state.style, "shadow")
	state.style = "changed by consumer"
	eq(Do(w, viewer, a, "GetProfileSession").style, "shadow", "each session read is a fresh sanitized copy")

	local caption = "A fixed host-approved caption"
	eq(Do(w, viewer, a, "SetProfileEffect", "shadow", true, caption), true)
	eq(host.effect.owner, "api-profile:1"); eq(host.effect.caption, caption)
	ok, why = Do(w, viewer, b, "StartProfileSession", "shadow")
	eq(ok, false); eq(why, "busy", "another handle cannot take over the live owner")
	eq(Do(w, viewer, b, "SetProfileEffect", "shadow", false), false)
	eq(select(2, Do(w, viewer, b, "SetProfileEffect", "shadow", false)), "owner")

	eq(Do(w, viewer, a, "StopProfileSession"), true)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, 2); eq(told[2].state, nil, "a close is delivered as a sanitized nil session")
	eq(Do(w, viewer, a, "StartProfileSession", "shadow"), true)
	eq(Do(w, viewer, a, "SetProfileEffect", "shadow", true, caption), true)
	local before = #host.calls
	w:As(viewer, C.Choose, "api:mappins", false)
	eq(host.calls[before + 1].op, "close"); eq(host.calls[before + 1].owner, "api-profile:1")
	eq(host.calls[before + 2].op, "disable"); eq(host.calls[before + 2].owner, "api-profile:1")
	eq(host.session, nil); eq(host.effect, nil, "revocation actively clears both host-owned states")
	ok, why = Do(w, viewer, a, "StartProfileSession", "shadow")
	eq(ok, false); eq(why, "refused")
	ok, why = Do(w, viewer, a, "SetProfileEffect", "shadow", true, caption)
	eq(ok, false); eq(why, "refused")
	eq(Do(w, viewer, a, "StopProfileSession"), true, "stop remains available after revoke")
	eq(Do(w, viewer, a, "SetProfileEffect", "shadow", false), true, "disable remains available after revoke")
	state, why = Do(w, viewer, a, "GetProfileSession")
	eq(state, nil); eq(why, "refused")
	W3.NoErrors(w)
end)

-- 1.2.5.1, the quiet presence (Core.lua, Comm.QUIET_WORDS): self only, for the session; only the
-- King, a High Councillor (a current signed issuer) or the author may turn it on, with the player's
-- Yes, in an Olympus guild, through an addon the Olympus team authorized (a reserved feature); the
-- handle that turned it on owns it; QUIET_PRESENCE_CHANGED; a No and a /reload end it. On the world's clients, with their own King, Workshop and Wallet: no crown, author
-- presence or auditor hello leaves while it is on, and each goes again once it is off.
test("1.2.5.1 the API quiet presence: the King, a councillor or the author alone, with a Yes, in an Olympus guild; its owner, its event; a No and a /reload end it", function()
	local w, cast = W3.New({ more = {
		{ "councillor", N.councillor, { guild = World.KING_GUILD } },
		{ "author", N.author },
		{ "steward", N.steward, { guild = World.KING_GUILD } },
	} })
	local king, member = cast.king, cast.spectator
	local function Tool(c, name)
		if not rawget(c.ns, "API") then LoadAPI(w, c, false) end
		name = name or "QuietTool"
		Install(c, name, "Quiet Tool")
		local h = assert(w:As(c, c.OlympusAPI.Register, name), "a handle for " .. name)
		return h, "api:" .. name:lower()
	end
	local function Yes(c, key, on) w:As(c, c.ns.Consent.Choose, key, on ~= false) end
	local function SentFrom(c, pattern)
		local n = 0
		for _, s in ipairs(w:Sent({ from = c })) do if s.msg:find(pattern) then n = n + 1 end end
		return n
	end
	-- The King's crown is on (his position goes out every few seconds).
	king.globals.C_Map = { GetBestMapForUnit = function() return 1453 end,
		GetPlayerMapPosition = function() return { GetXY = function() return 0.42, 0.51 end } end }
	king.db.throneLocation = true
	w:Run(6)
	assert(SentFrom(king, "^T1~P~") > 0, "his crown, before")

	local hk, kingKey = Tool(king)
	local API = king.ns.API
	eq(w:As(king, king.OlympusAPI.Has, "presence.quiet"), true)
	eq(w:As(king, king.OlympusAPI.Has, "QUIET_PRESENCE_CHANGED"), true)
	local ok, why = Do(w, king, hk, "SetQuietPresence", true)
	eq(ok, false); eq(why, "pending", "nothing before the player's Yes")
	eq(select(2, Do(w, king, hk, "GetQuietPresence")), "pending")
	Yes(king, kingKey)
	local told = {}
	eq(Do(w, king, hk, "On", "QUIET_PRESENCE_CHANGED", function(_, state) told[#told + 1] = state end), true)
	local state = Do(w, king, hk, "GetQuietPresence")
	eq(state.on, false); eq(state.since, nil)
	eq(select(2, Do(w, king, hk, "SetQuietPresence", "on")), "state")
	eq(Do(w, king, hk, "SetQuietPresence", false), true, "off while off: nothing to do")
	-- On: for this session, his own; the addon is told, with a copy.
	eq(Do(w, king, hk, "SetQuietPresence", true), true)
	state = Do(w, king, hk, "GetQuietPresence")
	eq(Keys(state), "on,since"); eq(state.on, true); eq(state.since, w.clock)
	state.on = false
	eq(Do(w, king, hk, "GetQuietPresence").on, true, "each read is a fresh copy")
	w:Run(API.DISPATCH_DELAY)
	eq(#told, 1); eq(told[1].on, true); eq(Keys(told[1]), "on,since")
	-- (A reserved feature, 2026-10-19) An addon the Olympus team has not authorized gets
	-- "unauthorized", even on the King's own client with his Yes: it can neither turn it on nor off,
	-- read it nor hear of it.
	local crier, crierKey = Tool(king, "TownCrier")
	Yes(king, crierKey)
	eq(Do(w, king, crier, "Status"), "granted")
	for _, on in ipairs({ true, false }) do
		ok, why = Do(w, king, crier, "SetQuietPresence", on)
		eq(ok, false); eq(why, "unauthorized", "SetQuietPresence " .. tostring(on))
	end
	local none, noWhy = Do(w, king, crier, "GetQuietPresence")
	eq(none, nil); eq(noWhy, "unauthorized")
	eq(Do(w, king, crier, "On", "QUIET_PRESENCE_CHANGED", function() end), false)
	eq(Do(w, king, hk, "GetQuietPresence").on, true, "still on, and still its owner's")
	-- Nothing of him leaves: no crown, no auditor hello (he is one), while his reads go on.
	local crowns, hellos = SentFrom(king, "^T1~P~"), SentFrom(king, "^ZQ~L1~H~")
	eq(w:As(king, king.ns.Wallet.Hello), false, "no hello of the arena's auditors")
	w:Run(30)
	eq(SentFrom(king, "^T1~P~"), crowns, "no crown while it is on")
	eq(SentFrom(king, "^ZQ~L1~H~"), hellos)
	eq(type(Do(w, king, hk, "GetProfile")), "table", "reads go on")
	-- Another handle of his can neither turn it off nor take it over; it hears of it all the same.
	local other, otherKey = Tool(king, "OtherTool")
	Yes(king, otherKey)
	local otherTold = {}
	eq(Do(w, king, other, "On", "QUIET_PRESENCE_CHANGED", function(_, s) otherTold[#otherTold + 1] = s end), true)
	eq(select(2, Do(w, king, other, "SetQuietPresence", false)), "owner")
	eq(select(2, Do(w, king, other, "SetQuietPresence", true)), "owner")
	eq(Do(w, king, other, "GetQuietPresence").on, true)
	-- Its owner turns it off; everything goes again.
	eq(Do(w, king, hk, "SetQuietPresence", false), true)
	w:Run(API.DISPATCH_DELAY)
	eq(told[#told].on, false); eq(Keys(told[#told]), "on")
	eq(otherTold[#otherTold].on, false, "the other handle is told too")
	w:Run(6)
	assert(SentFrom(king, "^T1~P~") > crowns, "his crown again")
	eq(w:As(king, king.ns.Wallet.Hello), true)
	w:Run(2)
	assert(SentFrom(king, "^ZQ~L1~H~") > hellos, "his auditor hello again")
	-- A No for the handle that turned it on ends it.
	eq(Do(w, king, hk, "SetQuietPresence", true), true)
	Yes(king, kingKey, false)
	eq(Do(w, king, other, "GetQuietPresence").on, false, "the No ended it")
	eq(select(2, Do(w, king, hk, "SetQuietPresence", true)), "refused")
	-- A councillor and the author may; a Steward (a signed issuer), a member and the guildless may not.
	local hc, hcKey = Tool(cast.councillor)
	Yes(cast.councillor, hcKey)
	eq(Do(w, cast.councillor, hc, "SetQuietPresence", true), true, "a High Councillor")
	eq(Do(w, cast.councillor, hc, "SetQuietPresence", false), true)
	local ha, authorKey = Tool(cast.author)
	Yes(cast.author, authorKey)
	eq(Do(w, cast.author, ha, "SetQuietPresence", true), true, "the author")
	local presence = SentFrom(cast.author, "^V4~")
	w:As(cast.author, cast.author.ns.Workshop.SendPresence)
	w:Run(1)
	eq(SentFrom(cast.author, "^V4~"), presence, "no author presence while it is on")
	eq(Do(w, cast.author, ha, "SetQuietPresence", false), true)
	w:Run(1)
	assert(SentFrom(cast.author, "^V4~") > presence, "his presence at once once off")
	for _, c in ipairs({ cast.steward, member }) do
		local h, key = Tool(c)
		Yes(c, key)
		ok, why = Do(w, c, h, "SetQuietPresence", true)
		eq(ok, false); eq(why, "authority", c.name)
		eq(Do(w, c, h, "GetQuietPresence").on, false)
	end
	-- Outside an Olympus guild, even a councillor may not.
	cast.councillor.guild = nil -- (World:Client's guild = false gives the default guild)
	eq(select(2, Do(w, cast.councillor, hc, "SetQuietPresence", true)), "guild")
	cast.councillor.guild = World.KING_GUILD
	-- A /reload ends it, and nothing of it was saved.
	eq(Do(w, king, other, "SetQuietPresence", true), true)
	w:Logout(king); w:Login(king)
	for k in pairs(king.db) do eq(tostring(k):lower():find("quiet", 1, true), nil, "saved: " .. tostring(k)) end
	local again = Tool(king, "OtherTool")
	eq(Do(w, king, again, "Status"), "granted", "the Yes is kept")
	eq(Do(w, king, again, "GetQuietPresence").on, false, "a new session starts without it")
	W3.NoErrors(w)
end)

-- 1.2.5.1, review of the quiet presence: the King's court, the lists his client repeats for late
-- logins, the treasury's repeated ask and his "taking donations", a councillor's help notice and his
-- "got it", and an arbiter's availability still said the player was online (some of them where)
-- while it was on. On the world's clients with their own King, Treasury, Workshop and Stakes (and
-- Court.lua, loaded here as the TOC does): none of it while it is on, and each again once it is off.
test("1.2.5.1 the API quiet presence on the world: no court, list repeat, treasury repeat ask, donations, help notice or arbiter availability while on; each again once off", function()
	local w, cast = W3.New({ more = { { "councillor", N.councillor, { guild = World.KING_GUILD } } } })
	local king, hc, arb, asker = cast.king, cast.councillor, cast.arbiter, cast.spectator
	local L = king.ns.L
	local function Tool(c)
		LoadAPI(w, c, false)
		Install(c, "QuietTool", "Quiet Tool")
		local h = assert(w:As(c, c.OlympusAPI.Register, "QuietTool"), "a handle")
		w:As(c, c.ns.Consent.Choose, "api:quiettool", true)
		return h
	end
	local function Count(c, pattern)
		local n = 0
		for _, s in ipairs(w:Sent({ from = c })) do if s.msg:find(pattern) then n = n + 1 end end
		return n
	end
	local function Printed(c, text)
		for _, line in ipairs(c.printed) do if line:find(text, 1, true) then return true end end
		return false
	end
	-- Court.lua as the TOC loads it, its LOGIN part (the zone event, the resend's ticker) run here once.
	w:As(king, function()
		local on, login = king.ns.On, {}
		rawset(king.ns, "On", function(event, fn) if event == "LOGIN" then login[#login + 1] = fn else on(event, fn) end end)
		local ok, err = pcall(function() assert(loadfile(H.ADDON_DIR .. "Court.lua"))("Olympus", king.ns) end)
		rawset(king.ns, "On", on)
		assert(ok, err)
		for _, fn in ipairs(login) do fn() end
	end)
	local map = 1453
	king.globals.C_Map = { GetBestMapForUnit = function() return map end }
	king.globals.GetRealZoneText = function() return map == 1453 and "Stormwind City" or "Elwynn Forest" end
	local Court, K, T = W3.M(w, king, "Court"), king.King, king.Treasury
	-- Before: the court where he stands, his Hands (an empty list is said too), the agenda, his
	-- donations, the treasury's ask, a councillor's help notice, an arbiter on duty.
	king.rdb.kingHands = {}
	hc.db.councilHelp = true
	-- (The agenda's popup on the army's clients: the game's, a no-op on this world.)
	for _, c in ipairs(w.clients) do c.globals.StaticPopup_Show = function() end end
	assert(king.Roles.SetArbiters({ { name = N.arbiter, cap = 2 } }))
	w:Run(301)
	w:Logout(arb); w:Login(arb) -- (its saved data then persists: Arena.Persists)
	w:Run(0)
	local duty, dutyWhy = W3.M(w, arb, "Stakes").OnDuty(true)
	eq(duty, true, "on duty: " .. tostring(dutyWhy))
	Court.Toggle()
	assert(K.SetAgenda("120 Muster at the gates"))
	T.SetDonations(true)
	w:Run(60)
	for _, word in ipairs({ { king, "^T1~C~%d+~[^~]*~1453~Stormwind City$" }, { king, "^T1~H~" }, { king, "^T1~A~" }, { king, "^TD~[^~]*~1~" },
		{ king, "^TA~" }, { hc, "^HA~1" }, { arb, "^ZV~" } }) do
		assert(Count(word[1], word[2]) > 0, "before: " .. word[2])
	end
	-- On: the King's and the councillor's through their own handles; the arbiter's module asked as
	-- Core.lua answers it (an arbiter alone may not turn it on).
	local hk, hh = Tool(king), Tool(hc)
	eq(Do(w, king, hk, "SetQuietPresence", true), true)
	eq(Do(w, hc, hh, "SetQuietPresence", true), true)
	local arbQuiet, arbCore = true, arb.ns.QuietPresence
	rawset(arb.ns, "QuietPresence", function() return arbQuiet end)
	local before = {}
	local words = { { king, "^T1~[CZ]~" }, { king, "^T1~H~" }, { king, "^T1~A~" }, { king, "^TD~" }, { king, "^TA~" },
		{ hc, "^HA~" }, { hc, "^HK~" }, { arb, "^ZV~" } }
	for i, word in ipairs(words) do before[i] = Count(word[1], word[2]) end
	local ok, err = pcall(function()
		-- His court's resend, and his moving on: nothing; closed and opened again: nothing, and he is told.
		w:Run(Court.RESEND + 30)
		map = 1429
		w:Fire(king, "ZONE_CHANGED_NEW_AREA")
		Court.Toggle()
		Court.Toggle()
		assert(Printed(king, L.QUIET_PRESENCE_HELD), "told that the court waits")
		-- His donations off and on again: nothing either.
		T.SetDonations(false)
		T.SetDonations(true)
		-- An ask for help reaches the councillor: shown to him, no "got it". His help off and on
		-- again: no "not available" either (the others' copy lapses, HELP_FRESH).
		w:As(hc, hc.ns.Workshop.HandleAsk, "WHISPER", asker.name, "HR~a hand please")
		assert(Printed(hc, "a hand please"), "the ask still shows to him")
		hc.Workshop.SetCouncilHelp(false)
		hc.Workshop.SetCouncilHelp(true)
		-- Past every repeat's time: the hands', the agenda's, the treasury ask's (15 minutes).
		w:Run(16 * 60)
		for i, word in ipairs(words) do eq(Count(word[1], word[2]), before[i], "nothing while it is on: " .. word[2]) end
		eq(T.Ask(true), true, "a fresh ask is a read, and goes")
		w:Run(0)
		eq(Count(king, "^TA~"), before[5] + 1)
		before[5] = before[5] + 1
		-- Off: the court where he stands now, his donations and the help notice at once; the
		-- repeats at their time; the arbiter's availability at once.
		eq(Do(w, king, hk, "SetQuietPresence", false), true)
		eq(Do(w, hc, hh, "SetQuietPresence", false), true)
		arbQuiet = false
		w:As(arb, arb.ns.Fire, "QUIET_PRESENCE_CHANGED", false)
		w:Run(0)
		eq(Count(king, "^T1~C~%d+~[^~]*~1429~Elwynn Forest$"), 1, "the court at once, in his new zone")
		assert(Count(king, "^TD~[^~]*~1~") > 0 and Count(king, "^TD~") > before[4], "his donations at once")
		eq(Count(hc, "^HA~1"), before[6] + 1, "the help notice at once")
		eq(Count(arb, "^ZV~"), before[8] + 1, "the arbiter's availability at once")
		w:Run(61)
		assert(Count(king, "^T1~H~") > before[2], "his Hands again")
		assert(Count(king, "^T1~A~") > before[3], "the agenda again")
		-- (The treasury's: ASK_EVERY after the fresh one he made meanwhile.)
		w:Run(T.ASK_EVERY)
		assert(Count(king, "^TA~[^~]*~1$") > 0 and Count(king, "^TA~") > before[5], "the treasury's ask again")
		-- At logout a keeper's "off" goes by the game's own call (Comm is gone by then): not while
		-- it is on either.
		local raw = {}
		king.globals.C_ChatInfo.SendAddonMessage = function(_, msg) raw[#raw + 1] = msg return 0 end
		king.globals.GetChannelName = function() return 5 end
		rawset(king.ns.Comm, "ChannelName", function() return "OlympusTest" end)
		eq(Do(w, king, hk, "SetQuietPresence", true), true)
		w:Fire(king, "PLAYER_LOGOUT")
		eq(#raw, 0, "no word at logout while it is on: " .. tostring(raw[1]))
		eq(Do(w, king, hk, "SetQuietPresence", false), true)
		T.SetDonations(true)
		w:Fire(king, "PLAYER_LOGOUT")
		assert(raw[1] and raw[1]:find("^TD~[^~]*~0~"), "off: the logout's word goes as ever: " .. tostring(raw[1]))
	end)
	rawset(arb.ns, "QuietPresence", arbCore)
	assert(ok, err)
	W3.NoErrors(w)
end)

test("1.2.5.1 the API quiet presence: its permission line, docs/API.md, the README and the CurseForge page say who may, what it holds back and what still goes", function()
	local src = Read(H.ADDON_DIR .. "Locales/APIText.lua")
	local head, tail = src:match("^(.-)\nif GetLocale and GetLocale%(%) == \"ptBR\" then(\n.*)$")
	-- (Review: "sends nothing that says you are online" and "other clients see you as offline" were
	-- not true for a guild leader or officer, whom the guildmates' census still shows online from the
	-- game's guild roster; the line now names what stops and what still shows.)
	for _, word in ipairs({ "turn on a quiet presence for this session", "only for the King, a High Councillor or the addon's author",
		"Olympus stops sending on its own the words that announce you online or say where you are",
		"other Olympus clients age you out as after a logout", "your guild roster, the census your guildmates build from it",
		"a guild leader or officer still shows online there, and your zone may for up to 12 minutes", "/who and chat still show you",
		"Olympus chat lines you type and what you post yourself still go out", "a /reload or logout ends it",
		"cannot enable the presentation or the quiet presence" }) do
		assert(head:find(word, 1, true), "the line says: " .. word)
	end
	for _, word in ipairs({ "ligar uma presença silenciosa nesta sessão", "só para o Rei, um membro do Alto Conselho ou o autor do addon",
		"as palavras que anunciam você online ou dizem onde você está", "o censo que seus colegas de guilda montam com ela",
		"um mestre ou oficial de guilda ainda aparece online lá", "o /who e o chat ainda mostrarão você",
		"as linhas de chat do Olympus que você digitar e o que você mesmo publicar ainda serão enviados",
		"não pode ativar a apresentação nem a presença silenciosa" }) do
		assert(tail:find(word, 1, true), "the pt-BR line says: " .. word)
	end
	assert(not head:find("see you as offline", 1, true) and not tail:find("verão você como offline", 1, true),
		"no promise that other clients see the player as offline")
	local doc = Read(H.ROOT .. "docs/API.md")
	for _, word in ipairs({ '"presence.quiet"', "handle:SetQuietPresence(on)", "handle:GetQuietPresence()", "QUIET_PRESENCE_CHANGED",
		'`false, "authority"`', '`false, "guild"`', '`false, "owner"`', '`false, "quiet"`', "No word says it went quiet",
		"Olympus chat lines he types", "the census\nstill shows a guild leader or officer online", "for up to 12 minutes",
		"PLAYER_GUILD_UPDATE", "It is never saved", "{ on = true, since = 1792000000 }" }) do
		assert(doc:find(word, 1, true), "docs/API.md: " .. word)
	end
	for _, path in ipairs({ "README.md", "docs/CURSEFORGE.md" }) do
		local section = Read(H.ROOT .. path):match("\n### Other addons: the Olympus API %(1%.2%.4%)\n(.-)\n##")
		for _, word in ipairs({ "quiet presence for the King, a High Councillor or the addon's", "age\nhim out as after a logout",
			"a guild leader or officer still shows online there", "Olympus chat lines he types and what he posts himself still go\nout",
			"A line on top of the Census and the\nRealm says so" }) do
			assert(section and section:find(word, 1, true), path .. ": " .. word)
		end
		assert(section and not section:find("see that player as offline", 1, true), path .. ": no promise of offline")
	end
end)

test("1.2.5 the API area sightings: hostile-area shape, privacy, ownership, host map pins and cancellation", function()
	local w, cast, viewer, API = Setup()
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	local host = SightingHost(viewer)
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	local state, why = Do(w, viewer, a, "StartAreaSearch", 9999)
	eq(state, nil); eq(why, "pending"); eq(host.reads, 0, "pending permission precedes map and search inspection")
	w:As(viewer, C.Choose, "api:mappins", false)
	state, why = Do(w, viewer, a, "StartAreaSearch", 9999)
	eq(state, nil); eq(why, "refused"); eq(host.reads, 0, "refused permission precedes map and search inspection")
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)
	viewer.guild = nil
	state, why = Do(w, viewer, a, "StartAreaSearch", 9999)
	eq(state, nil); eq(why, "guild"); eq(host.reads, 0, "membership loss precedes map and search inspection")
	viewer.guild = World.GUILD
	local secret = setmetatable({}, { __tostring = function() error("secret used", 2) end,
		__eq = function() error("secret compared", 2) end })
	viewer.globals.issecretvalue = function(value) return rawequal(value, secret) end
	local hidden, hiddenWhy = Do(w, viewer, a, "StartAreaSearch", secret)
	eq(hidden, nil); eq(hiddenWhy, "map"); eq(#host.areaStarts, 0, "a secret map id never reaches the transport")
	eq(select(2, Do(w, viewer, a, "GetAreaSearch", secret)), "unknown")
	eq(select(2, Do(w, viewer, a, "ShowAreaSearchOnMap", secret)), "unknown")
	eq(select(2, Do(w, viewer, a, "ClearAreaSearchMap", secret)), "unknown")
	eq(select(2, Do(w, viewer, a, "CancelAreaSearch", secret)), "unknown")

	state = assert(Do(w, viewer, a, "StartAreaSearch", 1453))
	eq(state.id, "7"); eq(state.mode, "area"); eq(state.scope, "hostile"); eq(state.mapID, 1453)
	eq(state.status, "searching"); eq(#state.sightings, 2, "wrong-map rows fail closed")
	eq(Keys(state), "createdAt,expiresAt,id,mapID,mode,scope,sightings,status")
	-- (Each row now says whether its player is hostile; a hostile session drops a not-hostile row.)
	eq(Keys(state.sightings[1]), "expiresAt,hostile,kind,layer,mapID,receivedAt,seenAt,target,x,y")
	eq(state.sightings[1].hostile, true); eq(state.sightings[2].hostile, true)
	eq(host.areaScopes[1], "(none)", "the default start passes no scope to the transport")
	eq(state.sightings[1].observer, nil); eq(state.sightings[1].observerGuild, nil)
	local exported = ""
	for _, row in ipairs(state.sightings) do for _, value in pairs(row) do exported = exported .. tostring(value) .. "\n" end end
	eq(exported:find("Hidden Scout", 1, true), nil, "observer identity is not in an area copy")
	eq(exported:find("area-row-secret", 1, true), nil)
	eq(select(2, Do(w, viewer, a, "GetPlayerSearch", "7")), "unknown", "an area id is not a player search")
	eq(select(2, Do(w, viewer, b, "GetAreaSearch", "7")), "unknown", "handle ownership")
	eq(#assert(Do(w, viewer, a, "GetAreaSearches")), 1)

	local pins = { rows = {}, clears = 0 }
	function pins:AddWorldMapIconMap(ref, frame, mapID, x, y)
		self.rows[#self.rows + 1] = { ref = ref, frame = frame, mapID = mapID, x = x, y = y }
		return true
	end
	function pins:RemoveAllWorldMapIcons(ref)
		local keep = {}
		for _, row in ipairs(self.rows) do if row.ref ~= ref then keep[#keep + 1] = row end end
		self.rows, self.clears = keep, self.clears + 1
	end
	viewer.ns.Pins = function() return pins end
	viewer.ns.WorldMapIcons = function() return true end
	local saved = { create = CreateFrame, parent = UIParent, map = WorldMapFrame, show = ShowUIPanel }
	UIParent = {}
	CreateFrame = function()
		local frame = { hidden = false }
		function frame:SetSize() end
		function frame:CreateTexture()
			return { SetAllPoints = function() end, SetTexture = function() end }
		end
		function frame:SetScript() end
		function frame:Hide() self.hidden = true end
		function frame:Show() self.hidden = false end
		return frame
	end
	WorldMapFrame = { SetMapID = function(self, mapID) self.mapID = mapID end }
	ShowUIPanel = function() return true end
	local future = w:As(viewer, viewer.ns.Now) + 1000
	for _, row in ipairs(host.sessions["7"].results) do row.expiresAt = future end
	local ok, why = Do(w, viewer, a, "ShowAreaSearchOnMap", "7")
	eq(ok, true, why); eq(#pins.rows, 2); eq(pins.rows[1].mapID, 1453); eq(WorldMapFrame.mapID, 1453)
	eq(pins.rows[1].frame.row.observer, nil, "host-owned pin keeps only the sanitized row")
	local firstFrame, secondFrame = pins.rows[1].frame, pins.rows[2].frame
	-- Map ownership is a lifecycle subscription of its own. The consuming addon did not register a
	-- SIGHTING_CHANGED callback, but the host must still redraw pins after the transport event.
	host.sessions["7"].results[#host.sessions["7"].results + 1] = {
		target = "Enemy New-Emberfall", observer = "Hidden Scout-Emberfall", observerGuild = "Olympus",
		seenAt = 120, receivedAt = 121, expiresAt = future,
		mapID = 1453, x = 420, y = 530, layer = 3, kind = "nearby",
	}
	w:As(viewer, function() viewer.ns.Fire("PLAYER_SIGHTINGS_CHANGED", "7") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#pins.rows, 3, "an active map redraws without a data-event subscription")
	eq(pins.rows[1].frame, firstFrame, "the first map frame is reused on refresh")
	eq(pins.rows[2].frame, secondFrame, "the second map frame is reused on refresh")
	local thirdFrame = pins.rows[3].frame
	assert(thirdFrame ~= firstFrame and thirdFrame ~= secondFrame, "only the newly needed third frame is added")
	-- Empty is not terminal: keep the explicit map view armed so a later observation returns on its
	-- own, and reuse the bounded frame pool rather than leaking undestroyable WoW frames per update.
	host.sessions["7"].results = {}
	w:As(viewer, function() viewer.ns.Fire("PLAYER_SIGHTINGS_CHANGED", "7") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#pins.rows, 0, "a temporarily empty searching session removes stale pins")
	eq(rawget(firstFrame, "row"), nil, "empty refresh wipes copied row data from the reusable frame")
	eq(rawget(secondFrame, "row"), nil); eq(rawget(thirdFrame, "row"), nil)
	host.sessions["7"].results[1] = {
		target = "Enemy Return-Emberfall", observer = "Hidden Scout-Emberfall", observerGuild = "Olympus",
		seenAt = 122, receivedAt = 123, expiresAt = future,
		mapID = 1453, x = 470, y = 580, layer = 3, kind = "nearby",
	}
	w:As(viewer, function() viewer.ns.Fire("PLAYER_SIGHTINGS_CHANGED", "7") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#pins.rows, 1, "a later result redraws after the temporary empty state")
	eq(pins.rows[1].frame, firstFrame, "a later result reuses the bounded frame pool")
	eq(Do(w, viewer, b, "ClearAreaSearchMap"), true, "another handle clears only its own empty pin set")
	eq(#pins.rows, 1, "another handle cannot clear this handle's pins")
	host.sessions["7"].phase = "complete"
	w:As(viewer, function() viewer.ns.Fire("PLAYER_SIGHTINGS_CHANGED", "7") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#pins.rows, 0, "expiry/completion clears an active map without a data-event subscription")

	eq(Do(w, viewer, a, "CancelAreaSearch", "7"), true)
	eq(#pins.rows, 0, "cancel removes host-owned pins")
	eq(host.cancels[#host.cancels].id, "7"); eq(host.cancels[#host.cancels].why, "api")
	eq(select(2, Do(w, viewer, a, "ShowAreaSearchOnMap", "7")), "unknown")
	CreateFrame, UIParent, WorldMapFrame, ShowUIPanel = saved.create, saved.parent, saved.map, saved.show
	W3.NoErrors(w)
end)

-- The pin library (HereBeDragons-Pins) as the game runs it, for the sighting pins: a map it does not
-- know gives false; the library itself shows a minimap dot, and only for the player's own zone
-- (UpdateMinimapPins/drawMinimapPin), hides one it takes off without clearing its anchors
-- (RemoveMinimapIcon, RemoveAllMinimapIcons), and re-adding a frame replaces its entry. The world map
-- stays closed here, so it shows none. ns.WorldMapIcons as Core.lua's: without the world map (the
-- gamepad UI) it takes the ref's world-map icons off itself. Plain frames, a tooltip, and a way back.
local PIN_KNOWN_MAPS = { [1453] = true, [1429] = true, [1415] = true }
local function PinLibrary(viewer)
	local pins = { world = {}, mini = {}, miniAdds = 0, worldAdds = 0 }
	local function Without(list, ref, frame)
		local keep = {}
		for _, row in ipairs(list) do if row.ref ~= ref or (frame and row.frame ~= frame) then keep[#keep + 1] = row end end
		return keep
	end
	function pins:AddWorldMapIconMap(ref, frame, mapID, x, y)
		self.worldAdds = self.worldAdds + 1
		if not PIN_KNOWN_MAPS[mapID] then return false end
		self.world = Without(self.world, ref, frame)
		self.world[#self.world + 1] = { ref = ref, frame = frame, mapID = mapID, x = x, y = y }
		return true
	end
	function pins:AddMinimapIconMap(ref, frame, mapID, x, y)
		self.miniAdds = self.miniAdds + 1
		if not PIN_KNOWN_MAPS[mapID] then return false end
		self.mini = Without(self.mini, ref, frame)
		self.mini[#self.mini + 1] = { ref = ref, frame = frame, mapID = mapID, x = x, y = y }
		if mapID == viewer.mapID and not viewer.instance then
			frame:Show(); frame:ClearAllPoints(); frame:SetPoint("CENTER", "Minimap", "CENTER", x, y)
		elseif frame.libraryShown then
			frame:Hide()
		end
		frame.libraryShown = mapID == viewer.mapID and not viewer.instance or nil
		return true
	end
	function pins:RemoveWorldMapIcon(ref, frame) self.world = Without(self.world, ref, frame) frame:Hide() end
	function pins:RemoveMinimapIcon(ref, frame) self.mini = Without(self.mini, ref, frame) frame.libraryShown = nil frame:Hide() end
	function pins:RemoveAllWorldMapIcons(ref)
		for _, row in ipairs(self.world) do if row.ref == ref then row.frame:Hide() end end
		self.world = Without(self.world, ref)
	end
	function pins:RemoveAllMinimapIcons(ref)
		for _, row in ipairs(self.mini) do if row.ref == ref then row.frame.libraryShown = nil row.frame:Hide() end end
		self.mini = Without(self.mini, ref)
	end
	viewer.ns.Pins = function() return pins end
	local state = { worldOn = true }
	viewer.ns.WorldMapIcons = function(P, ref)
		if not state.worldOn then P:RemoveAllWorldMapIcons(ref) end
		return state.worldOn
	end
	local tip = { lines = {} }
	function tip:SetOwner() self.lines = {} end
	function tip:AddLine(text, r, g, bl) self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = bl } end
	function tip:Show() self.shown = true end
	function tip:Hide() self.shown = false end
	-- (The viewer's own globals: its files run in that client's world.)
	local G = viewer.globals
	local saved = { create = rawget(G, "CreateFrame"), parent = rawget(G, "UIParent"), tip = rawget(G, "GameTooltip") }
	rawset(G, "UIParent", {}); rawset(G, "GameTooltip", tip)
	rawset(G, "CreateFrame", function()
		local frame = { hidden = false, scripts = {} }
		function frame:SetSize() end
		function frame:EnableMouse() end
		function frame:SetAlpha(alpha) self.alpha = alpha end
		function frame:SetPoint(...) self.point = { ... } end
		function frame:ClearAllPoints() self.point = nil end
		function frame:CreateTexture()
			local t = {}
			function t:SetTexture() end
			function t:SetAllPoints() end
			function t:SetPoint() end
			function t:SetVertexColor(r, g, bl) self.color = { r, g, bl } end
			return t
		end
		function frame:SetScript(name, fn) self.scripts[name] = fn end
		function frame:Hide() self.hidden = true end
		function frame:Show() self.hidden = false end
		return frame
	end)
	function state.Restore()
		rawset(G, "CreateFrame", saved.create); rawset(G, "UIParent", saved.parent); rawset(G, "GameTooltip", saved.tip)
	end
	return pins, tip, state
end

-- The sighting pins' timers still to fire on the viewer.
local function PinTicks(viewer)
	local n = 0
	for _, tick in ipairs(viewer.pinTicks or {}) do if not tick.fired then n = n + 1 end end
	return n
end

-- Two invented authorized addons with their Yes, and the pin library above.
local function PinSetup()
	local w, cast, viewer, API = Setup()
	-- The pins' timer, told apart from the world's other timers by its ns.After name.
	local after = viewer.ns.After
	viewer.pinTicks = {}
	viewer.ns.After = function(seconds, where, fn)
		if where ~= "api sighting pins" then return after(seconds, where, fn) end
		local tick = {}
		viewer.pinTicks[#viewer.pinTicks + 1] = tick
		viewer.pinTicksMost = math.max(viewer.pinTicksMost or 0, PinTicks(viewer))
		return after(seconds, where, function() tick.fired = true return fn() end)
	end
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	SightingHost(viewer)
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	eq(select(2, Do(w, viewer, a, "SetSightingPins", {})), "pending", "the permission comes first")
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)
	local pins, tip, state = PinLibrary(viewer)
	return w, viewer, a, b, pins, tip, state
end

test("1.2.5.1 the API sighting pins: coloured world-map and minimap dots, Olympus's own tooltip, no world map with the gamepad UI, gone with the permission", function()
	local w, viewer, a, b, pins, tip, state = PinSetup()
	local C = viewer.Consent
	local now = w:As(viewer, viewer.ns.Now)
	local list = {
		{ target = "Enemy One-Emberfall", category = "hostile", mapID = 1453, x = 410, y = 520, seenAt = now - 30,
			expiresAt = now + 600, kind = "nearby", accuracyYards = 30, own = true },
		{ target = "Marked Rogue-Emberfall", category = "marked", mapID = 1453, x = 500, y = 500, seenAt = now - 400,
			expiresAt = now + 500, kind = "exact-unit", marks = { "Watch", "Wanted", "|cffff0000Red|r", "Fourth" } },
		{ target = "Passing Stranger-Emberfall", category = "outsider", mapID = 1429, x = 300, y = 300, seenAt = now - 150,
			expiresAt = now + 600, kind = "nearby", label = "|cff00ff00Minorities|r" },
		{ target = "Expired-Emberfall", category = "hostile", mapID = 1453, x = 1, y = 1, seenAt = now - 900, expiresAt = now - 1 },
		{ target = "Odd Colour-Emberfall", category = "purple", mapID = 1453, x = 1, y = 1, seenAt = now, expiresAt = now + 60 },
		{ target = "Off Map-Emberfall", category = "hostile", mapID = 1453, x = 1001, y = 1, seenAt = now, expiresAt = now + 60 },
	}
	local ok, drawn = Do(w, viewer, a, "SetSightingPins", list)
	eq(ok, true, drawn); eq(drawn, 3, "an expired row, an unknown category and an off-map point are not drawn")
	eq(#pins.world, 3); eq(#pins.mini, 3)
	eq(pins.mini[3].mapID, 1429); eq(pins.mini[3].x, 0.3, "the dots on another map wait for that map")
	eq(pins.world[1].frame.dot.color[1], 0.92, "hostile: red")
	eq(pins.world[2].frame.dot.color[2], 0.62, "marked: orange")
	eq(pins.mini[3].frame.dot.color[3], 1, "outsider: blue")
	eq(pins.world[1].frame.alpha, 1); eq(pins.world[3].frame.alpha, 0.75); eq(pins.world[2].frame.alpha, 0.5, "an older dot fades")

	w:As(viewer, pins.mini[1].frame.scripts.OnEnter, pins.mini[1].frame)
	local text = {}
	for _, line in ipairs(tip.lines) do text[#text + 1] = line.text end
	eq(text[1], "Enemy One-Emberfall"); eq(tip.lines[1].r, 0.92)
	eq(text[2], viewer.ns.L.API_PIN_HOSTILE); eq(text[3], viewer.ns.L.API_PIN_UNMARKED)
	eq(text[4], viewer.ns.L.API_PIN_SEEN:format(viewer.ns.L.AGO_SEC:format(30)))
	eq(text[5], viewer.ns.L.API_PIN_YARDS:format(30)); eq(text[6], viewer.ns.L.API_PIN_OWN)
	w:As(viewer, pins.world[2].frame.scripts.OnEnter, pins.world[2].frame)
	eq(tip.lines[3].text, viewer.ns.L.API_PIN_MARKS:format("Watch, Wanted, Red"), "at most three plain marks")
	eq(tip.lines[5].text, viewer.ns.L.API_AREA_EXACT); eq(#tip.lines, 5, "not seen by this player")
	w:As(viewer, pins.world[3].frame.scripts.OnEnter, pins.world[3].frame)
	eq(tip.lines[2].text, "Minorities", "the consumer's own plain name for the category")
	eq(tip.lines[5].text, viewer.ns.L.API_PIN_NEARBY)

	-- Each call replaces the whole set and reuses the frames; another handle has its own.
	local firstMini = pins.mini[1].frame
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { list[1] })), 1)
	eq(#pins.world, 1); eq(#pins.mini, 1); eq(pins.mini[1].frame, firstMini)
	eq(Do(w, viewer, b, "ClearSightingPins"), true)
	eq(#pins.mini, 1, "another handle cannot clear these dots")
	-- With the gamepad UI the world map gets none; the minimap keeps them.
	state.worldOn = false
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { list[1], list[3] })), 2)
	eq(#pins.world, 0); eq(#pins.mini, 2)
	state.worldOn = true
	eq(select(2, Do(w, viewer, a, "SetSightingPins", "nope")), "invalid")
	-- Security boundary: only the documented first 96 inputs are inspected, and a consumer cannot
	-- turn a short last-seen result into a permanent marker with invented lifetime metadata.
	local bounded = {}
	for i = 1, viewer.ns.API.PIN_MAX do bounded[i] = { category = "invalid" } end
	bounded[viewer.ns.API.PIN_MAX + 1] = list[1]
	eq(select(2, Do(w, viewer, a, "SetSightingPins", bounded)), 0, "nothing after the 96-row input cap is inspected")
	local forever = {}
	for k, v in pairs(list[1]) do forever[k] = v end
	forever.expiresAt = forever.seenAt + viewer.ns.API.PIN_LIFETIME_MAX + 1
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { forever })), 0, "a pin cannot outlive a sighting result")
	forever.expiresAt = forever.seenAt
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { forever })), 0, "expiry must follow the sighting")
	-- A permission's No removes them.
	w:As(viewer, C.Choose, "api:mappins", false)
	eq(#pins.world, 0); eq(#pins.mini, 0)
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { list[1] })), "refused")
	eq(#pins.mini, 0)
	state.Restore()
	W3.NoErrors(w)
end)

-- Review of the sighting pins (2026-10-20): Olympus showed each dot itself after adding it, so a
-- reused minimap frame given a row in another zone (or one the library could not place) stood on
-- the minimap where its old row had been, with the new row's colour and tooltip.
test("1.2.5.1 the API sighting pins: the library alone shows a minimap dot, no stale dot from a reused frame, an unknown map neither drawn nor counted, unchanged rows not placed again", function()
	local w, viewer, a, b, pins, tip, state = PinSetup()
	local now = w:As(viewer, viewer.ns.Now)
	local here = { target = "Here One-Emberfall", category = "hostile", mapID = 1453, x = 410, y = 520, seenAt = now - 30,
		expiresAt = now + 600, kind = "nearby", accuracyYards = 30 }
	local away = { target = "Away One-Emberfall", category = "outsider", mapID = 1429, x = 300, y = 300, seenAt = now - 30,
		expiresAt = now + 600, kind = "nearby" }
	local unknown = { target = "Nowhere One-Emberfall", category = "marked", mapID = 9999, x = 300, y = 300, seenAt = now - 30,
		expiresAt = now + 600, kind = "nearby" }
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { here })), 1)
	local slot1 = pins.mini[1].frame
	eq(slot1.hidden, false, "in the player's zone the library shows it"); assert(slot1.point, "and places it")
	-- The same slot now holds a row in another zone: hidden, with no anchor left behind.
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { away, here })), 2)
	eq(pins.mini[1].frame == slot1 or pins.mini[2].frame == slot1, true, "the frame is reused")
	eq(slot1.pinRow.target, "Away One-Emberfall")
	eq(slot1.hidden, true, "no dot of another zone on this minimap"); eq(slot1.point, nil, "nor its old anchor")
	-- In an instance the library has no position: a re-added dot stays hidden.
	viewer.instance = true
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { here })), 1)
	eq(slot1.hidden, true, "never shown by Olympus itself")
	viewer.instance = nil
	-- A map the library does not know: not drawn, not counted, its frame left for the next row.
	eq(Do(w, viewer, a, "ClearSightingPins"), true)
	local ok, drawn = Do(w, viewer, a, "SetSightingPins", { unknown, here })
	eq(ok, true); eq(drawn, 1, "only the row on a map")
	eq(#pins.mini, 1); eq(#pins.world, 1); eq(pins.mini[1].frame.pinRow.target, "Here One-Emberfall", "its frame went to the next row")
	eq(pins.mini[1].frame.hidden, false)
	-- The same rows again: their dots stay where they are (no blink, nothing placed again).
	local miniAdds, worldAdds = pins.miniAdds, pins.worldAdds
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { here, away })), 2)
	local moved = pins.miniAdds - miniAdds
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { here, away })), 2)
	eq(pins.miniAdds - miniAdds, moved, "an unchanged set places nothing again"); eq(#pins.mini, 2); eq(#pins.world, 2)
	eq(pins.worldAdds - worldAdds, moved)
	-- A row that moved is placed again, at its new point.
	local moving = { target = "Here One-Emberfall", category = "hostile", mapID = 1453, x = 600, y = 610, seenAt = now - 5,
		expiresAt = now + 600, kind = "exact-unit" }
	miniAdds = pins.miniAdds
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { moving, away })), 2)
	eq(pins.miniAdds - miniAdds, 1, "only the moved row")
	local at
	for _, row in ipairs(pins.mini) do if row.frame.pinRow.target == "Here One-Emberfall" then at = row end end
	eq(at.x, 0.6); eq(at.y, 0.61); eq(#pins.world, 2)
	state.Restore()
	W3.NoErrors(w)
end)

-- Review of the sighting pins (2026-10-20): the fading and the expiry ran only inside a Set, so a
-- consumer that stopped calling left full-opacity dots up past their rows' expiresAt.
test("1.2.5.1 the API sighting pins: dots fade and go by themselves while nobody calls, and go once the player is no longer a member; no timer left without dots", function()
	local w, viewer, a, b, pins, tip, state = PinSetup()
	local now = w:As(viewer, viewer.ns.Now)
	local soon = { target = "Soon Gone-Emberfall", category = "hostile", mapID = 1453, x = 410, y = 520, seenAt = now - 110,
		expiresAt = now + 100, kind = "nearby" }
	local later = { target = "Later Gone-Emberfall", category = "marked", mapID = 1453, x = 500, y = 500, seenAt = now - 10,
		expiresAt = now + 400, kind = "exact-unit" }
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { soon, later })), 2)
	eq(PinTicks(viewer), 1, "one timer while there are dots")
	local soonFrame, laterFrame = pins.mini[1].frame, pins.mini[2].frame
	-- (The dots' frames exist now: the world's own frames back for the clock's other pages.)
	state.Restore()
	eq(soonFrame.alpha, 1)
	local adds = pins.miniAdds
	w:Run(2 * viewer.ns.API.PIN_TICK + 1)
	eq(soonFrame.alpha, 0.75, "an older dot fades with nobody calling"); eq(laterFrame.alpha, 1)
	eq(pins.miniAdds, adds, "its alpha alone: nothing placed again")
	w:Run(100)
	eq(#pins.mini, 1, "a dot past its row's expiresAt goes by itself"); eq(#pins.world, 1)
	eq(soonFrame.hidden, true); eq(soonFrame.pinRow, nil); eq(pins.mini[1].frame, laterFrame)
	w:Run(300)
	eq(#pins.mini, 0); eq(#pins.world, 0); eq(laterFrame.hidden, true)
	eq(PinTicks(viewer), 0, "no timer once the dots are gone")
	-- No longer a member (the guild left, the Accord asked again): every dot goes on the next tick.
	now = w:As(viewer, viewer.ns.Now)
	later.seenAt, later.expiresAt = now - 10, now + 600
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { later })), 1)
	local isMember = viewer.ns.IsMember
	viewer.ns.IsMember = function() return false end
	w:Run(2 * viewer.ns.API.PIN_TICK + 1)
	viewer.ns.IsMember = isMember
	eq(#pins.mini, 0); eq(#pins.world, 0); eq(PinTicks(viewer), 0)
	-- After a Clear the pending timer fires once and asks for no other.
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { later })), 1)
	eq(PinTicks(viewer), 1)
	eq(Do(w, viewer, a, "ClearSightingPins"), true)
	eq(#pins.mini, 0)
	w:Run(viewer.ns.API.PIN_TICK + 1)
	eq(PinTicks(viewer), 0); eq(#pins.mini, 0); eq(viewer.pinTicksMost, 1, "one timer at a time")
	state.Restore()
	W3.NoErrors(w)
end)

-- Review of the sighting pins (2026-10-20): while Olympus hides locations from a player (a
-- moderator's timeout, a hold), the guildmates' dots, the crown and the Wanted pins go; these
-- dots stayed and could be set again.
test("1.2.5.1 the API sighting pins: none while Olympus hides locations from this player, and those up go at once", function()
	local w, viewer, a, b, pins, tip, state = PinSetup()
	local now = w:As(viewer, viewer.ns.Now)
	local row = { target = "Enemy One-Emberfall", category = "hostile", mapID = 1453, x = 410, y = 520, seenAt = now - 30,
		expiresAt = now + 600, kind = "nearby" }
	-- (This world's client has WatchChat's stand-in: a module that answers Barred, the rest its own.)
	local ownWC = rawget(viewer.ns, "WatchChat")
	local barred = false
	rawset(viewer.ns, "WatchChat", setmetatable({ missing = false, Barred = function(kind, name)
		if kind == "locations" and name == nil and barred then return { kind = "timeout" } end
		return nil
	end }, { __index = ownWC }))
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { row })), 1)
	eq(select(2, Do(w, viewer, b, "SetSightingPins", { row })), 1)
	eq(#pins.mini, 2); eq(#pins.world, 2)
	state.Restore() -- (the dots' frames exist now)
	-- The sanction arrives: every handle's dots go at once.
	barred = true
	w:As(viewer, viewer.ns.Fire, "WATCHCHAT_CHANGED", "W", viewer.ns.me)
	eq(#pins.mini, 0, "gone at once"); eq(#pins.world, 0)
	-- And none can be set while it lasts.
	local ok, why = Do(w, viewer, a, "SetSightingPins", { row })
	eq(ok, false); eq(why, "barred"); eq(#pins.mini, 0); eq(#pins.world, 0)
	-- Lifted: they may come back.
	barred = false
	eq(select(2, Do(w, viewer, a, "SetSightingPins", { row })), 1)
	-- A sanction no event announced: the next tick takes them off.
	barred = true
	w:Run(2 * viewer.ns.API.PIN_TICK + 1)
	eq(#pins.mini, 0); eq(#pins.world, 0); eq(PinTicks(viewer), 0)
	rawset(viewer.ns, "WatchChat", ownWC)
	state.Restore()
	W3.NoErrors(w)
end)

test("1.2.5 the API area sightings: a partial host reports unavailable without spending quota", function()
	local w, cast, viewer, API = Setup()
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	local host = SightingHost(viewer)
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)

	local startArea = host.StartArea
	host.StartArea = nil
	for _ = 1, API.RATE_MAX + 1 do
		local state, why = Do(w, viewer, api, "StartAreaSearch", 1453)
		eq(state, nil); eq(why, "unavailable")
	end
	host.StartArea = startArea
	local state = assert(Do(w, viewer, api, "StartAreaSearch", 1453),
		"an unavailable partial host does not spend the handle's request quota")
	eq(state.mapID, 1453)
	eq(Do(w, viewer, api, "CancelAreaSearch", state.id), true)
	W3.NoErrors(w)
end)

test("1.2.5 the API area scope: hostile by default, outsiders on request with labelled rows, refused when unknown or unsupported", function()
	local w, cast, viewer, API = Setup()
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	local host = SightingHost(viewer)
	eq(w:As(viewer, O.Has, "network.sightings.area-scope"), true, "the wider scope is feature-detected")
	Install(viewer, "MapPins", "Map Pins")
	local a = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)
	local secret = setmetatable({}, { __tostring = function() error("secret used", 2) end })
	viewer.globals.issecretvalue = function(value) return rawequal(value, secret) end
	for _, bad in ipairs({ "everyone", "", 7, secret }) do
		local state, why = Do(w, viewer, a, "StartAreaSearch", 1453, bad)
		eq(state, nil); eq(why, "scope")
	end
	eq(#host.areaStarts, 0, "an unknown scope never reaches the transport")

	local state = assert(Do(w, viewer, a, "StartAreaSearch", 1453, "outsiders"))
	eq(host.areaScopes[1], "outsiders"); eq(state.scope, "outsiders")
	eq(#state.sightings, 3, "the hostile rows and the labelled not-hostile one")
	local byName = {}
	for _, row in ipairs(state.sightings) do byName[row.target] = row end
	eq(byName["Enemy One-Emberfall"].hostile, true); eq(byName["Enemy Exact-Emberfall"].hostile, true)
	eq(byName["Passing Stranger-Emberfall"].hostile, false)
	eq(Keys(byName["Passing Stranger-Emberfall"]), "expiresAt,hostile,kind,layer,mapID,receivedAt,seenAt,target,x,y",
		"a not-hostile row omits the observer like any area row")
	eq(Do(w, viewer, a, "GetAreaSearch", state.id).scope, "outsiders")
	eq(Do(w, viewer, a, "GetAreaSearches")[1].scope, "outsiders")
	eq(Do(w, viewer, a, "CancelAreaSearch", state.id), true)

	-- A hostile session never shows a not-hostile row, whatever its transport holds.
	w:Run(API.AREA_ROTATE_MIN + 1)
	state = assert(Do(w, viewer, a, "StartAreaSearch", 1453, "hostile"))
	eq(host.areaScopes[2], "(none)", "hostile asks the transport exactly as before")
	eq(state.scope, "hostile"); eq(#state.sightings, 2)
	for _, row in ipairs(state.sightings) do eq(row.hostile, true, row.target) end
	eq(Do(w, viewer, a, "CancelAreaSearch", state.id), true)

	-- A transport that does not list the wider scope: not advertised, and refused before any start.
	host.AREA_SCOPES = { hostile = true }
	eq(w:As(viewer, O.Has, "network.sightings.area-scope"), false)
	w:Run(API.AREA_ROTATE_MIN + 1)
	local refused, why = Do(w, viewer, a, "StartAreaSearch", 1453, "outsiders")
	eq(refused, nil); eq(why, "scope"); eq(#host.areaStarts, 2)
	state = assert(Do(w, viewer, a, "StartAreaSearch", 1453), "the default still starts")
	eq(state.scope, "hostile")
	W3.NoErrors(w)
end)

-- The leader's lines behind the public adapter: Hop.lua's census-driven King, his realm, the
-- "on his layer" answer and its zone names, and the layers Layers.ForMap lists from the
-- announcements, are this host (the world loads Hop and Layers once, shared); his crown is the
-- client's own King.Location, and each layer's name the real Layers.Name.
local function LeaderHost(c)
	local host = { king = nil, onLayer = false, otherRealm = false, layers = {} }
	local name = c.ns.Layers.Name
	rawset(c.ns, "Layers", {
		ForMap = function(mapID) return host.layers[mapID] or {} end,
		Name = name,
		CurrentMap = function() return c.mapID end,
		Mine = function() return nil end,
	})
	rawset(c.ns, "Hop", {
		King = function() return host.king and { name = host.king.name, mapID = host.king.mapID,
			zoneUID = host.king.zoneUID, realm = host.king.realm } or nil end,
		KingOtherRealm = function(k) return k ~= nil and host.otherRealm end,
		OnKingLayer = function(strict) return strict == true and host.onLayer end,
		ZoneName = function(mapID) return ({ [1453] = "Stormwind City", [1429] = "Elwynn Forest" })[mapID] or "?" end,
	})
	return host
end

-- The King's client shares his crown at that point of map 1453.
local function Crown(w, king, x, y)
	king.mapID, king.x, king.y = 1453, x, y
	king.globals.C_Map = {
		GetBestMapForUnit = function() return king.mapID end,
		GetPlayerMapPosition = function() return { GetXY = function() return king.x, king.y end } end,
	}
	king.db.throneLocation = true
	w:Run(6)
end

test("1.2.5 the API leader presence: only what the King's lines, his crown and the Realm tab's layers show; nothing while barred; consent, guild and rate gates", function()
	local w, cast, viewer, API = Setup()
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	rawset(viewer.ns, "Hop", { missing = true }) -- (Core.lua's stand-in for a file not loaded yet)
	Install(viewer, "MapPins", "Map Pins")
	local a = w:As(viewer, O.Register, "MapPins")
	eq(w:As(viewer, O.Has, "leader"), false, "no leader lines in this build: not advertised")
	eq(select(2, Do(w, viewer, a, "GetLeaderPresence")), "unavailable")
	local host = LeaderHost(viewer)
	eq(w:As(viewer, O.Has, "leader"), true); eq(w:As(viewer, O.Has, "LEADER_CHANGED"), true)
	eq(select(2, Do(w, viewer, a, "GetLeaderPresence")), "pending")
	w:As(viewer, C.Choose, "api:mappins", false)
	eq(select(2, Do(w, viewer, a, "GetLeaderPresence")), "refused")
	w:As(viewer, C.Choose, "api:mappins", true)

	-- No King online: that alone.
	local p = assert(Do(w, viewer, a, "GetLeaderPresence"))
	eq(Keys(p), "online"); eq(p.online, false)

	-- Online, his layer not announced and no crown: no place at all.
	host.king = { name = "The Crown", realm = viewer.ns.realm }
	p = assert(Do(w, viewer, a, "GetLeaderPresence"))
	eq(Keys(p), "name,onYourLayer,online,otherRealm")
	eq(p.name, "The Crown"); eq(p.online, true); eq(p.otherRealm, false); eq(p.onYourLayer, false)

	-- His layer announced in the viewer's zone, his crown shared: the zone, the crown's point in
	-- thousandths, and the Realm tab's layers with their "~N with Olympus" counts.
	Crown(w, cast.king, 0.42, 0.51)
	local at = assert(w:As(viewer, viewer.ns.King.Location), "the viewer's own crown")
	host.king.mapID, host.king.zoneUID = 1453, 9
	host.layers[1453] = {
		{ zoneUID = 9, count = 2, head = { name = "Crown Bearer", rank = 0, guild = World.KING_GUILD }, mine = false, lastSeen = 1 },
		{ zoneUID = 4, count = 1, head = { name = "Far Captain", rank = 1, guild = World.GUILD }, mine = false, lastSeen = 1 },
	}
	local shown = w:As(viewer, viewer.ns.Layers.ForMap, 1453)
	eq(#shown, 2, "the Realm tab lists two layers")
	p = assert(Do(w, viewer, a, "GetLeaderPresence"))
	eq(Keys(p), "layer,layers,mapID,mapName,name,onYourLayer,online,otherRealm,position")
	eq(p.mapID, 1453); eq(p.mapName, "Stormwind City")
	eq(Keys(p.position), "mapID,seenAt,x,y")
	eq(p.position.mapID, 1453); eq(p.position.x, 420); eq(p.position.y, 510); eq(p.position.seenAt, at.t)
	eq(#p.layers, 2)
	for i, layer in ipairs(p.layers) do
		eq(Keys(layer), "leader,name,olympus,yours")
		eq(layer.name, w:As(viewer, viewer.ns.Layers.Name, shown[i]), "the name the Realm tab shows")
		eq(layer.olympus, shown[i].count, "its ~N with Olympus")
		eq(layer.leader, shown[i].zoneUID == 9)
		eq(layer.yours, false)
	end
	eq(p.layers[1].olympus, 2); eq(p.layers[1].leader, true); eq(p.layer, p.layers[1].name)
	eq(p.layers[1].name, viewer.ns.L.LAYER_OF:format("Crown Bearer"))
	host.onLayer = true
	eq(Do(w, viewer, a, "GetLeaderPresence").onYourLayer, true, "the line 'on the King's layer'")
	host.onLayer = false

	-- In another zone: the zone the line names and the crown, never that zone's layers.
	viewer.mapID = 1429
	p = assert(Do(w, viewer, a, "GetLeaderPresence"))
	eq(p.mapID, 1453); eq(p.layers, nil); eq(p.layer, nil); eq(p.position.x, 420)
	viewer.mapID = 1453

	-- Another realm: said so; his layer there is not this realm's, so no layers.
	host.otherRealm, host.king.realm = true, "Farshore"
	p = assert(Do(w, viewer, a, "GetLeaderPresence"))
	eq(p.otherRealm, true); eq(p.realm, "Farshore"); eq(p.layers, nil); eq(p.onYourLayer, false)
	eq(p.mapID, 1453, "the crown's map, which his crown shows")
	host.otherRealm, host.king.realm = false, viewer.ns.realm

	-- Barred from locations (as King.Location and the King's lines): no field of where he is.
	local ownWC = rawget(viewer.ns, "WatchChat")
	rawset(viewer.ns, "WatchChat", { Barred = function(kind) return kind == "locations" and { kind = "timeout" } or nil end })
	eq(w:As(viewer, viewer.ns.King.Location), nil, "the crown is hidden from him as well")
	p = assert(Do(w, viewer, a, "GetLeaderPresence"))
	eq(Keys(p), "name,online")
	rawset(viewer.ns, "WatchChat", ownWC)

	-- The King himself: that, and nothing of where.
	local K = viewer.ns.King
	local isKing = K.IsKing
	K.IsKing = function() return true end
	p = assert(Do(w, viewer, a, "GetLeaderPresence"))
	eq(Keys(p), "isYou,name,online")
	K.IsKing = isKing

	-- A fresh copy each call.
	p = assert(Do(w, viewer, a, "GetLeaderPresence"))
	p.layers[1].olympus, p.position.x = 999, 1
	local again = Do(w, viewer, a, "GetLeaderPresence")
	eq(again.layers[1].olympus, 2); eq(again.position.x, 420)

	-- Outside an Olympus guild, nothing; past the rate, busy.
	viewer.guild = nil
	eq(select(2, Do(w, viewer, a, "GetLeaderPresence")), "guild")
	viewer.guild = World.GUILD
	w:Run(API.RATE_WINDOW + 1)
	for _ = 1, API.RATE_MAX do assert(Do(w, viewer, a, "GetLeaderPresence")) end
	eq(select(2, Do(w, viewer, a, "GetLeaderPresence")), "busy")
	W3.NoErrors(w)
end)

test("1.2.5 the API LEADER_CHANGED: once per real change, after a burst settles, on the crown's expiry, never without a Yes", function()
	local w, cast, viewer, API = Setup()
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	local host = LeaderHost(viewer)
	host.king = { name = "The Crown", realm = viewer.ns.realm }
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	local told, toldB = {}, {}
	eq(Do(w, viewer, a, "On", "LEADER_CHANGED", function(_, presence) told[#told + 1] = presence end), true)
	eq(Do(w, viewer, b, "On", "LEADER_CHANGED", function(_, presence) toldB[#toldB + 1] = presence end), true)
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, function() viewer.ns.Fire("LAYERS_CHANGED") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, 0, "nothing changed since the Yes: nothing told")

	-- His crown goes up: once, with what GetLeaderPresence returns.
	Crown(w, cast.king, 0.42, 0.51)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, 1); eq(told[1].position.x, 420)
	local now = Do(w, viewer, a, "GetLeaderPresence")
	eq(told[1].position.seenAt, now.position.seenAt); eq(told[1].mapID, now.mapID)
	eq(#toldB, 0, "never for an addon without a Yes")

	-- A burst of events with nothing new in his lines: nothing.
	w:As(cast.king, cast.king.ns.King.ToggleLocation)
	eq(cast.king.db.throneLocation, false)
	w:Run(1)
	local count = #told
	w:Run(API.DISPATCH_DELAY)
	eq(#told, count + 1, "his crown taken down: told once")
	eq(told[#told].position, nil)
	w:As(viewer, function()
		viewer.ns.Fire("LAYERS_CHANGED"); viewer.ns.Fire("HOP_CHANGED"); viewer.ns.Fire("DATA_CHANGED")
	end)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, count + 1, "no change: no call")

	-- His layer announced: a burst of two announcements, one call.
	host.king.mapID, host.king.zoneUID = 1453, 9
	host.layers[1453] = { { zoneUID = 9, count = 1, head = { name = "Crown Bearer", rank = 0, guild = World.KING_GUILD }, mine = false } }
	w:As(viewer, function() viewer.ns.Fire("LAYERS_CHANGED") end)
	host.layers[1453][1].count = 2
	w:As(viewer, function() viewer.ns.Fire("LAYERS_CHANGED") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, count + 2, "one call for the burst")
	eq(told[#told].layers[1].olympus, 2)

	-- A crown that stops coming leaves the map with no event of its own: told when it expires.
	local K = viewer.ns.King
	local location = K.Location
	local seenAt = w:As(viewer, viewer.ns.Now)
	local shared = { mapID = 1453, x = 0.3, y = 0.6, t = seenAt }
	K.Location = function() if viewer.ns.Now() - shared.t > K.LOCATION_EXPIRE then return nil end return shared end
	w:As(viewer, function() viewer.ns.Fire("KING_LOCATION_CHANGED", "show") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, count + 3); eq(told[#told].position.x, 300)
	w:Run(K.LOCATION_EXPIRE + 2)
	eq(#told, count + 4, "the expiry told once, with no event from the crown")
	eq(told[#told].position, nil)
	w:Run(K.LOCATION_EXPIRE + 2)
	eq(#told, count + 4, "and no timer keeps calling once nothing is shown")
	K.Location = location

	-- After a No: nothing more.
	w:As(viewer, C.Choose, "api:mappins", false)
	host.king = nil
	w:As(viewer, function() viewer.ns.Fire("DATA_CHANGED") end)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, count + 4)
	W3.NoErrors(w)
end)

-- (Daniel, 2026-10-19) The leader's presence and the sightings searches answer only the addons the
-- Olympus team authorized, and so do the quiet presence and the profile presentation (the same
-- rule, agreed with the authorized client's team): a consenting ordinary addon gets "unauthorized"
-- from each of their methods, cannot listen to their events and is asked only about what it can
-- read, while the rest of the API is unchanged for it.
test("1.2.5.1 the API reserved features: an addon that is not authorized gets \"unauthorized\" from every leader, sightings, quiet presence and profile-presentation method, none of their events, and a privacy line without them", function()
	local w, cast, viewer, API = Setup()
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	local sightings = SightingHost(viewer)
	local leader = LeaderHost(viewer)
	local profile = ProfileEffectsHost(viewer)
	leader.king = { name = "The Crown", realm = viewer.ns.realm }
	eq(w:As(viewer, O.Has, "leader"), true, "Has still says what this build has")
	eq(w:As(viewer, O.Has, "network.sightings"), true)
	eq(w:As(viewer, O.Has, "presence.quiet"), true)
	eq(w:As(viewer, O.Has, "network.profile-effects"), true)
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "TownCrier", "Town Crier")
	local partner = w:As(viewer, O.Register, "MapPins")
	local crier = w:As(viewer, O.Register, "TownCrier")
	assert(partner and crier, "both handles")
	eq(Line(w, viewer, "api:mappins").text, "API_CONSENT_TEXT", "the authorized addon is asked about all it may do")
	eq(Line(w, viewer, "api:towncrier").text, "API_CONSENT_TEXT_BASIC", "the ordinary addon only about what it can read")

	-- Before any answer the reserved methods already say "unauthorized": nothing about the player.
	eq(select(2, Do(w, viewer, crier, "GetLeaderPresence")), "unauthorized")
	w:As(viewer, C.Choose, "api:towncrier", false)
	eq(select(2, Do(w, viewer, crier, "StartPlayerSearch", "Tracked Name-Emberfall")), "unauthorized", "also after a No")
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:towncrier", true)
	eq(Do(w, viewer, crier, "Status"), "granted")

	-- (Its No above already ran Olympus's own revoke cleanup for its empty profile owner: a close and a
	-- disable that hold nothing. From here on nothing it calls reaches the host.)
	local profileBefore = #profile.calls
	for _, call in ipairs(profile.calls) do
		assert(call.op == "close" or call.op == "disable", "only the No's cleanup: " .. call.op)
	end
	local caption = "A fixed host-approved caption"
	local calls = {
		GetLeaderPresence = {}, StartPlayerSearch = { "Tracked Name-Emberfall" }, GetPlayerSearch = { "7" },
		GetPlayerSearches = {}, StartAreaSearch = { 1453 }, GetAreaSearch = { "7" }, GetAreaSearches = {},
		CancelPlayerSearch = { "7" }, CancelAreaSearch = { "7" }, ShowAreaSearchOnMap = { "7" }, ClearAreaSearchMap = {},
		SetSightingPins = { {} }, ClearSightingPins = {},
		SetQuietPresence = { true }, GetQuietPresence = {},
		StartProfileSession = { "shadow" }, StopProfileSession = {}, SetProfileEffect = { "shadow", true, caption }, GetProfileSession = {},
	}
	local count = 0
	for method, no in pairs(API.RESERVED_METHODS) do
		count = count + 1
		local args = assert(calls[method], "a call for " .. method)
		local result, why = Do(w, viewer, crier, method, unpack(args))
		eq(why, "unauthorized", method)
		if no == "false" then eq(result, false, method) else eq(result, nil, method) end
	end
	eq(count, 19, "every leader, sightings, quiet presence and profile-presentation method is reserved")
	-- Even a release: its own state is none, so another addon's cannot be touched through it.
	eq(select(2, Do(w, viewer, crier, "SetQuietPresence", false)), "unauthorized")
	eq(select(2, Do(w, viewer, crier, "SetProfileEffect", "shadow", false)), "unauthorized")
	eq(#sightings.starts, 0, "no exact-name request went out for it")
	eq(#sightings.areaStarts, 0, "no area request went out for it")
	eq(#profile.calls, profileBefore, "no profile session or presentation word for it")
	eq(profile.session, nil); eq(profile.effect, nil)
	eq(w:As(viewer, viewer.ns.QuietPresenceState).on, false, "no quiet presence for it")
	for _, event in ipairs({ "LEADER_CHANGED", "SIGHTING_CHANGED", "QUIET_PRESENCE_CHANGED", "PROFILE_EFFECT_SESSION_CHANGED" }) do
		eq(Do(w, viewer, crier, "On", event, function() end), false, event)
	end

	-- What it may read is unchanged.
	eq(type(Do(w, viewer, crier, "GetWanted")), "table")
	eq(type(Do(w, viewer, crier, "GetRankings")), "table")
	eq(Do(w, viewer, crier, "GetProfile").member, true)
	eq(Do(w, viewer, crier, "On", "WANTED_CHANGED", function() end), true)
	eq(Do(w, viewer, crier, "On", "PERMISSION_CHANGED", function() end), true)

	-- The authorized partner, in the same session, still has all of it.
	local told = {}
	eq(Do(w, viewer, partner, "On", "LEADER_CHANGED", function(_, presence) told[#told + 1] = presence end), true)
	eq(type(Do(w, viewer, partner, "GetLeaderPresence")), "table")
	local state = assert(Do(w, viewer, partner, "StartPlayerSearch", "Tracked Name-Emberfall"))
	eq(#sightings.starts, 1)
	eq(type(Do(w, viewer, partner, "GetPlayerSearch", state.id)), "table")
	eq(select(2, Do(w, viewer, crier, "GetPlayerSearch", state.id)), "unauthorized", "never another addon's search")
	Crown(w, cast.king, 0.42, 0.51)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, 1, "the partner is told")
	-- Its quiet presence and profile presentation pass the list and meet their own rules: the
	-- viewer, a member, may not turn the quiet presence on; the host opens the session for it.
	eq(Do(w, viewer, partner, "On", "QUIET_PRESENCE_CHANGED", function() end), true)
	eq(Do(w, viewer, partner, "On", "PROFILE_EFFECT_SESSION_CHANGED", function() end), true)
	eq(Do(w, viewer, partner, "GetQuietPresence").on, false)
	eq(select(2, Do(w, viewer, partner, "SetQuietPresence", true)), "authority", "a member: the role's rule, past the list")
	eq(select(2, Do(w, viewer, partner, "GetProfileSession")), "none")
	eq(Do(w, viewer, partner, "StartProfileSession", "shadow"), true)
	eq(profile.calls[#profile.calls].op, "open")
	eq(select(2, Do(w, viewer, crier, "GetProfileSession")), "unauthorized", "never another addon's session")
	eq(select(2, Do(w, viewer, crier, "StopProfileSession")), "unauthorized")
	eq(profile.session and profile.session.owner, "api-profile:1", "the partner's session stays open")
	eq(Do(w, viewer, partner, "StopProfileSession"), true)

	-- Taken off the list during the session: its callbacks stop and its reads say "unauthorized".
	API.AUTHORIZED[w:As(viewer, API.AuthorizedKey, "MapPins")] = nil
	Crown(w, cast.king, 0.30, 0.40)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, 1, "no LEADER_CHANGED once it is not authorized")
	eq(select(2, Do(w, viewer, partner, "GetLeaderPresence")), "unauthorized")
	eq(type(Do(w, viewer, partner, "GetWanted")), "table", "its ordinary reads go on")
	W3.NoErrors(w)
end)

test("1.2.5.1 the API reserved features: the list as it ships names nobody (one digest), a name folds before its digest, no hash means nobody, and every leader, search, quiet presence or presentation method and event is reserved", function()
	local w, cast, viewer = Setup({ wanted = false })
	local API = LoadAPI(w, viewer, false, false)
	local n = 0
	for key, on in pairs(API.AUTHORIZED) do
		n = n + 1
		eq(on, true)
		assert(type(key) == "string" and #key == 128 and not key:find("[^0-9a-f]"), "a SHA-512 digest in hex: " .. tostring(key))
	end
	eq(n, 1, "one authorized addon ships")
	local key = w:As(viewer, API.AuthorizedKey, "MapPins")
	eq(API.AUTHORIZED[key], nil, "an invented name is not on the shipped list")
	eq(w:As(viewer, API.AuthorizedKey, "mappins"), key, "the name folds as Register folds it")
	assert(w:As(viewer, API.AuthorizedKey, "Map Pins") ~= key)
	eq(w:As(viewer, API.AuthorizedKey, 42), nil)
	-- Ed25519.lua not loaded (Core.lua's stand-in for a missing file).
	local ed = rawget(viewer.ns, "Ed25519")
	rawset(viewer.ns, "Ed25519", { missing = true })
	eq(w:As(viewer, API.AuthorizedKey, "MapPins"), nil, "without the hash nobody is authorized")
	rawset(viewer.ns, "Ed25519", ed)
	-- A method a reserved feature adds later must join the list (and each listed one exists): the
	-- leader's, the searches', and (1.2.5.1) the quiet presence's and the profile presentation's.
	local src = Read(H.ADDON_DIR .. "API.lua")
	local methods = {}
	for m in src:gmatch("\nfunction METHODS%.(%u%a+)%(") do methods[m] = true end
	local reserved = 0
	for m in pairs(methods) do
		if m:find("Leader", 1, true) or m:find("Search", 1, true) or m:find("Quiet", 1, true) or m:find("Profile", 1, true) then
			-- (GetProfile, the player's own frame and title, is an ordinary read.)
			if m ~= "GetProfile" then
				assert(API.RESERVED_METHODS[m], "reserved: " .. m)
				reserved = reserved + 1
			end
		end
	end
	eq(reserved, 17, "the leader's, the searches', the quiet presence's and the presentation's methods")
	eq(API.RESERVED_METHODS.GetProfile, nil, "the player's own profile stays an ordinary read")
	for m, no in pairs(API.RESERVED_METHODS) do
		assert(methods[m], "a real method: " .. m)
		assert(no == "nil" or no == "false", m)
	end
	for m, no in pairs({ SetQuietPresence = "false", GetQuietPresence = "nil", StartProfileSession = "false",
		StopProfileSession = "false", SetProfileEffect = "false", GetProfileSession = "nil" }) do
		eq(API.RESERVED_METHODS[m], no, m)
	end
	eq(Keys(API.RESERVED_EVENTS), "LEADER_CHANGED,PROFILE_EFFECT_SESSION_CHANGED,QUIET_PRESENCE_CHANGED,SIGHTING_CHANGED")
	-- Each event of a reserved feature is reserved, and each reserved one is a real event.
	local events = {}
	for _, e in ipairs(API.EVENTS) do events[e] = true end
	for e in pairs(API.RESERVED_EVENTS) do assert(events[e], "a real event: " .. e) end
	-- The public page says it without naming any addon.
	local doc = Read(H.ROOT .. "docs/API.md")
	for _, word in ipairs({ "addons the Olympus team has authorized", '"unauthorized"' }) do
		assert(doc:find(word, 1, true), "docs/API.md: " .. word)
	end
	W3.NoErrors(w)
end)

test("1.2.5 the API area rotation: one live map, one minute, and only current or owned fresh exact-result maps", function()
	local w, cast, viewer = Setup()
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	local host = SightingHost(viewer)
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	local state, why
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)

	local exact = assert(Do(w, viewer, a, "StartPlayerSearch", "Chosen Name-Emberfall"))
	local raw = host.sessions[exact.id]
	raw.expiresAt = w.clock + 600
	for _, row in ipairs(raw.results) do
		if row.kind == "exact-unit" or row.kind == "exact-group" then
			row.seenAt, row.receivedAt, row.expiresAt = w.clock, w.clock + 1, w.clock + 65
		end
	end
	raw.results[#raw.results + 1] = { target = raw.target, observer = "Scout Three-Emberfall",
		observerGuild = "Olympus", seenAt = w.clock, expiresAt = w.clock + 600,
		mapID = 84, x = 500, y = 500, layer = 3, kind = "nearby" }
	raw.results[#raw.results + 1] = { target = raw.target, observer = "Scout Four-Emberfall",
		observerGuild = "Olympus", seenAt = w.clock - 20, expiresAt = w.clock - 1,
		mapID = 1429, x = 500, y = 500, layer = 3, kind = "exact-unit", accuracyYards = 0 }
	assert(Do(w, viewer, a, "GetPlayerSearch", exact.id), "the handle reads and owns the fresh exact evidence")
	local exactRows, withdrawn = {}, {}
	for _, row in ipairs(raw.results) do
		if (row.kind == "exact-unit" or row.kind == "exact-group") and row.mapID == 1415 and row.expiresAt > w.clock then
			exactRows[#exactRows + 1] = row
		else
			withdrawn[#withdrawn + 1] = row
		end
	end
	raw.results = withdrawn
	w:As(viewer, function() viewer.ns.Fire("PLAYER_SIGHTINGS_CHANGED", exact.id) end)
	w:Run(2)
	state, why = Do(w, viewer, a, "StartAreaSearch", 1415)
	eq(state, nil); eq(why, "map", "a withdrawn live exact row stops authorizing its map")
	for _, row in ipairs(exactRows) do raw.results[#raw.results + 1] = row end
	eq(Do(w, viewer, a, "CancelPlayerSearch", exact.id), true,
		"rotating the exact-name queue retains only its bounded fresh map evidence")

	state, why = Do(w, viewer, a, "StartAreaSearch", 84)
	eq(state, nil); eq(why, "map", "a nearby encounter does not authorize another map")
	state, why = Do(w, viewer, a, "StartAreaSearch", 1453.4)
	eq(state, nil); eq(why, "map", "a fractional map id is not rounded into another map")
	state, why = Do(w, viewer, a, "StartAreaSearch", 1429)
	eq(state, nil); eq(why, "map", "an expired exact point does not authorize another map")

	local shown = 0
	viewer.globals.ShowUIPanel = function() shown = shown + 1 end
	state = assert(Do(w, viewer, a, "StartAreaSearch", 1453))
	eq(state.mapID, 1453); eq(shown, 0, "starting coverage never opens the world map")
	local second
	second, why = Do(w, viewer, a, "StartAreaSearch", 1453)
	eq(second, nil); eq(why, "active", "one handle has only one live area")
	eq(Do(w, viewer, a, "CancelAreaSearch", state.id), true)
	second, why = Do(w, viewer, a, "StartAreaSearch", 1415)
	eq(second, nil); eq(why, "cooldown", "rotation waits one minute after a successful start")

	w:Run(60)
	state = assert(Do(w, viewer, a, "StartAreaSearch", 1415))
	eq(state.mapID, 1415, "a fresh exact point from this handle authorizes its map")
	eq(Do(w, viewer, a, "CancelAreaSearch", state.id), true)

	local foreign = assert(Do(w, viewer, b, "StartPlayerSearch", "Other Choice-Emberfall"))
	local foreignRaw = host.sessions[foreign.id]
	foreignRaw.expiresAt = w.clock + 600
	foreignRaw.results[2].mapID = 1428
	foreignRaw.results[2].seenAt, foreignRaw.results[2].receivedAt = w.clock, w.clock + 1
	foreignRaw.results[2].expiresAt = w.clock + 600
	assert(Do(w, viewer, b, "GetPlayerSearch", foreign.id))
	eq(Do(w, viewer, b, "CancelPlayerSearch", foreign.id), true)
	w:Run(60)
	state, why = Do(w, viewer, a, "StartAreaSearch", 1428)
	eq(state, nil); eq(why, "map", "another handle's retained exact result is not an area source")
	state, why = Do(w, viewer, a, "StartAreaSearch", 1415)
	eq(state, nil); eq(why, "map", "the retained exact-result map stops at that result's own expiry")

	local revocable = assert(Do(w, viewer, a, "StartPlayerSearch", "Revocable Choice-Emberfall"))
	local revocableRaw = host.sessions[revocable.id]
	revocableRaw.expiresAt = w.clock + 600
	revocableRaw.results[2].mapID = 1427
	revocableRaw.results[2].seenAt, revocableRaw.results[2].receivedAt = w.clock, w.clock + 1
	revocableRaw.results[2].expiresAt = w.clock + 600
	assert(Do(w, viewer, a, "GetPlayerSearch", revocable.id))
	eq(Do(w, viewer, a, "CancelPlayerSearch", revocable.id), true)

	-- No ends the visible session and its local cadence. A later deliberate Yes and Start may begin a
	-- fresh current-map session without inheriting the old timer or retained exact-map evidence.
	w:As(viewer, C.Choose, "api:mappins", false)
	w:As(viewer, C.Choose, "api:mappins", true)
	state, why = Do(w, viewer, a, "StartAreaSearch", 1427)
	eq(state, nil); eq(why, "map", "permission revocation clears retained exact-map evidence")
	state = assert(Do(w, viewer, a, "StartAreaSearch", 1453))
	eq(state.mapID, 1453); eq(#host.areaStarts, 3, "only accepted starts reached the transport")
	W3.NoErrors(w)
end)

test("1.2.5 the API retained exact-result map proofs stay bounded per handle", function()
	local w, cast, viewer, API = Setup()
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	local host = SightingHost(viewer)
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)

	for i = 1, API.AREA_PROOF_MAX + 1 do
		if i > 1 and (i - 1) % (API.RATE_MAX - 1) == 0 then w:Run(API.RATE_WINDOW) end
		local search = assert(Do(w, viewer, api, "StartPlayerSearch", "Bounded" .. i .. "-Emberfall"))
		local raw = host.sessions[search.id]
		raw.results[2].mapID = 2000 + i
		raw.results[2].seenAt, raw.results[2].receivedAt = w.clock, w.clock + 1
		raw.results[2].expiresAt = w.clock + 10000 + i
		eq(Do(w, viewer, api, "CancelPlayerSearch", search.id), true)
	end
	w:Run(API.RATE_WINDOW)
	local state, why = Do(w, viewer, api, "StartAreaSearch", 2001)
	eq(state, nil); eq(why, "map", "the oldest-expiring proof is evicted after the per-handle bound")
	state = assert(Do(w, viewer, api, "StartAreaSearch", 2000 + API.AREA_PROOF_MAX + 1))
	eq(state.mapID, 2000 + API.AREA_PROOF_MAX + 1, "a fresher retained proof remains eligible")
	eq(Do(w, viewer, api, "CancelAreaSearch", state.id), true)
	W3.NoErrors(w)
end)

test("1.2.5 the API area sightings: a reused transport id never enters a stale handle's map frames", function()
	local w, cast, viewer, API = Setup()
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	local host = SightingHost(viewer)
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)
	local state = assert(Do(w, viewer, api, "StartAreaSearch", 1453))

	local pins = { rows = {}, seen = {} }
	function pins:AddWorldMapIconMap(ref, frame, mapID, x, y)
		self.rows[#self.rows + 1] = { ref = ref, frame = frame, mapID = mapID, x = x, y = y }
		self.seen[#self.seen + 1] = frame.row and frame.row.target
		return true
	end
	function pins:RemoveAllWorldMapIcons(ref)
		local keep = {}
		for _, row in ipairs(self.rows) do if row.ref ~= ref then keep[#keep + 1] = row end end
		self.rows = keep
	end
	viewer.ns.Pins = function() return pins end
	viewer.ns.WorldMapIcons = function() return true end
	local saved = { create = CreateFrame, parent = UIParent, map = WorldMapFrame, show = ShowUIPanel }
	UIParent = {}
	CreateFrame = function()
		local frame = {}
		function frame:SetSize() end
		function frame:CreateTexture() return { SetAllPoints = function() end, SetTexture = function() end } end
		function frame:SetScript() end
		function frame:Hide() self.hidden = true end
		function frame:Show() self.hidden = false end
		return frame
	end
	WorldMapFrame = { SetMapID = function() end }
	ShowUIPanel = function() return true end
	local future = w:As(viewer, viewer.ns.Now) + 1000
	for _, row in ipairs(host.sessions[state.id].results) do row.expiresAt = future end
	eq(Do(w, viewer, api, "ShowAreaSearchOnMap", state.id), true)
	eq(#pins.rows, 2)
	pins.seen = {}
	-- The bounded transport may reuse an id, but ownership includes the immutable map and creation
	-- time. The replacement must be rejected before any of its row is copied into this handle's pins.
	host.sessions[state.id] = {
		id = tonumber(state.id), mode = "area", scope = "hostile", mapID = 84, phase = "waiting",
		createdAt = state.createdAt + 50, expiresAt = future,
		results = { { target = "Replacement Secret-Realm", seenAt = 130, expiresAt = future,
			mapID = 84, x = 330, y = 440, layer = 2, kind = "nearby" } },
	}
	w:As(viewer, function() viewer.ns.Fire("PLAYER_SIGHTINGS_CHANGED", state.id) end)
	w:Run(API.DISPATCH_DELAY)
	eq(#pins.rows, 0, "the stale map view is cleared")
	eq(#pins.seen, 0, "the replacement row was never passed to the map library")
	eq(select(2, Do(w, viewer, api, "GetAreaSearch", state.id)), "unknown")
	CreateFrame, UIParent, WorldMapFrame, ShowUIPanel = saved.create, saved.parent, saved.map, saved.show
	W3.NoErrors(w)
end)

test("1.2.5 the API area sightings: a map-library false return leaves no partial host pins", function()
	local w, cast, viewer = Setup()
	viewer.mapID = 1453
	local O, C = viewer.OlympusAPI, viewer.Consent
	local host = SightingHost(viewer)
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)
	local state = assert(Do(w, viewer, api, "StartAreaSearch", 1453))

	local pins = { rows = {}, clears = 0, calls = 0 }
	function pins:AddWorldMapIconMap(ref, frame, mapID, x, y)
		self.calls = self.calls + 1
		self.rows[#self.rows + 1] = { ref = ref, frame = frame, mapID = mapID, x = x, y = y }
		return self.calls < 2
	end
	function pins:RemoveAllWorldMapIcons(ref)
		local keep = {}
		for _, row in ipairs(self.rows) do if row.ref ~= ref then keep[#keep + 1] = row end end
		self.rows, self.clears = keep, self.clears + 1
	end
	viewer.ns.Pins = function() return pins end
	viewer.ns.WorldMapIcons = function() return false end
	local saved = { create = CreateFrame, parent = UIParent, map = WorldMapFrame, show = ShowUIPanel }
	UIParent = {}
	CreateFrame = function()
		local frame = {}
		function frame:SetSize() end
		function frame:CreateTexture() return { SetAllPoints = function() end, SetTexture = function() end } end
		function frame:SetScript() end
		function frame:Hide() self.hidden = true end
		return frame
	end
	WorldMapFrame = { SetMapID = function() end }
	ShowUIPanel = function() return true end
	local future = w:As(viewer, viewer.ns.Now) + 1000
	for _, row in ipairs(host.sessions[state.id].results) do row.expiresAt = future end
	local ok, why = Do(w, viewer, api, "ShowAreaSearchOnMap", state.id)
	eq(ok, false); eq(why, "unsupported")
	eq(#pins.rows, 0, "an unsupported client keeps the sanitized rows but claims no pins")
	eq(#assert(Do(w, viewer, api, "GetAreaSearch", state.id)).sightings, 2,
		"an unsupported map path does not remove the area results")
	viewer.ns.WorldMapIcons = function() return true end
	ok, why = Do(w, viewer, api, "ShowAreaSearchOnMap", state.id)
	eq(ok, false); eq(why, "failed")
	eq(#pins.rows, 0, "a false AddWorldMapIconMap result removes the first partial pin")
	assert(pins.clears >= 2, "the failed draw was cleaned up")
	CreateFrame, UIParent, WorldMapFrame, ShowUIPanel = saved.create, saved.parent, saved.map, saved.show
	W3.NoErrors(w)
end)

test("1.2.5 the API guild-tools route: named profiles and neutral sections stay host-owned", function()
	local w, _, viewer = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	rawset(viewer.ns, "Watch", nil)
	eq(w:As(viewer, O.Has, "ui.guild-tools"), false)
	local ok, why = Do(w, viewer, api, "OpenGuildTools")
	eq(ok, false); eq(why, "unavailable")

	local selected
	viewer.ns.UI = viewer.ns.UI or {}
	viewer.ns.UI.SelectTab = function(tab) selected = tab return true end
	local page, available = "justice", { desk = true, reports = true, cases = true, justice = true }
	viewer.ns.Watch = {
		Show = function(section, key)
			if section == "profile" and type(key) == "string" and key ~= "" then
				page = "profile:" .. key
				return
			end
			local wanted = section or "desk"
			page = available[wanted] and wanted or "desk"
		end,
		OpenMember = function(target)
			if target == "Hidden-Realm" then page = "profile:Wrong-Realm" return false, "access" end
			if target == "Bad-Realm" then error("host profile failure") end
			page = "profile:" .. target
			return true
		end,
		PageId = function() return page end,
	}
	eq(w:As(viewer, O.Has, "ui.guild-tools"), true, "the host route exposes no section data")
	eq(Do(w, viewer, api, "OpenGuildTools"), true,
		"host-owned UI routing does not disclose data while API consent is pending")
	eq(selected, "watch"); eq(page, "desk")
	for _, section in ipairs({ "reports", "cases", "justice" }) do
		selected = nil
		eq(Do(w, viewer, api, "OpenGuildTools", section), true, section)
		eq(selected, "watch"); eq(page, section)
	end

	selected = nil
	ok, why = Do(w, viewer, api, "OpenGuildTools", "profile")
	eq(ok, false); eq(why, "target"); eq(page, "justice", "a missing target changes no host page")
	eq(Do(w, viewer, api, "OpenGuildTools", "profile", "Target-Realm"), true)
	eq(selected, "watch"); eq(page, "profile:Target-Realm")

	selected = nil
	ok, why = Do(w, viewer, api, "OpenGuildTools", "profile", "Hidden-Realm")
	eq(ok, false); eq(why, "access"); eq(selected, nil)
	eq(page, "profile:Target-Realm", "a refused named profile restores the page that was open")
	ok, why = Do(w, viewer, api, "OpenGuildTools", "profile", "Bad-Realm")
	eq(ok, false); eq(why, "failed")
	eq(page, "profile:Target-Realm", "a failed named profile restores the page that was open")

	ok, why = Do(w, viewer, api, "OpenGuildTools", "chat")
	eq(ok, false); eq(why, "access"); eq(selected, nil, "a hidden host section cannot be forced open")
	eq(page, "profile:Target-Realm", "a refused route restores the page that was open")
	ok, why = Do(w, viewer, api, "OpenGuildTools", "ban")
	eq(ok, false); eq(why, "section", "only documented host sections are accepted")

	viewer.ns.UI.SelectTab = function() return false, "blocked" end
	ok, why = Do(w, viewer, api, "OpenGuildTools", "reports")
	eq(ok, false); eq(why, "blocked", "a host navigation refusal is preserved")
	eq(page, "profile:Target-Realm", "a refused tab navigation restores the page that was open")
	viewer.ns.UI.SelectTab = function(tab) selected = tab return true end
	w:As(viewer, C.Choose, "api:mappins", false)
	selected = nil
	eq(Do(w, viewer, api, "OpenGuildTools", "reports"), true,
		"a data No does not disable Olympus's own accessible page")
	eq(selected, "watch"); eq(page, "reports")
	local pageCalls = 0
	viewer.ns.Watch.PageId = function() pageCalls = pageCalls + 1 error("host state unavailable") end
	ok, why = Do(w, viewer, api, "OpenGuildTools", "cases")
	eq(ok, false); eq(why, "failed"); eq(pageCalls, 1)
	eq(page, "reports", "an unreadable prior page fails before changing host state")
	viewer.ns.Watch.PageId = function() return page end
	viewer.guild = nil
	ok, why = Do(w, viewer, api, "OpenGuildTools")
	eq(ok, false); eq(why, "guild", "outside the guild there is no guild-tools route")
	viewer.guild = World.GUILD
	viewer.ns.UI.SelectTab = function() error("UI failure") end
	ok, why = Do(w, viewer, api, "OpenGuildTools")
	eq(ok, false); eq(why, "failed", "a host UI failure is contained")
	eq(page, "reports", "a thrown tab failure restores the prior host page")
	W3.NoErrors(w)
end)

test("1.2.4 the API: one shared UI surface, opaque ownership, retry after rejection, and lifecycle calls routed to its owner", function()
	local w, cast, viewer = Setup()
	local host = SurfaceHost(viewer)
	local O = viewer.OlympusAPI
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local first = w:As(viewer, O.Register, "MapPins")
	local second = w:As(viewer, O.Register, "BountyBoard")

	for _, method in ipairs({ "OpenSurface", "ToggleSurface", "RefreshSurface", "IsSurfaceOpen" }) do
		local ok, why = Do(w, viewer, first, method)
		eq(ok, false, method); eq(why, "unregistered", method)
	end
	eq(#host.calls, 0, "nothing reaches UI before that handle registers its surface")

	local ok, why = Do(w, viewer, first, "RegisterSurface", { label = "" })
	eq(ok, false); eq(why, "invalid-label", "host validation is returned")
	eq(Do(w, viewer, first, "RegisterSurface", { label = "Map tools", icon = "Interface\\Icons\\INV_Misc_Map_01", build = function() end }), true,
		"a rejected specification does not consume the handle's one surface")
	local firstOwner = host.calls[2].owner
	assert(type(firstOwner) == "string" and firstOwner ~= "", "an internal owner slot")
	for _, private in ipairs({ "MapPins", "mappins", "api:mappins" }) do
		eq(firstOwner:lower():find(private:lower(), 1, true), nil, "the owner does not identify its caller")
	end
	eq(first.surfaceOwner, nil, "the owner is not exposed by the handle")
	local calls = #host.calls
	ok, why = Do(w, viewer, first, "RegisterSurface", { label = "Another page" })
	eq(ok, false); eq(why, "registered"); eq(#host.calls, calls, "a second surface is refused before UI")

	ok, why = Do(w, viewer, second, "RegisterSurface", {
		label = "Bounty tools", icon = "Interface\\Icons\\INV_Misc_Note_01", build = function() end,
	})
	eq(ok, false); eq(why, "surface-full", "data handles remain available after the one shared surface slot is used")
	local secondOwner = host.calls[#host.calls].owner
	assert(secondOwner ~= firstOwner, "each handle is still assigned a different opaque owner slot")
	for _, private in ipairs({ "BountyBoard", "bountyboard", "api:bountyboard" }) do
		eq(secondOwner:lower():find(private:lower(), 1, true), nil, "the refused owner's slot does not identify its caller")
	end

	eq(Do(w, viewer, first, "IsSurfaceOpen"), false)
	eq(Do(w, viewer, first, "OpenSurface"), true)
	eq(Do(w, viewer, first, "IsSurfaceOpen"), true)
	eq(select(2, Do(w, viewer, second, "IsSurfaceOpen")), "unregistered", "the refused handle owns no surface")
	eq(Do(w, viewer, first, "RefreshSurface"), true)
	eq(Do(w, viewer, first, "ToggleSurface"), true)
	eq(Do(w, viewer, first, "IsSurfaceOpen"), false)
	for _, call in ipairs(host.calls) do
		assert(call.owner == firstOwner or call.owner == secondOwner, "every call carries an assigned owner")
	end
	W3.NoErrors(w)
end)

test("1.2.4 the API: UI surfaces work while data consent is pending or refused; data reads remain blocked", function()
	local w, cast, viewer = Setup()
	SurfaceHost(viewer)
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	eq(Do(w, viewer, api, "Status"), "pending")
	eq(Do(w, viewer, api, "RegisterSurface", { label = "Map tools", icon = "Interface\\Icons\\INV_Misc_Map_01", build = function() end }), true)
	eq(Do(w, viewer, api, "OpenSurface"), true)
	eq(Do(w, viewer, api, "IsSurfaceOpen"), true)
	local data, why = Do(w, viewer, api, "GetProfile")
	eq(data, nil); eq(why, "pending", "surface access does not grant data access")

	eq(w:As(viewer, C.Choose, "api:mappins", false), true)
	eq(Do(w, viewer, api, "Status"), "refused")
	eq(Do(w, viewer, api, "RefreshSurface"), true)
	eq(Do(w, viewer, api, "ToggleSurface"), true)
	eq(Do(w, viewer, api, "IsSurfaceOpen"), false)
	data, why = Do(w, viewer, api, "GetWanted")
	eq(data, nil); eq(why, "refused", "refused data stays blocked")
	W3.NoErrors(w)
end)

test("1.2.4 the API: nothing before a deliberate authorization nor after No; Keep current choices grants nothing and Authorize all grants visible pending lines", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	-- Every line the page had shown already (the player closed it): no question waits.
	w:As(viewer, function() C.Show() C.Hide() end)
	eq(w:As(viewer, C.Waiting), false)
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	local told = {}
	eq(Do(w, viewer, api, "On", "PERMISSION_CHANGED", function(event, status) told[#told + 1] = event .. ":" .. tostring(status) end), true)
	eq(w:As(viewer, C.Waiting), true, "a new question: the addon's line")
	eq(w:As(viewer, C.Ask, "login"), true, "the page opens by itself for it")
	w:As(viewer, C.Hide)
	eq(w:As(viewer, C.Ask, "login"), false, "once: closed unanswered, it never opens by itself again for it")
	for _, m in ipairs({ "GetWanted", "GetRankings", "GetProfile" }) do
		local data, why = Do(w, viewer, api, m)
		eq(data, nil, m); eq(why, "pending", m)
	end
	-- The secondary action closes without granting this explicit line.
	w:As(viewer, function() C.Show() C.KeepCurrent() end)
	eq(Do(w, viewer, api, "Status"), "pending", "Keep current choices grants nothing")
	eq(Do(w, viewer, api, "GetWanted"), nil)
	eq(#told, 0)
	-- No: nothing, and the addon is told.
	eq(w:As(viewer, C.Choose, "api:mappins", false), true)
	eq(Do(w, viewer, api, "Status"), "refused")
	local data, why = Do(w, viewer, api, "GetProfile")
	eq(data, nil); eq(why, "refused")
	eq(told[1], "PERMISSION_CHANGED:refused")
	-- Yes: it reads.
	eq(w:As(viewer, C.Choose, "api:mappins", true), true)
	eq(Do(w, viewer, api, "Status"), "granted")
	eq(told[2], "PERMISSION_CHANGED:granted")
	assert(type(Do(w, viewer, api, "GetWanted")) == "table", "granted: the Wanted rows")
	eq(viewer.db.apiAddons.mappins.on, true); eq(viewer.db.apiAddons.mappins.v, API.CONSENT_VERSION)
	-- Another addon is asked on its own: the first one's Yes is not its.
	Install(viewer, "BountyBoard", "Bounty Board")
	local other = w:As(viewer, O.Register, "BountyBoard")
	eq(Do(w, viewer, other, "Status"), "pending")
	eq(Do(w, viewer, other, "GetWanted"), nil)
	w:As(viewer, function() C.Show() C.AuthorizePending() end)
	eq(Do(w, viewer, other, "Status"), "granted", "Authorize all deliberately grants the visible pending addon")
	-- The next session: the account's answer stands, and the page asks nothing again for it.
	w:Logout(viewer); w:Login(viewer)
	W3.Rules(w, viewer)
	Install(viewer, "MapPins", "Map Pins")
	LoadAPI(w, viewer)
	PlantWanted(w, viewer)
	api = w:As(viewer, viewer.OlympusAPI.Register, "MapPins")
	eq(Do(w, viewer, api, "Status"), "granted", "kept for the account")
	eq(w:As(viewer, viewer.Consent.Answer, "api:mappins"), true)
	eq(w:As(viewer, viewer.Consent.Waiting), false, "asked once, for good")
	-- A Yes given for what an older API gave is asked again.
	viewer.db.apiAddons.mappins.v = API.CONSENT_VERSION - 1
	eq(Do(w, viewer, api, "Status"), "pending")
	eq(Do(w, viewer, api, "GetWanted"), nil)
	W3.NoErrors(w)
end)

test("1.2.4 the API: a granted addon gets copies of exactly what the pages show: the Wanted rows, the Slayers boards, the donors' and the Church's top three, the published games; its own profile; outside an Olympus guild, only that", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)
	-- Wanted: the active entry alone (the taken-off one stays off), the fields its row shows.
	local rows = Do(w, viewer, api, "GetWanted")
	eq(#rows, 1)
	eq(Keys(rows[1]), "bounty,cycle,guid,kills,name,place")
	eq(rows[1].name, HORDE.name); eq(rows[1].guid, HORDE.guid); eq(rows[1].bounty, 42); eq(rows[1].kills, 3); eq(rows[1].cycle, 2); eq(rows[1].place, 1)
	-- What the Wanted tab lists, the same order: Wanted.Targets (the page's own call).
	local page = w:As(viewer, viewer.ns.Wanted.Targets, true)
	eq(page[1].name, rows[1].name); eq(page[1].current, rows[1].bounty)
	-- Rankings: every kind; the Slayers' month and all time, as the tab's boards.
	local r = Do(w, viewer, api, "GetRankings")
	-- (Review of 1.2.4: no donors while the King keeps the Treasury's ranking from the army, the
	-- default; this test asked for them at once before.)
	eq(Keys(r), "games,slayers")
	eq(Keys(r.slayers), "all,month")
	eq(#r.slayers.month, 1); eq(r.slayers.month[1].name, N.fighterA); eq(r.slayers.month[1].points, 70)
	eq(Keys(r.slayers.month[1]), "claims,name,place,points")
	eq(#r.slayers.all, 2); eq(r.slayers.all[2].name, N.fighterB); eq(r.slayers.all[2].place, 2)
	eq(r.slayers.signed, nil, "no signed top three held")
	eq(r.donors, nil, "the Treasury's ranking kept from the army: no donors (below once shown)")
	-- The games: none the King kept to the staff.
	eq(Keys(r.games), "")
	eq(Do(w, viewer, api, "GetRankings", "games").lottery, nil)
	-- The Church's top three while its public ranking is open (ChurchCount.Top3), nothing else of it.
	rawset(viewer.ns, "ChurchCount", { Top3 = function()
		return { at = w.clock, by = "Keeper Name", apostles = { N.bettor2 }, missionaries = { N.bettor3, viewer.name } }
	end })
	local church = Do(w, viewer, api, "GetRankings", "church")
	eq(Keys(church), "apostles,missionaries"); eq(church.missionaries[2], viewer.name); eq(church.apostles[1], N.bettor2)
	rawset(viewer.ns, "ChurchCount", { Top3 = function() return nil end })
	eq(Do(w, viewer, api, "GetRankings", "church"), nil, "closed: nothing")
	eq(select(2, Do(w, viewer, api, "GetRankings", "census")), "kind")
	-- Lottery history is private even with a prior public ranking word.
	viewer.db.lotteryWinners = { L = { e1 = { at = w.clock - 3600, rows = { { name = N.bettor3, beast = 7, amount = 25000 } } } } }
	eq(W3.M(w, cast.king, "ArenaHome").SetRankingsPublic(true, "lottery"), false)
	assert(W3.M(w, cast.king, "ArenaRoles").Publish("lottery", true)) -- an older client's word
	w:Run(1)
	eq(w:As(viewer, viewer.ns.ArenaHome.RankingsPublic, "lottery"), false, "never a public Lottery ranking")
	local games = Do(w, viewer, api, "GetRankings", "games")
	eq(games.lottery, nil, "private saved winners are never exported")
	eq(viewer.db.lotteryWinners.L.e1.rows[1].name, N.bettor3, "the history is retained")
	-- The profile: his guild, rank and role, the frame and title his profile shows.
	local p = Do(w, viewer, api, "GetProfile")
	eq(Keys(p), "frame,guild,member,name,rank,rankIndex,role")
	eq(p.member, true); eq(p.name, viewer.name); eq(p.guild, World.GUILD); eq(p.rank, "Member"); eq(p.rankIndex, 3); eq(p.role, "member")
	eq(p.frame, "rank"); eq(p.title, nil)
	-- His pick: the all-time donors' frame he holds (third), and its title.
	eq(W3.M(w, viewer, "ArenaProfile").SetPick("donor-top-3", "donor-top-3"), true)
	p = Do(w, viewer, api, "GetProfile")
	eq(p.frame, "donor-top-3"); eq(p.title, w:As(viewer, viewer.ns.HonorsNet.TitleText, "donor-top-3"))
	assert(type(p.title) == "string" and p.title ~= "", "the title's words")
	-- The King's own: his role.
	LoadAPI(w, cast.king, false)
	Install(cast.king, "MapPins", "Map Pins")
	local kapi = w:As(cast.king, cast.king.OlympusAPI.Register, "MapPins")
	w:As(cast.king, cast.king.Consent.Choose, "api:mappins", true)
	eq(Do(w, cast.king, kapi, "GetProfile").role, "king")
	eq(Do(w, cast.king, kapi, "GetProfile").rankIndex, 0)
	-- Outside an Olympus guild: that he is in none, and nothing else.
	viewer.guild = nil
	p = Do(w, viewer, api, "GetProfile")
	eq(Keys(p), "member"); eq(p.member, false)
	local none, why = Do(w, viewer, api, "GetWanted")
	eq(none, nil); eq(why, "guild")
	eq(select(2, Do(w, viewer, api, "GetRankings")), "guild")
	viewer.guild = World.GUILD
	-- The donors' top three once the King shows the army the Treasury's ranking: the names the
	-- Treasurer's word gave every client (this world wears every family's frame: the month's too).
	W3.M(w, cast.king, "Treasury").SetFlag("ranking", true)
	w:Run(1)
	r = Do(w, viewer, api, "GetRankings")
	eq(Keys(r), "donors,games,slayers")
	eq(Keys(r.donors), "all,month")
	eq(r.donors.all[1], cast.A.name); eq(r.donors.all[3], viewer.name)
	W3.NoErrors(w)
end)

-- (1.2.4, the author's report: "many with 0 points, 0 kills on the Most Wanted list": they are not
-- on it any more, and the API reads the tab's list.)
test("1.2.4 the API: GetWanted lists what the Wanted tab lists: a Horde player with 0 points and 0 kills (one a member killed who killed none of ours) is left out, though his entry and its claim stay", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)
	local at = w.clock - 300
	viewer.rdb.wanted.targets["g:Player-4002-0000F00D"] = { key = "g:Player-4002-0000F00D", name = "Prey Only-Emberfall",
		guid = "Player-4002-0000F00D", active = true, addedAt = at, source = "PARTY_KILL", current = 0, lifetimeKills = 0, cycle = 2,
		openSince = at, victimOverflow = 0, victims = {},
		claims = { { id = "c2", slayer = N.fighterA, points = 50, cycle = 1, at = at, evidence = "PARTY_KILL", level = 25 } } }
	eq(#w:As(viewer, viewer.ns.Wanted.Targets, true), 2, "both entries on the ledger")
	local rows = Do(w, viewer, api, "GetWanted")
	eq(#rows, 1, "only the one wanted"); eq(rows[1].guid, HORDE.guid)
	local page = w:As(viewer, viewer.ns.Wanted.Targets, "listed")
	eq(#page, 1); eq(page[1].guid, rows[1].guid, "the tab's list")
	W3.NoErrors(w)
end)

test("1.2.4 the API Lottery privacy: even an older ArenaHome exposing a public Lottery word cannot export saved winners", function()
	local w, cast, viewer = Setup()
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, viewer.OlympusAPI.Register, "MapPins")
	w:As(viewer, viewer.Consent.Choose, "api:mappins", true)
	viewer.db.lotteryWinners = { L = { old = { at = w.clock - 10, rows = { { name = N.bettor3, beast = 7, amount = 25000 } } } } }
	-- This is the verified old ArenaHome contract, whose per-game publish word exposed Lottery.
	viewer.ns.ArenaHome.RankingsPublic = function(game) return game == "lottery" end
	local result = Do(w, viewer, api, "GetRankings", "games")
	eq(result.lottery, nil, "the API itself enforces private Lottery history")
	eq(viewer.db.lotteryWinners.L.old.rows[1].name, N.bettor3, "the private record survives")
	W3.NoErrors(w)
end)

test("1.2.4 the API: every table is the addon's own copy: changing it changes nothing of Olympus's, nor what the next call or another addon gets", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)
	-- (The donors come only while the King shows the army the Treasury's ranking: review of 1.2.4.)
	W3.M(w, cast.king, "Treasury").SetFlag("ranking", true)
	w:Run(1)
	local rows = Do(w, viewer, a, "GetWanted")
	rows[1].bounty, rows[1].name, rows[1].guid = 99999, "Someone Else", "Player-1-00000001"
	rows[2] = { name = "Injected" }
	local r = Do(w, viewer, a, "GetRankings")
	r.slayers.all[1].points = 1
	table.remove(r.slayers.all, 2)
	r.donors.all[1] = "Mallory"
	local p = Do(w, viewer, a, "GetProfile")
	p.guild, p.role, p.frame = "Other", "king", "donor-top-1"
	-- Olympus's own: as before.
	local t = viewer.rdb.wanted.targets["g:" .. HORDE.guid]
	eq(t.current, 42); eq(t.name, HORDE.name); eq(t.guid, HORDE.guid)
	local s = viewer.rdb.wanted.slayers["g:" .. SECRET.slayerGuid]
	eq(s.total, 70)
	eq(w:As(viewer, viewer.ns.HonorsNet.Donors).all[1], cast.A.name)
	eq(#w:As(viewer, viewer.ns.Wanted.Targets, true), 1)
	-- The next call, and the other addon: the true rows.
	for _, h in ipairs({ a, b }) do
		local again = Do(w, viewer, h, "GetWanted")
		eq(#again, 1); eq(again[1].bounty, 42); eq(again[1].name, HORDE.name)
		local rr = Do(w, viewer, h, "GetRankings")
		eq(#rr.slayers.all, 2); eq(rr.slayers.all[1].points, 70); eq(rr.donors.all[1], cast.A.name)
		local pp = Do(w, viewer, h, "GetProfile")
		eq(pp.guild, World.GUILD); eq(pp.role, "member"); eq(pp.frame, "rank")
	end
	assert(Do(w, viewer, a, "GetWanted") ~= Do(w, viewer, a, "GetWanted"), "a fresh table each call")
	W3.NoErrors(w)
end)

test("1.2.4 the API: rate-limited per addon (RATE_MAX calls a RATE_WINDOW), the others unaffected; Status and On cost nothing", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)
	for i = 1, API.RATE_MAX do assert(type(Do(w, viewer, a, i % 2 == 0 and "GetWanted" or "GetProfile")) == "table", "call " .. i) end
	for _ = 1, 30 do Do(w, viewer, a, "Status") end
	local data, why = Do(w, viewer, a, "GetWanted")
	eq(data, nil); eq(why, "busy", "past the rate")
	assert(type(Do(w, viewer, b, "GetWanted")) == "table", "another addon's own rate")
	local logged = 0
	for _, l in ipairs(viewer.log) do if l:find("api: MapPins asked more than", 1, true) then logged = logged + 1 end end
	eq(logged, 1, "said once in the log")
	w:Run(API.RATE_WINDOW)
	assert(type(Do(w, viewer, a, "GetWanted")) == "table", "the next window")
	-- (Review of 1.2.4) An addon polling past the rate window after window: still that one line, not
	-- one a window (they filled the log's ring and the last lines /oly bug copies).
	for window = 1, 6 do
		local busy = 0
		for _ = 1, API.RATE_MAX + 5 do
			if select(2, Do(w, viewer, a, "GetProfile")) == "busy" then busy = busy + 1 end
		end
		assert(busy >= 5, "window " .. window .. ": past the rate (" .. busy .. ")")
		w:Run(API.RATE_WINDOW)
	end
	local function Lines(name)
		local n = 0
		for _, l in ipairs(viewer.log) do if l:find("api: " .. name .. " asked more than", 1, true) then n = n + 1 end end
		return n
	end
	eq(Lines("MapPins"), 1, "once a session, however many windows")
	-- The other addon's own line, once too.
	for _ = 1, 2 * API.RATE_MAX do Do(w, viewer, b, "GetProfile") end
	w:Run(API.RATE_WINDOW)
	for _ = 1, 2 * API.RATE_MAX do Do(w, viewer, b, "GetProfile") end
	eq(Lines("BountyBoard"), 1); eq(Lines("MapPins"), 1)
	W3.NoErrors(w)
end)

test("1.2.4 the API: callbacks fire on a change, once a burst settles, only when what the call returns changed, never in combat nor for an addon without a Yes; an erroring callback is contained, logged, dropped after three errors", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	Install(viewer, "BountyBoard", "Bounty Board")
	Install(viewer, "Quiet", "Quiet")
	local a = w:As(viewer, O.Register, "MapPins")
	local b = w:As(viewer, O.Register, "BountyBoard")
	local q = w:As(viewer, O.Register, "Quiet")
	w:As(viewer, C.Choose, "api:mappins", true)
	w:As(viewer, C.Choose, "api:bountyboard", true)
	-- (The donors' frame Lida holds switches on by itself the first time her honours are looked at,
	-- Honors.Update: a real change of her profile. Looked at once here, before anyone listens.)
	w:As(viewer, viewer.ns.HonorsNet.Refresh)
	eq(Do(w, viewer, a, "GetProfile").frame, "donor-top-3", "her new honour, switched on by itself")
	local got, bad, good, quiet, profiles, rankings = {}, 0, {}, 0, {}, {}
	eq(Do(w, viewer, a, "On", "WANTED_CHANGED", function(event, rows) got[#got + 1] = { event = event, rows = rows } rows[1].bounty = -1 end), true)
	eq(Do(w, viewer, a, "On", "NOT_AN_EVENT", function() end), false)
	eq(Do(w, viewer, b, "On", "WANTED_CHANGED", function() bad = bad + 1 error("addon bug") end), true)
	eq(Do(w, viewer, b, "On", "WANTED_CHANGED", function(_, rows) good[#good + 1] = rows end), true)
	eq(Do(w, viewer, q, "On", "WANTED_CHANGED", function() quiet = quiet + 1 end), true, "an addon without a Yes may listen")
	eq(Do(w, viewer, a, "On", "PROFILE_CHANGED", function(_, p) profiles[#profiles + 1] = p end), true)
	eq(Do(w, viewer, a, "On", "RANKINGS_CHANGED", function(_, r) rankings[#rankings + 1] = r end), true)
	local function Fire(event) w:As(viewer, viewer.ns.Fire, event) end
	local t = viewer.rdb.wanted.targets["g:" .. HORDE.guid]
	-- A burst of changes: told once, DISPATCH_DELAY after (the bounty, and a Slayer's points).
	t.current = 50
	viewer.rdb.wanted.slayers["g:" .. SECRET.slayerGuid].total = 75
	for _ = 1, 5 do Fire("WANTED_CHANGED") end
	eq(#got, 0, "not at once")
	w:Run(API.DISPATCH_DELAY)
	eq(#got, 1, "once for the burst")
	eq(got[1].event, "WANTED_CHANGED"); eq(got[1].rows[1].bounty, -1, "the addon's own copy, changed by it")
	eq(#good, 1); eq(good[1][1].bounty, 50, "the other addon's copy: untouched by the first")
	eq(bad, 1); eq(quiet, 0, "nothing without a Yes")
	eq(t.current, 50, "Olympus's own: untouched")
	local failed = 0
	for _, l in ipairs(viewer.log) do if l:find("api: BountyBoard's WANTED_CHANGED callback failed", 1, true) then failed = failed + 1 end end
	eq(failed, 1, "the error in the log, with the addon's name")
	eq(#viewer.errors, 0, "never Olympus's error report")
	eq(#rankings, 1, "the Slayers boards are told too (a Wanted change)")
	eq(rankings[1].slayers.all[1].points, 75)
	-- The same rows again: nothing to tell.
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(#got, 1, "no change: no call")
	-- In combat: it waits.
	viewer.combat = true
	t.lifetimeKills = 4
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(#got, 1, "in combat: not yet")
	viewer.combat = false
	w:Run(API.COMBAT_RETRY)
	eq(#got, 2, "after combat"); eq(got[2].rows[1].kills, 4)
	-- The failing callback goes after three errors; the others stay.
	t.current = 51
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(bad, 3)
	t.current = 52
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(bad, 3, "dropped"); eq(#good, 4); eq(#got, 4)
	local dropped = false
	for _, l in ipairs(viewer.log) do if l:find("api: BountyBoard's WANTED_CHANGED callback dropped", 1, true) then dropped = true end end
	eq(dropped, true)
	-- PROFILE_CHANGED: the pick (HONORS_CHANGED) changes the frame; a census change alone does not.
	Fire("DATA_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(#profiles, 0, "the profile did not change")
	eq(W3.M(w, viewer, "ArenaProfile").SetPick("rank"), true)
	w:Run(API.DISPATCH_DELAY)
	eq(#profiles, 1); eq(profiles[1].frame, "rank", "her rank's frame again")
	-- Off: no more calls; a No: none either.
	eq(Do(w, viewer, a, "Off", "WANTED_CHANGED"), true)
	t.current = 53
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(#got, 4, "off"); eq(#good, 5)
	w:As(viewer, C.Choose, "api:bountyboard", false)
	t.current = 54
	Fire("WANTED_CHANGED")
	w:Run(API.DISPATCH_DELAY)
	eq(#good, 5, "after the No: nothing")
	eq(quiet, 0)
	W3.NoErrors(w)
end)

test("1.2.4 the API: no secret ever comes back: not the realm key nor the sealed channel's name, the account key, a victim, a place, who added or took off an entry, a member's GUID", function()
	local w, cast, viewer, API = Setup()
	local O, C = viewer.OlympusAPI, viewer.Consent
	viewer.rdb.realmKey = "rk-Secret-0123456789"
	local channel = "Oly" .. H.ns.Comm.Hash36(viewer.rdb.realmKey)
	w:As(viewer, viewer.ns.Debts.MyKey)
	local seed, pk = viewer.db.arenaKey and viewer.db.arenaKey.seed, viewer.db.arenaKey and viewer.db.arenaKey.pk
	assert(type(seed) == "string" and #seed > 8, "the account's key")
	rawset(viewer.ns, "ChurchCount", { Top3 = function() return { at = w.clock, by = SECRET.by, apostles = { N.bettor2 }, missionaries = { N.bettor3 } } end })
	viewer.db.lotteryWinners = { L = { e1 = { at = w.clock - 3600, rows = { { name = N.bettor3, beast = 7, amount = 25000, sig = SECRET.source } } } } }
	for _, game in ipairs({ "arena", "bones", "lottery" }) do W3.M(w, cast.king, "ArenaHome").SetRankingsPublic(true, game) end
	w:Run(1)
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	local told = {}
	for _, e in ipairs(API.EVENTS) do Do(w, viewer, api, "On", e, function(event, data) told[#told + 1] = { event, data } end) end
	w:As(viewer, C.Choose, "api:mappins", true)
	viewer.rdb.wanted.targets["g:" .. HORDE.guid].current = 43
	for _, e in ipairs({ "WANTED_CHANGED", "HONORS_CHANGED", "CHURCH_TOP_CHANGED", "ARENA_CHANGED", "DATA_CHANGED" }) do w:As(viewer, viewer.ns.Fire, e) end
	w:Run(API.DISPATCH_DELAY)
	assert(#told >= 2, "callbacks told: " .. #told)
	local out = { Do(w, viewer, api, "GetWanted"), Do(w, viewer, api, "GetRankings"), Do(w, viewer, api, "GetProfile"), Do(w, viewer, api, "Status"), told }
	local strings = {}
	local function Walk(v, depth)
		assert(depth < 12, "no cycle")
		if type(v) == "table" then
			for k, x in pairs(v) do Walk(k, depth + 1) Walk(x, depth + 1) end
		elseif type(v) == "string" then
			strings[#strings + 1] = v
		else
			assert(v == nil or type(v) == "number" or type(v) == "boolean", "plain data only: " .. type(v))
		end
	end
	Walk(out, 0)
	assert(#strings > 10, "the returns were read: " .. #strings)
	local all = table.concat(strings, "\n"):lower()
	for what, s in pairs({ key = viewer.rdb.realmKey, channel = channel, seed = seed, pk = pk, victim = SECRET.victim, zone = SECRET.zone,
		sighting = SECRET.sighting, by = SECRET.by, slayerGuid = SECRET.slayerGuid, source = SECRET.source }) do
		eq(all:find(s:lower(), 1, true), nil, what .. " never comes back")
	end
	assert(all:find(HORDE.guid:lower(), 1, true), "the Horde player's GUID is his row's")
	W3.NoErrors(w)
end)

test("1.2.4 the API: read-only by its source: no send, no message, no window, no game event, no timer at load; the TOC loads it after the boards it reads", function()
	local src = Read(H.ADDON_DIR .. "API.lua"):gsub("%-%-[^\n]*", "")
	for _, word in ipairs({ "Comm.", "SendChatMessage", "SendAddonMessage", "Whisper", "Send(", "Decree", "ShowDialog", "StaticPopup",
		"RegisterEvent", "ns.Every", "SetCVar", "ns.Print", "_G[", "hooksecurefunc" }) do
		eq(src:find(word, 1, true), nil, "API.lua uses " .. word)
	end
	local toc, at, n = Read(H.ADDON_DIR .. "Olympus.toc"), {}, 0
	for line in toc:gmatch("[^\r\n]+") do n = n + 1; at[line] = n end
	assert(at["API.lua"], "API.lua in the TOC")
	for _, f in ipairs({ "Consent.lua", "Wanted.lua", "Roster.lua", "King.lua" }) do assert(at[f] < at["API.lua"], "after " .. f) end
	assert(at["API.lua"] < at["ArenaMath.lua"], "a core file, before the Arena's load tail")
	assert(at["Locales\\APIText.lua"] and at["Locales\\APIText.lua"] < at["Core.lua"], "its words with the other locales")
	-- An idle client with the API loaded: no event, timer or frame of its own.
	local w = World.New()
	local a = w:Client("Lida Fenn")
	local events, timers, frames = 0, #w:Timers(a), #a.frames
	for _ in pairs(w:Events(a)) do events = events + 1 end
	LoadAPI(w, a, false)
	local after = 0
	for _ in pairs(w:Events(a)) do after = after + 1 end
	eq(after, events, "no game event"); eq(#w:Timers(a), timers, "no timer"); eq(#a.frames, frames, "no frame")
	w:As(a, a.ns.Fire, "WANTED_CHANGED")
	eq(#w:Timers(a), timers, "a change with nobody listening: no timer either")
end)

test("1.2.4 the API: its words in English and pt-BR; docs/API.md names every method and event; the README and the CurseForge page say the same", function()
	local L = H.ns.L
	local src = Read(H.ADDON_DIR .. "Locales/APIText.lua")
	local head, tail = src:match("^(.-)\nif GetLocale and GetLocale%(%) == \"ptBR\" then(\n.*)$")
	local en, pt = {}, {}
	for k in head:gmatch("\nL%.([%w_]+) =") do en[k] = true end
	for k in tail:gmatch("\n\tL%.([%w_]+) =") do pt[k] = true end
	eq(Keys(en), "API_AREA_EXACT,API_AREA_NEARBY,API_AREA_OUTSIDER,API_CONSENT_LABEL,API_CONSENT_TEXT,API_CONSENT_TEXT_BASIC,"
		.. "API_PIN_HOSTILE,API_PIN_MARKED,API_PIN_MARKS,API_PIN_NEARBY,API_PIN_OUTSIDER,API_PIN_OWN,API_PIN_SEEN,API_PIN_UNMARKED,API_PIN_YARDS")
	eq(Keys(pt), Keys(en))
	-- (1.2.5.1) An addon that is not authorized for the reserved features is asked only about its
	-- reads: since the quiet presence and the profile presentation are reserved too (2026-10-19), its
	-- line offers neither, while the authorized addon's line still describes both.
	do
		local k = "API_CONSENT_TEXT_BASIC"
		local basic = assert(src:match("\nL%." .. k .. ' = "(.-)"\n'), k)
		for _, word in ipairs({ "what Olympus shows you", "Never your location or the King's", "Authorize all", "Keep current choices",
			"addons you trust", "No, Keep current choices, or no answer: it receives nothing." }) do
			assert(basic:find(word, 1, true), k .. " says: " .. word)
		end
		for _, word in ipairs({ "King's presence", "search", "crown", " layer", "presentation", "caption", "issuer",
			"quiet presence", "High Councillor" }) do
			eq(basic:find(word, 1, true), nil, k .. " never offers: " .. word)
		end
		local ptBasic = assert(tail:match("\n\tL%." .. k .. ' = "(.-)"\n'), k .. " (pt-BR)")
		for _, word in ipairs({ "Nunca a sua localização nem a do Rei", "Autorizar tudo", "Manter escolhas atuais",
			"Não, Manter escolhas atuais ou sem resposta: ele não recebe nada." }) do
			assert(ptBasic:find(word, 1, true), k .. " (pt-BR) says: " .. word)
		end
		for _, word in ipairs({ "presença do Rei", "busca", "coroa", "camada", "apresentação", "legenda", "emissor",
			"presença silenciosa", "Alto Conselho" }) do
			eq(ptBasic:find(word, 1, true), nil, k .. " (pt-BR) never offers: " .. word)
		end
		local full = assert(src:match('\nL%.API_CONSENT_TEXT = "(.-)"\n'), "API_CONSENT_TEXT")
		local ptFull = assert(tail:match('\n\tL%.API_CONSENT_TEXT = "(.-)"\n'), "API_CONSENT_TEXT (pt-BR)")
		for _, word in ipairs({ "short host-owned profile-presentation session", "pre-approved caption", "quiet presence" }) do
			assert(full:find(word, 1, true), "API_CONSENT_TEXT still says: " .. word)
		end
		for _, word in ipairs({ "sessão curta de apresentação de perfil controlada pelo Olympus", "legenda pré-aprovada", "presença silenciosa" }) do
			assert(ptFull:find(word, 1, true), "API_CONSENT_TEXT (pt-BR) still says: " .. word)
		end
	end
	for _, word in ipairs({ "Seen nearby", "Exact last-seen point", "Visto nas proximidades", "Ponto exato do último avistamento",
		"Not hostile, outside Olympus's guilds", "Não hostil, fora das guildas do Olympus" }) do
		assert(src:find(word, 1, true), "the map tooltip says: " .. word)
	end
	for _, word in ipairs({ "exact-name last-seen search", "target, nameplate or mouseover observation",
		"observer and guild", "five-minute hostile-area search", "selected map ID", "at most six observations",
		"A visible Start must declare", "any list source it includes", "at least 60 seconds after the previous area start",
		"show the selected map and rotation position", "never open the world map automatically",
		"stop on Off, permission loss or UI reload",
		"at most 48 distinct hostile players", "Olympus-owned world-map pins",
		"target's native observed-unit or matching party/raid-unit point", "observer's nearby encounter point",
		"at most 64 observations", "only in memory", "up to 15 minutes", "Authorize all",
		"short host-owned profile-presentation session", "current signed issuer", "single fixed Olympus-owned style",
		"cannot choose a target, texture, atlas, colour, layout or arbitrary message", "pre-approved caption",
		"every 10 seconds", "about 32 seconds",
		"Keep current choices", "last-seen information, not continuous tracking",
		"no protected game action", "census", "keys" }) do
		assert(src:find(word, 1, true), "the line says: " .. word)
	end
	for _, word in ipairs({ "Nome-Reino exato", "busca curta por último avistamento de um nome exato",
		"alvo, placa de nome ou mouseover", "observador e sua guilda",
		"busca de cinco minutos por jogadores hostis", "ID do mapa selecionado", "no máximo seis observações",
		"Um Iniciar visível precisa declarar", "qualquer fonte de lista que incluir", "esperar pelo menos 60 segundos",
		"mostrar o mapa selecionado e a posição na rotação", "nunca abrir o mapa-múndi automaticamente",
		"parar ao Desligar, perder a permissão ou recarregar a interface",
		"no máximo 48 jogadores hostis distintos", "marcadores do mapa-múndi pertencentes ao Olympus",
		"ponto nativo do alvo observado ou da unidade correspondente no grupo ou raide", "ponto próximo do encontro",
		"sessão curta de apresentação de perfil controlada pelo Olympus", "emissor assinado atual",
		"único estilo fixo do Olympus", "não poderá escolher alvo, textura, atlas, cor, layout ou mensagem arbitrária",
		"legenda pré-aprovada", "a cada 10 segundos", "cerca de 32 segundos",
		"no máximo 64 observações", "só na memória", "por até 15 minutos", "Autorizar tudo",
		"Manter escolhas atuais", "último avistamento, não rastreamento contínuo",
		"nenhuma ação protegida", "censo", "chaves" }) do
		assert(src:find(word, 1, true), "the pt-BR line says: " .. word)
	end
	-- Its promises are Olympus's own: ordinary reads are passive, while the separately described,
	-- explicit search or visible user-started session is the only network action. What the other
	-- addon does with copies is its own.
	eq(head:find("it sends nothing for you", 1, true), nil, "no promise for the other addon")
	eq(tail:find("ele não envia nada por você", 1, true), nil, "no promise for the other addon (pt-BR)")
	for _, word in ipairs({ "what Olympus shows you", "what that addon then does with the copies is up to that addon", "addons you trust",
		"No, Keep current choices, or no answer: it receives nothing, starts no search and cannot enable the presentation" }) do
		assert(head:find(word, 1, true), "the line says: " .. word)
	end
	for _, word in ipairs({ "o que o Olympus mostra a você", "o que esse addon fizer depois com as cópias é responsabilidade dele",
		"em que você confia", "Não, Manter escolhas atuais ou sem resposta: ele não recebe nada, não inicia busca e não pode ativar a apresentação" }) do
		assert(tail:find(word, 1, true), "the pt-BR line says: " .. word)
	end
	local doc = Read(H.ROOT .. "docs/API.md")
	local observerConsent = Read(H.ADDON_DIR .. "Locales/PlayerSightingsText.lua")
	for _, word in ipairs({ "at most 64 observations", "in memory", "up to 15 minutes", "never saved",
		"five-minute hostile-area search", "selected map ID", "at most six",
		"at most 48 distinct hostile players", "world position that can be placed on your current map",
		"omits your identity and guild", "Authorize all",
		"no máximo 64 observações", "na memória", "posição no mundo que possa ser colocada no seu mapa atual",
		"busca de cinco minutos por jogadores hostis", "ID de mapa selecionado", "no máximo seis",
		"no máximo 48 jogadores hostis distintos", "por até 15 minutos", "nunca é salvo",
		"omite sua identidade e guilda", "Autorizar tudo" }) do
		assert(observerConsent:find(word, 1, true), "observer consent says: " .. word)
	end
	local api = Read(H.ADDON_DIR .. "API.lua")
	for m in api:gmatch("\nfunction METHODS%.(%u%a+)%(") do assert(doc:find(":" .. m .. "(", 1, true), "docs/API.md: " .. m) end
	for e in api:match("API%.EVENTS = (%b{})"):gmatch('"([%u_]+)"') do assert(doc:find(e, 1, true), "docs/API.md: " .. e) end
	for _, f in ipairs({ "OlympusAPI.VERSION", "OlympusAPI.SURFACE_LIMIT", "OlympusAPI.Has", "OlympusAPI.Register", "## OptionalDeps: Olympus", "/oly privacy" }) do
		assert(doc:find(f, 1, true), "docs/API.md: " .. f)
	end
	for _, word in ipairs({ '"ui.surface"', "one client-owned page", "availableWhenLocked", 'style = "old" or "hd"',
		"OlympusAPI.SURFACE_LIMIT", '"surface-full"', "works while the answer is pending or refused",
		"contains no addon name, consent key or", "expiry is enforced locally by each client",
		"x = 520, y = 375", 'kind = "exact-group"', "accuracyYards = 0",
		"receivedAt = 1792000125", "expiresAt = 1792001023", "must stop alerts and sharing",
		"bundled supported map library", "Conversion rejects another", "out-of-map coordinates",
		"at most 64 names for at most 15 minutes", "user-started tool session",
		"cancel a request before rotating it out", "stop alerts when a result expires",
		"list source that the same visible", "Do not append a silent list source",
		"initial snapshot", "queued-send transition", "terminal marker", "discard every previously copied result",
		"present a nearby encounter point as exact" }) do
		assert(doc:find(word, 1, true), "docs/API.md surface contract: " .. word)
	end
	for _, word in ipairs({ '"ui.guild-tools"', "handle:OpenGuildTools([section[, target]])",
		'`"profile"` requires', "Watch.OpenMember(target)", "remain inside the host-owned Watch page",
		"restores the Watch page" }) do
		assert(doc:find(word, 1, true), "docs/API.md guild-tools contract: " .. word)
	end
	for _, word in ipairs({ "handle:StartAreaSearch(mapID)", "handle:CancelAreaSearch(id)",
		"handle:GetAreaSearch(id)", "handle:GetAreaSearches()", "handle:ShowAreaSearchOnMap(id)",
		"handle:ClearAreaSearchMap([id])", "five-minute hostile-area search", "at most six distinct rows",
		"at most 48 target rows", "public rows omit the observer and guild", "an anchor name or an instruction",
		"this same handle owned", "result's own", "Permission loss and `/reload` discard every retained proof",
		"only one live area search", "at least 60 seconds apart",
		"show the selected map", "position in the rotation", "never open the world map automatically",
		"neither a later permission grant", "Passive configured names", '"active"', '"cooldown"',
		"pins refresh when that session changes", "client or gamepad UI that disables that path",
		"area rows remain readable", "removed on cancellation, expiry/completion" }) do
		assert(doc:find(word, 1, true), "docs/API.md area contract: " .. word)
	end
	for _, word in ipairs({ '"network.profile-effects"', "handle:StartProfileSession(style)",
		"handle:StopProfileSession()", "handle:SetProfileEffect(style, enabled[, caption])",
		"handle:GetProfileSession()", "PROFILE_EFFECT_SESSION_CHANGED", "issuer, grant identifier, caption",
		"10 seconds", "about 32 seconds", "memory-only", "available after permission is refused" }) do
		assert(doc:find(word, 1, true), "docs/API.md profile-presentation contract: " .. word)
	end
	eq(doc:find("trusted roster", 1, true), nil, "the public contract stays consumer-neutral")
	local sections = {}
	for _, path in ipairs({ "README.md", "docs/CURSEFORGE.md" }) do
		local page = Read(H.ROOT .. path)
		local s = page:match("\n### Other addons: the Olympus API %(1%.2%.4%)\n(.-)\n##")
		assert(s and s ~= "", path .. ": the section")
		assert(s:find("docs/API.md", 1, true), path .. ": its link")
		-- The public pages make the same distinction as the permission line: passive ordinary reads,
		-- one explicit bounded search or visible session, and the consuming addon's responsibility
		-- for its copies.
		eq(s:find("nothing is sent for you", 1, true), nil, path .. ": no promise for the other addon")
		for _, word in ipairs({ "send nothing. A compatible addon", "Name-Realm", "player sightings", "native",
			"five-minute hostile-area search", "selected map ID", "at most six", "at most 48 distinct players",
			"visible Start declares selected/configured names", "included list source", "one area at a time",
			"wait 60 seconds to rotate", "shows map/position and Stop/Off", "resumes after No or `/reload` automatically",
			"public area row", "sanitized area rows",
			"bounded profile presentation", "fixed style", "pre-approved caption", "no target, asset path or arbitrary text",
			"encounter point, rounded", "not continuous tracking", "at most 64", "only in memory",
			"Authorize all", "Keep current choices", "Requests and answers expire", "up to it", "authorize only addons",
			"while he shows the Treasury's ranking",
			"one such page per session", "data handles still work", "data answer is pending or refused", "hosting it grants no Olympus data" }) do
			assert(s:find(word, 1, true), path .. ": " .. word)
		end
		local privacy = page:match("\n%*%*What waits for your yes%.%*%*(.-)\n\n")
		for _, word in ipairs({ "ordinary reads send nothing",
			"authorized exact-name search sends the Name-Realm",
			"five-minute hostile-area search sends one selected map ID", "at most six rows from one observer and 48 distinct players at the requester",
			"visible Start declares selected/configured names", "included list sources",
			"one live area uses the current or an owned exact-result map until its row expires", "cancels before a 60-second rotation",
			"bounded host-owned profile-presentation session", "single fixed style on themself",
			"never accepts a target, asset path or arbitrary message",
			"Guild tools: player sightings", "up to 64 direct observations may remain only in memory",
			"what the addon does with its bounded copies is its own" }) do
			assert(privacy and privacy:find(word, 1, true), path .. ": privacy: " .. word)
		end
		eq(page:find("it reads on your computer alone", 1, true), nil, path .. ": no promise for the other addon")
		sections[#sections + 1] = s
	end
	eq(sections[1], sections[2], "the same words on both pages")
end)

-- Every string in a return, for what must never be in it.
local function Strings(v, out, depth)
	out, depth = out or {}, depth or 0
	assert(depth < 12, "no cycle")
	if type(v) == "table" then
		for k, x in pairs(v) do Strings(k, out, depth + 1) Strings(x, out, depth + 1) end
	elseif type(v) == "string" then
		out[#out + 1] = v:lower()
	end
	return out
end
local function NoName(v, names, what)
	local all = table.concat(Strings(v), "\n")
	for _, n in ipairs(names) do eq(all:find(n:lower(), 1, true), nil, what .. ": " .. n) end
end

-- (Review of 1.2.4) GetRankings gave the donors' top three of the month and of all time whatever
-- the King's switch: while he keeps the Treasury's ranking from the army (the default) no page
-- lists them. (1.2.4, after the borders lane: the month's koi is worn, so its three come too while
-- the ranking shows; a build without the koi gives none.) In a world as the release ships it (its frames,
-- Honors.FRAMES_SHIPPED), without the Wanted boards (so every name in a return is a donor's).
test("1.2.4 the API: the donors' top three only while the King shows the army the Treasury's ranking, never by the staff's view; the month's only in a build that wears its koi (1.2.4 does)", function()
	local w, cast, viewer, API = Setup({ wanted = false, world = { compliance = "shipped" } })
	local O, C = viewer.OlympusAPI, viewer.Consent
	eq(w:As(viewer, viewer.ns.Honors.FrameShipped, { family = "donor-month" }), true, "1.2.4 wears the koi")
	eq(w:As(viewer, viewer.ns.Honors.FrameShipped, { family = "donor-top" }), true)
	eq(w:As(viewer, viewer.ns.Treasury.PublicShows, "ranking"), false, "the King's switch: off until he turns it")
	local word = w:As(viewer, viewer.ns.HonorsNet.Donors)
	eq(#word.all, 3, "the Treasurer's word reached this client")
	local names = {}
	for _, n in ipairs(word.all) do names[#names + 1] = n end
	for _, n in ipairs(word.month or {}) do names[#names + 1] = n end
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)
	local told = {}
	eq(Do(w, viewer, api, "On", "RANKINGS_CHANGED", function(_, r) told[#told + 1] = r end), true)
	-- (The world settles first: the honours' first look and the words of the login are told, so the
	-- King's switch is the only change below.)
	w:Run(60)
	local base = #told
	-- Off: no donor's name comes back, by kind or with every ranking.
	local d, why = Do(w, viewer, api, "GetRankings", "donors")
	eq(d, nil, "the ranking kept from the army: no donors"); eq(why, nil)
	local r = Do(w, viewer, api, "GetRankings")
	eq(r.donors, nil)
	NoName(r, names, "every ranking")
	for _, t in ipairs(told) do NoName(t, names, "a callback") end
	-- The King sees the ranking on his own Treasury tab: his addon gets no more (never a staff view).
	LoadAPI(w, cast.king, false)
	Install(cast.king, "MapPins", "Map Pins")
	local kapi = w:As(cast.king, cast.king.OlympusAPI.Register, "MapPins")
	w:As(cast.king, cast.king.Consent.Choose, "api:mappins", true)
	eq(w:As(cast.king, cast.king.ns.Treasury.MaySee, "ranking"), true, "his tab shows it")
	eq(Do(w, cast.king, kapi, "GetRankings", "donors"), nil, "his addon: no donors either")
	NoName(Do(w, cast.king, kapi, "GetRankings"), names, "the King's addon")
	w:Run(60)
	eq(#told, base, "nothing changed")
	-- He shows the army the ranking: the all-time three, which head it, and the month's (its koi worn).
	W3.M(w, cast.king, "Treasury").SetFlag("ranking", true)
	w:Run(1)
	eq(w:As(viewer, viewer.ns.Treasury.PublicShows, "ranking"), true, "every client heard the King")
	d = Do(w, viewer, api, "GetRankings", "donors")
	eq(Keys(d), "all,month", "the month's too: its koi is worn")
	eq(table.concat(d.month, ","), table.concat(word.month or {}, ","))
	eq(table.concat(d.all, ","), table.concat(word.all, ","))
	-- A listener is told when the switch turns (Olympus's TREASURY_CHANGED), and when it turns back:
	-- then no name again.
	w:Run(API.DISPATCH_DELAY)
	eq(#told, base + 1, "told of the switch"); eq(table.concat(told[base + 1].donors.all, ","), table.concat(word.all, ","))
	w:Run(60)
	eq(#told, base + 1, "nothing else")
	W3.M(w, cast.king, "Treasury").SetFlag("ranking", false)
	w:Run(1)
	w:Run(API.DISPATCH_DELAY)
	eq(#told, base + 2, "told of it turning back"); eq(told[base + 2].donors, nil)
	NoName(told[base + 2], names, "the callback")
	eq(Do(w, viewer, api, "GetRankings", "donors"), nil)
	-- A build that does not wear the month's koi gives the all-time three alone.
	W3.M(w, cast.king, "Treasury").SetFlag("ranking", true)
	w:Run(1)
	viewer.ns.Honors.FRAMES_SHIPPED = { ["donor-top"] = true }
	d = Do(w, viewer, api, "GetRankings", "donors")
	eq(Keys(d), "all", "no koi: no month")
	W3.NoErrors(w)
end)

-- (Review of 1.2.4) 1.2.3's adoption took every line still waiting in an account's first session
-- with the record (1.2.2's saved data: the games notice shown, no record of the lines) as asked,
-- an addon's too, which no build before 1.2.4 asked: updating from 1.2.2 straight to 1.2.4, the
-- page never opened by itself for it. 1.2.1's lines stay taken as asked.
test("1.2.4 the API: an account updating from 1.2.2 is asked about an addon by itself once, after the login's wait; the old lines stay as 1.2.3 took them", function()
	local w, cast, viewer, API = Setup({ wanted = false })
	if viewer.Consent.Frame() then viewer.Consent.Frame():Hide() end
	viewer.db.consentNotices, viewer.db.consentAsked, viewer.db.consentAdopt = { games = true }, nil, nil
	viewer.db.apiAddons = nil
	local function Session()
		w:Logout(viewer)
		w:Login(viewer)
		W3.Rules(w, viewer)
		Install(viewer, "MapPins", "Map Pins")
		LoadAPI(w, viewer, false)
		-- The other addon registers as it loads, before the login's wait is over.
		local api = w:As(viewer, viewer.OlympusAPI.Register, "MapPins")
		assert(type(api) == "table", "its handle")
		return api, viewer.Consent
	end
	local api, C = Session()
	local old = {}
	for _, item in ipairs(w:As(viewer, C.Pending)) do
		if item.key ~= "api:mappins" then old[#old + 1] = item.key end
	end
	assert(#old > 0, "lines 1.2.2 left unanswered")
	w:Run(C.LOGIN_WAIT + 1)
	local page = C.Frame()
	assert(page and page:IsShown(), "the page opens by itself for the addon's line")
	eq(viewer.db.consentAsked["api:mappins"], API.CONSENT_VERSION, "shown: asked")
	for _, key in ipairs(old) do assert(viewer.db.consentAsked[key] ~= nil, key .. ": taken as asked, as 1.2.3 does") end
	page:Hide()
	eq(w:As(viewer, C.Ask, "login"), false, "once")
	eq(Do(w, viewer, api, "Status"), "pending", "nothing answered for him")
	-- The next session: never again by itself.
	api, C = Session()
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame() == nil or not C.Frame():IsShown(), true, "the next session: not again")
	eq(Do(w, viewer, api, "Status"), "pending")
	W3.NoErrors(w)
end)

-- (Review of 1.2.4) docs/API.md's examples, run as another addon runs them: the data events come
-- only on a change, so the title example set the title only once it changed, never at the Yes.
test("1.2.4 the API: docs/API.md's title example shows the player's title on his Yes and at load once granted", function()
	local w, cast, viewer, API = Setup({ wanted = false })
	local code = Read(H.ROOT .. "docs/API.md"):match("\nShowing the player's own title in your frame.-\n```lua\n(.-)```")
	assert(code, "the example")
	eq(W3.M(w, viewer, "ArenaProfile").SetPick("donor-top-3", "donor-top-3"), true)
	local title = w:As(viewer, viewer.ns.HonorsNet.TitleText, "donor-top-3")
	assert(type(title) == "string" and title ~= "", "his title's words")
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, viewer.OlympusAPI.Register, "MapPins")
	local function Load()
		local shown = {}
		local frame = { title = { SetText = function(_, text) shown[#shown + 1] = text end } }
		local fn = assert(loadstring(code, "=docs/API.md"))
		setfenv(fn, setmetatable({ api = api, MyFrame = frame }, { __index = _G }))
		w:As(viewer, fn)
		return shown
	end
	local shown = Load()
	eq(shown[#shown] or "", "", "before the Yes: no title")
	w:As(viewer, viewer.Consent.Choose, "api:mappins", true)
	eq(shown[#shown], title, "his title, on his Yes")
	eq(Load()[1], title, "already granted: at load")
	W3.NoErrors(w)
end)

-- 1.2.5.1: the Olympus Accord (Accord.lua). Until this account accepted it the player is no member
-- (ns.IsMember): a granted addon reads what it reads outside an Olympus guild ("guild", member =
-- false), and the contract stays (CONSENT_VERSION 9). Accepting it (Accord.lua's ACCORD_CHANGED,
-- fired here as the Accord fires it) tells every data event's listeners once the burst settles.
test("accord: the API before the Olympus Accord is accepted reads as outside an Olympus guild; once it is, WANTED, RANKINGS and PROFILE listeners are told", function()
	local w, cast, viewer, API = Setup()
	eq(API.CONSENT_VERSION, 9, "the contract unchanged")
	local O, C = viewer.OlympusAPI, viewer.Consent
	Install(viewer, "MapPins", "Map Pins")
	local api = w:As(viewer, O.Register, "MapPins")
	w:As(viewer, C.Choose, "api:mappins", true)
	assert(Do(w, viewer, api, "GetWanted"), "a member reads")
	local accord = viewer.db.accord
	viewer.db.accord = nil
	local p = Do(w, viewer, api, "GetProfile")
	eq(Keys(p), "member"); eq(p.member, false)
	local none, why = Do(w, viewer, api, "GetWanted")
	eq(none, nil); eq(why, "guild")
	eq(select(2, Do(w, viewer, api, "GetRankings")), "guild")
	local told = {}
	for _, event in ipairs({ "WANTED_CHANGED", "RANKINGS_CHANGED", "PROFILE_CHANGED" }) do
		eq(Do(w, viewer, api, "On", event, function(e) told[#told + 1] = e end), true)
	end
	w:Run(API.DISPATCH_DELAY)
	told = {}
	viewer.db.accord = accord
	w:As(viewer, viewer.ns.Fire, "ACCORD_CHANGED", true)
	w:Run(API.DISPATCH_DELAY)
	table.sort(told)
	eq(table.concat(told, ","), "PROFILE_CHANGED,RANKINGS_CHANGED,WANTED_CHANGED", "each told once")
	eq(Do(w, viewer, api, "GetProfile").member, true)
	W3.NoErrors(w)
end)
