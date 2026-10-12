local ADDON, ns = ...

-- 1.2, the Blood Arena: HonorsNet.lua. A stub the arena's core created for the fights part (fights and honours) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- Level-race claims (IL), the donor holders' word (ID, also on GUILD from the Treasurer's own
-- client), the Oracle's (IO), the belt podium, and verification of a pick for any viewer through
-- Honors. Registers IL ID IO (sent in L whatever the live switch: Arena.LIVE_EXEMPT). The honours
-- exemption of the weight rule: PLAYER_LEVEL_UP (acting at a multiple of 10) and one AP timer while
-- the pick is not the default, through ns.On/ns.Every.
-- API (the design): Verified(name) -> { frame, title, mark, chat }, Holdings(name), FrameTexture(key),
--   MarkTexture(key), ChatMark(key), TitleText(key), Levels(), Donors(), Oracle(), Podium(cat),
--   ChurchTop() (1.2.3: the Church's top 3 as ChurchCount.Top3 holds it, or nil);
--   NewPortrait(parent, size) and DressPortrait(rig, key): the player's own portrait with a frame.
-- The King's letter (the design) when an honour is earned: a popup of Olympus's own, queued.
local HonorsNet = {}
ns.HonorsNet = HonorsNet

-- One honours system for frames, nameplate marks, chat marks and titles (the design).
-- Every viewer works out what a player holds from his own facts (Honors.Holdings over the belts
-- and podium words, the level race's book, the Treasurer's donor word, a bank's Oracle word and the
-- census's best guild) and shows a player's pick only when it holds (Honors.Shown), else the rank's
-- frame: nobody can make another client show an honour he does not hold.
--
-- The words (the design, with its later changes):
--   IL gk~level~t                 the character itself, at PLAYER_LEVEL_UP to 20, 40 or 60 (the
--                                 design's level race: the FIRST to each), again 10 minutes and an
--                                 hour later, never once that milestone's place is known here. Each
--                                 client keeps the claim (timed when it first heard it) and counts it
--                                 vouched once it is a verified member's (H.Vouched, 1.2.1: our own
--                                 guild's roster, the server's, at or above that level, with his own
--                                 GUID; another guild's census, two of its senders other than him
--                                 listing him there, within 24 hours; never one census row); only
--                                 vouched claims take the place, which stays unless the server's word
--                                 shows it false (H.CheckPlaces: his unit or our roster below it, or
--                                 the GUID not his; then it goes, and he never takes it again here,
--                                 by that GUID or by his name).
--   ID t~monthKey~m1,m2,m3~a1,a2,a3   names only: the month's top 3 donors and all time's (the
--                                 the design dropped the week's), from the Treasurer's characters'
--                                 client (or the King's), on the channel and on GUILD; the newest
--                                 wins; sent whatever the Treasury's ranking switches say.
--   IO monthKey~t~n1,n2,n3        the Oracle's gold, silver and bronze for that month, from a bank of
--                                 this realm's T1~B (the first open bank by sorted name); IO R~month~
--                                 rows by whisper: another bank's top 10 for it (name:profit:staked:
--                                 markets:first;...). The newest word for a month wins.
-- The podium (the belts' silver and bronze) is the clerk's AV 2 and 3 (ArenaLedger); the best guild
-- is the census's (Honors.GuildTop, its leader vouched by two senders). (1.2.3) The missionaries'
-- top 3 (the crook) is the Church's: ChurchCount.Top3, the newest NR~1~t word taken from the Head's,
-- the King's or the author's client (the server stamps its sender; ChurchCount.TakeTop refuses anyone
-- else's), held while the Church's public ranking is open and the word no older than
-- Honors.CHURCH_MAX_AGE. In this version only the author's client sends it (ChurchCount.SendTop: a
-- keeper whose root is W or H; the King's client is no keeper, and the Head is the King, root K), so
-- the crooks move only while the author's client is online with the ranking open, and every client
-- shows none 30 days after his last word. No word of its own here: the Church's comes on CHANNEL and
-- GUILD, and CHURCH_TOP_CHANGED (or the ranking's switch, CHURCH_PUBLIC_CHANGED) looks at the
-- honours again.
--
-- A newly earned honour switches on by itself (Honors.Update, unless the player locked his pick; 1.2.3:
-- only when told for the first time, so an honour earned again, its letter told already, leaves his
-- pick as it is), and the King's letter tells him: a parchment in a window of Olympus's own naming the
-- honour and its title, the new frame on his own portrait, "Wear it" and "Later"; queued when several come,
-- re-readable from the profile's Edit (ProfileEdit); once per honour per character (a month's honour:
-- once per month), never by itself where the save did not come back, and never to the King himself
-- (1.2.1). Honours count only in the live arena (Arena.Counts).

local L = ns.L
local H = HonorsNet
local Arena = ns.Arena
local B36, N = Arena.B36, Arena.N

H.MEDIA = "Interface\\AddOns\\Olympus\\media\\honors\\"
H.IL_AFTER = { 60, 600, 3600 }  -- IL this long after the level-up (and on AQ~H)
H.VOUCH_WINDOW = 86400          -- a census report this close to the claim vouches for it
H.VOUCHERS = 2                  -- census senders of one guild, not him, who must list him (1.2.1)
H.VOUCH_RULE = 2                -- the rule claims were vouched under (1.2.1: claims vouched before are looked at again)
H.STRIKE_AFTER = 3600           -- a roster read this long after a place's time shows the level-up, or a lie
H.STRUCK_MAX = 20               -- places found false kept per milestone (the oldest goes)
H.CLAIMS_MAX = 200
H.CLAIM_DAYS = 7
H.DONOR_EVERY = 1800            -- the Treasurer's client says the donors again every 30 minutes
H.ORACLE_EVERY = 1800
H.LETTERS_MAX = 20
H.LETTER_PORTRAIT = 60          -- the letter's portrait: the size of his own on his unit frame
H.LETTER_W = 440                -- the letter's window across (its height follows its words)
H.LETTER_PAD = 16               -- the parchment's margin
H.LETTER_FONT = 15              -- its words' size at least
H.LETTER_BUTTON = 120
H.REFRESH_DELAY = 60            -- after login, the own honours looked at once the words came in
-- The start of the level race: the 1.2 release (a claim timed before it counts for nothing).
H.RACE_START = 1790812800

local stats = { refused = {}, claims = 0, vouched = 0, places = 0 }
local function Count(why) stats.refused[why] = (stats.refused[why] or 0) + 1 return false, why end
function H.Stats() return stats end

local function Now() return Arena.Now() end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.FullName(a):lower() == ns.FullName(b):lower() end
local function Short(name) return type(name) == "string" and ns.ShortName(ns.FullName(ns.Normal and ns.Normal(name) or name)):lower() or nil end
local function Gk(s)
	if type(s) ~= "string" or s == "-" or s == "" or #s > 24 then return nil end
	return Arena.GuidOf(s) and s or nil
end
-- A GUID as Honors compares it: the game's form (a gk turned back).
local function GameGuid(g)
	if type(g) ~= "string" then return nil end
	if g:find("^Player%-") then return g end
	return Arena.GuidOf(g)
end
H.GameGuid = GameGuid

---------------------------------------------------------------------------
-- The core's honours store (this realm's live store: honours count only in L)
---------------------------------------------------------------------------

function H.Store(make)
	local s = Arena.Store("L")
	if not s then return nil end
	if type(s.honors) ~= "table" then
		if not make then return nil end
		s.honors = {}
	end
	local h = s.honors
	if make then
		h.levels = type(h.levels) == "table" and h.levels or {}
		h.claims = type(h.claims) == "table" and h.claims or {}
		h.oracle = type(h.oracle) == "table" and h.oracle or {}
	end
	return h
end

local gen = 0
local function Changed(name)
	gen = gen + 1
	ns.Fire("HONORS_CHANGED", name)
	Arena.Changed()
end
H.Changed = Changed
ns.On("DATA_CHANGED", function() gen = gen + 1 end)
ns.On("HONORS_CHANGED", function() gen = gen + 1 end)
-- (1.2.3) The Church's top 3 (a newer trusted word) or its public ranking's switch: the
-- missionaries' crooks, everyone's frames and our own honours looked at again.
ns.On("CHURCH_TOP_CHANGED", function() Changed() end)
ns.On("CHURCH_PUBLIC_CHANGED", function() Changed() end)

---------------------------------------------------------------------------
-- What a player holds, and what his pick shows
---------------------------------------------------------------------------

-- The census's best guild, its leader vouched (two senders naming him guild master, Data.KnownRank;
-- our own guild: our roster).
local function BestGuild()
	local rows = ns.rdb and ns.rdb.guilds
	if type(rows) ~= "table" then return nil end
	local M = ns.Moderation
	local top = ns.Honors.GuildTop(rows, { faction = ns.faction or "Alliance", now = ns.Now(), skip = function(guild)
		if not ns.IsFederation(guild) then return true end
		return type(M) == "table" and not M.missing and M.Guild and M.Guild(guild) ~= nil
	end })
	if not top then return nil end
	local D = ns.Data
	local leader = ns.FullName(top.leader, rows[top.guild] and rows[top.guild].realm or nil)
	if type(D) == "table" and type(D.KnownRank) == "function" then
		local ok, rank, named = pcall(D.KnownRank, leader, top.guild)
		local mine = GetGuildInfo and GetGuildInfo("player")
		if not ok or rank ~= 0 or ((named or 0) < 2 and top.guild ~= mine) then return nil end
	end
	return top
end

-- (1.2.3) The Church's top 3 as a trusted client published it (ChurchCount.Top3: nil while the
-- public ranking is closed or none was heard), or nil.
local function ChurchTop()
	local C = ns.ChurchCount
	if type(C) ~= "table" or C.missing or type(C.Top3) ~= "function" then return nil end
	local ok, top = pcall(C.Top3)
	if not ok or type(top) ~= "table" or type(top.missionaries) ~= "table" then return nil end
	return top
end
H.ChurchTop = ChurchTop

local inputs, inputsGen, inputsAt
-- The facts every Holdings call takes (kept while nothing changed, a minute at most).
function H.Inputs()
	local now = Now()
	if inputs and inputsGen == gen and inputsAt == math.floor(now / 60) then return inputs end
	local LG = ns.ArenaLedger
	local store = H.Store()
	local donors = store and store.donors
	local oracle = store and store.oracle
	local lastMonth = ns.Honors.MonthOf(now) - 1
	local ow = oracle and oracle[lastMonth]
	local function Places(names)
		local out = {}
		for i, name in ipairs(names or {}) do out[i] = { name = name, place = i } end
		return out
	end
	local tiers = {}
	for gk, tier in pairs(LG and LG.Tiers and LG.Tiers("L") or {}) do
		tiers[gk] = tier
		local g = Arena.GuidOf(gk)
		if g then tiers[g] = tier end
	end
	local church = ChurchTop()
	inputs = {
		belts = LG and LG.Holders and LG.Holders("L") or {},
		podium = LG and LG.PodiumWords and LG.PodiumWords("L") or {},
		tiers = tiers,
		donors = donors and { all = Places(donors.all), month = Places(donors.month), monthNo = donors.monthNo } or nil,
		levels = store and store.levels or {},
		guild = BestGuild(),
		oracle = ow and { month = Places(ow.names), monthNo = lastMonth } or nil,
		church = church and { missionaries = Places(church.missionaries), at = church.at } or nil,
		now = now,
	}
	inputsGen, inputsAt = gen, math.floor(now / 60)
	return inputs
end

-- The player's guild as this client knows it: his unit's, our own's, the census's word on him.
local function GuildOf(name)
	if Same(name, ns.me) then return GetGuildInfo and GetGuildInfo("player") or nil end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and M.GuildOf then
		local ok, g = pcall(M.GuildOf, name)
		if ok and type(g) == "string" then return g end
	end
	return nil
end

-- Every honour `name` holds as this client sees it (guid: the game's or the arena's form, only
-- when known for sure: a unit's, or a verified profile's).
function H.Holdings(name, guid)
	if type(name) ~= "string" then return {} end
	-- (The dev's own character, as the core's borders know him: no arena file names the author.)
	local B = ns.Borders
	local author = type(B) == "table" and type(B.IsDevName) == "function" and B.IsDevName(ns.FullName(name)) == true
	return ns.Honors.Holdings({ name = name, guid = GameGuid(guid), guild = GuildOf(name), author = author }, H.Inputs())
end

-- A player's pick as heard (or ours), and a GUID for him we are sure of.
local function PickOf(name)
	local P = ns.ArenaProfile
	if Same(name, ns.me) then return P.Pick(), P.MyGk() end
	local p = P.Of(name)
	if not p then return nil, nil end
	return { frame = p.frame or "rank", title = p.title }, p.verified and p.gk or nil
end

local cache, cacheGen, cacheHour = {}, -1, -1
-- What a player's pick shows to this client (the design): { frame (an honour key, "rank" or "none"),
-- title (an honour key or nil), mark (the honour's art, or "rank"), chat (the honour's art for a
-- chat mark, or nil), honour (the honour shown), art, shape, metal, milestone }.
-- guid: a unit's GUID (the Borders' and Nameplates'), which beats a profile's.
function H.Verified(name, guid)
	if type(name) ~= "string" or name == "" then return { frame = "rank", mark = "rank" } end
	local key = ns.FullName(name):lower() .. "|" .. tostring(guid)
	-- Kept while nothing changed, and never past the hour: the month's koi and ravens turn over with
	-- the clock alone (no word comes when a month ends).
	local hour = math.floor(Now() / 3600)
	if cacheGen ~= gen or cacheHour ~= hour then cache, cacheGen, cacheHour = {}, gen, hour end
	if cache[key] then return cache[key] end
	local pick, known = PickOf(name)
	local v = { frame = "rank", mark = "rank" }
	if pick then
		local held = H.Holdings(name, guid or known)
		local frame, mark, title, h = ns.Honors.Shown(pick, held)
		v.frame, v.mark, v.title, v.honour = frame, mark, title, h
		if h then v.art, v.shape, v.metal, v.milestone, v.chat = h.art, h.shape, h.metal, h.milestone, h.art end
	end
	cache[key] = v
	return v
end

-- The textures: a frame's (its shape too), its nameplate mark, its chat mark ("|T...|t", never a %).
function H.FrameTexture(key)
	local art, shape = ns.Honors.ArtOf(key)
	if not art then return nil end
	return H.MEDIA .. art, shape
end
function H.MarkTexture(key)
	local art = ns.Honors.ArtOf(key) or (type(key) == "string" and key:match("^[%l%-]+%-%l+$") and key) or nil
	if not art then return nil end
	return H.MEDIA .. art .. "-mark"
end
function H.ChatMark(key)
	local tex = H.MarkTexture(key)
	if not tex or tex:find("%", 1, true) then return nil end
	return "|T" .. tex .. ":0|t"
end

-- The player's own portrait with a frame on it, in the core's windows (the King's letter, the
-- profile's Edit, the Arena's own letter): Borders.NewPortrait, the builder of the Arena's
-- portraits too (1.2, the owner's ask: every Olympus portrait identical to his own on his unit
-- frame: the same picture, mask and ring, and the same art at the same offsets, turned round as
-- his own). `size` across; its slot is the square the window places, its reach how far its art
-- may reach past it (Borders.SizePortrait), for the window's words to keep clear. Where
-- Borders.lua is the core's stand-in, the picture alone, square, and no frame.
function H.NewPortrait(parent, size)
	local B = ns.Borders
	local rig = B.missing ~= true and B.NewPortrait(parent, size) or nil
	if type(rig) == "table" then return rig end
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetSize(size, size)
	return { slot = tex, portrait = tex, plain = true, reach = { left = 0, right = 0, top = 0, bottom = 0 } }
end
-- It filled: his live picture (square, as his unit frame asks SetPortraitTexture for it: the
-- rig's mask rounds it) and the frame `key` names: an honour's (its art, as round his own
-- portrait, Borders.ShowHonour; none where this client has no art for it), "rank" his rank's
-- border as his own frame works it out (Borders.TierOf), "none" or nil none. What shows:
-- "honour", "rank" or nil.
function H.DressPortrait(rig, key)
	if SetPortraitTexture then pcall(SetPortraitTexture, rig.portrait, "player", not rig.plain) end
	if rig.plain then return nil end
	local B = ns.Borders
	if type(key) == "string" and key ~= "rank" and key ~= "none" then
		if B.ShowHonour(rig, key) then return "honour" end
		B.ShowTier(rig, nil)
		return nil
	end
	local tier = key == "rank" and B.TierOf("player") or nil
	B.ShowTier(rig, tier)
	return tier and "rank" or nil
end
-- The arena division's crossed swords (a tier's badge): the game's icon and the metal's colour.
H.BADGE_ICONS = { "Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\INV_Sword_27" }
H.METAL_COLOR = { gold = { 1, 0.82, 0 }, silver = { 0.78, 0.8, 0.85 }, bronze = { 0.62, 0.46, 0.34 } }
function H.BadgeTexture(tier)
	local UI = ns.UI
	local tex = type(UI) == "table" and UI.FirstTexture and UI.FirstTexture(H.BADGE_ICONS) or H.BADGE_ICONS[1]
	return tex, H.METAL_COLOR[tier]
end

-- A title's words (the design; one locale table so the moderators can edit them).
local CLASS_FILE = { warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST", shaman = "SHAMAN",
	mage = "MAGE", warlock = "WARLOCK", druid = "DRUID" }
local RACE_ID = { human = 1, orc = 2, dwarf = 3, nightelf = 4, undead = 5, tauren = 6, gnome = 7, troll = 8 }
function H.TitleText(key)
	if type(key) ~= "string" then return nil end
	local fixed = L.HONOR_TITLES and L.HONOR_TITLES[key]
	if fixed then return fixed end
	local base, place = key:match("^(.-)%-([23])$")
	if not base then base, place = key, "1" end
	place = tonumber(place)
	local class = base:match("^arena%-class%-(%l+)$")
	if class then
		local names = LOCALIZED_CLASS_NAMES_MALE
		local name = (type(names) == "table" and names[CLASS_FILE[class] or ""]) or (L.HONOR_CLASS_NAMES and L.HONOR_CLASS_NAMES[class]) or class
		return (L.HONOR_CLASS_TITLE[place] or L.HONOR_CLASS_TITLE[1]):format(name)
	end
	local race = base:match("^arena%-race%-(%l+)$")
	if race then
		local name = L.HONOR_RACE_NAMES and L.HONOR_RACE_NAMES[race] or race
		local info = C_CreatureInfo and C_CreatureInfo.GetRaceInfo
		if type(info) == "function" and RACE_ID[race] then
			local ok, r = pcall(info, RACE_ID[race])
			if ok and type(r) == "table" and type(r.raceName) == "string" then name = r.raceName end
		end
		return (L.HONOR_RACE_TITLE[place] or L.HONOR_RACE_TITLE[1]):format(name)
	end
	return nil
end
-- The honour's name in the list (the title, with its metal and what it is for).
function H.Label(key)
	local title = H.TitleText(key)
	local _, _, metal = ns.Honors.ArtOf(key)
	return title, metal
end

function H.Levels()
	local s = H.Store()
	return s and s.levels or {}
end
function H.Donors()
	local s = H.Store()
	return s and s.donors or nil
end
function H.Oracle(month)
	local s = H.Store()
	month = month or (ns.Honors.MonthOf(Now()) - 1)
	return s and s.oracle and s.oracle[month] or nil
end
-- A belt category's podium as this client holds it: { [2] = { gk, name }, [3] = ... }.
function H.Podium(cat)
	local out = {}
	local LG = ns.ArenaLedger
	for _, p in ipairs(LG and LG.PodiumWords and LG.PodiumWords("L") or {}) do
		if p.cat == cat then out[p.place] = { gk = p.gk, name = p.name } end
	end
	return out
end

---------------------------------------------------------------------------
-- The level race (IL, and the clerk's AB~H)
---------------------------------------------------------------------------

local function Placed(m)
	local s = H.Store()
	local list = s and s.levels and s.levels[m]
	return type(list) == "table" and list[1] ~= nil
end
H.Placed = Placed

-- Our own claim: sent at the level-up's moments, never once the place is known.
local claimed = {} -- [level] = t
function H.SendClaim(level)
	if Placed(level) then return false, "placed" end
	local gk = ns.ArenaProfile.MyGk()
	if not gk then return false, "gk" end
	local t = claimed[level] or Now()
	claimed[level] = t
	return Arena.Send("IL", "L", table.concat({ gk, B36(level), B36(t) }, "~"))
end
function H.OnLevelUp(level)
	level = tonumber(level)
	if not level or not ns.Honors.LEVEL_METAL[level] or Placed(level) then return end
	claimed[level] = claimed[level] or Now()
	for _, after in ipairs(H.IL_AFTER) do
		ns.After(after, "arena level claim", function() H.SendClaim(level) end)
	end
end

-- The honours exemption (the design): PLAYER_LEVEL_UP only on a character that can still
-- reach a milestone whose place is not known here.
local levelHooked = false
function H.WatchLevels()
	if levelHooked then return true end
	local level = UnitLevel and tonumber(UnitLevel("player")) or 60
	local open = false
	for _, m in ipairs(ns.Honors.MILESTONES) do if m > level and not Placed(m) then open = true end end
	if not open then return false end
	levelHooked = true
	ns.RegisterEvent("PLAYER_LEVEL_UP", function(newLevel) ns.SafeCall("arena level up", H.OnLevelUp, newLevel) end)
	return true
end

-- A value the client hides from addons counts as none.
local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

-- Our own guild's roster as the server gives it (Roster.Fresh: a whole, recent read of our guild):
-- a member's level, by name; nil, true for a fresh roster without him; nil, false for none fresh.
local rosterOf, rosterLevels
local function RosterLevel(name)
	local R = ns.Roster
	local fresh = type(R) == "table" and type(R.Fresh) == "function" and R.Fresh() or nil
	if type(fresh) ~= "table" or type(fresh.members) ~= "table" or type(name) ~= "string" then return nil, false end
	if rosterOf ~= fresh.members then
		rosterOf, rosterLevels = fresh.members, {}
		for _, m in ipairs(fresh.members) do
			if type(m) == "table" and type(m.full) == "string" and tonumber(m.level) then rosterLevels[m.full:lower()] = tonumber(m.level) end
		end
	end
	return rosterLevels[ns.FullName(name):lower()], true
end
-- In our guild by our roster (fresh or not): the server's word on him, never another guild's census.
local function Guildmate(name)
	local R = ns.Roster
	return type(R) == "table" and type(R.RankOf) == "function" and R.RankOf(name) ~= nil
end
-- A character's level as the game gives it for a unit it knows by his GUID (a party, a target, a
-- nameplate), or nil.
local function UnitLevelOf(guid)
	if type(guid) ~= "string" or type(UnitTokenFromGUID) ~= "function" or type(UnitLevel) ~= "function" then return nil end
	local ok, token = pcall(UnitTokenFromGUID, guid)
	if not ok or type(token) ~= "string" or Secret(token) then return nil end
	local okL, level = pcall(UnitLevel, token)
	if not okL or Secret(level) or type(level) ~= "number" or level < 1 then return nil end
	return level
end
-- The players this client has in view now, by their full names (a forged claim's GUID may be one
-- the game never gives, so his unit is found by his name, which the server sets): { [name, lower
-- case] = { guid, level (nil: not given) } }.
H.SEEN_UNITS = { "target", "focus", "mouseover", "party1", "party2", "party3", "party4" }
local function SeenUnits()
	local out = {}
	if type(UnitExists) ~= "function" or type(UnitGUID) ~= "function" then return out end
	for _, token in ipairs(H.SEEN_UNITS) do
		local ok, exists = pcall(UnitExists, token)
		local okP, player = true, true
		if type(UnitIsPlayer) == "function" then okP, player = pcall(UnitIsPlayer, token) end
		if ok and not Secret(exists) and exists and okP and not Secret(player) and player then
			local name = ns.UnitFullName(token)
			local okG, guid = pcall(UnitGUID, token)
			if type(name) == "string" and okG and type(guid) == "string" and not Secret(guid) then
				local okL, level = true, nil
				if type(UnitLevel) == "function" then okL, level = pcall(UnitLevel, token) end
				if not okL or Secret(level) or type(level) ~= "number" or level < 1 then level = nil end
				out[ns.FullName(name):lower()] = { guid = guid, level = level }
			end
		end
	end
	return out
end

-- Short names as H.Vouched compares them (Short), kept once worked out (1.2.1, the stutter players
-- reported: every census report heard made the race work out again every name of every report for
-- every claim waiting, a fifth of a second and more on a release client). Kept only for a name whose
-- short form can't change with what this client learns of realms: one without "-", one whose first
-- part has a space (Forever's "First Surname-Realm"), or any while names are not split (ns.Normal
-- leaves them be). Returns the short name and whether it is such a name.
H.SHORTS_MAX = 5000
local shorts, shortsCount, shortsSplit = {}, 0, false
local function ShortOf(name)
	if type(name) ~= "string" then return nil, true end
	local split = ns.splitNames and true or false
	if split ~= shortsSplit then shorts, shortsCount, shortsSplit = {}, 0, split end
	local v = shorts[name]
	if v then return v, true end
	v = Short(name)
	local dash = name:find("-", 1, true)
	local space = dash and name:find(" ", 1, true)
	if split and dash and not (space and space < dash) then return v, false end
	if shortsCount >= H.SHORTS_MAX then shorts, shortsCount = {}, 0 end
	shorts[name], shortsCount = v, shortsCount + 1
	return v, true
end

-- The census's tops by the short name of each player they list (1.2.1): the rows listing him, in
-- the order pairs gives the rows (the order H.Vouched always went through them), each with the
-- highest level it lists him at (by[short]: { r, guild, level, nxt }, a chain). Worked out again
-- only when the rows changed: Data.Revision where the census has one, and in any case another row
-- in a place, another top, or another name or level in one, or a name whose short form hangs on the
-- realms this client knows (ShortOf: worked out again each time) that now reads otherwise. What a
-- row says beside its top (its sender, its time, our own) is read from the row itself when it is
-- looked at.
local listing = { by = {}, tails = {}, pool = {}, used = 0, keys = {}, refs = {}, tops = {}, xs = {}, xn = {}, xl = {}, n = 0, m = 0,
	loose = {}, looseShort = {}, nLoose = 0, builds = 0 }
local function Revision()
	local D = ns.Data
	if type(D) ~= "table" or type(D.Revision) ~= "function" then return nil end
	local ok, rev = pcall(D.Revision)
	return ok and rev or nil
end
local function ListingHolds(rows)
	local T = listing
	if T.rows ~= rows or T.split ~= (ns.splitNames and true or false) or T.rev ~= Revision() then return false end
	local keys, refs, tops, xs, xn, xl = T.keys, T.refs, T.tops, T.xs, T.xn, T.xl
	local i, j = 0, 0
	for guild, r in pairs(rows) do
		i = i + 1
		if keys[i] ~= guild or refs[i] ~= r then return false end
		local top = type(r) == "table" and r.top or nil
		if tops[i] ~= top then return false end
		if type(top) == "table" then
			for _, x in ipairs(top) do
				j = j + 1
				if xs[j] ~= x or (type(x) == "table" and (xn[j] ~= x.name or xl[j] ~= x.level)) then return false end
			end
		end
	end
	if i ~= T.n or j ~= T.m then return false end
	for k = 1, T.nLoose do
		local at = T.loose[k]
		if ShortOf(xn[at]) ~= T.looseShort[at] then return false end
	end
	return true
end
local function ListingBuild(rows)
	local T = listing
	local by, tails, pool = T.by, T.tails, T.pool
	for k in pairs(by) do by[k] = nil end
	for k in pairs(tails) do tails[k] = nil end
	local keys, refs, tops, xs, xn, xl = T.keys, T.refs, T.tops, T.xs, T.xn, T.xl
	local i, j, used, nLoose = 0, 0, 0, 0
	local loose, looseShort = T.loose, T.looseShort
	for k = 1, T.nLoose do
		looseShort[loose[k]] = nil
		loose[k] = nil
	end
	for guild, r in pairs(rows) do
		i = i + 1
		local top = type(r) == "table" and r.top or nil
		keys[i], refs[i], tops[i] = guild, r, top
		if type(top) == "table" then
			for _, x in ipairs(top) do
				j = j + 1
				xs[j], xn[j], xl[j] = x, nil, nil
				if type(x) == "table" then
					xn[j], xl[j] = x.name, x.level
					local who, fixed = ShortOf(x.name)
					if not fixed then
						nLoose = nLoose + 1
						loose[nLoose], looseShort[j] = j, who
					end
					if who then
						local level, last = tonumber(x.level) or 0, tails[who]
						if last and last.i == i then
							if level > last.level then last.level = level end
						else
							used = used + 1
							local e = pool[used] or {}
							pool[used] = e
							e.i, e.r, e.guild, e.level, e.nxt = i, r, guild, level, nil
							if last then last.nxt = e else by[who] = e end
							tails[who] = e
						end
					end
				end
			end
		end
	end
	for k = i + 1, T.n do keys[k], refs[k], tops[k] = nil, nil, nil end
	for k = j + 1, T.m do xs[k], xn[k], xl[k] = nil, nil, nil end
	for k = used + 1, T.used do pool[k].r, pool[k].guild, pool[k].nxt = nil, nil, nil end
	T.n, T.m, T.used, T.nLoose = i, j, used, nLoose
	T.rows, T.split, T.rev = rows, ns.splitNames and true or false, Revision()
	T.builds = T.builds + 1
	return by
end
-- The listing for the census as it stands (nil without one).
local function Listing()
	local rows = ns.rdb and ns.rdb.guilds
	if type(rows) ~= "table" then return nil end
	if ListingHolds(rows) then return listing.by end
	return ListingBuild(rows)
end
function H.ListingBuilds() return listing.builds end

-- Vouched (1.2.1, the security review: one census row of anyone else's was proof, so a forged
-- report won the place): the claim is a verified member's, at or above that level.
--   Our guildmate: our fresh roster, the server's, at or above it (another guild's rows say nothing
--   of one of ours), and the claim's GUID his as the game gives it (VerifyGk: a guildmate's
--   resolves; a made-up one never does, and his claim waits).
--   Anyone else: census reports (Data.Receive keeps one guild per sender) of an Olympus guild not
--   netted off, heard within VOUCH_WINDOW of the claim, listing him at or above it, from VOUCHERS
--   senders of that one guild, none of them him (by his name alone, as Data.KnownRank asks). A
--   guild's row is its newest report, so each sender seen is kept on the claim (c.by: guild ->
--   senders) as his turn comes (the reporter every 3 minutes, its runner-up every 10).
--   This is the census's own trust bar (Data.KnownRank's two senders), not the server's word:
--   nothing proves a sender is in the guild he reports, nor that the guild exists (any name the
--   Olympus rule takes), so three characters acting together can still forge a place here. Such a
--   place goes once the server's word shows it false (CheckPlaces). A claimant who is one of his
--   guild's two census senders (or whose guild has one other sender) is vouched here only by our
--   roster, when he is our guildmate.
-- (1.2.1) by: the census's Listing, worked out once for all the claims looked at together: the
-- rows that list him are found by his name, the rest never looked at.
local function VouchedBy(c, by)
	if type(c) ~= "table" or type(c.name) ~= "string" or not tonumber(c.level) then return false end
	if Guildmate(c.name) then
		-- (His own GUID, as the game gives a guildmate's: never a made-up one beside our roster's level.)
		local P = ns.ArenaProfile
		if not (type(P) == "table" and type(P.VerifyGk) == "function" and P.VerifyGk(c.name, c.gk) == true) then return false end
		local level, fresh = RosterLevel(c.name)
		return fresh and level ~= nil and level >= c.level or false
	end
	if not by then return false end
	local who = ShortOf(c.name)
	local D = ns.Data
	c.by = type(c.by) == "table" and c.by or {}
	local e = by[who]
	while e do
		local r, guild = e.r, e.guild
		if type(r.reporterFull) == "string" and not r.mine and type(guild) == "string"
			and ShortOf(r.reporterFull) ~= who and math.abs((r.t or 0) - (c.heardLocal or 0)) <= H.VOUCH_WINDOW
			and ns.IsFederation(guild) and not (type(D) == "table" and type(D.NetOff) == "function" and D.NetOff(guild))
			and e.level >= c.level then
			local g = guild:lower()
			local n = 0
			for _ in pairs(c.by) do n = n + 1 end
			if c.by[g] or n < 4 then
				local senders = c.by[g] or {}
				c.by[g] = senders
				local k, m = ShortOf(r.reporterFull), 0
				for _ in pairs(senders) do m = m + 1 end
				if k and (senders[k] or m < 4) then senders[k] = true end
			end
		end
		e = e.nxt
	end
	for _, senders in pairs(c.by) do
		local n = 0
		for _ in pairs(senders) do n = n + 1 end
		if n >= H.VOUCHERS then return true end
	end
	return false
