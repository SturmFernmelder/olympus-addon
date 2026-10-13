local ADDON, ns = ...
local L = ns.L

-- The guild masters' nominees (1.1.5, the author's ask after the High Council's yes): the guild
-- master of an Olympus guild names, from Olympus, up to MAX_CENTURIONS centurions and one
-- correspondent per department of the High Council (the named departments of the council's signed
-- titles list, MAX_DEPTS at most): MAX people in all, members of his own guild. The addon holds the
-- caps (an eleventh centurion, a second correspondent for a department, someone named twice, a
-- name outside his roster: each refused with its reason), so nobody has to count them by hand.
-- Each wears Max's bronze border without wings (Borders.lua's "bronze"), and the bronze mark of a
-- guild master on nameplates and in the game's chat, only while the server gives him that guild
-- (GetGuildInfo): nobody outside it can borrow it.
--
-- Where (1.1.5, the author's call on seeing the page): a tab of its own, in the Throne's place
-- (King.lua's Build; UI.lua's "throne" key). A guild master of an Olympus guild (not the King's)
-- has it as his Guild tab, his guild's page: the King's Hands page's look and flow (King.lua's HandsLines, the
-- Throne's parchment and ink), a title, a one-line hint, "+ Name a centurion (your target, or type
-- a name)", his list with a click that takes the title back (asked first), the departments'
-- correspondents (the role picker: a line per department, a click names its correspondent) and the
-- note on how the army learns his list. And
-- `/oly nominees [centurion <name> | correspondent <n> <name> | remove <name>]` (alone: the tab).
--
-- The King's own guild: no guild master's Guild tab (its master is the King), no correspondents, and
-- (1.2.4, the author's rule) no centurions named: each High Councillor is a centurion for the King.
-- The signed council list says who (appointment only); the Throne's page lists them to read
-- (Nominees.MainLines), and they lead the King's guild's squads in the War Room (WarSquads.Leaders).
-- 1.1.5's list of the King's guild's centurions, named on the Throne by the King or a councillor,
-- counts for nothing since: what older clients still hold of it is ended from here (Retire, below).
--
-- How it travels, as the King's list of Hands (King.lua): the guild master's own client keeps his
-- list (ns.rdb.nominees, under his character) and sends it on the Olympus channel a few seconds
-- after each change and every EVERY seconds while he is online. Every client takes it only from
-- that guild's master as the census proves him, the very proof the borders ask for a guild
-- master's bronze (Borders.lua's Facts): our own guild's from our roster (the server's word),
-- another guild's from its census report, two senders naming him guild master, one of them
-- someone else (Data.KnownRank). The sender is the name the server stamps, so nobody can send it
-- for him. A list from anyone else is refused, and never takes the place of the real one. Each
-- client keeps the last list it heard from each guild's master, in memory only (heard this
-- session), for FRESH after his client stopped repeating it, and drops it at once when the census
-- or our roster shows he is no longer that guild's master (another one proven, or his own rank
-- below it), or when his new list names nobody.
--   NM~1~<guild>~<rev>~<i>~<n>~<entry>;<entry>;...
-- One list in n parts (i of n), each one addon message of PART bytes at most, put together by
-- their <rev> (the time of his last change); an entry is c=<Name[-Realm]> (a centurion) or
-- d=<department>=<Name[-Realm]> (that department's correspondent), a name without a realm his
-- own realm's. Bounded on every side: MAX_PARTS parts, the caps above (the first ones kept), each
-- name and each department once, a department's name of DEPT_LEN bytes. No part is ever chunked:
-- clients before 1.1.5 have no handler for NM and leave each part unread, nothing counted bad
-- (Comm.lua). Version 1: a client takes the parts of its own version alone.
-- The gamepad UI: the borders and marks it gives are off there, as every border (Borders.lua), and
-- its name boxes are Olympus's own dialogs (ns.ShowDialog), never the game's popups.
-- /oly status: his own list, and the lists held here (Nominees.StatusLine).

local Nominees = {}
ns.Nominees = Nominees

Nominees.MAX_CENTURIONS = 10
Nominees.MAX_DEPTS = 6
Nominees.MAX = Nominees.MAX_CENTURIONS + Nominees.MAX_DEPTS
Nominees.EVERY = 300          -- his client repeats the list for late logins
Nominees.FRESH = 6 * 60 * 60  -- a list he stopped repeating (he logged off) counts this long after
Nominees.SEND_AFTER = 3       -- several changes in a row go out as one list
Nominees.PART = 250           -- bytes in one part (one addon message)
Nominees.MAX_PARTS = Nominees.MAX
Nominees.PART_WAIT = 60       -- the parts of one list wait this long for the rest
Nominees.DEPT_LEN = 40
Nominees.WIRE = "1"           -- the message's version

local lists = {}   -- [guild, lower case] = { guild, by, rev, at, entries = { { role, dept, name } }, set = { [name, lower case] = entry } }
local pending = {} -- [sender] = { guild, rev, n, parts = { [i] = body }, got, t }: a list's parts as they come
local version = 0  -- one more at each change of what any list counts for (Borders.Changed)
local lastSent, sendPending = -math.huge, false
local sentOnce = false -- his list went out this session (then an empty one goes out too)
-- 1.2.4: ending 1.1.5's list of the King's guild's centurions where older clients hold it (Retire):
-- the newest rev heard of one that names anyone, whether one heard waits for an answer (no empty one
-- newer than every named one came after it), when this client last sent one, and whether one is on
-- its way. (An end heard or sent earlier answers nothing heard after it: a 1.2.3 client that logged
-- in since never heard it, and takes the named one, older than that end, as the newest.)
local retireNamed, retireWanted, retiredAt, retirePending = 0, false, -math.huge, false
Nominees.RETIRE_GAP = 60 -- an answer to an older client's list, once a minute at most

function Nominees.Version() return version end
local function Bump() version = version + 1 end

---------------------------------------------------------------------------
-- Names, guilds, departments
---------------------------------------------------------------------------

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- A character's name as the server writes it ("First Surname-Realm"; a name without a realm is
-- `realm`'s, ours when none), or nil if it can't be one: letters only (Forever's first name and
-- surname), the realm letters and digits.
local function Person(s, realm)
	s = Trim(ns.Normal(Trim(s)))
	local short, theirs = s:match("^([^%-]+)%-([^%-]+)$")
	short = short or s
	if #short > 30 or not short:match("^[%a\128-\255]+ ?[%a\128-\255]*$") then return nil end
	if theirs and (#theirs > 40 or not theirs:match("^[%w\128-\255]+$")) then return nil end
	return ns.FullName(short, theirs or realm)
end
Nominees.Person = Person

-- A name typed, as our roster spells it (the server's): whatever its case, and (anyRealm: typed
-- without one) on another realm when only one member carries it. nil when our roster has nobody
-- of that name.
local function RosterName(name, anyRealm)
	if type(name) ~= "string" then return nil end
	if ns.Roster.RankOf(name) ~= nil then return name end
	local byName = ns.Roster.byName
	if type(byName) ~= "table" then return nil end
	local low, short = name:lower(), ns.ShortName(name):lower()
	local found, twice
	for full in pairs(byName) do
		if type(full) == "string" then
			if full:lower() == low then return full end
			if anyRealm and ns.ShortName(full):lower() == short then
				twice = found ~= nil
				found = found or full
			end
		end
	end
	return not twice and found or nil
end

-- An Olympus guild's name as a list may give it, or nil.
local function GuildName(s)
	s = tostring(s or ""):gsub("[%c|]", "")
	if s == "" or #s > 24 or not s:match("^[%w\128-\255 ]+$") or not ns.IsFederation(s) then return nil end
	return s
end

-- A department's name as the lists carry it: no separator of theirs, DEPT_LEN bytes at most.
local function DeptName(s)
	s = Trim(tostring(s or ""):gsub("[%c|~;=]", ""))
	if s == "" or #s > Nominees.DEPT_LEN then return nil end
	if s:lower() == "association of citizenry" or s:lower() == "association of artisanry" then return "Association of Artisanry" end
	return s
end

-- The High Council's six departments (the author's names, 1.1.5): the correspondents' roles, one
-- each per guild. (The signed titles list names only the departments that have councillors.)
Nominees.DEPARTMENTS = { "Federal Treasury", "Department of War", "Council of Justice", "Association of Artisanry",
	"Department of Heritage", "The Missionary Church of Olympus" }
Nominees.SHIPPED_DEPARTMENTS = Nominees.DEPARTMENTS
function Nominees.Departments()
	local out = {}
	for i, name in ipairs(Nominees.DEPARTMENTS) do
		if i <= Nominees.MAX_DEPTS then out[#out + 1] = name end
	end
	return out
end
local function IsDept(dept)
	if type(dept) ~= "string" then return nil end
	dept = DeptName(dept)
	if not dept then return nil end
	for _, d in ipairs(Nominees.Departments()) do
		if d:lower() == dept:lower() then return d end
	end
	return nil
end

-- A role as a line says it: "centurion", "correspondent for Events".
function Nominees.RoleLabel(role, dept)
	if role == "correspondent" then return L.NOMINEE_ROLE_CORRESPONDENT:format(dept or "?") end
	return L.NOMINEE_ROLE_CENTURION
end

---------------------------------------------------------------------------
-- Who is the guild's master
---------------------------------------------------------------------------

-- This character is the guild master of an Olympus guild (the server's rank), and that guild.
local function RealMaster()
	if ns.IsMember() ~= true then return false end
	local guild, _, rank = GetGuildInfo("player")
	-- (The King's own guild has no centurions or correspondents: the author's call.)
	if type(guild) == "string" and ns.IsKingGuild and ns.IsKingGuild(guild) then return false end
	return rank == 0 and type(guild) == "string", guild
end

-- The author's "guild master's view" (1.1.5, his ask: his character is no guild master): from the
-- Workshop, his section shows as a guild master's would, to see and try it. Nothing it does is
-- sent (Nominees.Send refuses it): what he names stays on his screen. Since 1.2 it is View as's
-- "Guild Master" (ViewAs.lua): that preview drives it, and /oly nominees view picks it there.
local function ViewAsGM()
	local V = ns.ViewAs
	return type(V) == "table" and not V.missing and type(V.Is) == "function" and V.Is("gm") == true
end
function Nominees.DevView()
	if RealMaster() then return false end
	if ViewAsGM() then return true end
	return ns.db ~= nil and ns.db.devGMView == true and ns.Workshop ~= nil and ns.Workshop.Visible ~= nil
		and ns.Workshop.Visible() == true
end
function Nominees.SetDevView(on)
	local V = ns.ViewAs
	if type(V) == "table" and not V.missing and type(V.Available) == "function" and V.Available() == true
		and type(V.Set) == "function" and (on or ViewAsGM()) then
		V.Set(on and "gm" or "my") -- (it clears the old switch, ns.db.devGMView, and redraws)
	else
		ns.db.devGMView = on and true or false
		ns.Fire("DATA_CHANGED")
	end
	ns.Print(on and ns.L.DEV_GM_VIEW_NOW_ON or ns.L.DEV_GM_VIEW_NOW_OFF)
end

function Nominees.IsMaster()
	local real, guild = RealMaster()
	if real then return real, guild end
	if Nominees.DevView() then return true, GetGuildInfo("player") or "Olympus" end
	return false
end

-- The King's own guild: its centurions are the High Council (1.2.4), nobody's list.
local function IsMain(guild) return type(guild) == "string" and ns.IsKingGuild(guild) == true end
Nominees.IsMain = IsMain
function Nominees.MainGuild() return ns.KingGuildName() end

-- `sender` is `guild`'s master as Borders proves the bronze: our own guild's from our roster (the
-- server's), another guild's from its census (two senders naming him, one of them someone else).
-- The King's guild's (1.1.5's list, from an older client: Retired below): the King's character or
-- a signed High Councillor.
local function Proven(sender, guild)
	if IsMain(guild) then return ns.IsKingCharacter(sender) == true or ns.IsHighCouncillor(sender) == true end
	local mine = GetGuildInfo("player")
	if mine and guild == mine then return ns.Roster.RankOf(sender) == 0 end
	if mine and guild:lower() == mine:lower() then return false end -- (our guild spelled another way)
	local rank, named = ns.Data.KnownRank(sender, guild)
	return rank == 0 and (named or 0) >= 2
end
Nominees.Proven = Proven

-- He is no longer that guild's master, as far as this client can tell: our roster gives him
-- another rank or names another guild master; another guild's census proves another one, or gives
-- him another rank. Nothing known (a census gone quiet): not that.
local function Deposed(l)
	local mine = GetGuildInfo("player")
	if mine and l.guild:lower() == mine:lower() then
		local rank = ns.Roster.RankOf(l.by)
		if rank ~= nil then return rank ~= 0 end
		local stats = ns.Roster.lastStats
		local lead = ns.Roster.guild == mine and type(stats) == "table" and stats.leader or nil
		return type(lead) == "string" and ns.FullName(lead):lower() ~= l.by:lower()
	end
	local rank = ns.Data.KnownRank(l.by, l.guild)
	if rank ~= nil and rank ~= 0 then return true end
	local g = ns.Data.Guild(l.guild)
	if type(g) == "table" and type(g.leader) == "string" then
		local lead = ns.FullName(g.leader, g.realm)
		if lead:lower() ~= l.by:lower() then
			local other, named = ns.Data.KnownRank(lead, l.guild)
			if other == 0 and (named or 0) >= 2 then return true end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The guild master's own list (his client's alone)
---------------------------------------------------------------------------

-- His saved list for the guild he leads now, made when `make` (nil when he leads none).
-- { guild, rev, list = { { r = "c" | "d", d = department, n = "Name-Realm" }, ... } }
local function Saved(make)
	local master, guild = Nominees.IsMaster()
	if not master or not ns.rdb or not ns.me then return nil end
	local all = ns.rdb.nominees
	local s = type(all) == "table" and all[ns.me] or nil
	if type(s) ~= "table" or s.guild ~= guild or type(s.list) ~= "table" then
		if not make then return nil end
		if type(all) ~= "table" then all = {}; ns.rdb.nominees = all end
		s = { guild = guild, rev = ns.Now(), list = {} }
		all[ns.me] = s
	end
	return s
end

-- His entries as they count (a correspondent's department still one of the council's), in
-- order: { { role, dept, name } }; and the ones that do not (their department gone).
local function OwnEntries(s)
	local out, stale, c, depts = {}, {}, 0, {}
	for _, e in ipairs(s and s.list or {}) do
		if type(e) == "table" and type(e.n) == "string" then
			if e.r == "c" and c < Nominees.MAX_CENTURIONS then
				c = c + 1
				out[#out + 1] = { role = "centurion", name = e.n }
			elseif e.r == "d" then
				local dept = IsDept(e.d)
				if dept and not depts[dept:lower()] then
					depts[dept:lower()] = true
					out[#out + 1] = { role = "correspondent", dept = dept, name = e.n }
				else
					stale[#stale + 1] = { role = "correspondent", dept = tostring(e.d or "?"), name = e.n }
				end
			end
		end
	end
	return out, stale
end

---------------------------------------------------------------------------
-- The King's centurions (1.2.4, the author's rule): the High Council
---------------------------------------------------------------------------

-- In the King's guild each High Councillor is a centurion for the King: the signed council list says
-- who, and nobody names one in game. They lead its squads in the War Room (WarSquads.Leaders), sit
-- in the centurions' chat rooms (ChatRooms.lua) and wear their own silver (Borders.lua), above a
-- centurion's bronze. 1.1.5's list of the King's guild's centurions, named on the Throne, counts
-- for nothing here (ListOf: none for the King's guild). Clients of 1.2.3 or older still take it from
-- the King's or a councillor's client (NM) and keep the newest one heard, its holders as their own
-- (repeated every EVERY seconds): the King's and the councillors' clients end it there with one
-- empty list newer than it (Retire). Once, at their first minute, while this client still keeps its
-- own old copy (ns.rdb.mainNominees, forgotten then: Nominees.Minute), and soon after hearing an
-- older client's list that names anyone (RETIRE_GAP apart at most). The bronze it gave ends with it.
-- (Read only for that: to be dropped once no client of 1.2.3 or older is left.)

-- The King's character, or a signed High Councillor: the clients older ones take that list from.
local function Retirer()
	if ns.IsMember() ~= true then return false end
	local K = ns.King
	return type(K) == "table" and type(K.IsKing) == "function" and K.IsKing() == true or ns.IsHighCouncillor(ns.me) == true
end

-- Whom the Throne shows them to as the King's centurions, and /oly nominees names nobody for: the
-- King, a councillor, and the author's preview of the King (King.Preview).
local function KingsSide()
	local K = ns.King
	if type(K) == "table" and type(K.Preview) == "function" and K.Preview() == true then return true end
	return Retirer()
end

-- The King's centurions: the signed High Council's names (as signed, without a realm), in the
-- signed order (the held blob's, as WarSquads.Leaders reads it), then any other on its names list,
-- by name. Each once, and only while the signed list names it (ns.IsHighCouncillor).
function Nominees.KingsCenturions()
	local c = ns.rdb and ns.rdb.council
	if type(c) ~= "table" or type(c.names) ~= "table" then return {} end
	local out, seen = {}, {}
	local function Add(name)
		name = Trim(name)
		local key = ns.ShortName(name):lower()
		if name == "" or seen[key] or ns.IsHighCouncillor(name) ~= true then return end
		seen[key], out[#out + 1] = true, name
	end
	local blob = type(c.blob) == "string" and c.blob:match("^HS1~%d+~[^~]*~([^~]*)~%x+$")
	for name in tostring(blob or ""):gmatch("[^,]+") do Add(name) end
	local rest = {}
	for key, display in pairs(c.names) do
		local name = type(display) == "string" and display or key
		if type(name) == "string" then rest[#rest + 1] = name end
	end
	table.sort(rest, function(a, b) return a:lower() < b:lower() end)
	for _, name in ipairs(rest) do Add(name) end
	return out
end

-- The list that counts for `guild` here: his own on the guild master's client; else the one
-- heard from its master, while fresh. nil for none, and for the King's guild (1.2.4: its centurions
-- are the High Council, nobody's list).
local function ListOf(guild)
	if type(guild) ~= "string" or guild == "" or IsMain(guild) then return nil end
	local master, mine = Nominees.IsMaster()
	if master and mine == guild then
		local entries = OwnEntries(Saved(false))
		local set = {}
		for _, e in ipairs(entries) do set[e.name:lower()] = e end
		return { guild = guild, by = ns.me, entries = entries, set = set, own = true }
	end
	local l = lists[guild:lower()]
	if not l or ns.Now() - l.at > Nominees.FRESH then return nil end
	return l
end
Nominees.ListOf = ListOf

-- Whom `guild`'s master named `who` (Borders.lua): "centurion", or "correspondent" and its
-- department; nil for nobody. A lookup.
function Nominees.RoleOf(who, guild)
	if type(who) ~= "string" or who == "" then return nil end
	local l = ListOf(guild)
	local e = l and l.set[ns.FullName(who):lower()]
	if not e then return nil end
	return e.role, e.dept and DeptName(e.dept)
end

-- Operational duties require our own live guild roster, not the census used for a border.
-- Recheck the list's master on every use so revocation does not wait for the pruning timer.
function Nominees.IsCorrespondent(who, guild, dept)
	if type(who) ~= "string" or type(dept) ~= "string" or not ns.IsMember() then return false end
	local mine = GetGuildInfo and GetGuildInfo("player")
	local R = ns.Roster
	if type(guild) ~= "string" or guild ~= mine or not ns.IsFederation(guild)
		or not R or R.complete ~= true or R.guild ~= guild or R.group ~= ns.group or R.faction ~= ns.faction
		or type(R.byName) ~= "table" or type(R.RankOf) ~= "function" or type(R.snapshotAt) ~= "number"
		or type(R.generation) ~= "number" or R.generation < 1 then return false end
	local age = ns.Now() - R.snapshotAt
	if age < 0 or age > (R.AUTHORITY_FRESH or 600) then return false end
	local full = ns.FullName(who)
	if R.RankOf(full) == nil then return false end
	local list = ListOf(guild)
	if not list or type(list.by) ~= "string" or R.RankOf(ns.FullName(list.by)) ~= 0 then return false end
	local role, department = Nominees.RoleOf(full, guild)
	return role == "correspondent" and department == DeptName(dept)
end

function Nominees.Correspondent(guild, dept)
	local list = ListOf(guild)
	for _, entry in ipairs(list and list.entries or {}) do
		if Nominees.IsCorrespondent(entry.name, guild, dept) then return entry.name end
	end
	return nil
end

function Nominees.OwnDepartment(who)
	local guild = GetGuildInfo and GetGuildInfo("player")
	for _, dept in ipairs(Nominees.Departments()) do
		if Nominees.IsCorrespondent(who or ns.me, guild, dept) then return dept, guild end
	end
	return nil
end

function Nominees.GuildAccess()
	local V, guild = ns.ViewAs, GetGuildInfo and GetGuildInfo("player")
	if V and V.Available and V.Available() and V.Role and V.Role() ~= "my" then
		return V.Role() == "gm" or V.Role() == "correspondent", guild
	end
	local master, mine = Nominees.IsMaster()
	if master then return true, mine end
	local dept = Nominees.OwnDepartment()
	return dept ~= nil, guild
end

-- Its parts, each one addon message: NM~1~<guild>~<rev>~<i>~<n>~<entries>.
local function Wire(name)
	return ns.RealmOf(name) == ns.realm and ns.ShortName(name) or name
end
function Nominees.Parts(guild, rev, entries)
	local head = ("NM~%s~%s~%d~"):format(Nominees.WIRE, guild, rev)
	local room = Nominees.PART - #head - #("16~16~")
	local bodies, body = {}, ""
	for _, e in ipairs(entries) do
		local text = e.role == "centurion" and ("c=" .. Wire(e.name)) or ("d=" .. e.dept .. "=" .. Wire(e.name))
		if body ~= "" and #body + 1 + #text > room then
			bodies[#bodies + 1], body = body, ""
		end
		body = body == "" and text or (body .. ";" .. text)
	end
	if body ~= "" or #bodies == 0 then bodies[#bodies + 1] = body end
	local out = {}
	for i, b in ipairs(bodies) do out[i] = ("%s%d~%d~%s"):format(head, i, #bodies, b) end
	return out
end

-- His list goes out (force: now; else once EVERY), from the guild master's client alone. Nobody
-- named yet, nothing sent; named and then all removed, the empty list (everyone drops it).
function Nominees.Send(force)
	if not RealMaster() then return false end -- (the author's view sends nothing)
	local s = Saved(false)
	if not s then return false end
	local now = ns.Now()
	if not force and now - lastSent < Nominees.EVERY then return false end
	local entries = OwnEntries(s)
	if #entries == 0 and not sentOnce then return false end
	lastSent, sentOnce = now, true
	for i, part in ipairs(Nominees.Parts(s.guild, tonumber(s.rev) or now, entries)) do
		ns.Comm.Send("CHANNEL", part, "nominees" .. i)
	end
	return true
end

local function SendSoon()
	if sendPending then return end
	sendPending = true
	ns.After(Nominees.SEND_AFTER, "nominees send", function()
		sendPending = false
		Nominees.Send(true)
	end)
end

local function Changed()
	Bump()
	ns.Fire("DATA_CHANGED")
end

-- The guild master names someone: role "centurion", or "correspondent" with a department.
-- Refused, with its reason, past the caps, outside his roster, twice, or for himself.
function Nominees.Name(role, input, dept)
	local s = Saved(false)
	local master, guild = Nominees.IsMaster()
	if not master then return false, ns.Print(L.NOMINEES_ONLY_MASTER) end
	local raw = Trim(input)
	if raw == "" and UnitIsPlayer and UnitIsPlayer("target") then raw = ns.UnitFullName("target") or "" end
	local name = Person(raw)
	if not name then return false, ns.Print(L.NOMINEES_WHO) end
	-- His own guild's members alone, as his roster has them (the server's), in its spelling.
	local member = ns.Roster.guild == guild and RosterName(name, not ns.RealmOf(Trim(ns.Normal(raw)))) or nil
	if name:lower() == tostring(ns.me):lower() or (member and member:lower() == tostring(ns.me):lower()) then
		return false, ns.Print(L.NOMINEES_SELF)
	end
	if not member then return false, ns.Print(L.NOMINEES_NOT_MEMBER:format(ns.DisplayName(name))) end
	name = member
	local entries = OwnEntries(s)
	for _, e in ipairs(entries) do
		if e.name:lower() == name:lower() then
			return false, ns.Print(L.NOMINEES_ALREADY:format(ns.DisplayName(name), Nominees.RoleLabel(e.role, e.dept)))
		end
	end
	local entry
	if role == "centurion" then
		local c = 0
		for _, e in ipairs(entries) do if e.role == "centurion" then c = c + 1 end end
		if c >= Nominees.MAX_CENTURIONS then return false, ns.Print(L.NOMINEES_FULL:format(Nominees.MAX_CENTURIONS)) end
		entry = { r = "c", n = name }
	elseif role == "correspondent" then
		local d = IsDept(dept)
		if not d then return false, ns.Print(L.NOMINEES_NO_DEPT:format(tostring(dept or "?"))) end
		for _, e in ipairs(entries) do
			if e.role == "correspondent" and e.dept:lower() == d:lower() then
				return false, ns.Print(L.NOMINEES_DEPT_TAKEN:format(d, ns.DisplayName(e.name)))
			end
		end
		entry = { r = "d", d = d, n = name }
	else
		return false
	end
	s = Saved(true)
	-- (A correspondent whose department is gone gives his place up to the new one.)
	local _, stale = OwnEntries(s)
	if entry.r == "d" and #stale > 0 then
		local kept = {}
		for _, e in ipairs(s.list) do
			if not (e.r == "d" and not IsDept(e.d)) then kept[#kept + 1] = e end
		end
		s.list = kept
	end
	s.list[#s.list + 1] = entry
	s.rev = math.max(ns.Now(), (tonumber(s.rev) or 0) + 1)
	ns.Print(L.NOMINEES_ADDED:format(ns.DisplayName(name), Nominees.RoleLabel(role, entry.d)))
	ns.Log("nominees: %s named %s (%s)", tostring(ns.me), name, role .. (entry.d and (" " .. entry.d) or ""))
	SendSoon()
	Changed()
	return true
end

-- The guild master removes one of his own (by name; typed without a realm, the one he named of
-- that name on another realm too, when only one).
function Nominees.Remove(input)
	local s = Saved(false)
	if not s then return false, ns.Print(L.NOMINEES_ONLY_MASTER) end
	local raw = Trim(input)
	local name = Person(raw)
	local at, short, others = nil, name and ns.ShortName(name):lower(), {}
	for i, e in ipairs(s.list) do
		if type(e) == "table" and type(e.n) == "string" and name then
			if e.n:lower() == name:lower() then at = i break end
			if ns.ShortName(e.n):lower() == short then others[#others + 1] = i end
		end
	end
	if not at and #others == 1 and not ns.RealmOf(Trim(ns.Normal(raw))) then at = others[1] end
	local e = at and s.list[at]
	if not e then return false, ns.Print(L.NOMINEES_NOT_NAMED:format(ns.DisplayName(name) or raw)) end
	table.remove(s.list, at)
	s.rev = math.max(ns.Now(), (tonumber(s.rev) or 0) + 1)
	local dept = e.r == "d" and tostring(e.d or "?") or nil
	ns.Print(L.NOMINEES_REMOVED:format(ns.DisplayName(e.n), Nominees.RoleLabel(dept and "correspondent" or "centurion", dept)))
	ns.Log("nominees: %s removed %s", tostring(ns.me), e.n)
	SendSoon()
	Changed()
	return true
end

-- 1.2.4: one empty list of the King's guild's centurions, newer than `rev` and than now, from the
-- King's or a councillor's client alone. An older client takes it as the newest (its holder as its
-- own), and the bronze 1.1.5's list gave ends there.
function Nominees.Retire(rev)
	if not Retirer() then return false end
	rev = math.max(ns.Now(), (tonumber(rev) or 0) + 1)
	for i, part in ipairs(Nominees.Parts(Nominees.MainGuild(), rev, {})) do
		ns.Comm.Send("CHANNEL", part, "mainnominees" .. i)
	end
	retiredAt = ns.Now()
	if rev > retireNamed then retireWanted = false end
	ns.Log("nominees: <%s>'s old list of centurions ended for older clients (rev %d)", Nominees.MainGuild(), rev)
	return true
end

-- An answer a few seconds after an older client's list (one for several heard together), RETIRE_GAP
-- after the last one at the soonest, unless an empty list newer than it came after it meanwhile.
local function RetireSoon()
	if retirePending or not Retirer() then return end
	retirePending = true
	ns.After(math.max(Nominees.SEND_AFTER, Nominees.RETIRE_GAP - (ns.Now() - retiredAt)), "main nominees end", function()
		retirePending = false
		if not retireWanted then return end
		if ns.Now() - retiredAt < Nominees.RETIRE_GAP then return RetireSoon() end
		Nominees.Retire(retireNamed)
	end)
end

---------------------------------------------------------------------------
-- Heard: a guild master's list
---------------------------------------------------------------------------

-- A list's entries from its parts, its caps held (the first ones kept), or nil when it can't be one.
local function Read(parts, n, realm, main)
	local entries, set, c, depts = {}, {}, 0, {}
	for i = 1, n do
		for entry in tostring(parts[i] or ""):gmatch("[^;]+") do
			local kind, a, b = entry:match("^(%a)=([^=]*)=?([^=]*)$")
			local e
			if kind == "c" and b == "" and c < Nominees.MAX_CENTURIONS then
				local name = Person(a, realm)
				if name and not set[name:lower()] then
					c = c + 1
					e = { role = "centurion", name = name }
				end
			elseif kind == "d" and b ~= "" and not main then -- (none for the King's guild: 1.1.5)
				local dept, name = DeptName(a), Person(b, realm)
				local count = 0
				for _ in pairs(depts) do count = count + 1 end
				if dept and name and not set[name:lower()] and not depts[dept:lower()] and count < Nominees.MAX_DEPTS then
					depts[dept:lower()] = true
					e = { role = "correspondent", dept = dept, name = name }
				end
			end
			if e then
				entries[#entries + 1] = e
				set[e.name:lower()] = e
			end
		end
	end
	return entries, set
end

-- What a list names, as text, to tell a new one from a repeat.
local function Signature(l)
	local out = { l.by:lower() }
	for _, e in ipairs(l.entries) do out[#out + 1] = (e.dept or "") .. "=" .. e.name:lower() end
	return table.concat(out, ";")
end

-- A whole list from a proven guild master: kept (a repeat refreshes it), or dropped when it names
-- nobody. This client is told when it is named, or no longer.
local function Take(sender, guild, rev, entries, set)
	local key = guild:lower()
	local old = lists[key]
	if old and ns.Now() - old.at > Nominees.FRESH then old = nil end -- (gone quiet: as if none)
	if old and old.by == sender and rev < (old.rev or 0) then return end -- (an older one, late)
	local mine = GetGuildInfo("player")
	local was = old and old.set[tostring(ns.me):lower()]
	local l = { guild = guild, by = sender, rev = rev, at = ns.Now(), entries = entries, set = set }
	if #entries == 0 then
		lists[key] = nil
	else
		lists[key] = l
	end
	local now = #entries > 0 and set[tostring(ns.me):lower()] or nil
	if mine and guild == mine then
		if now and not (was and was.role == now.role and was.dept == now.dept) then
			ns.Print(L.NOMINEES_YOU:format(ns.DisplayName(sender) or "?", Nominees.RoleLabel(now.role, now.dept), guild))
		elseif was and not now then
			ns.Print(L.NOMINEES_NO_LONGER:format(Nominees.RoleLabel(was.role, was.dept), guild))
		end
	end
	if not old or #entries == 0 or Signature(old) ~= Signature(l) then
		ns.Log("nominees: <%s>'s list from %s, %d named", guild, sender, #entries)
		Changed()
	end
end

-- 1.1.5's list of the King's guild's centurions, from an older client of the King's or a councillor's
-- (1.2.4): nothing of it is kept or counts here. One that names anyone is answered from the King's or
-- a councillor's client (Retire), whatever its rev: an end sent before it never reached a client that
-- logged in since. An empty one newer than every named one heard, after them, is that answer already.
local function Retired(sender, rev, entries)
	if #entries == 0 then
		if rev > retireNamed then retireWanted = false end
		return
	end
	ns.Log("nominees: <%s>'s list from %s ignored: the High Council are the King's centurions", Nominees.MainGuild(), sender)
	retireNamed, retireWanted = math.max(retireNamed, rev), true
	RetireSoon()
end

-- A part of a list, from the channel: only from that guild's master (Proven), put together with
-- the rest of its parts.
function Nominees.Handle(dist, sender, text)
	if dist ~= "CHANNEL" or type(sender) ~= "string" or type(text) ~= "string" or #text > 255 then return end
	local wire, guild, rev, i, n, body = text:match("^NM~(%d+)~([^~]*)~(%d+)~(%d+)~(%d+)~([^~]*)$")
	if wire ~= Nominees.WIRE then return end -- (another version's: not ours to read)
	guild, rev, i, n = GuildName(guild), tonumber(rev), tonumber(i), tonumber(n)
	if not guild or not rev or not i or not n or i < 1 or n < 1 or i > n or n > Nominees.MAX_PARTS then return end
	sender = ns.FullName(sender)
	if not Proven(sender, guild) then
		return ns.Log("nominees: <%s>'s list from %s refused: not its guild master here", guild, sender)
	end
	local now = ns.Now()
	local p = pending[sender]
	if not p or p.guild ~= guild or p.rev ~= rev or p.n ~= n or now - p.t > Nominees.PART_WAIT then
		p = { guild = guild, rev = rev, n = n, parts = {}, got = 0, t = now }
		pending[sender] = p
	end
	if not p.parts[i] then
		p.parts[i], p.got = body, p.got + 1
	end
	if p.got < n then return end
	pending[sender] = nil
	local main = IsMain(guild)
	local entries, set = Read(p.parts, n, ns.RealmOf(sender), main)
	if main then return Retired(sender, rev, entries) end
	Take(sender, guild, rev, entries, set)
end
ns.Comm.Handle("NM", function(...) Nominees.Handle(...) end)

-- What Deposed reads for a list: our roster for our own guild; another guild's census row as it
-- stands (its time and votes, as Borders.Changed reads them). Asked again only when these change
-- (DATA_CHANGED comes with every census report heard).
local function DeposedInputs(l)
	local mine = GetGuildInfo("player")
	if mine and l.guild:lower() == mine:lower() then return ns.Roster.byName, ns.Roster.lastStats, mine end
	local guilds = ns.rdb and ns.rdb.guilds
	local g = type(guilds) == "table" and guilds[l.guild] or nil
	return g, type(g) == "table" and g.t or nil, type(g) == "table" and g.vouch or nil
end

-- Lists whose master is no longer that guild's master, or that went quiet past FRESH, and parts
-- left waiting: dropped. Returns whether a list went.
function Nominees.Prune()
	local now, gone = ns.Now(), false
	for key, l in pairs(lists) do
		local a, b, c = DeposedInputs(l)
		local fresh = l.ia ~= a or l.ib ~= b or l.ic ~= c or not l.asked
		if fresh then l.ia, l.ib, l.ic, l.asked = a, b, c, true end
		if now - l.at > Nominees.FRESH then
			lists[key], gone = nil, true
		elseif fresh and Deposed(l) then
			lists[key], gone = nil, true
			ns.Log("nominees: <%s>'s list dropped: %s is no longer its guild master", l.guild, l.by)
		end
	end
	for sender, p in pairs(pending) do
		if now - p.t > Nominees.PART_WAIT then pending[sender] = nil end
	end
	if gone then Bump() end
	return gone
end

---------------------------------------------------------------------------
-- The pages: a guild master's Guild tab, the King's guild's centurions on the Throne (King.lua), and
-- the command
---------------------------------------------------------------------------

-- The guild master's own list, as his Guild tab shows it: { entries, stale }; nil for anyone else
-- (the Guild tab is his alone).
function Nominees.Ours()
	if not Nominees.IsMaster() then return nil end
	local entries, stale = OwnEntries(Saved(false))
	return { entries = entries, stale = stale }
end

-- How many he has named.
function Nominees.Count()
	local o = Nominees.Ours()
	return o and #o.entries or 0
end

-- The name box: a centurion or a department's correspondent of his guild.
function Nominees.Prompt(role, dept)
	local master, guild = Nominees.IsMaster()
	if not master then return ns.Print(L.NOMINEES_ONLY_MASTER) end
	return ns.ShowDialog("OLYMPUS_NOMINEE", Nominees.RoleLabel(role, dept), guild, { role = role, dept = dept })
end
-- Asked before a title is taken back (the box's data: his own's name).
function Nominees.AskRemove(e)
	if type(e) ~= "table" or not Nominees.IsMaster() then return nil end
	return ns.ShowDialog("OLYMPUS_NOMINEE_REMOVE", ns.DisplayName(e.name), Nominees.RoleLabel(e.role, e.dept), e.name)
end
local function Taken(data, text)
	data = type(data) == "table" and data or {}
	return Nominees.Name(data.role, text, data.dept)
end
local function TakenBack(data)
	if type(data) ~= "string" then return false end -- (1.1.5's King's guild's box gave a table: 1.2.4 names nobody there)
	return Nominees.Remove(data)
end

-- The Throne's look (King.lua's Line, Para: dark ink on the parchment), as the Hands page's.
local function Ink() local K = ns.King return K.Line, K.INK, K.TITLE, K.Para end

-- A named one's line: a click takes the title back (asked first), when this client may.
local function Row(e, text, editable, roster)
	local Line, INK = Ink()
	local name = ns.DisplayName(e.name)
	return Line(text or name, INK, {
		key = name, indent = 1,
		right = roster and ns.Roster.RankOf(e.name) == nil and ns.Views.Grey(L.NOMINEES_NOT_IN_ROSTER) or nil,
		onClick = editable and function() Nominees.AskRemove(e) end or nil,
		tooltip = function(tt)
			tt:AddLine(name, 1, 0.82, 0)
			tt:AddLine(Nominees.RoleLabel(e.role, e.dept), 1, 1, 1, true)
			if editable then tt:AddLine(L.NOMINEES_CLICK_REMOVE, 0.6, 0.6, 0.6, true) end
		end,
	})
end

-- "+ Name a centurion (your target, or type a name)", its count; greyed when full (its click says why).
local function AddLine(count)
	local Line, _, TITLE = Ink()
	local full = count >= Nominees.MAX_CENTURIONS
	local add = "+ " .. L.NOMINEES_ADD_CENTURION
	local function Full() return L.NOMINEES_FULL:format(Nominees.MAX_CENTURIONS) end
	return Line(full and ns.Views.Grey(add) or add, TITLE, {
		right = ("%d/%d"):format(count, Nominees.MAX_CENTURIONS),
		onClick = function()
			if full then return ns.Print(Full()) end
			Nominees.Prompt("centurion", nil)
		end,
		tooltip = function(tt)
			tt:AddLine(L.NOMINEES_ADD_CENTURION, 1, 0.82, 0)
			tt:AddLine(full and Full() or L.NOMINEES_CLICK_NAME, 1, 1, 1, true)
		end,
	})
end

-- The guild master's section, as the King's Hands page (King.lua's HandsLines): a title, a
-- one-line hint, "+ Name a centurion (your target, or type a name)", his centurions (a click takes
-- the title back, asked first), then the correspondents' departments, one line each (the role
-- picker: a click names that department's correspondent, or takes the title back), and the note
-- on how the army learns his list. Nothing for anyone but him.
function Nominees.PageLines(lines)
	local o = Nominees.Ours()
	if not o then return lines end
	local Line, INK, TITLE, Para = Ink()
	lines[#lines + 1] = Line(L.NOMINEES_TITLE, TITLE)
	Para(lines, L.NOMINEES_HINT, INK, { gapAfter = true })
	-- The centurions.
	local centurions = {}
	for _, e in ipairs(o.entries) do if e.role == "centurion" then centurions[#centurions + 1] = e end end
	lines[#lines + 1] = AddLine(#centurions)
	for _, e in ipairs(centurions) do lines[#lines + 1] = Row(e, nil, true, true) end
	if #centurions == 0 then lines[#lines + 1] = Line(L.NOMINEES_NONE, INK, { indent = 1 }) end
	lines[#lines].gapAfter = true
	-- The correspondents: a line per department, its correspondent or a click to name one.
	local depts = Nominees.Departments()
	local byDept, named = {}, 0
	for _, e in ipairs(o.entries) do
		if e.role == "correspondent" then
			byDept[e.dept:lower()] = e
			named = named + 1
		end
	end
	lines[#lines + 1] = Line(L.NOMINEES_CORRESPONDENTS, TITLE, { right = ("%d/%d"):format(named, #depts) })
	for _, d in ipairs(depts) do
		local e = byDept[d:lower()]
		if e then
			lines[#lines + 1] = Row(e, d .. ": " .. ns.DisplayName(e.name), true, true)
		else
			lines[#lines + 1] = Line(d .. ": " .. L.NOMINEES_ADD_CORRESPONDENT, INK, { indent = 1,
				onClick = function() Nominees.Prompt("correspondent", d) end,
				tooltip = function(tt)
					tt:AddLine(Nominees.RoleLabel("correspondent", d), 1, 0.82, 0)
					tt:AddLine(L.NOMINEES_CLICK_NAME, 1, 1, 1, true)
				end })
		end
	end
	-- (His own whose department the council's list no longer has: they count for nothing, sent to nobody.)
	for _, e in ipairs(o.stale) do
		local row = Row(e, e.dept .. ": " .. ns.DisplayName(e.name), true, true)
		row.right = ns.Views.Grey(L.NOMINEES_DEPT_GONE)
		lines[#lines + 1] = row
	end
	if #depts == 0 then lines[#lines + 1] = Line(L.NOMINEES_NO_DEPTS, INK, { indent = 1 }) end
	lines[#lines].gapAfter = true
	return Para(lines, L.NOMINEES_NOTE:format(math.floor(Nominees.FRESH / 3600)), INK)
end

-- A guild master's Guild tab (1.1.5): the tab in the Throne's place, his guild's page (King.Build).
function Nominees.GuildLines()
	local allowed, guild = Nominees.GuildAccess()
	if not allowed then return {} end
	local Line, INK, TITLE, Para = Ink()
	local V = ns.ViewAs
	local preview = V and V.Available and V.Available() and V.Role and V.Role() ~= "my"
	local master = preview and V.Role() == "gm" or not preview and Nominees.IsMaster()
	local dept = not preview and Nominees.OwnDepartment() or nil
	local lines = { Line(L.GUILD_TAB_TITLE:format(tostring(guild)), TITLE, { gapAfter = true }) }
	if master then Nominees.PageLines(lines) end
	Para(lines, L.GUILD_DEPARTMENT_SCOPE:format(tostring(guild)), INK, { gapAfter = true })
	local routes = { ["Federal Treasury"] = "treasury", ["Department of War"] = "war", ["Council of Justice"] = "watch",
		["Association of Artisanry"] = "crafters", ["Department of Heritage"] = "decrees", ["The Missionary Church of Olympus"] = "church" }
	for _, department in ipairs(Nominees.Departments()) do
		if master or preview or dept == department then
			local name = not preview and Nominees.Correspondent(guild, department) or nil
			lines[#lines + 1] = Line(department, TITLE)
			lines[#lines + 1] = Line(name and L.GUILD_DEPARTMENT_NAMED:format(ns.DisplayName(name)) or L.GUILD_DEPARTMENT_EMPTY, INK, { indent = 1 })
			local route = routes[department]
			if department == "Association of Artisanry" or department == "Department of Heritage" then
				Para(lines, L.GUILD_DEPARTMENT_LIMITED, INK, { indent = 1 })
			elseif department == "The Missionary Church of Olympus" then
				Para(lines, L.GUILD_DEPARTMENT_CHURCH, INK, { indent = 1 })
			end
			if route then lines[#lines + 1] = Line(L.GUILD_DEPARTMENT_OPEN, INK, { indent = 1,
				onClick = not preview and function()
					local current = ns.ViewAs
					if current and current.Previewing and current.Previewing() then return end
					if not Nominees.IsMaster() and not Nominees.IsCorrespondent(ns.me, guild, department) then return end
					if route == "war" then if ns.War and ns.War.Show then ns.War.Show() end
					elseif route == "treasury" then if ns.Treasury and ns.Treasury.OpenOwnGuild then ns.Treasury.OpenOwnGuild() end
					else if route == "watch" and ns.Watch then ns.Watch.Show("chat") end; ns.UI.SelectTab(route) end
				end or nil }) end
			lines[#lines].gapAfter = true
		end
	end
	if preview then for _, row in ipairs(lines) do row.onClick = nil end end
	return lines
end

-- The King's centurions (1.2.4), on the Throne's page: a title, a hint, then the signed High
-- Council to read, in the signed order (nobody names one or takes a title back here). For a reader
-- in the King's guild, its roster fresh, each councillor's War Room squad (its soldiers, WarSquads),
-- or that he is not of the guild, the squads' leaders first in the War Room's order. While the King
-- streams (ns.CouncilMasked) each is "High Councillor N" (a squad's leader, the War Room's N), and
-- for a reader the council is not shown to yet (ns.CouncilVisible) they are only counted.
-- In the King's guild (and the author's preview of the King, inert there), a line to the War Room. Then the note.
function Nominees.MainLines(lines)
	local Line, INK, TITLE, Para = Ink()
	local guild, mine = Nominees.MainGuild(), GetGuildInfo("player")
	local K = ns.King
	local preview = type(K) == "table" and type(K.Preview) == "function" and K.Preview() == true
	lines[#lines + 1] = Line(L.NOMINEES_MAIN_TITLE, TITLE)
	Para(lines, L.NOMINEES_MAIN_HINT, INK, { gapAfter = true })
	local names = Nominees.KingsCenturions()
	local S, R = ns.WarSquads, ns.Roster
	local ours = IsMain(mine) and type(R) == "table" and type(R.Fresh) == "function" and R.Fresh() ~= nil
		and type(S) == "table" and not S.missing and type(S.Leaders) == "function" and type(S.Get) == "function"
	local squads = {}
	if ours then
		for _, e in ipairs(S.Leaders()) do squads[ns.ShortName(e.name):lower()] = e end
		-- The War Room's squads' leaders first, in its order (e.index), then the rest in the signed
		-- order: "High Councillor N" is the same councillor on both pages while the King streams.
		local leading, rest = {}, {}
		for _, name in ipairs(names) do
			local e = squads[ns.ShortName(name):lower()]
			if e then leading[#leading + 1] = { name = name, at = e.index } else rest[#rest + 1] = name end
		end
		table.sort(leading, function(a, b) return a.at < b.at end)
		names = {}
		for _, e in ipairs(leading) do names[#names + 1] = e.name end
		for _, name in ipairs(rest) do names[#names + 1] = name end
	end
	if #names == 0 then
		lines[#lines + 1] = Line(L.NOMINEES_MAIN_NONE, INK, { indent = 1 })
	elseif ns.CouncilVisible() ~= true then
		lines[#lines + 1] = Line(L.NOMINEES_MAIN_COUNT:format(#names), INK, { indent = 1 })
	else
		local masked = ns.CouncilMasked() == true
		for i, name in ipairs(names) do
			local right
			if ours then
				local e = squads[ns.ShortName(name):lower()]
				local squad = e and S.Get(e.name)
				if squad then right = L.SQUAD_COUNT:format(squad.count or 0)
				elseif not RosterName(ns.FullName(name), true) then right = ns.Views.Grey(L.NOMINEES_MAIN_OUTSIDE:format(guild)) end
			end
			lines[#lines + 1] = Line(masked and L.SQUAD_COUNCILLOR:format(i) or ns.DisplayName(ns.FullName(name)), INK,
				{ key = "kingscenturion" .. i, indent = 1, right = right })
		end
	end
	if IsMain(mine) or preview then
		lines[#lines + 1] = Line(L.NOMINEES_MAIN_WAR, INK, { indent = 1,
			onClick = not preview and function() if ns.War and ns.War.Show then ns.War.Show() end end or nil })
	end
	lines[#lines].gapAfter = true
	return Para(lines, L.NOMINEES_MAIN_NOTE:format(guild, type(S) == "table" and S.MAX_SOLDIERS or 99), INK)
end

-- /oly status: a guild master's own list, and the lists this client holds, each its master's
-- (five named, the rest counted).
function Nominees.StatusLine()
	local out, held, now = {}, {}, ns.Now()
	local o = Nominees.Ours()
	if o then out[1] = ("yours %d of %d"):format(#o.entries, Nominees.MAX) end
	for _, l in pairs(lists) do
		if now - l.at <= Nominees.FRESH then held[#held + 1] = l end
	end
	table.sort(held, function(a, b) return a.guild < b.guild end)
	for i, l in ipairs(held) do
		if i > 5 then out[#out + 1] = ("and %d more"):format(#held - 5) break end
		out[#out + 1] = ("<%s> %d by %s (heard %s)"):format(l.guild, #l.entries, ns.DisplayName(l.by) or "?", ns.Ago(l.at))
	end
	return #out > 0 and table.concat(out, ", ") or "none"
end

-- `/oly nominees [centurion <name> | correspondent <n> <name> | remove <name>]`: alone, the tab
-- (a guild master's Guild tab; the Throne, with the King's centurions, for the King's people).
-- A guild master names in his own guild; the King, a councillor and the King preview are told that the
-- High Council are the King's centurions, nobody named (1.2.4). Anyone else is told whose it is.
function Nominees.Slash(rest)
	rest = Trim(rest)
	local verb, arg = rest:match("^(%S*)%s*(.-)$")
	verb = (verb or ""):lower()
	-- The author's guild master's view (his alone: anyone else gets the usual answer below).
	if verb == "view" and ns.Workshop and ns.Workshop.Visible and ns.Workshop.Visible() then
		Nominees.SetDevView(not Nominees.DevView())
		if Nominees.DevView() then verb = "" else return end
	end
	local master = Nominees.IsMaster()
	local kings = not master and KingsSide()
	if verb == "" then
		local K = ns.King
		if not (K and K.TabVisible and K.TabVisible()) then return ns.Print(L.NOMINEES_ONLY_MASTER) end
		K.mode = "home" -- (the Throne Room, or his Guild tab: never the King's Hands page)
		if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("throne") end
		return
	end
	local centurion = verb == "centurion" or verb == "centuriao" or verb == "centurião"
	local remove = verb == "remove" or verb == "remover"
	if kings and (centurion or remove) then return ns.Print(L.NOMINEES_MAIN_NOBODY) end
	if centurion then return Nominees.Name("centurion", arg) end
	if (verb == "correspondent" or verb == "correspondente") and (master or not kings) then
		local n, name = arg:match("^(%d+)%s*(.-)$")
		local d = n and Nominees.Departments()[tonumber(n)]
		if not d then
			local list = {}
			for i, dept in ipairs(Nominees.Departments()) do list[#list + 1] = ("%d %s"):format(i, dept) end
			return ns.Print(L.NOMINEES_DEPTS:format(#list > 0 and table.concat(list, ", ") or L.NOMINEES_NONE))
		end
		return Nominees.Name("correspondent", name, d)
	end
	if remove then return Nominees.Remove(arg) end
	ns.Print(L.NOMINEES_USAGE)
end

StaticPopupDialogs["OLYMPUS_NOMINEE"] = {
	text = L.NOMINEES_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 240,
	maxLetters = 60,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then
			local target = UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullName("target")
			eb:SetText(target and ns.DisplayName(target) or "")
			ns.Focus(eb)
		end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("name nominee", Taken, data or (self and self.data), eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("name nominee", Taken, parent.data, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_NOMINEE_REMOVE"] = {
	text = L.NOMINEES_REMOVE_CONFIRM,
	button1 = L.NOMINEES_REMOVE_BTN,
	button2 = CANCEL or "Cancel",
	OnAccept = function(self, data) ns.SafeCall("remove nominee", TakenBack, data or (self and self.data)) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Before Borders.lua's and Nameplates.lua's (this file loads first): a list whose master was
-- deposed by the census or roster just heard is gone when they work their borders out again.
ns.On("DATA_CHANGED", function() Nominees.Prune() end)

-- Once a minute from the login: his list out again (a guild master's, once EVERY); 1.1.5's old copy
-- of the King's guild's list ended and forgotten (1.2.4: once; on the King's or a councillor's client
-- one empty, newer list first, when it named anyone; the King preview's copy forgotten too); the lists
-- gone quiet or deposed dropped.
function Nominees.Minute()
	Nominees.Send()
	if ns.db and ns.db.previewMainNominees ~= nil then ns.db.previewMainNominees = nil end
	local old = ns.rdb and ns.rdb.mainNominees
	if old ~= nil and ns.IsMember() == true then
		if type(old) == "table" and type(old.list) == "table" and #old.list > 0 and Retirer() then Nominees.Retire(old.rev) end
		ns.rdb.mainNominees = nil
	end
	if Nominees.Prune() then ns.Fire("DATA_CHANGED") end
end
ns.On("LOGIN", function() ns.Every(60, "nominees", Nominees.Minute) end)

-- Tests start from a clean state.
function Nominees.Reset()
	wipe(lists); wipe(pending)
	lastSent, sendPending, sentOnce = -math.huge, false, false
	retireNamed, retireWanted, retiredAt, retirePending = 0, false, -math.huge, false
	Bump()
end
