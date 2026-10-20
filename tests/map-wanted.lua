-- The map option is artwork-only; sightings consent and minimap pins stay independent.
local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]map%-wanted%.lua$") or "./"
local function Frame(name, frames)
	local f = { scripts = {}, shown = false, labels = {}, ScrollContainer = false }
	if name then frames[name] = f end
	function f:SetScript(event, fn) self.scripts[event] = fn end
	function f:GetScript(event) return self.scripts[event] end
	function f:HookScript(event, fn)
		local before = self.scripts[event]
		self.scripts[event] = function(...)
			if before then before(...) end
			return fn(...)
		end
	end
	function f:Show() self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
	function f:Hide() self.shown = false end
	function f:IsShown() return self.shown end
	function f:SetShown(on) if on then self:Show() else self:Hide() end end
	function f:SetChecked(on) self.checked = on end
	function f:GetChecked() return self.checked end
	function f:SetAlpha(value) self.alpha = value end
	function f:SetMapID(value) self.mapID = value if self.OnMapChanged then self:OnMapChanged() end end
	function f:GetMapID() return self.mapID end
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

-- What a line's tooltip says, its lines joined.
local function TipText(line)
	local tt = { lines = {} }
	function tt:AddLine(text) self.lines[#self.lines + 1] = tostring(text) end
	assert(line and line.tooltip, "a line with a tooltip")
	line.tooltip(tt)
	return table.concat(tt.lines, "\n")
end

local function WithMapWanted(fn)
	local names = { "CreateFrame", "WorldMapFrame", "UIParent", "ShowUIPanel", "GameTooltip", "IsInInstance", "UnitGUID", "UnitIsPlayer",
		"UnitFactionGroup", "UnitCanAttack", "UnitIsPVP", "GetGuildInfo", "C_Map", "issecretvalue", "hooksecurefunc" }
	local saved = {}
	for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
	local ok, err = pcall(function()
		local frames, hooks, world, mini, listeners = {}, {}, {}, {}, {}
		local member, inside, worldAllowed = true, false, true
		local epoch, uiRefreshes = 1800000000, 0
		local guid = "Player-1-0A000001"
		local lib = {}
		function lib:AddWorldMapIconMap(_, f, mapID, x, y) world[f] = true f.mapID, f.mapX, f.mapY = mapID, x, y end
		function lib:RemoveWorldMapIcon(_, f) world[f] = nil end
		function lib:AddMinimapIconMap(_, f) mini[f] = true end
		function lib:RemoveMinimapIcon(_, f) mini[f] = nil end
		CreateFrame = function(_, name) return Frame(name, frames) end
		UIParent, WorldMapFrame = Frame(nil, frames), Frame(nil, frames)
		WorldMapFrame.OnMapChanged = function() end
		hooksecurefunc = function(owner, method, fn)
			local before = owner[method]
			owner[method] = function(self, ...)
				if before then before(self, ...) end
				return fn(self, ...)
			end
		end
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
			UI = {}, Consent = {}, Comm = {}, Data = { ServerTime = function() return epoch end },
			Moderation = { SelfOff = function() return false end }, Layers = {},
			Gate = { Hooks = function(key, value) hooks[key] = value end, Allowed = function() return true end },
			On = function(event, call) listeners[event] = listeners[event] or {}; table.insert(listeners[event], call) end,
			Fire = function(event, ...) for _, call in ipairs(listeners[event] or {}) do call(...) end end,
			RegisterEvent = function() end, IsMember = function() return member end,
			Pins = function() return lib end, MakeRoundButton = function(name) return Frame(name, frames) end,
			UnitFullName = function(unit) return unit == "target" and "Enemy-Realm" or "Observer-Realm" end,
			WorldMapIcons = function()
				if not worldAllowed then for f in pairs(world) do world[f] = nil end end
				return worldAllowed
			end }, { __index = ns })
		assert(loadfile(ROOT .. "Olympus/Map.lua"))("Olympus", c)
		hooks["map-overlay"].install()
		local menu = assert(frames.OlympusMapMenu)
		c.UI = {
			IsShown = function() return true end,
			PageId = function() return "wanted/" .. (c.Wanted and c.Wanted.PageId and c.Wanted.PageId() or "list") end,
			Refresh = function() uiRefreshes = uiRefreshes + 1 end,
			RefreshSoon = function() uiRefreshes = uiRefreshes + 1 end,
		}
		c.TestUIRefreshes = function() return uiRefreshes end
		c.TestAdvance = function(seconds) epoch = epoch + seconds end
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
		stored.base = { lifetimeKills = 1, lastSighting = { zone = "Bosque de Elwynn", mapID = 1429, at = 1799000000,
			precision = "approximate", evidence = "SELF_DEATH" } }
		c.Wanted.Rebuild()

		local lines = c.Wanted.Build()
		local target, location
		for _, line in ipairs(lines) do
			if line.id == "wanted:g:" .. guid then target = line end
			if line.id == "wanted-location:g:" .. guid then location = line end
		end
		assert(target and location and location.onClick, "the list has a dated, actionable last-seen row")
		assert(location.text:find("Bosque de Elwynn", 1, true), location.text)
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
		local profileLocation, online
		for _, line in ipairs(profile) do
			if line.id == "wanted-location:g:" .. guid then profileLocation = line end
			if line.id == "wanted-online:g:" .. guid then online = line end
		end
		assert(profileLocation and profileLocation.onClick, "the profile keeps the same dated map action")
		-- (RH-09, changed on purpose: Daniel's "visto online por último" counts the shared records too,
		-- so the stored death now dates the profile's one "Last seen online" line, which replaced
		-- 1.2.4's session-only "Last observed online". What this assertion kept is kept: its source
		-- says the record, never a sighting by this client.)
		assert(online and online.text:find(date("%Y-%m-%d %H:%M", 1799000000), 1, true), online and online.text)
		local tip = TipText(online)
		assert(tip:find(c.L.WANTED_ONLINE_KILL, 1, true), tip)
		assert(not tip:find(c.L.WANTED_ONLINE_OWN, 1, true), "stored combat evidence is not called this client's own sighting")
		c.db.wantedSightings = true
		assert(c.Wanted.ObserveUnit("target"), "the game genuinely observes this unit")
		profile = c.Wanted.Build()
		online = nil
		for _, line in ipairs(profile) do
			if line.id == "wanted-online:g:" .. guid then online = line end
		end
		assert(online and online.text:find(date("%Y-%m-%d %H:%M", 1800000000), 1, true),
			"the newer native in-game observation dates the line")
		assert(TipText(online):find(c.L.WANTED_ONLINE_OWN, 1, true), "and its source says so")
	end)
