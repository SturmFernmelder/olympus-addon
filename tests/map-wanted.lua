-- The map option is artwork-only; sightings consent and minimap pins stay independent.
local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]map%-wanted%.lua$") or "./"
local function Frame(name, frames)
	local f = { scripts = {}, shown = false, labels = {}, ScrollContainer = false, OnMapChanged = false }
	if name then frames[name] = f end
	function f:SetScript(event, fn) self.scripts[event] = fn end
	function f:GetScript(event) return self.scripts[event] end
	function f:Show() self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
	function f:Hide() self.shown = false end
	function f:IsShown() return self.shown end
	function f:SetShown(on) if on then self:Show() else self:Hide() end end
	function f:SetChecked(on) self.checked = on end
	function f:GetChecked() return self.checked end
	function f:SetAlpha(value) self.alpha = value end
	function f:SetMapID(value) self.mapID = value end
	function f:GetFrameLevel() return 1 end
	function f:CreateTexture() return Frame(nil, frames) end
	function f:CreateFontString()
		local label = Frame(nil, frames)
		function label:SetText(text) self.text = text end
		self.labels[#self.labels + 1] = label
		return label
	end
	return setmetatable(f, { __index = function() return function() end end })
end

local function WithMapWanted(fn)
	local names = { "CreateFrame", "WorldMapFrame", "UIParent", "ShowUIPanel", "GameTooltip", "IsInInstance", "UnitGUID", "UnitIsPlayer",
		"UnitFactionGroup", "UnitCanAttack", "UnitIsPVP", "GetGuildInfo", "C_Map", "issecretvalue" }
	local saved = {}
	for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
	local ok, err = pcall(function()
		local frames, hooks, world, mini = {}, {}, {}, {}
		local member, inside, worldAllowed = true, false, true
		local guid = "Player-1-0A000001"
		local lib = {}
		function lib:AddWorldMapIconMap(_, f, mapID, x, y) world[f] = true f.mapID, f.mapX, f.mapY = mapID, x, y end
		function lib:RemoveWorldMapIcon(_, f) world[f] = nil end
		function lib:AddMinimapIconMap(_, f) mini[f] = true end
		function lib:RemoveMinimapIcon(_, f) mini[f] = nil end
		CreateFrame = function(_, name) return Frame(name, frames) end
		UIParent, WorldMapFrame = Frame(nil, frames), Frame(nil, frames)
		ShowUIPanel = function(frame) frame:Show() end
		GameTooltip = Frame(nil, frames)
		IsInInstance = function() return inside end
		UnitGUID = function(unit) return unit == "target" and guid or "Player-1-0A000002" end
		UnitIsPlayer = function() return true end
		UnitFactionGroup = function() return "Horde" end
		UnitCanAttack, UnitIsPVP = function() return true end, function() return true end
		GetGuildInfo = function(unit) return unit == "player" and "Olympus" or nil end
		issecretvalue = function() return false end
		C_Map = { GetMapInfo = function() return { mapType = 3 } end,
			GetBestMapForUnit = function() return 1429 end,
			GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.5 end } end }
		local c = setmetatable({ db = {}, rdb = {}, Wanted = false, me = "Observer-Realm", faction = "Alliance",
			UI = {}, Consent = {}, Comm = {}, Data = { ServerTime = function() return 1800000000 end },
			Moderation = { SelfOff = function() return false end }, Layers = {},
			Gate = { Hooks = function(key, value) hooks[key] = value end, Allowed = function() return true end },
			On = function() end, RegisterEvent = function() end, IsMember = function() return member end,
			Pins = function() return lib end, MakeRoundButton = function(name) return Frame(name, frames) end,
			UnitFullName = function(unit) return unit == "target" and "Enemy-Realm" or "Observer-Realm" end,
			WorldMapIcons = function()
				if not worldAllowed then for f in pairs(world) do world[f] = nil end end
				return worldAllowed
			end }, { __index = ns })
		assert(loadfile(ROOT .. "Olympus/Map.lua"))("Olympus", c)
		hooks["map-overlay"].install()
		local menu = assert(frames.OlympusMapMenu)
		fn(c, menu, world, mini, guid, function(m, i, w) member, inside, worldAllowed = m, i, w end)
	end)
	for _, name in ipairs(names) do _G[name] = saved[name] end
	if not ok then error(err, 0) end