end
function H.Vouched(c) return VouchedBy(c, Listing()) end

-- A place found false (1.2.1, the security review: a place stayed forever whatever came to light):
-- the server's word puts its holder below its milestone, his unit's level (by his GUID), or our
-- guild's fresh roster read STRIKE_AFTER past the place's time (so it had his level-up). Levels
-- never go down: the claim was false. Its GUID is his word too (a made-up one is never resolved):
-- the game giving that GUID another character's name (ArenaProfile.VerifyGk), or his own unit in
-- view (by his name: H.SEEN_UNITS) with another GUID, or below the milestone, shows it false too.
-- seen: SeenUnits(), when the caller has it.
function H.Falsified(p, m, gk, seen)
	if type(p) ~= "table" or not tonumber(m) then return false end
	local guid = GameGuid(p.guid)
	local level = UnitLevelOf(guid)
	if level and level < m then return true end
	gk = gk or Arena.GK(guid)
	local P = ns.ArenaProfile
	if gk and type(p.name) == "string" and type(P) == "table" and type(P.VerifyGk) == "function" and P.VerifyGk(p.name, gk) == false then return true end
	local unit = type(p.name) == "string" and (seen or SeenUnits())[ns.FullName(p.name):lower()] or nil
	if unit then
		local seenGk = Arena.GK(unit.guid)
		if gk and seenGk and seenGk ~= gk then return true end
		if unit.level and unit.level < m then return true end
	end
	if type(p.name) == "string" and Guildmate(p.name) and Now() - (tonumber(p.t) or Now()) >= H.STRIKE_AFTER then
		local rl, fresh = RosterLevel(p.name)
		if fresh and rl and rl < m then return true end
	end
	return false
