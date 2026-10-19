-- 1.2.6, Watch duel: what a spectator's game shows, for the duel view's tests (the data's,
-- tests/arena/spectate-data.lua, and the window's, tests/arena/spectate-view.lua): unit tokens,
-- bodies (class, race, health, power, casts, combat), the gear and its stats, Forever's talent tree,
-- and Inspect.lua at its boundary (the arena world loads none). Every name is invented; the game's
-- functions are shaped as Forever's documentation gives them (F docs UnitDocumentation.lua,
-- SharedTraitsDocumentation.lua, SpecializationInfoDocumentation.lua, ItemDocumentation.lua) and
-- Era's/TBC's.
--
--   local SW = assert(loadfile(H.ROOT .. "tests/arena/lib/spectate-world.lua"))(H)
--   SW.Scene(w, c, o), SW.StubInspect(c), SW.Answer(w, c, I, key), SW.ForeverTalents(globals, points)
local H = ...
local Secret = assert(loadfile(H.ROOT .. "tests/arena/lib/secret.lua"))()
local SW = {}

-- The simple tokens UnitTokenFromGUID gives (never a compound one, "targettarget").
local TOKENS = { "target", "focus", "mouseover", "party1", "party2" }
for i = 1, 8 do TOKENS[#TOKENS + 1] = "nameplate" .. i end

-- What client c's game shows: o.units (token -> client; "player" is c), o.bodies (client -> {
-- class = { name, file, id }, race = { name, file, id }, level, guild, powerType = { n, token },
-- hp, hpMax, power, powerMax, combat (true | false | "secret"), cast = { name, texture, start,
-- finish (ms), channel }, secret (Forever: the live values secret), secretGuid, npc }),
-- o.canAttack (true | false | "none" | "secret"), o.items (client -> slot -> { id, link }),
-- o.stats (item id -> GetItemStats's table), o.uncached (item id -> true). Unit functions Olympus
-- must never call (UnitInRange is always secret; TargetUnit, FocusUnit, SetCVar reach into the
-- game) raise. Returns o (its tables may change later: the game moves on).
local function Scene(w, c, o)
	o = o or {}
	o.units, o.bodies, o.items, o.stats, o.uncached, o.loads = o.units or {}, o.bodies or {}, o.items or {}, o.stats or {}, o.uncached or {}, {}
	o.percent = {}
	local g = c.globals
	local function Of(unit)
		assert(not Secret.Is(unit), "a secret unit token was passed")
		if unit == "player" then return c end
		return o.units[unit]
	end
	local function B(x) return o.bodies[x] or {} end
	local function Live(x, v) if B(x).secret then return Secret.New() end return v end
	g.issecretvalue = Secret.Is
	g.UnitExists = function(u) return Of(u) ~= nil end
	g.UnitIsPlayer = function(u) local x = Of(u) return x ~= nil and not B(x).npc end
	g.UnitGUID = function(u)
		local x = Of(u)
		if not x then return nil end
		if B(x).secretGuid then return Secret.New() end
		return x.guid
	end
	g.UnitFullName = function(u) local x = Of(u) if x then return x.short, x.realm end end
	g.UnitName = function(u) local x = Of(u) if x then return x.short, x.realm ~= c.realm and x.realm or nil end end
	g.GetUnitName = function(u, withRealm) local x = Of(u) if x then return withRealm and (x.short .. "-" .. x.realm) or x.short end end
	g.UnitIsUnit = function(a, b) local x, y = Of(a), Of(b) return x ~= nil and x == y end
	g.UnitCanAttack = function()
		local v = o.canAttack
		if v == "secret" then return Secret.New() end
		if v == "none" then return nil end
		if v == nil then return true end
		return v
	end
	g.UnitTokenFromGUID = function(guid)
		if guid == c.guid then return "player" end
		for _, t in ipairs(TOKENS) do
			local x = o.units[t]
			if x and x.guid == guid and not B(x).secretGuid then return t end
		end
		return nil
	end
	g.UnitClass = function(u)
		local x = Of(u)
		if not x then return nil end
		local cl = B(x).class or { "Warrior", "WARRIOR", 1 }
		return cl[1], cl[2], cl[3]
	end
	g.UnitRace = function(u)
		local x = Of(u)
		if not x then return nil end
		local r = B(x).race or { "Human", "Human", 1 }
		return r[1], r[2], r[3]
	end
	g.UnitLevel = function(u) local x = Of(u) return x and (B(x).level or x.level) or 0 end
	g.UnitSex = function(u) return Of(u) and 2 or nil end
	g.UnitFactionGroup = function(u) local x = Of(u) return x and x.faction or nil end
	g.GetGuildInfo = function(u)
		local x = Of(u or "player")
		if not x then return nil end
		local guild = B(x).guild
		if guild == nil then guild = x.guild end
		return guild or nil, "Member", 3
	end
	g.UnitPowerType = function(u)
		local x = Of(u)
		if not x then return nil end
		local p = B(x).powerType or { 0, "MANA" }
		return p[1], p[2]
	end
	g.UnitHealth = function(u) local x = Of(u) if x then return Live(x, B(x).hp or 100) end end
	g.UnitHealthMax = function(u) local x = Of(u) if x then return B(x).hpMax or 100 end end
	g.UnitHealthPercent = function(u, predicted, curve)
		o.percent[#o.percent + 1] = { unit = u, curve = curve }
		local x = Of(u)
		if x then return Live(x, 0.5) end
	end
	g.UnitPower = function(u) local x = Of(u) if x then return Live(x, B(x).power or 50) end end
	g.UnitPowerMax = function(u) local x = Of(u) if x then return B(x).powerMax or 100 end end
	g.UnitPowerPercent = function(u, kind, unmodified, curve)
		o.percent[#o.percent + 1] = { unit = u, curve = curve, power = true }
		local x = Of(u)
		if x then return Live(x, 0.5) end
	end
	g.UnitAffectingCombat = function(u)
		local x = Of(u)
		if not x then return nil end
		if B(x).combat == "secret" then return Secret.New() end
		return B(x).combat == true
	end
	local function CastOf(u, channel)
		local x = Of(u)
		local cast = x and B(x).cast
		if not cast or (cast.channel == true) ~= channel then return nil end
		return x, cast
	end
	g.UnitCastingInfo = function(u)
		local x, cast = CastOf(u, false)
		if not x then return nil end
		-- (name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill (NeverSecret), castID, notInterruptible, spellID)
		return Live(x, cast.name), Live(x, cast.name), Live(x, cast.texture), Live(x, cast.start), Live(x, cast.finish), false, "Cast-1", Live(x, false), Live(x, 116)
	end
	g.UnitChannelInfo = function(u)
		local x, cast = CastOf(u, true)
		if not x then return nil end
		return Live(x, cast.name), Live(x, cast.name), Live(x, cast.texture), Live(x, cast.start), Live(x, cast.finish), false, Live(x, false), Live(x, 746)
	end
	g.UnitInParty = function(u) local x = Of(u) return x ~= nil and B(x).grouped == true end
	g.UnitInRaid = function() return nil end
	g.C_CurveUtil = { CreateCurve = function()
		local curve = { points = {} }
		function curve:AddPoint(x, y) self.points[#self.points + 1] = x .. "," .. y end
		return curve
	end }
	g.GetPlayerInfoByGUID = function(guid)
		for _, x in ipairs(w.clients) do
			if x.guid == guid then
				local cl, r = B(x).class or { "Warrior", "WARRIOR", 1 }, B(x).race or { "Human", "Human", 1 }
				return cl[1], cl[2], r[1], r[2], 2, x.short, ""
			end
		end
		return nil
	end
	g.GetInventoryItemLink = function(u, slot) local x = Of(u) local it = x and o.items[x] and o.items[x][slot] return it and it.link end
	g.GetInventoryItemID = function(u, slot) local x = Of(u) local it = x and o.items[x] and o.items[x][slot] return it and it.id end
	g.C_Item = {
		GetItemStats = function(link) return o.stats[tonumber(link:match("item:(%d+)"))] end,
		IsItemDataCachedByID = function(id) return not o.uncached[id] end,
		RequestLoadItemDataByID = function(id) o.loads[#o.loads + 1] = id end,
	}
	for _, name in ipairs({ "UnitInRange", "TargetUnit", "FocusUnit", "SetCVar" }) do
		g[name] = function() error(name .. " called") end
	end
	return o
end

-- Inspect.lua at its boundary (the arena world loads none): Want/Unwant/WantStatus kept here,
-- ReadGear the real one (it only reads GetInventoryItemLink/GetInventoryItemID). Want behaves as
-- Inspect.lua's: asked again while the want still waits (not done, not given up), the same want
-- is kept (its answer read; one not out yet back to "queued"); I.asked counts the asks per key.
local function StubInspect(c)
	local I = { wants = {}, asked = {}, WANT_TRIES = 3, ReadGear = H.ns.Inspect.ReadGear }
	function I.Want(guid, key, o)
		I.asked[key] = (I.asked[key] or 0) + 1
		local was = I.wants[key]
		if was and was.guid == guid and was.status ~= "done" and not (was.status == "timeout" and (was.tries or 0) >= I.WANT_TRIES) then
			was.unit, was.read = o.unit, o.read
			if was.status ~= "pending" then was.status = "queued" end
			return true
		end
		I.wants[key] = { guid = guid, unit = o.unit, read = o.read, status = "queued", tries = 0 }
		return true
	end
	function I.Unwant(key) I.wants[key] = nil end
	function I.WantStatus(guid)
		for _, x in pairs(I.wants) do
			if x.guid == guid then return x.status, x.at, x.tries end
		end
		return nil
	end
	rawset(c.ns, "Inspect", I)
	return I
end
-- The game's answer to a want (INSPECT_READY): its reader on the unit its own function gives.
local function Answer(w, c, I, key)
	local x = assert(I.wants[key], "no want " .. key)
	local unit = w:As(c, x.unit)
	assert(unit, "the want found no unit")
	w:As(c, x.read, unit, x.guid)
	x.status, x.at = "done", c.ns.Now()
	return unit
end

-- Forever's talent tree as its own Camelot talent frame reads it (C_Traits on the inspect config,
-- the class's three trees its groups): five nodes, one hidden.
local function ForeverTalents(g, points)
	g.Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
	local NODES = {
		[101] = { posX = 600, posY = 600, groupIDs = { 11 }, currentRank = 3, maxRanks = 5, activeEntry = { entryID = 201, rank = 3 }, entryIDs = { 201 } },
		[102] = { posX = 1200, posY = 600, groupIDs = { 11 }, currentRank = 0, maxRanks = 5, entryIDs = { 202 } },
		[103] = { posX = 600, posY = 1200, groupIDs = { 11 }, currentRank = 2, maxRanks = 2, activeEntry = { entryID = 203, rank = 2 }, entryIDs = { 203 } },
		[104] = { posX = 2400, posY = 600, groupIDs = { 12 }, currentRank = 0, maxRanks = 5, entryIDs = { 204 } },
		[105] = { posX = 4200, posY = 600, groupIDs = { 13 }, currentRank = 1, maxRanks = 1, entryIDs = { 205 }, isVisible = false },
	}
	g.C_Traits = {
		HasValidInspectData = function() return true end,
		GetConfigInfo = function(id) if id == -1 then return { ID = -1, treeIDs = { 77 } } end end,
		GetGroupDisplayInfoByTreeID = function() return {
			{ groupID = 12, treeID = 77, orderIndex = 2, displayName = "Combat", icon = 222 },
			{ groupID = 11, treeID = 77, orderIndex = 1, displayName = "Assassination", icon = 111 },
			{ groupID = 13, treeID = 77, orderIndex = 3, displayName = "Subtlety", icon = 333 } } end,
		GetTreeNodes = function() return { 101, 102, 103, 104, 105 } end,
		GetNodeInfo = function(config, node) assert(config == -1, "the inspect config") return NODES[node] end,
		GetEntryInfo = function(_, entry) return { definitionID = entry + 1000, maxRanks = 5 } end,
		GetDefinitionInfo = function(def) return { spellID = def + 10000 } end,
		GetTraitDescription = function(entry, rank) return "Reduces your speed penalty by " .. (3 * rank) .. "%." end,
	}
	g.C_Spell = { GetSpellName = function(id) return "Talent " .. id end, GetSpellTexture = function(id) return 130000 + id end,
		IsSpellPassive = function(id) return id ~= 11202 end }
	g.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetNumSpecializationsForClassID = function() return 3 end,
		GetSpecializationInfo = function(i) return 0, ({ "Assassination", "Combat", "Subtlety" })[i], "", 100 + i, nil, nil, (points or { 5, 0, 0 })[i] end }
end

SW.TOKENS, SW.Scene, SW.StubInspect, SW.Answer, SW.ForeverTalents = TOKENS, Scene, StubInspect, Answer, ForeverTalents
return SW