end

test("Wanted map option: labelled, enabled by default and safe without Wanted loaded", function()
	WithMapWanted(function(c, menu)
		local cb
		for _, check in ipairs(menu.checks) do if check.opt.key == "showWanted" then cb = check end end
		assert(cb, "Wanted checkbox exists")
		eq(menu.labels[#menu.labels].text, "Wanted")
		menu:Show(); eq(cb:GetChecked(), true)
		cb:SetChecked(false); cb:GetScript("OnClick")(cb); eq(c.db.showWanted, false)
		menu:Show(); eq(cb:GetChecked(), false)
		cb:SetChecked(true); cb:GetScript("OnClick")(cb); eq(c.db.showWanted, true)
		eq(c.db.wantedSightings, nil, "map choice never answers the consent question")
	end)
end)

test("Wanted last seen: an old zone stays dated on the list and map, focuses without invented coordinates, and native observation is separate", function()
	WithMapWanted(function(c, _, world, _, guid)
		c.Ago = function(at) return tostring(1800000000 - (tonumber(at) or 0)) .. "s" end
		c.Zones = { KeyForName = function(name) return name == "Elwynn Forest" and "m1429" or ("t" .. tostring(name)) end,
			MapID = function(key) return key == "m1429" and 1429 or nil end }
		c.WatchChat = { Barred = function() return nil end }
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		c.Wanted.CanManage = function() return true end
		assert(c.Wanted.AddTarget("Enemy-Realm", guid))
		local stored = assert(c.rdb.wanted.targets["g:" .. guid])
		stored.base = { lifetimeKills = 1, lastSighting = { zone = "Elwynn Forest", at = 1799000000,
			precision = "approximate", evidence = "SELF_DEATH" } }
		c.Wanted.Rebuild()

		local lines = c.Wanted.Build()
		local target, location
		for _, line in ipairs(lines) do
			if line.id == "wanted:g:" .. guid then target = line end
			if line.id == "wanted-location:g:" .. guid then location = line end
		end
		assert(target and location and location.onClick, "the list has a dated, actionable last-seen row")
		assert(location.text:find("Elwynn Forest", 1, true), location.text)
		assert(location.text:find(date("%Y-%m-%d %H:%M", 1799000000), 1, true), location.text)
		assert(location.text:find("1000000s", 1, true), location.text)
		assert(location.onClick())
		eq(WorldMapFrame.shown, true); eq(WorldMapFrame.mapID, 1429)

		c.Wanted.RefreshPins()
		local historical = assert(c.Wanted.HistoryFrames()[1429], "an old sighting remains on the map")
		assert(world[historical] == true, "history world state=" .. tostring(world[historical]) .. " onWorld=" .. tostring(historical.onWorld))
		eq(historical.mapX, 0.5); eq(historical.mapY, 0.5)
		assert(historical.badge.age.text and historical.badge.age.text ~= "", "the historical badge visibly carries its age")
		assert(historical.alpha and historical.alpha < 1, "the historical badge is visually stale")

		assert(target.onClick())
		local profile = c.Wanted.Build()
		local profileLocation
		for _, line in ipairs(profile) do
			if line.id == "wanted-location:g:" .. guid then profileLocation = line end
			assert(not tostring(line.text):find(c.L.WANTED_LAST_OBSERVED_LABEL, 1, true),
				"stored combat evidence is not called an online observation")
		end
		assert(profileLocation and profileLocation.onClick, "the profile keeps the same dated map action")
		c.db.wantedSightings = true
		assert(c.Wanted.ObserveUnit("target"), "the game genuinely observes this unit")
		profile = c.Wanted.Build()
		local observed
		for _, line in ipairs(profile) do
			if tostring(line.text):find(c.L.WANTED_LAST_OBSERVED_LABEL, 1, true) then observed = line end
		end
		assert(observed and observed.text:find(date("%Y-%m-%d %H:%M", 1800000000), 1, true),
			"native in-game observation gets its own dated line")
	end)
end)

test("Wanted last seen: a location sanction hides text, map action and historical pins", function()
	WithMapWanted(function(c, _, world, _, guid)
		local barred = false
		c.Ago = function(at) return tostring(1800000000 - (tonumber(at) or 0)) .. "s" end
		c.Zones = { KeyForName = function() return "m1429" end, MapID = function() return 1429 end }
		c.WatchChat = { Barred = function(kind) return kind == "locations" and barred or nil end }
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		c.Wanted.CanManage = function() return true end
		assert(c.Wanted.AddTarget("Enemy-Realm", guid))
		local stored = assert(c.rdb.wanted.targets["g:" .. guid])
		stored.base = { lifetimeKills = 1, lastSighting = { zone = "Elwynn Forest", at = 1799999000,
			precision = "approximate", evidence = "SELF_DEATH" } }
		c.Wanted.Rebuild()
		local location
		for _, line in ipairs(c.Wanted.Build()) do
			if line.id == "wanted-location:g:" .. guid then location = line end
		end
		assert(location and location.onClick and location.onClick(), "location is available before the sanction")
		c.Wanted.RefreshPins()
		local historical = assert(c.Wanted.HistoryFrames()[1429])
		assert(world[historical] == true, "history world state=" .. tostring(world[historical]) .. " onWorld=" .. tostring(historical.onWorld))
		barred = true
		local lines = c.Wanted.Build()
		for _, line in ipairs(lines) do assert(line.id ~= "wanted-location:g:" .. guid, "sanctioned clients see no location row") end
		c.Wanted.RefreshPins()
		eq(next(world), nil); eq(next(c.Wanted.HistoryFrames()), nil)
	end)
end)

test("Wanted map option: hides and restores actual sightings without changing minimap or consent", function()
	WithMapWanted(function(c, menu, world, mini, guid, mode)
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		-- (Only the wanted are sighted: the target is on this client's list.)
		c.Wanted.CanManage = function() return true end
		assert(c.Wanted.AddTarget("Enemy-Realm", guid))
		-- A prior confirmed kill whose bounty was already claimed, not a manual 0/0 listing.
		c.rdb.wanted.targets["g:" .. guid].base = { lifetimeKills = 1 }
		c.Wanted.Rebuild()
		c.db.wantedSightings = true -- (1.2.0: off until the member's Yes)
		assert(c.Wanted.ObserveUnit("target"))
		local f = assert(c.Wanted.PinFrames()[guid])
		eq(world[f.world], true); eq(mini[f.mini], true)
		local cb
		for _, check in ipairs(menu.checks) do if check.opt.key == "showWanted" then cb = check end end
		assert(cb, "Wanted checkbox exists")
		cb:SetChecked(false); cb:GetScript("OnClick")(cb)
		eq(world[f.world], nil); eq(mini[f.mini], true); eq(#c.Wanted.Sightings(), 1)
		eq(c.db.wantedSightings, true); eq(c.Wanted.SightingsOn(), true)
		c.Wanted.RefreshPins(); eq(world[f.world], nil)
		cb:SetChecked(true); cb:GetScript("OnClick")(cb)
		eq(world[f.world], true); eq(mini[f.mini], true)
		mode(true, false, false); c.Wanted.RefreshPins()
		eq(world[f.world], nil); eq(mini[f.mini], true, "gamepad gate stays independent")
		mode(true, false, true); c.Wanted.RefreshPins(); eq(world[f.world], true)
		mode(true, true, true); c.Wanted.RefreshPins()
		eq(next(world), nil); eq(next(mini), nil, "instances hide both")
		mode(false, false, true); c.Wanted.RefreshPins(); eq(next(world), nil); eq(next(mini), nil)
		mode(true, false, true); c.Wanted.RefreshPins(); eq(world[f.world], true); eq(mini[f.mini], true)
		c.Wanted.SetSightings(false, true)
		eq(c.db.wantedSightings, false); eq(#c.Wanted.Sightings(), 0)
		eq(next(world), nil); eq(next(mini), nil, "consent refusal still removes both")
	end)
end)