end)

test("Wanted last seen online (RH-09): this client's own sighting stays on the list row after its pin and a reload, the time alone; off records none and the No forgets it", function()
	WithMapWanted(function(c, _, _, _, guid)
		c.WatchChat = { Barred = function() return nil end }
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		c.Wanted.CanManage = function() return true end
		assert(c.Wanted.AddTarget("Enemy-Realm", guid))
		-- (A kill counted long ago with no time kept: nothing dates him yet.)
		c.rdb.wanted.targets["g:" .. guid].base = { lifetimeKills = 1 }
		c.Wanted.Rebuild()
		local function Find(id)
			for _, line in ipairs(c.Wanted.Build()) do if line.id == id then return line end end
			return nil
		end
		-- (Daniel, 2026-10-20, changed on purpose: "ficou ruim last seen online em linha nova". The
		-- list says it short on his own row, dim after its counts, never on a line of its own; the
		-- row's tooltip keeps the date and the source, and his page keeps its own line.)
		local online, rowId, sep = "wanted-online:g:" .. guid, "wanted:g:" .. guid, "|cff9d9d9d  ·  "
		local function Short()
			local right = assert(Find(rowId), "his row").right
			local at = right:find(sep, 1, true)
			return at and right:sub(at + #sep, -3) or nil -- (his short item, its "|r" aside)
		end
		eq(Short(), nil, "nothing dates him yet")
		eq(Find(online), nil)
		c.db.wantedSightings = false
		eq(select(2, c.Wanted.ObserveUnit("target")), "off")
		eq(c.rdb.wanted.targets["g:" .. guid].seenOnline, nil, "sightings off: no time is recorded")
		c.db.wantedSightings = true
		assert(c.Wanted.ObserveUnit("target"))
		eq(c.rdb.wanted.targets["g:" .. guid].seenOnline, 1800000000, "the time he was seen goes on his entry")

		-- His pin's 15 minutes pass, then a reload: no pin is left, the list still says when.
		c.TestAdvance(c.Wanted.SIGHT_TTL + 60)
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		assert(c.Wanted.Prune())
		eq(c.Wanted.LiveSighting(assert(c.Wanted.Target(nil, guid))), nil, "no session pin is left")
		eq(Short(), c.L.WANTED_ROW_SEEN:format(c.L.AGO_MIN:format(math.floor((c.Wanted.SIGHT_TTL + 60) / 60))),
			"the list row still says when, short")
		eq(Find(online), nil, "never on a line of its own on the list")
		local when = date("%Y-%m-%d %H:%M", 1800000000)
		local rowTip = TipText(assert(Find(rowId)))
		assert(rowTip:find(c.L.WANTED_LAST_ONLINE:format(when), 1, true), rowTip)
		assert(rowTip:find(c.L.WANTED_ONLINE_OWN, 1, true), "the row's tooltip names its source: this client's own sighting")
		assert(Find(rowId).onClick(), "a click on the row opens his page")
		local line = assert(Find(online), "his page has his Last seen online line")
		assert(line.text:find(c.L.WANTED_LAST_ONLINE:format(when), 1, true), line.text)
		assert(TipText(line):find(c.L.WANTED_ONLINE_OWN, 1, true), "its source: this client's own sighting")
		assert(c.Wanted.Back())
		-- The time alone on the entry, never where he or the observer stood.
		local stored = c.rdb.wanted.targets["g:" .. guid]
		for _, field in ipairs({ "mapID", "x", "y", "layer", "observer", "zone" }) do eq(stored[field], nil, field) end

		c.Wanted.SetSightings(false, true)
		eq(c.rdb.wanted.targets["g:" .. guid].seenOnline, nil, "the No forgets the time")
		eq(Short(), nil, "and nothing else dates him")
		eq(Find(online), nil)
	end)
end)

test("Wanted map refresh: gamepad gate is checked before the periodic path reads WorldMapFrame", function()
	WithMapWanted(function(c)
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		c.Gate.Allowed = function(key) return key ~= "wanted-map" end
		WorldMapFrame.IsShown = function() error("WorldMapFrame was read outside the wanted-map gate") end
		assert(c.Wanted.RefreshPins())
	end)
end)

test("Wanted last seen: the newest timestamp chooses the displayed location and only a selected live sighting suppresses history", function()
	WithMapWanted(function(c, _, _, _, guid)
		c.Zones = { KeyForName = function() return "m1429" end, MapID = function() return 1429 end }
		c.WatchChat = { Barred = function() return nil end }
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		c.Wanted.CanManage = function() return true end
		assert(c.Wanted.AddTarget("Enemy-Realm", guid))
		local stored = assert(c.rdb.wanted.targets["g:" .. guid])
		stored.base = { lifetimeKills = 1, lastSighting = { zone = "Elwynn Forest", at = 1800000001,
			precision = "approximate", evidence = "SELF_DEATH" } }
		c.Wanted.Rebuild()
		c.db.wantedSightings = true
		assert(c.Wanted.ObserveUnit("target"), "a genuine native observation is kept")

		local target = assert(c.Wanted.Target(nil, guid))
		local seen = assert(c.Wanted.LastSeen(target))
		eq(seen.source, "ledger"); eq(seen.at, 1800000001, "the newer combat sighting wins")
		assert(c.Wanted.LiveSighting(target), "the older native observation remains separately available")
		assert(c.Wanted.HistoricalSightings(1429)[1429],
			"history is retained when the ledger sighting, not the live pin, is selected")

		stored.base.lastSighting.at = 1799999999
		c.Wanted.Rebuild()
		target = assert(c.Wanted.Target(nil, guid))
		seen = assert(c.Wanted.LastSeen(target))
		eq(seen.source, "native"); eq(seen.at, 1800000000, "the newer native observation wins")
		eq(c.Wanted.HistoricalSightings(1429)[1429], nil,
			"history is suppressed only when the live observation is selected")
	end)
end)

test("Wanted last seen: ordinary world-map show and map changes refresh historical markers immediately", function()
	WithMapWanted(function(c, _, world, _, guid)
		c.Zones = { KeyForName = function(name) return name == "Elwynn Forest" and "m1429" end,
			MapID = function(key) return key == "m1429" and 1429 or nil end }
		c.WatchChat = { Barred = function() return nil end }
		assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c)
		c.Wanted.CanManage = function() return true end
		assert(c.Wanted.AddTarget("Enemy-Realm", guid))
		local stored = assert(c.rdb.wanted.targets["g:" .. guid])
		stored.base = { lifetimeKills = 1, lastSighting = { zone = "Elwynn Forest", at = 1799000000,
			precision = "approximate", evidence = "SELF_DEATH" } }
		c.Wanted.Rebuild()

		WorldMapFrame.mapID = 1429
		WorldMapFrame:Show()
		local historical = assert(c.Wanted.HistoryFrames()[1429], "OnShow draws the wanted history")
		assert(world[historical], "the OnShow refresh put the marker on the map")
		WorldMapFrame:SetMapID(1430)
		eq(c.Wanted.HistoryFrames()[1429], nil, "OnMapChanged removes a marker from the prior map")
		WorldMapFrame:SetMapID(1429)
		assert(c.Wanted.HistoryFrames()[1429], "OnMapChanged draws the newly selected map immediately")
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
		local refreshes = c.TestUIRefreshes()
		barred = true
		c.Fire("WATCHCHAT_CHANGED", "T", c.me)
		assert(c.TestUIRefreshes() > refreshes, "the open Wanted page refreshes with the sanction")
		local lines = c.Wanted.Build()
		for _, line in ipairs(lines) do assert(line.id ~= "wanted-location:g:" .. guid, "sanctioned clients see no location row") end
		eq(next(world), nil, "the sanction event removes the marker immediately")
		eq(next(c.Wanted.HistoryFrames()), nil)
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
