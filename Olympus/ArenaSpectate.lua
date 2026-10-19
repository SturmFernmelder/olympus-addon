local ADDON, ns = ...
local L = ns.L

-- 1.2.6, the Blood Arena: "Watch duel" (Daniel's duel-view request, 2026-10-19). The data of the
-- spectator view, no frame of its own: who is watched, each fighter's unit while in sight, his
-- class, race, level and guild, the gear and talents from this client's own inspection, the duel's
-- result as this client read it. The view (the companion's) draws it; every live value the client
-- keeps secret (health, power, casts) goes from the game's function straight into the view's
-- widgets here (S.Push, S.Cast), never into the model, a comparison, a sum or a string.
--
-- The weight rule: nothing is registered at load but /oly arena watch; while a view is open the
-- session is involved ("spectate"). Nothing is ever sent, nothing saved: a spectator's inspection
-- records no tabard row and makes no chat line, sound or report (Inspect.Want). Any member may
-- watch (ArenaHome.TabVisible); a pair that is no Olympus fight this client knows of is labelled so.
--
-- API (the view uses these; the side is "A" or "B", A on the left):
--   Who is watched (a subject, never changed once made):
--     S.PairFromUnits(u1, u2, how) -> subject | nil     two players in sight, u1's side A
--     S.PairFromUnit(unit) -> subject | nil             unit and unit .. "target"
--     S.OwnFight() -> subject | nil                     the viewer's own duel (a fight of his, not over)
--     S.Watchable(target) -> subject | nil              the menu line's rule (PlayerMenu's target)
--     S.PairFromSlash(args) -> subject | nil, why       /oly arena watch [name]: why "none" | "name" | "sight" | "pair"
--     subject = { A = { name, gk, guid, unit }, B = { ... }, fid (the Olympus fight, when this client
--       knows one), olympus (bool), own ("A" | "B" | nil: the viewer's side), how, t }
--   The session (the view's lifetime):
--     S.Open(subject)        the menu line and the slash: ArenaHome.Open("duel.watch", subject),
--                            which loads the companion (refused in combat) and shows the view
--     S.Start(subject)       the view's Show: the session, the units looked for, the inspections asked
--     S.Stop()               the view's Hide: the inspections dropped, the retries cancelled, all forgotten
--     S.Close()              /oly arena watch off: the view hidden (ArenaUI.Spectate.Hide), then Stop
--     S.Watching() -> subject | nil
--     S.Active() -> bool     a view open (the view's per-tick guard: nothing copied)
--   Each tick of the view (0.2 s; the sight pass every 5th, or forced on the target, focus and
--   nameplate events):
--     S.Track(force)         each side's unit token now (a full scan at most each SCAN_GAP on a miss)
--     S.Token(side) -> token | nil
--     S.Push(side, w)        w = { health, power (StatusBars), healthText, healthPct, powerText
--                            (FontStrings) }, any of them: "cur / max" (or "NN%" for a player outside
--                            the group on Era/TBC), "NN%"; no unit: emptied, "—". true while in sight
--     S.Cast(side, w)        w = { bar, name, icon, time }: the cast or channel; -> "cast" | "channel" | nil
--     S.Fighting() -> true | false | nil   either fighter in combat (nil: unknown, keep the view)
--   The model (no secret value, ever):
--     S.Model() -> m         { subject, olympus, own, fight = { fid, bo, round, a, b, state, w, m } | nil,
--                            result = { w = side, m = "K" | "R", t } | nil, sides = { A = side, B = side } }
--       side = { name, short, gk, guid, token, inSight, seenAt, class (file), className, classID,
--         race (file), raceName, level, sex, faction, guild (an Olympus guild's, King.CleanGuild),
--         powerType, powerToken, own, inspect = { status, at, tries }, gear = { [slot] = item string },
--         gearN, stats = { [key] = n }, resist = { [key] = n }, statsPending, statsKnown,
--         talents = { source ("traits" | "talents" | "spec"), grid (bool), total, trees = { { name,
--           icon, points (nil: hidden), tiers, columns, talents = { { name, icon, tier, column, rank,
--           max, spellID, entryID (Forever), talentID (Era/TBC), tab, index } } } } } | nil }
--     S.StatusLine(side) -> text | nil     the status line's words
--     S.RoundResult(m) -> bool             the result read is one round's of a longer fight going on
--     S.TalentLines(talent) -> { title, kind ("Passive" | "Active" | nil), desc, rank ("Rank 4 / 5") }
--     S.Text(m) -> text      the copyable text: names, numbers and the game's own words only
--   Forwarded by the view while shown:
--     S.OnSystem(text)       CHAT_MSG_SYSTEM: the duel's line (the result banner) -> side | nil
--     S.OnInventory(unit)    UNIT_INVENTORY_CHANGED: inspected again, REINSPECT_GAP apart at most,
--                            never while his inspection is on its way (then once it is read)
--     S.Reinspect(side)      the Refresh button
--   Layout and rows: S.GEAR_LEFT, S.GEAR_RIGHT, S.GEAR_BOTTOM (slots), S.STATS, S.RESISTS ({ key, label }).
--   Readers (inside the game's inspect answer; tests): S.ReadInspect(side, unit, guid, own),
--   S.GearStats(links), S.ReadTalents(unit, classID, inspect).

local ArenaSpectate = {}
ns.ArenaSpectate = ArenaSpectate
local S = ArenaSpectate
local Arena = ns.Arena

S.SCAN_GAP = 2           -- a side not found: the full unit scan (ArenaFights.TokenOf) at most this often
S.FACTS_EVERY = 1        -- class, race, level and guild read again at most this often
S.STATS_RETRY = 1        -- an item the client has not cached yet: its stats asked again this often...
S.STATS_TRIES = 5        -- ...this many times
S.REINSPECT_GAP = 30     -- the gear changed: inspected again at most this often (seconds)
S.PCT_SCALE = 1          -- what Forever's UnitHealthPercent gives at full health (an in-game probe: 1 or 100)
S.TREES_MAX = 5
S.TALENTS_MAX = 60       -- talents read per tree at most
S.NODES_MAX = 400        -- a trait tree's nodes read at most
S.SLOTS = 19

-- The gear's slots as the view lays them out (the game's inspect window's order).
S.GEAR_LEFT = { 1, 2, 3, 15, 5, 4, 19, 9 }
S.GEAR_RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }
S.GEAR_BOTTOM = { 16, 17, 18 }

-- The rows of "Stats from gear" and "Resistances": the keys the game's GetItemStats gives (its
-- own global strings' names), the first one an item has counted once.
S.STATS = {
	{ key = "str", label = "ARENA_WATCH_STAT_STR", keys = { "ITEM_MOD_STRENGTH_SHORT" } },
	{ key = "agi", label = "ARENA_WATCH_STAT_AGI", keys = { "ITEM_MOD_AGILITY_SHORT" } },
	{ key = "sta", label = "ARENA_WATCH_STAT_STA", keys = { "ITEM_MOD_STAMINA_SHORT" } },
	{ key = "int", label = "ARENA_WATCH_STAT_INT", keys = { "ITEM_MOD_INTELLECT_SHORT" } },
	{ key = "spi", label = "ARENA_WATCH_STAT_SPI", keys = { "ITEM_MOD_SPIRIT_SHORT" } },
	{ key = "armor", label = "ARENA_WATCH_STAT_ARMOR", keys = { "RESISTANCE0_NAME" } },
	{ key = "ap", label = "ARENA_WATCH_STAT_AP", keys = { "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_MELEE_ATTACK_POWER_SHORT" } },
	{ key = "sp", label = "ARENA_WATCH_STAT_SP", keys = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" } },
	{ key = "crit", label = "ARENA_WATCH_STAT_CRIT", keys = { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT", "ITEM_MOD_CRIT_SPELL_RATING_SHORT" } },
	{ key = "hit", label = "ARENA_WATCH_STAT_HIT", keys = { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT", "ITEM_MOD_HIT_SPELL_RATING_SHORT" } },
	{ key = "haste", label = "ARENA_WATCH_STAT_HASTE", keys = { "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_HASTE_MELEE_RATING_SHORT", "ITEM_MOD_HASTE_SPELL_RATING_SHORT" } },
}
S.RESISTS = {
	{ key = "holy", label = "ARENA_WATCH_RES_HOLY", keys = { "RESISTANCE1_NAME" } },
	{ key = "fire", label = "ARENA_WATCH_RES_FIRE", keys = { "RESISTANCE2_NAME" } },
	{ key = "nature", label = "ARENA_WATCH_RES_NATURE", keys = { "RESISTANCE3_NAME" } },
	{ key = "frost", label = "ARENA_WATCH_RES_FROST", keys = { "RESISTANCE4_NAME" } },
	{ key = "shadow", label = "ARENA_WATCH_RES_SHADOW", keys = { "RESISTANCE5_NAME" } },
	{ key = "arcane", label = "ARENA_WATCH_RES_ARCANE", keys = { "RESISTANCE6_NAME" } },
}

local SIDES = { "A", "B" }
-- The states of a fight the view shows as on (lower: preferred).
local ON = { L = 0, B = 0, C = 1, Y = 1, Z = 1, R = 1, S = 2 }

---------------------------------------------------------------------------
-- Small helpers. A value the client keeps secret errors on any comparison, even with nil: asked
-- first, every time (issecretvalue).
---------------------------------------------------------------------------

local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
-- fn(...)'s first value, nil when it errors or is secret.
local function Plain(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or Secret(v) then return nil end
	return v
end
-- Every value of fn(...), or nothing when it errors or any of them is secret.
local function Read(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	local n = table.maxn(r)
	for i = 2, n do if Secret(r[i]) then return nil end end
	return unpack(r, 2, n)
end
local function Bool(fn, ...)
	local v = Plain(fn, ...)
	if v == nil then return nil end
	return v ~= false and v ~= 0
end
local function Num(v) if Secret(v) or type(v) ~= "number" or v ~= v then return nil end return v end
local function Str(v) if Secret(v) or type(v) ~= "string" or v == "" then return nil end return v end
local function Fights() return ns.ArenaFights end
local function Same(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then return false end
	return ns.FullName(a):lower() == ns.FullName(b):lower()
end
local function Copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = Copy(x) end
	return out
end
local function Visible()
	local H = ns.ArenaHome
	if type(H) == "table" and type(H.TabVisible) == "function" then return H.TabVisible() == true end
	return ns.IsMember() == true and not Arena.Off()
end
-- Is `unit` (a plain token) the player with this GUID now?
local function GuidIs(unit, guid)
	if Secret(unit) or type(unit) ~= "string" or unit == "" or type(guid) ~= "string" then return false end
	local g = Str(Plain(UnitGUID, unit))
	return g ~= nil and g == guid
end

---------------------------------------------------------------------------
-- Who is watched
---------------------------------------------------------------------------

-- A player in sight: his name as the server writes it, his GUID and gk; nil for anything else.
local function Who(unit)
	if Secret(unit) or type(unit) ~= "string" or unit == "" then return nil end
	if not Bool(UnitExists, unit) or not Bool(UnitIsPlayer, unit) then return nil end
	local guid = Str(Plain(UnitGUID, unit))
	if not guid or not guid:find("^Player%-") then return nil end
	local ok, name = pcall(ns.UnitFullName, unit)
	name = ok and Str(name) or nil
	if not name then return nil end
	return { name = name, guid = guid, gk = Arena.GK(guid), unit = unit }
end

-- (unit: the token the pair was taken from, "targettarget" say: looked at again for him first.)
local function Fighter(name, gk, guid, unit)
	return { name = name, gk = gk or Arena.GK(guid), guid = guid or Arena.GuidOf(gk), unit = unit }
end

-- The fight this client knows for the pair (on, not over), the most live first.
local function FightOf(a, b)
	local AF = Fights()
	if type(AF) ~= "table" or type(AF.List) ~= "function" then return nil end
	local best, rank
	for _, f in ipairs(AF.List()) do
		local r = f.A and f.B and ON[AF.State(f)]
		if r and ((Same(f.A.name, a.name) and Same(f.B.name, b.name)) or (Same(f.A.name, b.name) and Same(f.B.name, a.name)))
			and (not best or r < rank) then best, rank = f, r end
	end
	return best
end

local function Subject(a, b, how, f)
	if f == nil then f = FightOf(a, b) end
	if f and Same(f.A.name, b.name) then a, b = b, a end
	local s = { A = Fighter(a.name, a.gk, a.guid, a.unit), B = Fighter(b.name, b.gk, b.guid, b.unit), how = how, t = Arena.Now(),
		olympus = f ~= nil, fid = f and f.fid or nil }
	if Same(s.A.name, ns.me) then s.own = "A" elseif Same(s.B.name, ns.me) then s.own = "B" end
	return s
end

function S.PairFromUnits(u1, u2, how)
	local a, b = Who(u1), Who(u2)
	if not a or not b or a.guid == b.guid then return nil end
	return Subject(a, b, how or "unit")
end
function S.PairFromUnit(unit)
	if Secret(unit) or type(unit) ~= "string" or unit == "" then return nil end
	return S.PairFromUnits(unit, unit .. "target", "unit")
end

-- The viewer's own fight, not over: the live one first, else the newest agreed.
function S.OwnFight()
	local AF = Fights()
	if type(AF) ~= "table" or type(AF.List) ~= "function" or type(AF.SideOf) ~= "function" then return nil end
	local best, rank
	for _, f in ipairs(AF.List({ mine = true })) do
		local r = f.A and f.B and ON[AF.State(f)]
		if r and AF.SideOf(f, ns.me) and (not best or r < rank) then best, rank = f, r end
	end
	if not best then return nil end
	return Subject({ name = best.A.name, gk = best.A.gk }, { name = best.B.name, gk = best.B.gk }, "own", best)
end

-- The menu line's rule: the player clicked is one of the viewer's own fight, or his unit targets
-- another player he can attack (a duel: the game's own word, UnitCanAttack, plain true only).
function S.Watchable(target)
	if type(target) ~= "table" or Secret(target.name) or type(target.name) ~= "string" or not Visible() then return nil end
	local own = S.OwnFight()
	if own and (Same(own.A.name, target.name) or Same(own.B.name, target.name)) then return own end
	local unit = target.unit
	if Secret(unit) or type(unit) ~= "string" or unit == "" then return nil end
	local other = unit .. "target"
	if not Bool(UnitExists, other) or not Bool(UnitIsPlayer, other) then return nil end
	if Bool(UnitIsUnit, unit, other) ~= false then return nil end
	if Plain(UnitCanAttack, unit, other) ~= true then return nil end
	return S.PairFromUnits(unit, other, "menu")
end

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function S.PairFromSlash(args)
	args = Trim(args)
	if args == "" then
		local s = S.OwnFight() or S.PairFromUnits("target", "targettarget", "slash") or S.PairFromUnits("target", "focus", "slash")
		if s then return s end
		return nil, "none"
	end
	local name = Arena.Name(args)
	if not name then return nil, "name" end
	local own = S.OwnFight()
	if own and (Same(own.A.name, name) or Same(own.B.name, name)) then return own end
	local AF = Fights()
	local ok, token = false, nil
	if type(AF) == "table" and type(AF.TokenOf) == "function" then ok, token = pcall(AF.TokenOf, nil, name) end
	token = ok and Str(token) or nil
	if not token then return nil, "sight" end
	local s = S.PairFromUnits(token, token .. "target", "slash")
	if s then return s end
	return nil, "pair"
end

local function Valid(s)
	return type(s) == "table" and type(s.A) == "table" and type(s.B) == "table" and type(s.A.name) == "string"
		and type(s.B.name) == "string" and s.A.name ~= "" and s.B.name ~= "" and not Same(s.A.name, s.B.name)
end

---------------------------------------------------------------------------
-- The session
---------------------------------------------------------------------------

local state -- { subject, sides = { A, B }, result, t } while a view is open

local function NewSide(f)
	-- (rev: bumped at each read of his gear, stats or talents, which the model copies once per rev.)
	return { name = f.name, short = ns.ShortName(f.name), gk = f.gk, guid = f.guid, hint = Str(f.unit), scanAt = -math.huge,
		own = Same(f.name, ns.me) or nil, rev = 0 }
end

function S.Watching() return state and Copy(state.subject) or nil end
-- Is a view open (the view's per-tick and per-event guard: nothing copied)?
function S.Active() return state ~= nil end
function S.Token(side) local s = state and state.sides[side] return s and s.token or nil end

local function HimNow(token, s)
	if s.guid then return GuidIs(token, s.guid) end
	local ok, n = pcall(ns.UnitFullName, token)
	return ok and Str(n) ~= nil and Same(n, s.name)
end

-- His token now: the one he had; the game's token for his GUID; the token the pair was taken
-- from ("targettarget"); his opponent's target (a duelist targets the other: "nameplate3target");
-- else (a scan of every unit, at most each SCAN_GAP) any unit with his name and a player's GUID
-- (ArenaFights.TokenOf).
local function Find(s, force, now, other)
	if s.token and HimNow(s.token, s) then return s.token end
	if s.guid and type(UnitTokenFromGUID) == "function" then
		local token = Str(Plain(UnitTokenFromGUID, s.guid))
		if token and HimNow(token, s) then return token end
	end
	if s.hint and HimNow(s.hint, s) then return s.hint end
	local theirs = other and other.token
	if theirs and not theirs:find("targettarget", 1, true) and HimNow(theirs .. "target", s) then return theirs .. "target" end
	if not force and now - s.scanAt < S.SCAN_GAP then return nil end
	s.scanAt = now
	local AF = Fights()
	if type(AF) ~= "table" or type(AF.TokenOf) ~= "function" then return nil end
	local ok, token, guid = pcall(AF.TokenOf, s.gk, s.name)
	token, guid = ok and Str(token) or nil, ok and Str(guid) or nil
	if not token then return nil end
	if not s.guid and guid and guid:find("^Player%-") then s.guid, s.gk = guid, s.gk or Arena.GK(guid) end
	return token
end

-- Class, race, level, guild and power type from his unit: each kept only when the game gave a
-- plain value (the last one seen stays).
local function Facts(s, token)
	local className, classFile, classID = Read(UnitClass, token)
	if Str(classFile) then s.class, s.className, s.classID = classFile, Str(className), Num(classID) or s.classID end
	local raceName, raceFile = Read(UnitRace, token)
	if Str(raceFile) then s.race, s.raceName = raceFile, Str(raceName) end
	local level = Num(Plain(UnitLevel, token))
	if level and level > 0 then s.level = level end
	s.sex = Num(Plain(UnitSex, token)) or s.sex
	s.faction = Str(Plain(UnitFactionGroup, token)) or s.faction
	local guild = Str(Plain(GetGuildInfo, token))
	local K = ns.King
	s.guild = guild and K and K.CleanGuild and K.CleanGuild(guild) or nil
	local powerType, powerToken = Read(UnitPowerType, token)
	if Num(powerType) then s.powerType, s.powerToken = powerType, Str(powerToken) end
	s.factsAt = GetTime()
end
-- Never seen yet: class and race from the game's word on his GUID.
local function InfoByGUID(s)
	if s.class or not s.guid then return end
	local className, classFile, raceName, raceFile, sex = Read(GetPlayerInfoByGUID, s.guid)
	if Str(classFile) then s.class, s.className = classFile, Str(className) end
	if Str(raceFile) then s.race, s.raceName = raceFile, Str(raceName) end
	s.sex = Num(sex) or s.sex
end

local Ask -- (below)

function S.Track(force)
	if not state then return end
	local now = GetTime()
	for _, key in ipairs(SIDES) do
		local s = state.sides[key]
		local hadGuid = s.guid
		local token = Find(s, force, now, state.sides[key == "A" and "B" or "A"])
		s.token, s.inSight = token, token ~= nil
		if token then
			s.seenAt = Arena.Now()
			if force or now - (s.factsAt or -math.huge) >= S.FACTS_EVERY then Facts(s, token) end
		end
		-- (A fighter whose GUID only his unit gave: his inspection asked now.)
		if s.guid and not hadGuid and not s.own and state then Ask(key) end
	end
	-- The result read stays until they fight again: a calm seen after it, then combat (the combat
	-- flag lingers a few seconds after a duel's end, so the calm first). A re-duel or the next
	-- round of a best of 3 starts with no old winner.
	local r = state and state.result
	if r then
		local fighting = S.Fighting()
		if fighting == false then r.calm = true
		elseif fighting == true and r.calm then state.result = nil end
	end
end

---------------------------------------------------------------------------
-- Gear and stats (this client's own inspection: display only, nothing kept past the session)
---------------------------------------------------------------------------

local function ItemID(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end
local function Cached(link)
	local id = ItemID(link)
	if not id then return false end
	local I = C_Item
	if type(I) == "table" and type(I.IsItemDataCachedByID) == "function" then return Bool(I.IsItemDataCachedByID, id) == true end
	local info = (type(I) == "table" and type(I.GetItemInfo) == "function" and I.GetItemInfo) or (type(GetItemInfo) == "function" and GetItemInfo) or nil
	return info ~= nil and Str(Plain(info, link)) ~= nil
end
local function Load(link)
	local id, I = ItemID(link), C_Item
	if id and type(I) == "table" and type(I.RequestLoadItemDataByID) == "function" then pcall(I.RequestLoadItemDataByID, id) end
end

-- What the items' own stats add up to (the game's GetItemStats: an item's base stats, no enchant):
-- sums, resistances, how many items are not cached yet, and whether the client can tell at all.
function S.GearStats(links)
	local get = (type(C_Item) == "table" and type(C_Item.GetItemStats) == "function" and C_Item.GetItemStats)
		or (type(GetItemStats) == "function" and GetItemStats) or nil
	local sums, resist, missing = {}, {}, 0
	for _, row in ipairs(S.STATS) do sums[row.key] = 0 end
	for _, row in ipairs(S.RESISTS) do resist[row.key] = 0 end
	if not get then return sums, resist, 0, false end
	local function Add(out, rows, t)
		for _, row in ipairs(rows) do
			for _, k in ipairs(row.keys) do
				local v = Num(t[k])
				if v then out[row.key] = out[row.key] + v break end
			end
		end
	end
	for slot = 1, S.SLOTS do
		local link = type(links) == "table" and links[slot] or nil
		if type(link) == "string" then
			if not Cached(link) then
				missing = missing + 1
				Load(link)
			else
				local t = Plain(get, link)
				if type(t) == "table" then
					Add(sums, S.STATS, t)
					Add(resist, S.RESISTS, t)
				end
			end
		end
	end
	return sums, resist, missing, true
end

local function Stats(side, tries)
	local s = state and state.sides[side]
	if not s then return end
	local sums, resist, missing, known = S.GearStats(s.links)
	s.stats, s.resist, s.statsPending, s.statsKnown = sums, resist, missing > 0, known
	s.rev = s.rev + 1
	tries = tries or 0
	if missing > 0 and tries < S.STATS_TRIES then
		local session = state
		Arena.After(S.STATS_RETRY, "spectate stats " .. side, function()
			if state == session then Stats(side, tries + 1) end
		end)
	end
end

---------------------------------------------------------------------------
-- Talents: points per tree on every client (C_SpecializationInfo); the whole grid where the
-- client gives it: Forever's trait tree (C_Traits on the inspect config, as its own talent frame
-- reads it), Era's and TBC's talents (C_SpecializationInfo.GetTalentInfo, else GetTalentInfo).
---------------------------------------------------------------------------

local function SpellName(id)
	if not Num(id) then return nil end
	if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then return Str(Plain(C_Spell.GetSpellName, id)) end
	return Str(Plain(GetSpellInfo, id))
end
local function SpellIcon(id)
	if not Num(id) then return nil end
	if type(C_Spell) == "table" and type(C_Spell.GetSpellTexture) == "function" then return Plain(C_Spell.GetSpellTexture, id) end
	local icon = Plain(GetSpellTexture, id)
	if icon ~= nil then return icon end
	return (select(3, Read(GetSpellInfo, id)))
end
local function Icon(v) if Num(v) or Str(v) then return v end return nil end

-- A spell's ID, a real one only: Era's and TBC's TalentInfoResult gives 0 by default (its
-- documentation's Default = 0), and spell 0's description or Passive is no talent's.
local function SpellID(v)
	v = Num(v)
	return v and v > 0 and v or nil
end
local function Talent(name, icon, tier, column, rank, max, spellID)
	name, tier, column = Str(name), Num(tier), Num(column)
	if not name or not tier or not column then return nil end
	return { name = name, icon = Icon(icon), tier = tier, column = column, rank = Num(rank) or 0, max = Num(max) or 1, spellID = SpellID(spellID) }
end

-- Tree names, icons and points (C_SpecializationInfo.GetSpecializationInfo: specId, name,
-- description, icon, role, primaryStat, pointsSpent...): a secret count is hidden, never guessed.
local function SpecTrees(classID, inspect, group)
	local SI = C_SpecializationInfo
	if type(SI) ~= "table" or type(SI.GetSpecializationInfo) ~= "function" then return nil end
	local n = Num(classID) and type(SI.GetNumSpecializationsForClassID) == "function" and Num(Plain(SI.GetNumSpecializationsForClassID, classID)) or nil
	n = math.min(n and n > 0 and n or 3, S.TREES_MAX)
	local out = {}
	for i = 1, n do
		local r = { pcall(SI.GetSpecializationInfo, i, inspect, false, nil, nil, group) }
		local name = r[1] and Str(r[3]) or nil
		if not name then break end
		local points = r[8]
		out[i] = { name = name, icon = Icon(r[5]), points = Num(points), secret = Secret(points) or nil }
	end
	return #out > 0 and out or nil
end

local function ClassicGrid(inspect, group)
	local SI = C_SpecializationInfo
	local query = type(SI) == "table" and type(SI.GetTalentInfo) == "function" and SI.GetTalentInfo or nil
	local legacy = type(GetTalentInfo) == "function" and GetTalentInfo or nil
	if not query and not legacy then return nil end
	local tabs = Num(Plain(GetNumTalentTabs, inspect, false))
	if not tabs or tabs < 1 then return nil end
	local trees = {}
	for tab = 1, math.min(tabs, S.TREES_MAX) do
		local count = Num(Plain(GetNumTalents, tab, inspect, false))
		local tree = { talents = {} }
		for i = 1, math.min(count or S.TALENTS_MAX, S.TALENTS_MAX) do
			local t
			if query then
				local r = Plain(query, { specializationIndex = tab, talentIndex = i, isInspect = inspect, isPet = false, groupIndex = group })
				if type(r) == "table" then
					t = Talent(r.name, r.icon, r.tier, r.column, r.rank, r.maxRank, r.spellID)
					if t then t.talentID = Num(r.talentID) end
				end
			end
			if not t and legacy then
				local name, icon, tier, column, rank, max = Read(legacy, tab, i, inspect, false, group)
				t = Talent(name, icon, tier, column, rank, max)
			end
			if t then
				t.tab, t.index = tab, i
				tree.talents[#tree.talents + 1] = t
			elseif not count then
				break
			end
		end
		trees[tab] = tree
	end
	return trees
end

-- Tiers and columns from a trait tree's node positions: the smallest step between two of them.
local function Steps(list, key)
	local vals = {}
	for _, t in ipairs(list) do vals[#vals + 1] = t[key] end
	table.sort(vals)
	local gap
	for i = 2, #vals do
		local d = vals[i] - vals[i - 1]
		if d > 0.5 and (not gap or d < gap) then gap = d end
	end
	return vals[1] or 0, gap
end
local function Place(tree)
	local x0, dx = Steps(tree.talents, "x")
	local y0, dy = Steps(tree.talents, "y")
	for _, t in ipairs(tree.talents) do
		t.column = dx and math.floor((t.x - x0) / dx + 0.5) + 1 or 1
		t.tier = dy and math.floor((t.y - y0) / dy + 0.5) + 1 or 1
	end
end

local function TraitGrid(inspect)
	local T = C_Traits
	if type(T) ~= "table" then return nil end
	for _, fn in ipairs({ "GetConfigInfo", "GetTreeNodes", "GetNodeInfo", "GetEntryInfo", "GetDefinitionInfo", "GetGroupDisplayInfoByTreeID" }) do
		if type(T[fn]) ~= "function" then return nil end
	end
	local configID
	if inspect then
		if type(T.HasValidInspectData) == "function" and not Plain(T.HasValidInspectData) then return nil end
		local K = type(Constants) == "table" and type(Constants.TraitConsts) == "table" and Constants.TraitConsts or nil
		configID = K and Num(K.INSPECT_TRAIT_CONFIG_ID) or -1
	else
		local CT = C_ClassTalents
		configID = type(CT) == "table" and Num(Plain(CT.GetActiveConfigID)) or nil
	end
	if not configID then return nil end
	local config = Plain(T.GetConfigInfo, configID)
	local treeID = type(config) == "table" and type(config.treeIDs) == "table" and Num(config.treeIDs[1]) or nil
	if not treeID then return nil end
	-- The class's trees: the trait tree's groups, in the game's order.
	local groups = {}
	local infos = Plain(T.GetGroupDisplayInfoByTreeID, treeID)
	if type(infos) == "table" then
		for _, g in ipairs(infos) do
			if type(g) == "table" and Num(g.groupID) then
				groups[#groups + 1] = { id = g.groupID, name = Str(g.displayName), icon = Icon(g.icon), order = Num(g.orderIndex) or #groups }
			end
		end
	end
	if #groups == 0 then return nil end
	table.sort(groups, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.id < b.id
	end)
	local trees, index = {}, {}
	for i, g in ipairs(groups) do
		if i > S.TREES_MAX then break end
		trees[i], index[g.id] = { name = g.name, icon = g.icon, talents = {} }, i
	end
	local nodes = Plain(T.GetTreeNodes, treeID)
	if type(nodes) ~= "table" then return nil end
	for n, nodeID in ipairs(nodes) do
		if n > S.NODES_MAX then break end
		local info = Num(nodeID) and Plain(T.GetNodeInfo, configID, nodeID) or nil
		if type(info) == "table" and info.isVisible ~= false then
			local active = type(info.activeEntry) == "table" and Num(info.activeEntry.entryID) or nil
			local entryID = active or (type(info.entryIDs) == "table" and Num(info.entryIDs[1])) or nil
			local entry = entryID and Plain(T.GetEntryInfo, configID, entryID) or nil
			local defID = type(entry) == "table" and Num(entry.definitionID) or nil
			local def = defID and Plain(T.GetDefinitionInfo, defID) or nil
			def = type(def) == "table" and def or {}
			local spellID = SpellID(def.spellID)
			local name = Str(def.overrideName) or SpellName(spellID)
			local x, y = Num(info.posX), Num(info.posY)
			local tree
			if type(info.groupIDs) == "table" then
				for _, gid in ipairs(info.groupIDs) do
					if index[gid] then tree = trees[index[gid]] break end
				end
			end
			if tree and name and x and y and #tree.talents < S.TALENTS_MAX then
				tree.talents[#tree.talents + 1] = { name = name, icon = Icon(def.overrideIcon) or Icon(SpellIcon(spellID)), x = x, y = y,
					rank = Num(info.currentRank) or Num(info.activeRank) or Num(info.ranksPurchased) or 0,
					max = Num(info.maxRanks) or (type(entry) == "table" and Num(entry.maxRanks)) or 1,
					spellID = spellID, entryID = entryID, nodeID = nodeID }
			end
		end
	end
	for _, tree in ipairs(trees) do Place(tree) end
	return trees
end

-- What the inspected player (inspect) or the viewer himself has: nil when the client gives nothing.
function S.ReadTalents(unit, classID, inspect)
	inspect = inspect ~= false
	local SI = C_SpecializationInfo
	local group = type(SI) == "table" and Num(Plain(SI.GetActiveSpecGroup, inspect)) or nil
	local grid, source = TraitGrid(inspect), "traits"
	if not grid then grid, source = ClassicGrid(inspect, group), "talents" end
	local spec = SpecTrees(classID, inspect, group)
	if not grid and not spec then return nil end
	local trees, any = grid or {}, false
	for i, sp in ipairs(spec or {}) do
		local t = trees[i] or { talents = {} }
		trees[i] = t
		t.name, t.icon = t.name or sp.name, t.icon or sp.icon
		t.specPoints, t.secret = sp.points, sp.secret
	end
	local total = 0
	for _, t in ipairs(trees) do
		t.talents = t.talents or {}
		table.sort(t.talents, function(a, b)
			if a.tier ~= b.tier then return a.tier < b.tier end
			if a.column ~= b.column then return a.column < b.column end
			return a.name < b.name
		end)
		local tiers, columns, sum = 0, 0, 0
		for _, x in ipairs(t.talents) do
			tiers, columns, sum = math.max(tiers, x.tier), math.max(columns, x.column), sum + x.rank
		end
		t.tiers, t.columns = tiers, columns
		if #t.talents > 0 then
			any = true
			t.points = sum
		else
			t.points = t.specPoints
		end
		t.specPoints = nil
		total = total + (t.points or 0)
	end
	return { source = any and source or "spec", grid = any, trees = trees, total = total }
end

-- A talent's tooltip: its name, Passive (or Active, when the client says), its description, its rank.
local function Description(t)
	if t.entryID and type(C_Traits) == "table" then
		local d = Str(Plain(C_Traits.GetTraitDescription, t.entryID, math.max(1, t.rank or 0)))
		if d then return d end
	end
	if not t.spellID then return nil end
	if type(C_Spell) == "table" and type(C_Spell.GetSpellDescription) == "function" then return Str(Plain(C_Spell.GetSpellDescription, t.spellID)) end
	return Str(Plain(GetSpellDescription, t.spellID))
end
function S.TalentLines(t)
	if type(t) ~= "table" or type(t.name) ~= "string" then return nil end
	if t.desc == nil then t.desc = Description(t) end
	if t.passive == nil and t.spellID then
		if type(C_Spell) == "table" and type(C_Spell.IsSpellPassive) == "function" then t.passive = Bool(C_Spell.IsSpellPassive, t.spellID)
		else t.passive = Bool(IsPassiveSpell, t.spellID) end
	end
	local kind
	if t.passive == true then kind = L.ARENA_WATCH_PASSIVE elseif t.passive == false then kind = L.ARENA_WATCH_ACTIVE end
	return { title = t.name, kind = kind, desc = t.desc, rank = L.ARENA_WATCH_RANK:format(t.rank or 0, t.max or 1) }
end

---------------------------------------------------------------------------
-- The inspection: asked of Inspect.lua (its pump, its pace), read inside the game's answer
---------------------------------------------------------------------------

-- Inspected again `left` seconds from now (one timer a side, this session's only).
local function Later(side, left)
	local session = state
	Arena.After(left, "spectate reinspect " .. side, function()
		if state == session then S.Reinspect(side) end
	end)
end

function S.ReadInspect(side, unit, guid, own)
	local s = state and state.sides[side]
	if not s or (guid and s.guid and guid ~= s.guid) then return false end
	local I = ns.Inspect
	local items, n = {}, 0
	if type(I) == "table" and type(I.ReadGear) == "function" then
		local ok, a, b = pcall(I.ReadGear, unit)
		if ok and type(a) == "table" then items, n = a, tonumber(b) or 0 end
	end
	-- (The links, for the stats: whole while the answer lasts, kept as plain text for a retry.)
	local links = {}
	for slot = 1, S.SLOTS do
		local link = Str(Plain(GetInventoryItemLink, unit, slot))
		links[slot] = link and link:find("item:", 1, true) and link or items[slot]
	end
	s.gear, s.gearN, s.links = items, n, links
	Stats(side)
	local _, _, classID = Read(UnitClass, unit)
	s.classID = Num(classID) or s.classID
	s.talents = S.ReadTalents(unit, s.classID, not own)
	s.inspected = ns.Now()
	s.rev = s.rev + 1
	-- (His gear changed while this inspection was on its way: looked at again REINSPECT_GAP later.)
	if s.again then
		s.again = nil
		Later(side, S.REINSPECT_GAP)
	end
	return true
end

local function WantKey(side) return "spectate:" .. side end
Ask = function(side)
	local s = state and state.sides[side]
	local I = ns.Inspect
	if not s or not s.guid or type(I) ~= "table" or type(I.Want) ~= "function" then return false end
	local session = state
	local ok = I.Want(s.guid, WantKey(side), {
		unit = function()
			if state ~= session then return nil end
			return Find(s, false, GetTime(), state.sides[side == "A" and "B" or "A"])
		end,
		read = function(unit, guid)
			if state ~= session then return end
			S.ReadInspect(side, unit, guid)
		end,
	}) == true
	if ok then s.askedAt = ns.Now() end
	return ok
end
-- The viewer's own side: his own gear and talents, read at once (no inspection).
local function ReadOwn(side)
	if not state then return false end
	return S.ReadInspect(side, "player", nil, true)
end

function S.Reinspect(side)
	local s = state and state.sides[side]
	if not s then return false end
	if s.own then return ReadOwn(side) end
	return Ask(side)
end

-- His inspection asked and not answered nor given up yet (Inspect.WantStatus).
local function Asking(s)
	local I = ns.Inspect
	if s.own or not s.guid or type(I) ~= "table" or type(I.WantStatus) ~= "function" then return false end
	local status, _, tries = I.WantStatus(s.guid)
	if status == nil or status == "done" then return false end
	return not (status == "timeout" and (tries or 0) >= (tonumber(I.WANT_TRIES) or 3))
end

function S.OnInventory(unit)
	if not state or Secret(unit) or type(unit) ~= "string" then return false end
	for _, key in ipairs(SIDES) do
		local s = state.sides[key]
		if s.guid and GuidIs(unit, s.guid) then
			-- Not read yet, or his inspection on its way: never asked again at once (the answer on its
			-- way would be lost); its read looks again REINSPECT_GAP later. Else REINSPECT_GAP after
			-- the last read or ask at the soonest.
			if not s.inspected or Asking(s) then
				s.again = true
				return false
			end
			local left = S.REINSPECT_GAP - (ns.Now() - math.max(s.inspected, s.askedAt or -math.huge))
			if left <= 0 then return S.Reinspect(key) end
			Later(key, left)
			return false
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The live values: from the game straight into the view's widgets
---------------------------------------------------------------------------

local curve -- Forever's percentage, scaled to 0-100 for "NN%" (C_CurveUtil); false: none on this client
local function Curve()
	if curve ~= nil then return curve or nil end
	curve = false
	local CU = C_CurveUtil
	if type(CU) ~= "table" or type(CU.CreateCurve) ~= "function" then return nil end
	local ok, c = pcall(CU.CreateCurve)
	if ok and c and pcall(function() c:AddPoint(0, 0); c:AddPoint(S.PCT_SCALE, 100) end) then curve = c end
	return curve or nil
end
function S.ResetCurve() curve = nil end -- (tests)

local function Grouped(token)
	if token == "player" or token:find("^party%d") or token:find("^raid%d") then return true end
	return Bool(UnitInParty, token) == true or Bool(UnitInRaid, token) == true
end

local function Empty(w)
	for _, k in ipairs({ "health", "power" }) do
		local bar = w[k]
		if bar then bar:SetMinMaxValues(0, 1); bar:SetValue(0) end
	end
	for _, k in ipairs({ "healthText", "healthPct", "powerText" }) do
		if w[k] then w[k]:SetText(L.ARENA_WATCH_DASH) end
	end
end

-- Health and power of a side into w. A value is looked at (compared, divided) only once
-- issecretvalue said it is plain (Era, TBC, the viewer's own); a secret one only ever reaches a
-- StatusBar's SetMinMaxValues/SetValue or a FontString's SetFormattedText.
function S.Push(side, w)
	if type(w) ~= "table" then return false end
	local s = state and state.sides[side]
	local t = s and s.token
	if not t or type(UnitHealth) ~= "function" or type(UnitHealthMax) ~= "function" then Empty(w) return false end
	if w.health then
		w.health:SetMinMaxValues(0, UnitHealthMax(t))
		w.health:SetValue(UnitHealth(t))
	end
	if w.healthText or w.healthPct then
		local cur, max = UnitHealth(t), UnitHealthMax(t)
		if Secret(cur) or Secret(max) then
			if w.healthText then w.healthText:SetFormattedText("%d / %d", cur, max) end
			if w.healthPct then
				local c = Curve()
				if c and type(UnitHealthPercent) == "function" then w.healthPct:SetFormattedText("%.0f%%", UnitHealthPercent(t, true, c))
				else w.healthPct:SetText("") end
			end
		else
			cur, max = tonumber(cur) or 0, tonumber(max) or 0
			if w.healthText then
				-- (Era and TBC give a player outside the group in percent: a maximum of 100.)
				if max == 100 and not Grouped(t) then w.healthText:SetFormattedText("%d%%", cur)
				else w.healthText:SetFormattedText("%d / %d", cur, max) end
			end
			if w.healthPct then w.healthPct:SetFormattedText("%d%%", max > 0 and math.floor(cur * 100 / max + 0.5) or 0) end
		end
	end
	if type(UnitPower) == "function" and type(UnitPowerMax) == "function" and (w.power or w.powerText) then
		local kind = Num(Plain(UnitPowerType, t))
		if w.power then
			w.power:SetMinMaxValues(0, UnitPowerMax(t, kind))
			w.power:SetValue(UnitPower(t, kind))
		end
		if w.powerText then
			local cur, max = UnitPower(t, kind), UnitPowerMax(t, kind)
			if Secret(cur) or Secret(max) then
				local c = Curve()
				if c and type(UnitPowerPercent) == "function" then w.powerText:SetFormattedText("%.0f%%", UnitPowerPercent(t, kind, false, c))
				else w.powerText:SetText("") end
			else
				cur, max = tonumber(cur) or 0, tonumber(max) or 0
				w.powerText:SetFormattedText("%d%%", max > 0 and math.floor(cur * 100 / max + 0.5) or 0)
			end
		end
	end
	return true
end

-- The cast (or channel) of a side into w: its name, icon and fill; seconds only where the end is
-- plain (Era, TBC). Whether one is going on comes from the 6th value, isTradeskill, which Forever
-- never keeps secret (nil: nothing cast), so no secret is ever tested.
function S.Cast(side, w)
	local s = state and state.sides[side]
	local t = s and s.token
	if type(w) ~= "table" or not t or type(UnitCastingInfo) ~= "function" then return nil end
	local fn, kind = UnitCastingInfo, "cast"
	if select(6, UnitCastingInfo(t)) == nil then
		if type(UnitChannelInfo) ~= "function" or select(6, UnitChannelInfo(t)) == nil then return nil end
		fn, kind = UnitChannelInfo, "channel"
	end
	local name, _, texture, startMs, endMs = fn(t)
	if w.name then w.name:SetText(name) end
	if w.icon then w.icon:SetTexture(texture) end
	if w.bar then
		w.bar:SetMinMaxValues(startMs, endMs)
		w.bar:SetValue(GetTime() * 1000)
	end
	if w.time then
		if Secret(endMs) or type(endMs) ~= "number" then w.time:SetText("")
		else w.time:SetFormattedText("%.1f", math.max(0, endMs / 1000 - GetTime())) end
	end
	return kind
end

-- Either fighter in combat (the compact bar's switch): nil when neither unit says (secret, or none).
function S.Fighting()
	if not state then return nil end
	local known, any = false, false
	for _, key in ipairs(SIDES) do
		local t = state.sides[key].token
		local v = t and Plain(UnitAffectingCombat, t)
		if v ~= nil then
			known = true
			if v then any = true end
		end
	end
	if not known then return nil end
	return any
end

---------------------------------------------------------------------------
-- The duel's line, the model, the words
---------------------------------------------------------------------------

function S.OnSystem(text)
	if not state or Secret(text) or type(text) ~= "string" then return nil end
	local P, AF = ns.ArenaParse, Fights()
	if type(P) ~= "table" or type(P.DuelResult) ~= "function" or type(AF) ~= "table" or type(AF.LineSide) ~= "function" then return nil end
	local winner, loser, method = P.DuelResult(text)
	if not winner then return nil end
	local side = AF.LineSide(state.subject, winner, loser)
	if not side then return nil end
	state.result = { w = side, m = method == "fled" and "R" or "K", t = Arena.Now() }
	return side
end

-- The duel line read is one round's, of a longer fight of this client's knowledge still going on
-- (a best of 3 after its first round): its words then say "Last round", never who won the fight.
local OVER = { R = true, F = true, V = true, N = true, W = true }
function S.RoundResult(m)
	if type(m) ~= "table" or type(m.result) ~= "table" or type(m.fight) ~= "table" then return false end
	return (tonumber(m.fight.bo) or 1) > 1 and not OVER[m.fight.state or ""]
end

local KEEP = { "name", "short", "gk", "guid", "token", "inSight", "seenAt", "class", "className", "classID", "race", "raceName",
	"level", "sex", "faction", "guild", "powerType", "powerToken", "own", "gear", "gearN", "stats", "resist", "statsPending",
	"statsKnown", "talents", "inspected" }

-- (Copied once per read, the same copy after: the slow pass reads the model every second.)
local HEAVY = { gear = true, stats = true, resist = true, talents = true }

local function SideModel(s)
	local out = {}
	if s.copied ~= s.rev or not s.copies then
		s.copies = {}
		for k in pairs(HEAVY) do s.copies[k] = Copy(s[k]) end
		s.copied = s.rev
	end
	for _, k in ipairs(KEEP) do
		if HEAVY[k] then out[k] = s.copies[k] else out[k] = Copy(s[k]) end
	end
	if s.own then
		out.inspect = { status = "own", at = s.inspected }
	else
		local I = ns.Inspect
		local status, at, tries
		if s.guid and type(I) == "table" and type(I.WantStatus) == "function" then status, at, tries = I.WantStatus(s.guid) end
		out.inspect = { status = status or (s.guid and "queued" or "sight"), at = at, tries = tries }
	end
	return out
end

local function FightModel(subject)
	local AF = Fights()
	local f = subject.fid and type(AF) == "table" and type(AF.Fight) == "function" and AF.Fight(subject.fid) or nil
	if type(f) ~= "table" then return nil end
	local sc = type(f.sc) == "table" and f.sc or {}
	return { fid = f.fid, bo = f.bo or 1, round = f.round or 0, a = sc[1] or 0, b = sc[2] or 0, state = AF.State(f), w = f.w, m = f.m }
end

function S.Model()
	if not state then return nil end
	local m = { subject = Copy(state.subject), olympus = state.subject.olympus == true, own = state.subject.own, t = state.t,
		result = Copy(state.result), fight = FightModel(state.subject), sides = {} }
	for _, key in ipairs(SIDES) do m.sides[key] = SideModel(state.sides[key]) end
	return m
end

local STATUS = { sight = "ARENA_WATCH_ST_SIGHT", range = "ARENA_WATCH_ST_RANGE", queued = "ARENA_WATCH_ST_INSPECTING",
	pending = "ARENA_WATCH_ST_INSPECTING", combat = "ARENA_WATCH_ST_COMBAT", busy = "ARENA_WATCH_ST_BUSY",
	refused = "ARENA_WATCH_ST_REFUSED" }

function S.StatusLine(side)
	local m = type(side) == "table" and side or (state and SideModel(state.sides[side]))
	if type(m) ~= "table" or type(m.inspect) ~= "table" then return nil end
	local st = m.inspect.status
	if st == "own" then return L.ARENA_WATCH_ST_OWN end
	if st == "done" or (m.gear and st ~= "pending" and st ~= "queued") then
		local at = m.inspect.at or m.inspected
		local mins = at and math.floor(math.max(0, ns.Now() - at) / 60) or 0
		return mins < 1 and L.ARENA_WATCH_ST_NOW or L.ARENA_WATCH_ST_DONE:format(mins)
	end
	if st == "timeout" then
		if (m.inspect.tries or 0) >= ((ns.Inspect and ns.Inspect.WANT_TRIES) or 3) then return L.ARENA_WATCH_ST_REFUSED end
		return L.ARENA_WATCH_ST_INSPECTING
	end
	local key = STATUS[st or ""]
	return key and L[key] or nil
end

local function Display(name) return ns.DisplayName(ns.FullName(name)) or "?" end

-- The copyable text (Kit.Copy's pop-up): names, numbers, the game's own words (class, race, tree
-- and talent names) and fixed words; no text another player typed but an Olympus guild's name.
function S.Text(m)
	m = m or S.Model()
	if type(m) ~= "table" then return "" end
	local out = {}
	local A, B = m.sides.A, m.sides.B
	out[#out + 1] = L.ARENA_VS:format(Display(A.name), Display(B.name))
	if not m.olympus then out[#out + 1] = L.ARENA_WATCH_NOT_OLYMPUS end
	if m.fight then out[#out + 1] = L.ARENA_WATCH_FIGHT_LINE:format(m.fight.bo, m.fight.round, m.fight.a, m.fight.b) end
	if m.result then
		local w, l = m.sides[m.result.w], m.sides[m.result.w == "A" and "B" or "A"]
		local round = S.RoundResult(m)
		if m.result.m == "R" then
			out[#out + 1] = (round and L.ARENA_WATCH_ROUND_FLED or L.ARENA_WATCH_WON_FLED):format(Display(w.name), Display(l.name))
		else
			out[#out + 1] = (round and L.ARENA_WATCH_ROUND_KO or L.ARENA_WATCH_WON_KO):format(Display(w.name))
		end
	end
	for _, key in ipairs(SIDES) do
		local s = m.sides[key]
		out[#out + 1] = ""
		local who = { Display(s.name) }
		if s.className or s.raceName or s.level then
			who[#who + 1] = L.ARENA_WATCH_WHO:format(s.className or "?", s.raceName or "?", s.level or 0)
		end
		if s.guild then who[#who + 1] = "<" .. s.guild .. ">" end
		out[#out + 1] = table.concat(who, " · ")
		if s.stats then
			local parts = {}
			for _, row in ipairs(S.STATS) do parts[#parts + 1] = L[row.label] .. " " .. (s.stats[row.key] or 0) end
			out[#out + 1] = L.ARENA_WATCH_STATS .. ": " .. table.concat(parts, ", ")
			parts = {}
			for _, row in ipairs(S.RESISTS) do parts[#parts + 1] = L[row.label] .. " " .. (s.resist and s.resist[row.key] or 0) end
			out[#out + 1] = L.ARENA_WATCH_RESISTS .. ": " .. table.concat(parts, ", ")
		end
		if s.talents and s.talents.trees then
			local parts = {}
			for _, t in ipairs(s.talents.trees) do
				parts[#parts + 1] = (t.name or "?") .. " " .. (t.points and tostring(t.points) or L.ARENA_WATCH_DASH)
			end
			out[#out + 1] = L.ARENA_WATCH_TALENTS .. ": " .. table.concat(parts, ", ")
		end
	end
	return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- The session's start and end, the window, the command
---------------------------------------------------------------------------

function S.Start(subject)
	if not Valid(subject) then return false end
	if state then S.Stop() end
	state = { subject = Copy(subject), t = Arena.Now(), sides = { A = NewSide(subject.A), B = NewSide(subject.B) } }
	Arena.Involve("spectate", true)
	for _, key in ipairs(SIDES) do InfoByGUID(state.sides[key]) end
	S.Track(true)
	for _, key in ipairs(SIDES) do
		if state.sides[key].own then ReadOwn(key) else Ask(key) end
	end
	return true
end

function S.Stop()
	if not state then return false end
	state = nil
	local I = ns.Inspect
	for _, key in ipairs(SIDES) do
		if type(I) == "table" and type(I.Unwant) == "function" then I.Unwant(WantKey(key)) end
		Arena.After(0, "spectate stats " .. key, nil)
		Arena.After(0, "spectate reinspect " .. key, nil)
	end
	Arena.Involve("spectate", false)
	return true
end

function S.Open(subject)
	if not Valid(subject) or not Visible() then return false end
	local H = ns.ArenaHome
	if type(H) ~= "table" or type(H.Open) ~= "function" then return false end
	return H.Open("duel.watch", subject) == true
end

function S.Close()
	local ui = Arena.ui
	local view = type(ui) == "table" and ui.Spectate or nil
	if type(view) == "table" and type(view.Hide) == "function" then ns.SafeCall("arena watch close", view.Hide) end
	return S.Stop()
end

Arena.Slash("watch", function(args)
	args = Trim(args)
	if args:lower() == "off" then
		S.Close()
		return
	end
	if not Visible() then return ns.Print(L.MEMBERS_ONLY) end
	local subject, why = S.PairFromSlash(args)
	if not subject then
		if why == "sight" or why == "pair" then return ns.Print(L.ARENA_WATCH_NO_SIGHT:format(args)) end
		return ns.Print(L.ARENA_WATCH_NONE)
	end
	S.Open(subject)
end, L.ARENA_HELP_WATCH)