end
-- Struck for that milestone here: by his gk, or by his name (s.struckNames: a forger's next claim
-- may give another gk; his name is the server's).
local function NameKey(name) return type(name) == "string" and ns.FullName(name):lower() or nil end
local function Struck(s, m, gk, name)
	if gk ~= nil and type(s.struck) == "table" and type(s.struck[m]) == "table" and s.struck[m][gk] ~= nil then return true end
	local key = NameKey(name)
	return key ~= nil and type(s.struckNames) == "table" and type(s.struckNames[m]) == "table" and s.struckNames[m][key] ~= nil
end
-- One more key kept for milestone m in store[m] (STRUCK_MAX each, the oldest goes).
local function Remember(store, m, key)
	if not key then return end
	local list = type(store[m]) == "table" and store[m] or {}
	store[m] = list
	list[key] = Now()
	local n, oldest = 0, nil
	for k, t in pairs(list) do
		n = n + 1
		if k ~= key and (not oldest or t < list[oldest]) then oldest = k end
	end
	if n > H.STRUCK_MAX and oldest then list[oldest] = nil end
end
-- The places found false go: from the book, with the claims that made them (his gk's or his
-- name's), and their holder is kept as struck for that milestone by gk and by name (no claim of
-- his nor a clerk's record takes it again here). Once gone, the place is open here again: the
-- next vouched claim this client holds or hears for it takes it (one heard before the false place
-- was recorded, kept CLAIM_DAYS, or a new level-up to it); a player who reached it while the false
-- place stood sent no claim then (SendClaim), so he is not among them. Returns the places struck
-- ({ milestone, gk, name }).
function H.CheckPlaces()
	local s = H.Store()
	local out = {}
	if not s or type(s.levels) ~= "table" then return out end
	local seen
	for _, m in ipairs(ns.Honors.MILESTONES) do
		local p = type(s.levels[m]) == "table" and s.levels[m][1] or nil
		local gk = type(p) == "table" and Arena.GK(GameGuid(p.guid)) or nil
		if gk then seen = seen or SeenUnits() end
		if gk and H.Falsified(p, m, gk, seen) then
			s.struck = type(s.struck) == "table" and s.struck or {}
			s.struckNames = type(s.struckNames) == "table" and s.struckNames or {}
			Remember(s.struck, m, gk)
			Remember(s.struckNames, m, NameKey(p.name))
			s.levels[m] = nil
			for key, c in pairs(type(s.claims) == "table" and s.claims or {}) do
				if type(c) == "table" and c.level == m and (c.gk == gk or (NameKey(c.name) ~= nil and NameKey(c.name) == NameKey(p.name))) then
					s.claims[key] = nil
				end
			end
			out[#out + 1] = { milestone = m, gk = gk, name = p.name }
			stats.struck = (stats.struck or 0) + 1
		end
	end
	for _, x in ipairs(out) do Changed(x.name) end
	return out
end

-- The claims against what this client knows now, the race's first half: the places held against
-- the server's word, the claims past CLAIM_DAYS gone, and every unvouched one against the census
-- (H.Vouched). A census change asks this at once (a guild's row is its newest report: a sender's
-- report is seen now or may never be); the race itself waits RACE_SOON (H.RaceSoon, 1.2.1).
local function Look(s, now)
	-- (1.2.1: a claim vouched under the old rule, one census row, is vouched again under this one.)
	if s.vouchRule ~= H.VOUCH_RULE then
		for _, c in pairs(s.claims) do if type(c) == "table" then c.vouched = false end end
		s.vouchRule = H.VOUCH_RULE
	end
	H.CheckPlaces()
	local by, listed = nil, false
	for key, c in pairs(s.claims) do
		if now - (c.t or 0) > H.CLAIM_DAYS * 86400 then s.claims[key] = nil
		elseif not c.vouched then
			if not listed then by, listed = Listing(), true end
			if VouchedBy(c, by) then c.vouched = true stats.vouched = stats.vouched + 1 end
		end
	end
end

-- The one race waiting to run (1.2.1, the stutter players reported): a census change and an IL
-- look at the claims at once (Look) and leave the race to RACE_SOON later, once for a burst, never
-- inside the game's message event; a vouched claim waiting CONFIRM_AFTER has one re-check, at the
-- moment the first of them is old enough (each race used to start one more, 601 s on).
H.RACE_SOON = 5
local raceSoon = false
function H.RaceSoon()
	if raceSoon then return false end
	raceSoon = true
	ns.After(H.RACE_SOON, "arena level race soon", function() raceSoon = false H.RunRace() end)
	return true
end
local recheckAt, recheckSeq = nil, 0
local function Recheck(at)
	if recheckAt and recheckAt <= at then return end
	recheckSeq = recheckSeq + 1
	local seq = recheckSeq
	recheckAt = at
	ns.After(math.max(1, at - Now()), "arena level race", function()
		if seq ~= recheckSeq then return end -- (an earlier one took its place)
		recheckAt = nil
		H.RunRace()
	end)
end

-- The book again: the claims (vouched where they are) through Honors.LevelRace; a new place said.
-- A claim that can no longer be vouched (unvouched past VOUCH_WINDOW) stops holding the race up
-- (it stays until CLAIM_DAYS, so its sender can't claim that milestone again meanwhile); a gk that
-- several senders claim counts only for the one the game pairs it with (VerifyGk), else only
-- vouched claims of it count.
function H.RunRace()
	local s = H.Store(true)
	local now = Now()
	Look(s, now)
	local claims = {}
	local P = ns.ArenaProfile
	local senders = {}
	for _, c in pairs(s.claims) do
		if c.vouched or ns.Now() - (c.heardLocal or 0) <= H.VOUCH_WINDOW then
			claims[#claims + 1] = { name = c.name, gk = c.gk, guid = GameGuid(c.gk), level = c.level, t = c.t, vouched = c.vouched }
			senders[c.gk] = senders[c.gk] or {}
			senders[c.gk][ns.FullName(c.name):lower()] = true
		end
	end
	local kept = {}
	for _, c in ipairs(claims) do
		local n = 0
		for _ in pairs(senders[c.gk] or {}) do n = n + 1 end
		local ok = n <= 1
		if not ok then
			local verified = P and P.VerifyGk and P.VerifyGk(c.name, c.gk)
			if verified == true then ok = true
			elseif verified == nil then
				ok = c.vouched == true
				for other in pairs(senders[c.gk]) do
					if other ~= ns.FullName(c.name):lower() and P and P.VerifyGk and P.VerifyGk(other, c.gk) == true then ok = false end
				end
			end
		end
		if ok then kept[#kept + 1] = c end
	end
	claims = kept
	local book, fresh, pending = ns.Honors.LevelRace(s.levels, claims, now, { start = H.RACE_START })
	s.levels = book
	for _, p in ipairs(fresh) do
		stats.places = stats.places + 1
		Changed(p.name)
	end
	-- A vouched claim waits CONFIRM_AFTER: looked at again once the first of them is old enough.
	local due
	for _, list in pairs(pending or {}) do
		for _, c in ipairs(list) do
			if c.vouched then
				local at = (tonumber(c.t) or now) + ns.Honors.CONFIRM_AFTER + 1
				if not due or at < due then due = at end
			end
		end
	end
	if due then Recheck(due) end
	return fresh
end

local function OnLevel(dist, sender, mode, body)
	if mode ~= "L" then return Count("mode") end
	local gk, level, t = Arena.Fields(body, 3)
	if not t then return Count("shape") end
	gk, level = Gk(gk), N(level, 1, 60)
	if not gk or not level or not ns.Honors.LEVEL_METAL[level] then return Count("level") end
	if Placed(level) then return Count("placed") end
	local P = ns.ArenaProfile
	local ok = P.VerifyGk(sender, gk)
	if ok == false then return Count("gk") end
	local s = H.Store(true)
	-- (1.2.1: a character whose place at that milestone was found false never claims it again here.)
	if Struck(s, level, gk, sender) then return Count("struck") end
	-- One claim per sender and milestone, in his own name (never another's slot, nor a book filled
	-- by one sender); the book full, its oldest unvouched claim goes.
	local key = ns.FullName(sender):lower() .. ":" .. level
	local c = s.claims[key]
	if not c then
		local n, oldest = 0, nil
		for k, x in pairs(s.claims) do
			n = n + 1
			if not x.vouched and (not oldest or (x.t or 0) < (s.claims[oldest].t or 0)) then oldest = k end
		end
		if n >= H.CLAIMS_MAX then
			if not oldest then return Count("full") end
			s.claims[oldest] = nil
			Count("evicted")
		end
		-- Timed when this client first heard it (its clock, never the player's word).
		c = { gk = gk, name = ns.FullName(sender), level = level, t = Now(), heardLocal = ns.Now(), vouched = false }
		s.claims[key] = c
		stats.claims = stats.claims + 1
	end
	-- (1.2.1) The claims against the census at once, the race RACE_SOON later.
	Look(s, Now())
	H.RaceSoon()
end
ns.Comm.Handle("IL", ns.Arena.Handle("IL", OnLevel))

-- A census report came in, or our roster: the claims waiting are looked at again, and (1.2.1)
-- the places held (three at most: lookups alone) against the server's word, at once; the race
-- RACE_SOON later (H.RaceSoon), once for a burst of reports.
ns.On("DATA_CHANGED", function()
	local s = H.Store()
	if s and s.claims and next(s.claims) then
		for _, c in pairs(s.claims) do
			if not c.vouched then
				ns.SafeCall("arena level vouch", Look, s, Now())
				H.RaceSoon()
				return
			end
		end
	end
	if s and type(s.levels) == "table" and next(s.levels) then
		ns.SafeCall("arena level places", function()
			if #H.CheckPlaces() > 0 then H.RaceSoon() end
		end)
	end
end)

-- The clerk's AB~H: the places this clerk holds (m:gk:name:t), taken for a milestone with no
-- place here (a place never changes once recorded).
function H.RecordsBody()
	local s = H.Store()
	local parts = {}
	for _, m in ipairs(ns.Honors.MILESTONES) do
		local p = s and s.levels and s.levels[m] and s.levels[m][1]
		local gk = p and Arena.GK(p.guid)
		if gk then parts[#parts + 1] = table.concat({ B36(m), gk, ns.ArenaFights.Wire(p.name), B36(p.t or 0) }, ":") end
	end
	return #parts > 0 and ("H~" .. table.concat(parts, ",")) or nil
end
function H.SendRecords()
	local body = H.RecordsBody()
	if body then Arena.Send("AB", "L", body, { key = "ab h", low = true }) end
end
function H.TakeRecords(sender, mode, rest)
	if mode ~= "L" then return end
	local s = H.Store(true)
	local any = false
	for part in tostring(rest):gmatch("[^,]+") do
		local m, gk, name, t = part:match("^([0-9a-z]+):([^:]+):([^:]+):([0-9a-z]+)$")
		m = N(m, 1, 60)
		if m and ns.Honors.LEVEL_METAL[m] and Gk(gk) and not Placed(m) then
			local full = ns.ArenaFights.Unwire(name, sender)
			if full and not Struck(s, m, gk, full) then
				s.levels[m] = { { guid = Arena.GuidOf(gk), name = full, t = N(t, 0, 4294967295) or Now(), place = 1 } }
				any = true
				Changed(full)
			end
		end
	end
	return any
end
-- AQ~H: the clerk says the places; a claimant says his claim again.
function H.Answer(sender)
	local LG = ns.ArenaLedger
	if LG and LG.IsClerk and LG.IsClerk() then H.SendRecords() return true end
	for level in pairs(claimed) do if not Placed(level) then H.SendClaim(level) return true end end
	return false
end

---------------------------------------------------------------------------
-- The donors (ID)
---------------------------------------------------------------------------

-- The Treasurer's client works the donors out of his book (Treasury.DonationRecords, the money part's), by
-- Honors.Donors, and says the names.
function H.DonorWord()
	local T = ns.Treasury
	if type(T) ~= "table" or T.missing or type(T.DonationRecords) ~= "function" then return nil end
	local ok, records = pcall(T.DonationRecords)
	if not ok or type(records) ~= "table" then return nil end
	local s = H.Store(true)
	local D = ns.Dues
	local opts = { kept = s.donorsKept }
	if type(D) == "table" and not D.missing and type(D.Anchor) == "function" then
		local okA, a = pcall(D.Anchor)
		if okA then opts.anchor = a end
	end
	local r = ns.Honors.Donors(records, Now(), opts)
	s.donorsKept = { monthNo = r.monthNo, month = r.month, weekNo = r.weekNo, week = r.week }
	local function Names(list)
		local out = {}
		for i, d in ipairs(list or {}) do out[i] = ns.ArenaFights.Wire(d.name) end
		return out
	end
	return { monthNo = r.monthNo, month = Names(r.month), all = Names(r.all) }
end
local function IdBody(w, t)
	return table.concat({ B36(t), B36(w.monthNo), #w.month > 0 and table.concat(w.month, ",") or "-", #w.all > 0 and table.concat(w.all, ",") or "-" }, "~")
end
local lastId
function H.SendDonors(force)
	if not (ns.IsTreasurerCharacter and ns.IsTreasurerCharacter(ns.me)) and not ns.ArenaRoles.IsKing(ns.me) then return false, "who" end
	local w = H.DonorWord()
	if not w then return false, "book" end
	local sig = w.monthNo .. "|" .. table.concat(w.month, ",") .. "|" .. table.concat(w.all, ",")
	if sig == lastId and not force then return false, "same" end
	lastId = sig
	local body = IdBody(w, Now())
	H.TakeDonors(ns.me, body)
	Arena.Send("ID", "L", body, { key = "id" })
	if GetGuildInfo and GetGuildInfo("player") then Arena.Send("ID", "L", body, { dist = "GUILD", key = "id guild" }) end
	return true
end
function H.TakeDonors(sender, body)
	if not (ns.IsTreasurerCharacter(ns.FullName(sender)) or ns.ArenaRoles.IsKing(sender)) then return Count("sender") end
	local t, month, m, a = Arena.Fields(body, 4)
	if not a then return Count("shape") end
	t, month = N(t, 0, 4294967295), N(month, 0, 99999)
	if not t or not month or t > Now() + 60 then return Count("time") end
	local s = H.Store(true)
	if s.donors and (s.donors.t or 0) >= t and not Same(sender, ns.me) then return Count("older") end
	local function Names(list)
		local out = {}
		if list ~= "-" then
			for name in list:gmatch("[^,]+") do
				local full = ns.ArenaFights.Unwire(name, sender)
				if full and #out < 3 then out[#out + 1] = full end
			end
		end
		return out
	end
	s.donors = { t = t, monthNo = month, month = Names(m), all = Names(a), from = ns.FullName(sender) }
	Changed()
	return true
end
local function OnDonors(dist, sender, mode, body)
	if mode ~= "L" then return Count("mode") end
	H.TakeDonors(sender, body)
end
ns.Comm.Handle("ID", ns.Arena.Handle("ID", OnDonors))

---------------------------------------------------------------------------
-- The Oracle (IO)
---------------------------------------------------------------------------

-- A bank's rows for a month (the markets' markets over its ledger: Honors.OracleScores' rows): a hook the
-- markets fill; none, and a bank says nothing.
H.oracleSource = function() return nil end
local whispered = {} -- [month] = { [bank] = rows }

function H.OracleBanks()
	local out = {}
	for _, b in ipairs(ns.ArenaRoles.Banks("L")) do if b.state == "o" then out[#out + 1] = b.name end end
	table.sort(out, function(x, y) return x:lower() < y:lower() end)
	return out
end

local function RowsText(rows)
	local out = {}
	for i, r in ipairs(rows) do
		if i > 10 then break end
		out[#out + 1] = table.concat({ ns.ArenaFights.Wire(r.name), tostring(r.profit), tostring(r.staked), tostring(r.markets), B36(r.first or 0) }, ":")
	end
	return table.concat(out, ";")
end

-- On a bank's client at the month's end: the first open bank publishes; the others whisper it
-- their top 10.
function H.OracleTick()
	if not ns.ArenaRoles.IsBank(ns.me, "L") then return false end
	local month = ns.Honors.MonthOf(Now()) - 1
	local ok, rows = pcall(H.oracleSource, month)
	if not ok or type(rows) ~= "table" then return false end
	local banks = H.OracleBanks()
	local first = banks[1]
	if not first then return false end
	local cur = ns.ArenaRoles.Currency()
	if not Same(first, ns.me) then
		local _, ranked = ns.Honors.Oracle(rows, { cur = cur })
		Arena.Send("IO", "L", "R~" .. B36(month) .. "~" .. RowsText(ranked or {}), { to = first })
		return true
	end
	local all = {}
	for _, r in ipairs(rows) do r.bank = ns.me all[#all + 1] = r end
	for bank, list in pairs(whispered[month] or {}) do
		for _, r in ipairs(list) do r.bank = bank all[#all + 1] = r end
	end
	local top = ns.Honors.Oracle(all, { cur = cur })
	local names = {}
	for i, r in ipairs(top) do names[i] = ns.ArenaFights.Wire(r.name) end
	local body = table.concat({ B36(month), B36(Now()), #names > 0 and table.concat(names, ",") or "-" }, "~")
	H.TakeOracle(ns.me, "CHANNEL", body)
	Arena.Send("IO", "L", body, { key = "io" })
	return true
end

function H.TakeOracle(sender, dist, body)
	if not ns.ArenaRoles.IsBank(sender, "L") then return Count("sender") end
	if dist == "WHISPER" then
		local kind, month, rows = Arena.Fields(body, 3)
		if kind ~= "R" or not rows then return Count("shape") end
		month = N(month, 0, 99999)
		if not month or not ns.ArenaRoles.IsBank(ns.me, "L") then return Count("bank") end
		local list = {}
		for part in rows:gmatch("[^;]+") do
			local name, profit, staked, markets, first = part:match("^([^:]+):(%-?%d+):(%d+):(%d+):([0-9a-z]+)$")
			local full = name and ns.ArenaFights.Unwire(name, sender)
			if full and #list < 10 then
				list[#list + 1] = { name = full, profit = tonumber(profit), staked = tonumber(staked), markets = tonumber(markets), first = N(first, 0, 4294967295) }
			end
		end
		whispered[month] = whispered[month] or {}
		whispered[month][ns.FullName(sender)] = list
		return true
	end
	local month, t, names = Arena.Fields(body, 3)
	if not names then return Count("shape") end
	month, t = N(month, 0, 99999), N(t, 0, 4294967295)
	if not month or not t or t > Now() + 60 then return Count("time") end
	local s = H.Store(true)
	local had = s.oracle[month]
	if had and (had.t or 0) >= t and not Same(sender, ns.me) then return Count("older") end
	local list = {}
	if names ~= "-" then
		for name in names:gmatch("[^,]+") do
			local full = ns.ArenaFights.Unwire(name, sender)
			if full and #list < 3 then list[#list + 1] = full end
		end
	end
	s.oracle[month] = { t = t, names = list, from = ns.FullName(sender) }
	-- Two months kept.
	for m in pairs(s.oracle) do if type(m) == "number" and m < month - 1 then s.oracle[m] = nil end end
	Changed()
	return true
end
local function OnOracle(dist, sender, mode, body)
	if mode ~= "L" then return Count("mode") end
	H.TakeOracle(sender, dist, body)
end
ns.Comm.Handle("IO", ns.Arena.Handle("IO", OnOracle))

---------------------------------------------------------------------------
-- Our own honours: the automatic switch-on and the King's letter
---------------------------------------------------------------------------

-- The sources loaded (Honors.Update's known): a family is forgotten only once its source is here.
function H.Known()
	local LG = ns.ArenaLedger
	local s = H.Store()
	local titles = LG and LG.CoreT and LG.CoreT("L", "titles")
	local words = LG and LG.CoreT and LG.CoreT("L", "beltWords")
	local guilds = ns.rdb and ns.rdb.guilds
	local fresh = false
	for _, r in pairs(type(guilds) == "table" and guilds or {}) do
		if type(r) == "table" and r.t and ns.Now() - r.t <= ns.Honors.GUILD_MAX_AGE then fresh = true break end
	end
	-- (1.2.3: the Church's top 3 while it is shown and fresh; closed, unheard or stale it is not
	-- known, so a missionary's crook is remembered as it was: never "lost", nor "new" when it is back.)
	local church = ChurchTop()
	return {
		belt = (titles and next(titles) ~= nil) or (words and next(words) ~= nil) or Arena.Heavy("L") ~= nil,
		tier = Arena.Heavy("L") ~= nil,
		donor = s ~= nil and s.donors ~= nil,
		level = s ~= nil and s.levels ~= nil and next(s.levels) ~= nil,
		guild = fresh,
		oracle = s ~= nil and s.oracle ~= nil and next(s.oracle) ~= nil,
		missionary = church ~= nil and ns.Honors.ChurchFresh(church, Now()),
	}
end

local refreshing = false
local letters = {} -- the queue shown now: { key, t }
-- Our honours looked at again: what is new switches on (unless locked) and gets its letter.
function H.Refresh()
	if refreshing or not ns.db or not ns.IsMember() then return end
	refreshing = true
	local P = ns.ArenaProfile
	local ok, err = pcall(function()
		local held = H.Holdings(ns.me, P.MyGk())
		local before = P.Pick()
		local first = before.seen == nil
		-- (1.2.3) Only an honour told for the first time switches on by itself (its letter comes with
		-- it): back the same month to a place of the Church's 30-day ranking already told, his own
		-- pick since stays. What was told before a 1.2.0 profile's first look (FirstLook counts what
		-- it holds as told for the letters alone, on the safe side: those still switch on, as in 1.2.1).
		local told = H.Lettered()
		if P.Mine().letterLook then
			local copy = {}
			for mark, v in pairs(told) do copy[mark] = v end
			told = copy
		end
		H.FirstLook(held)
		local pick, earned, lost = ns.Honors.Update(before, held, H.Known(), function(h)
			return told[H.LetterMark(h.key, h.period)] == true
		end)
		-- Kept only when something is to remember (an idle client writes no profile).
		local same = pick.frame == before.frame and pick.title == before.title and #earned == 0 and #lost == 0
		if not same or (first and next(pick.seen or {}) ~= nil) then P.SavePick(pick) end
		local sent = false
		if pick.frame ~= before.frame or pick.title ~= before.title then
			P.Send(true)
			sent = true
		end
		for _, h in ipairs(earned) do
			if (h.frame or h.title) and not h.noLetter then H.QueueLetter(h.key, h.period) end
		end
		if sent or #earned > 0 then
			gen = gen + 1
			ns.Fire("HONORS_CHANGED", ns.me)
		end
		return first
	end)
	refreshing = false
	if not ok then error(err, 0) end
end

-- The letter is the King's (L.HONOR_LETTER_SIGN): never to the King himself (1.2.1, the owner's
-- ask, after the King's stream: a letter from himself about a frame he holds). The King is his
-- character (ns.IsKingCharacter) or, where none is pinned by name, the guild master of his guild
-- (King.IsKing). His honours switch on as anyone's; no letter comes, none is kept to read again.
-- (1.2.3: each is marked told all the same, QueueLetter, so they switch on once, as anyone's.)
function H.LetterToSender()
	if ns.IsKingCharacter(ns.me) then return true end
	local K = ns.King
	return type(K) == "table" and not K.missing and type(K.IsKing) == "function" and K.IsKing() == true
end

-- Each honour's letter comes once per character, ever (1.2.1, the owner's ask: never again after
-- a reload, a relog or an update, nor when an honour comes back after a gap in its source, or a
-- place lost and won back): the profile's lettered = { [mark] = true }, the honours told. A
-- month's honour (the month's donors, the Oracle: keys that name only the place) is told for its
-- month (H.LetterMark): won again another month, it is a new award, with its letter. (1.2.3: so is
-- the missionaries' crook, told for the calendar month he reaches its place in.)
-- The profiles 1.2.0 kept are read once, at the account's first login under 1.2.1 (ns.db's
-- honorLetters, set then: every profile kept before it is 1.2.0's, one made after it starts with
-- nothing told): every letter it queued (its letters, read or not) and every honour its pick
-- remembered held (its seen) count as told; and, on the safe side (a letter that has left the
-- list of 20), every honour held at that character's first look (H.FirstLook).
H.LETTERS_RULE = 1
function H.LetterMark(key, period)
	period = tonumber(period)
	return period and (key .. "@" .. period) or key
end
-- A 1.2.0 letter's or pick's mark: a month's honour for the month closed before t (the one it was
-- held for then, as Honors.Holdings counts it).
local function OldMark(key, t)
	local family = H.LetterFamily(key)
	if family ~= "donor-month" and family ~= "oracle" then return key end
	return H.LetterMark(key, ns.Honors.MonthOf(tonumber(t) or Now()) - 1)
end
function H.ReadOldLetters()
	local db = ns.db
	if type(db) ~= "table" or db.honorLetters ~= nil then return end
	for _, m in pairs(type(db.arenaProfile) == "table" and db.arenaProfile or {}) do
		if type(m) == "table" and m.lettered == nil and (type(m.letters) == "table" or type(m.seen) == "table") then
			local told = {}
			for _, x in ipairs(type(m.letters) == "table" and m.letters or {}) do
				if type(x) == "table" and type(x.key) == "string" then told[OldMark(x.key, x.t)] = true end
			end
			for _, s in pairs(type(m.seen) == "table" and m.seen or {}) do
				if type(s) == "table" then
					if type(s.frame) == "string" then told[OldMark(s.frame, m.at)] = true end
					if type(s.title) == "string" then told[OldMark(s.title, m.at)] = true end
				end
			end
			m.lettered, m.letterLook = told, true
		end
	end
	db.honorLetters = H.LETTERS_RULE
end
-- The honours told to this character (a table to read; QueueLetter keeps it).
function H.Lettered()
	H.ReadOldLetters()
	local m = ns.ArenaProfile.Mine()
	return type(m.lettered) == "table" and m.lettered or {}
end
-- A 1.2.0 profile's first look under 1.2.1 (H.Refresh's, before anything is earned): what it
-- holds then counts as told.
function H.FirstLook(held)
	H.ReadOldLetters()
	local m = ns.ArenaProfile.Mine()
	if not m.letterLook then return end
	m.lettered = type(m.lettered) == "table" and m.lettered or {}
	for _, h in ipairs(type(held) == "table" and held or {}) do
		if type(h) == "table" and type(h.key) == "string" then m.lettered[H.LetterMark(h.key, h.period)] = true end
	end
	m.letterLook = nil
end

-- A letter queued (and kept, re-readable): shown now, or after the one open; never twice (period:
-- a month's honour's month).
-- Where the save did not come back (Arena.Persists: the Forever beta loads an empty one at each
-- login; a first session) nothing told is known: every honour held looks new at each login. The
-- letter is kept in the profile's list, unread, to open from the Edit, and never opens by itself
-- (1.2.1, the owner's ask: never again at each update; as the update letter, Letters.lua).
function H.QueueLetter(key, period)
	if type(key) ~= "string" then return end
	local told = H.Lettered()
	local mark = H.LetterMark(key, period)
	if told[mark] then return end
	local P = ns.ArenaProfile
	local m = P.Mine(true)
	m.lettered = told
	told[mark] = true
	-- (1.2.3: the King's honours are told too, with no letter, so they switch on as anyone's: once.)
	if H.LetterToSender() then return end
	m.letters = type(m.letters) == "table" and m.letters or {}
	m.letters[#m.letters + 1] = { key = key, t = Now() }
	while #m.letters > H.LETTERS_MAX do table.remove(m.letters, 1) end
	if not Arena.Persists() then return end
	letters[#letters + 1] = { key = key, t = Now() }
	H.ShowLetter()
end
function H.Letters()
	if H.LetterToSender() then return {} end
	local m = ns.ArenaProfile.Mine()
	return type(m.letters) == "table" and m.letters or {}
end

-- The family a letter speaks for (its text in L.HONOR_LETTER).
function H.LetterFamily(key)
	if type(key) ~= "string" then return nil end
	if key:find("^arena%-champion") then return "arena" end
	if key:find("^arena%-class%-") then return "class" end
	if key:find("^arena%-race%-") then return "race" end
	if key:find("^donor%-top%-") then return "donor-top" end
	if key:find("^donor%-month%-") then return "donor-month" end
	if key:find("^level%-race%-") then return "level" end
	if key:find("^oracle%-") then return "oracle" end
	if key == "guild-top-leader" then return "guild" end
	if key:find("^missionary%-") then return "missionary" end
	return nil
end
-- The letter's words: the King's, naming the honour and its title (never a real name).
function H.LetterText(key)
	local family = H.LetterFamily(key)
	local fmt = family and L.HONOR_LETTER and L.HONOR_LETTER[family]
	if not fmt then return nil end
	local title = H.TitleText(key) or key
	local _, _, metal = ns.Honors.ArtOf(key)
	local milestone = tonumber(key:match("^level%-race%-(%d+)$"))
	return fmt:format(title, milestone or (metal and L["HONOR_METAL_" .. metal:upper()] or "")), title
end

-- Under the gamepad UI nothing of Olympus opens by itself (the design: focus only on a
-- click): a letter waits for the player's own click, the next time the Olympus window
-- (H.WindowShown) or his profile's Edit opens (ProfileEdit.Open), and chat says once that one is
-- waiting.
function H.WaitForWindow()
	if not H.toldWaiting then
		H.toldWaiting = true
		ns.Print(L.HONOR_LETTER_WAITING)
	end
end
-- The Olympus window opened (UI.lua, its OnShow: the window is made on its first open, in either
-- look and either template, so nothing here can hook it beforehand): the letter waiting shows.
function H.WindowShown()
	if letters[1] then return H.ShowLetter(nil, true) end
	return false
end

local frame
local INK_R, INK_G, INK_B = 0.18, 0.10, 0.02
-- The game's letter font (its mail's), else its quest font: dark ink on the parchment.
local function LetterFont()
	if _G.MailTextFontNormal then return "MailTextFontNormal" end
	return _G.QuestFont and "QuestFont" or "GameFontHighlight"
end
-- A font string at px at least (the client's own font, only bigger).
local function AtLeast(fs, px)
	if not (fs and fs.GetFont and fs.SetFont) then return end
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	if ok and type(path) == "string" and type(size) == "number" and size < px then fs:SetFont(path, px, flags) end
end
local function Ink(fs, wrap)
	fs:SetTextColor(INK_R, INK_G, INK_B)
	if fs.SetJustifyV then fs:SetJustifyV("TOP") end
	if wrap and fs.SetWordWrap then fs:SetWordWrap(true) end
	if wrap and fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
	AtLeast(fs, H.LETTER_FONT)
end
-- A text's height at `width`: the client's measure, else about 7 px a letter and 18 a line.
local function TextHeight(fs, width)
	local h = fs.GetStringHeight and fs:GetStringHeight()
	if type(h) == "number" and h > 0 then return h end
	local lines = 0
	for line in ((fs:GetText() or "") .. "\n"):gmatch("([^\n]*)\n") do
		lines = lines + math.max(1, math.ceil(#line / math.max(1, math.floor(width / 7))))
	end
	return lines * 18
end

-- The letter (1.2.1, the owner's ask after the King's stream: its words ran off the paper and its
-- buttons under it, no window round it): a window of Olympus's own (ns.Window: the Olympus
-- window's bronze metal without its portrait or logo, as the update letter), the head in its
-- title bar, the parchment (the game's QuestBG, its paper's part alone) inside it, his own
-- portrait with the new frame in its top left corner, the King's words right of it in the game's
-- letter font (15 px at least), wrapped inside the paper; the wax seal and the signature under
-- both, "Wear it" and "Later" at its foot. Its height follows the words. Never the game's popups.
local function Build()
	local f = ns.Window("OlympusKingsLetter", UIParent, { title = L.HONOR_LETTER_HEAD, inset = false, close = false })
	f:SetSize(H.LETTER_W, 300)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.head = f.TitleText
	local inner, pad = f.inner, H.LETTER_PAD
	f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.bg:SetPoint("TOPLEFT", inner[1], inner[2])
	f.bg:SetPoint("BOTTOMRIGHT", inner[3], inner[4])
	local UI = ns.UI
	local file = type(UI) == "table" and UI.FirstTexture and UI.FirstTexture(UI.PARCHMENTS or { "Interface\\QuestFrame\\QuestBG" })
		or "Interface\\QuestFrame\\QuestBG"
	if GetFileIDFromPath and not GetFileIDFromPath(file) then
		f.bg:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		f.bg:SetTexture(file)
		if file:find("QuestBG", 1, true) then f.bg:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	-- His own portrait with the honour's frame, as round his unit frame's (H.NewPortrait: 60, his
	-- frame's own size), its art clear of the paper's edge and the title bar.
	local rig = H.NewPortrait(f, H.LETTER_PORTRAIT)
	local reach = rig.reach
	f.paperTop = -inner[2] + pad
	rig.slot:SetPoint("TOPLEFT", inner[1] + pad + reach.left, -(f.paperTop + reach.top))
	f.rig, f.portrait = rig, rig.portrait
	-- The words right of the art, to the paper's right margin.
	local x = inner[1] + pad + reach.left + H.LETTER_PORTRAIT + reach.right + 12
	f.bodyWidth = H.LETTER_W + inner[3] - pad - x
	f.body = f:CreateFontString(nil, "ARTWORK", LetterFont())
	f.body:SetPoint("TOPLEFT", x, -f.paperTop)
	f.body:SetWidth(f.bodyWidth)
	f.body:SetJustifyH("LEFT")
	Ink(f.body, true)
	f.sign = f:CreateFontString(nil, "ARTWORK", LetterFont())
	f.sign:SetJustifyH("RIGHT")
	Ink(f.sign)
	f.sign:SetText(L.HONOR_LETTER_SIGN)
	f.seal = f:CreateTexture(nil, "ARTWORK")
	f.seal:SetSize(40, 40)
	-- The game's own wax seal (its quest letters from the King, QuestInfo.lua), the faction's.
	local atlas = ns.faction == "Horde" and "Quest-Horde-WaxSeal" or "Quest-Alliance-WaxSeal"
	local info = C_Texture and C_Texture.GetAtlasInfo
	local okA, has = false, nil
	if type(info) == "function" then okA, has = pcall(info, atlas) end
	if okA and has then f.seal:SetAtlas(atlas) else f.seal:SetTexture("Interface\\Icons\\Spell_Holy_SealOfSacrifice") end
	local function Btn(label, dx, fn)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(H.LETTER_BUTTON, 24)
		b:SetPoint("BOTTOM", dx, inner[4] + 12)
		b:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	f.wear = Btn(L.HONOR_LETTER_WEAR, -(H.LETTER_BUTTON / 2 + 6), function() H.CloseLetter(true) end)
	f.later = Btn(L.HONOR_LETTER_LATER, H.LETTER_BUTTON / 2 + 6, function() H.CloseLetter(false) end)
	-- Hidden another way (Escape, the game's window sweep): as "Later", so it never comes back by
	-- itself with the next letter or the Olympus window's open. The whole interface hidden (Alt+Z, a
	-- cinematic: still shown itself, as Dialog.lua's) is no answer: it is there again with it.
	f:SetScript("OnHide", function()
		if f:IsShown() then return end
		if f.key ~= nil then ns.SafeCall("kings letter", H.CloseLetter, false) end
	end)
	return f
end
-- Placed for the words it shows: the body's height measured, the seal and the signature under
-- the words and the art, the window as tall as that and its buttons.
local function Place(f)
	local inner, reach, top = f.inner, f.rig.reach, f.paperTop
	f.body:SetHeight(0) -- (a font string 0 tall is as tall as its words: measured whole)
	local h = math.ceil(TextHeight(f.body, f.bodyWidth)) + 2
	f.body:SetHeight(h)
	local y = math.max(top + h, top + reach.top + H.LETTER_PORTRAIT + reach.bottom) + 10
	f.sign:SetPoint("TOPRIGHT", inner[3] - H.LETTER_PAD - 8, -(y + 12))
	-- (1.2.4, the author's ask: the wax seal just before the signature, on the right, not at the
	-- paper's left edge.)
	f.seal:ClearAllPoints()
	f.seal:SetPoint("RIGHT", f.sign, "LEFT", -6, 0)
	f:SetHeight(y + 40 + 12 + 24 + inner[4] + 12)
end

-- key: a letter asked for (a click: shown at once); prompted: the player's click opened it.
function H.ShowLetter(key, prompted)
	if H.LetterToSender() then return false end
	if key then letters[#letters + 1] = { key = key, t = Now() } end
	local nextLetter = letters[1]
	if not nextLetter then return false end
	if frame and frame:IsShown() then return true end
	if not key and not prompted and ns.GamepadUI() then
		H.WaitForWindow()
		return false
	end
	H.toldWaiting = nil
	if InCombatLockdown and InCombatLockdown() then
		ns.After(5, "kings letter", function() H.ShowLetter(nil, prompted) end)
		return false
	end
	frame = frame or Build()
	local text = H.LetterText(nextLetter.key)
	frame.key = nextLetter.key
	frame.body:SetText(text or "")
	Place(frame)
	H.DressPortrait(frame.rig, nextLetter.key)
	frame:Show()
	return true
end
-- "Wear it" (its frame and title picked) or "Later"; the next letter after it.
function H.CloseLetter(wear)
	local cur = table.remove(letters, 1)
	if frame then
		frame.key = nil
		frame:Hide()
	end
	if cur then
		for _, x in ipairs(H.Letters()) do if x.key == cur.key then x.read = true end end
		if wear then
			local held = H.Holdings(ns.me, ns.ArenaProfile.MyGk())
			local frameKey, titleKey
			for _, h in ipairs(held) do
				-- (1.2.3: a frame this version does not wear yet, its title alone: Honors.Choose refused
				-- the pair, and "Wear it" did nothing.)
				if h.key == cur.key then frameKey, titleKey = ns.Honors.FrameShipped(h) and h.frame or nil, h.title end
			end
			if frameKey or titleKey then ns.ArenaProfile.SetPick(frameKey or ns.ArenaProfile.Pick().frame, titleKey) end
		end
	end
	-- (The next one after this click: the player's own.)
	if letters[1] then H.ShowLetter(nil, true) end
	return true
end
function H.LetterFrame() return frame end
function H.QueuedLetters() return letters end

---------------------------------------------------------------------------
-- The role clients' timers (the Treasurer's donors, a bank's Oracle), our own refresh
---------------------------------------------------------------------------

local donorTicker, oracleTicker
function H.WatchRoles()
	local treasurer = ns.IsTreasurerCharacter and ns.IsTreasurerCharacter(ns.me)
	if treasurer and not donorTicker then
		donorTicker = ns.Every(H.DONOR_EVERY, "arena donors", function() H.SendDonors(true) end)
		ns.After(60, "arena donors login", function() H.SendDonors(true) end)
	end
	local bank = ns.ArenaRoles.IsBank(ns.me, "L")
	if bank and not oracleTicker then
		oracleTicker = ns.Every(H.ORACLE_EVERY, "arena oracle", function() H.OracleTick() end)
	elseif not bank and oracleTicker then
		if oracleTicker.Cancel then oracleTicker:Cancel() end
		oracleTicker = nil
	end
end

ns.On("LOGIN", function()
	-- (First: the account's profiles as 1.2.0 left them, before anything of this session writes one.)
	H.ReadOldLetters()
	H.WatchLevels()
	H.WatchRoles()
	-- Our own honours whenever the realm's words change (HONORS_CHANGED, below); at login only where
	-- saved data already holds some (an idle client starts no timer: the weight rule).
	local LG = ns.ArenaLedger
	local titles = LG and LG.CoreT and LG.CoreT("L", "titles")
	if H.Store() or (titles and next(titles)) then
		ns.After(H.REFRESH_DELAY, "arena honours refresh", function() H.Refresh() end)
	end
end)
-- Our honours looked at again a moment after a change that may be ours (the realm's words, the
-- belts, our own), once for a burst.
local refreshDue = false
function H.RefreshSoon()
	if refreshDue or refreshing then return end
	refreshDue = true
	ns.After(2, "arena honours refresh", function() refreshDue = false H.Refresh() end)
end
ns.On("HONORS_CHANGED", function(name)
	if name == nil or Same(name, ns.me) then H.RefreshSoon() end
end)
ns.On("ARENA_CHANGED", function() H.WatchRoles() end)

Arena.Action("honors.letter", nil, function(key) return H.ShowLetter(key) end)
Arena.Action("honors.refresh", nil, function() return H.Refresh() end)
