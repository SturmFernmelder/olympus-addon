local ADDON, ns = ...
local L = ns.L

-- Logical rooms on the Chat page. They are deliberately not extra Channels tiers:
-- [Olympus], [Captains] and [Lords] keep their public wire, consent, chat-window routing and
-- Chattynator integration unchanged. These rooms use a versioned whole message of their own:
--
--   M2~1~<room>~<id>~<class>~<guild>~<text>
--
-- Guild uses the game's native guild chat. Restricted rooms go as one logged
-- whisper to each recipient from the signed authority lists. There is no broadcast fallback for
-- a private audience, and every queued whisper rechecks both ends immediately before it leaves.
-- (<class> is a legacy field: this client leaves it empty, and an older client's class code only
-- colours its name.) 1.2.3: the race and class rooms, open topic rooms on the Olympus channel, are
-- gone (the author: nobody used them); an older client's line to one is dropped (Rooms.Receive).
--
-- 1.2.4, the role rooms the author asked for ("a gente me ajuda a repensar quais são todos os chats
-- de função que precisam"), each one check for who reads, sends and is heard (Rooms.CanAccess; the
-- kinds below, in the Roles menu's order):
--   council          the High Council: the signed councillors, the King, the Federal Treasurer
--   secretariat      the King and his Stewards
--   masters          the guild masters of every Olympus guild
--   allcenturions    the guild masters and their centurions (officers and named), every guild
--   dept:<d>         one per department: its titled councillors and every guild's correspondent of it
--   gcorr:<g>        one per guild: its master and his correspondents
--   gcent:<g>        one per guild: its master and his centurions
-- then the rooms other files keep (Rooms.RegisterAudience): the Church's (Apostles, Apostles and
-- missionaries, the whole Church) and The Watch's. A per-guild room's id is the guild's key, the first
-- six bytes of SHA-256 of its folded name in hex (GuildKey): never its name, which may hold spaces a
-- moderator's reference cannot carry (WatchChat.lua). "treasurers", "departments" and "centurions"
-- (1.2.3's) are gone: their lines from an older client are dropped quietly (Retired).

local Rooms = {}
ns.ChatRooms = Rooms

Rooms.HISTORY = 100
Rooms.ROOMS_MAX = 12
Rooms.TEXT_MAX = 150
Rooms.SEND_GAP = 1.5
Rooms.PER_MINUTE = 6
Rooms.FLOOD = 60
Rooms.GONE_FOR = 10 * 60    -- a recipient the server said is not playing: no whisper this long
Rooms.GUILD_KEYS_MAX = 512  -- guild keys remembered (the census keeps 300 guilds, the signed list 128)

local states = {}          -- room -> bounded session history and receive budgets
local nextId = math.random and math.random(0, 9999) or 0
local lastSend = -math.huge
local sentTimes = {}
local receiveBuckets, receiveSeen, receiveMine = {}, {}, {}
local stats = { sent = 0, shown = 0, dropped = {} }
local providers = {}       -- private rooms owned by later modules (1.2: crafting requests)
local held                 -- dynamic-room key -> when Rooms.OpenMatter pinned it (saved; loaded at first use)
local writing = {}         -- matter key -> a look at the Chat page's box is coming (Rooms.OpenMatter)
-- 1.1.6: restricted M2 rooms whose audience a later module decides (Rooms.RegisterAudience: the
-- Church's). id -> { label, CanAccess(name), Recipients(), group, preview }; the transport stays this file's.
local audiences, audienceOrder = {}, {}

local function Now() return GetTime and GetTime() or ns.Now() end
local function Lower(s) return tostring(s or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and Lower(a) == Lower(b) end
local function Drop(why)
	stats.dropped[why] = (stats.dropped[why] or 0) + 1
	return false, why
end
local function IsMe(name)
	return ns.Channels and ns.Channels.IsMe and ns.Channels.IsMe(name) == true
end
-- A locale key's text, else `fallback` (Locales.lua gives a missing key back as the key itself).
local function Text(key, fallback)
	local value = type(key) == "string" and rawget(L, key) or nil
	return type(value) == "string" and value ~= "" and value or fallback
end
local function OwnGuild()
	local guild = GetGuildInfo and GetGuildInfo("player")
	return type(guild) == "string" and guild ~= "" and guild or nil
end

-- The departments (1.2.4: Nominees.DEPARTMENT_LIST, the one list a department is added to). The
-- signed titles list remains the authority. Aliases only normalize labels that have existed in that
-- list; they never grant somebody absent from it a room.
-- (Read at first use: the game loads Nominees.lua first, but a file loaded after it may not be.)
local DEPARTMENTS, DEPT_BY_NAME, DEPT_BY_ID = {}, {}, {}
local TREASURY
local function Departments()
	if DEPARTMENTS[1] then return DEPARTMENTS end
	local list = ns.Nominees and type(ns.Nominees.DEPARTMENT_LIST) == "table" and ns.Nominees.DEPARTMENT_LIST
		or type(ns.DEPARTMENT_LIST) == "table" and ns.DEPARTMENT_LIST or {}
	for _, d in ipairs(list) do
		if type(d) == "table" and type(d.name) == "string" and type(d.room) == "string" and d.room:match("^dept:%l+$") and not DEPT_BY_ID[d.room] then
			local dept = { id = d.room, name = d.name, labelKey = d.label, aliases = type(d.aliases) == "table" and d.aliases or {} }
			DEPARTMENTS[#DEPARTMENTS + 1], DEPT_BY_ID[dept.id] = dept, dept
			DEPT_BY_NAME[Lower(dept.name)] = DEPT_BY_NAME[Lower(dept.name)] or dept
			for _, alias in ipairs(dept.aliases) do DEPT_BY_NAME[Lower(alias)] = DEPT_BY_NAME[Lower(alias)] or dept end
		end
	end
	TREASURY = DEPT_BY_ID["dept:treasury"]
	return DEPARTMENTS
end
-- A department by a name the titles or a nominee list gives it.
local function DeptNamed(name)
	Departments()
	return DEPT_BY_NAME[Lower(name)]
end

local function DepartmentFor(name)
	local title = ns.CouncilTitle and ns.CouncilTitle(name)
	return title and type(title.dept) == "string" and DeptNamed(title.dept) or nil
end

local function IsSecretariat(name)
	return (ns.IsKingCharacter and ns.IsKingCharacter(name) == true)
		or (ns.IsSteward and ns.IsSteward(name) == true)
end

local function IsKing(name) return ns.IsKingCharacter and ns.IsKingCharacter(name) == true or false end

local function FederalTreasurer(name)
	local T = ns.Treasury
	return T and T.TreasurerPin and T.TreasurerPin(name) == 1 or false
end

-- 1.2.3: while one listing of the rooms runs (Rooms.Listing: Rooms.Options, Rooms.Tabs, the Chat
-- page's destinations), what every room's access check read again is read once for all of them: the
-- federation's guilds (Guilds), a name's nominations across them (Correspondent), a name's rank in a
-- guild (Rank) and each kind's rooms (Rooms.Options). Each department's, the treasurers', the masters'
-- and the centurions' rooms read every guild of the census again, a dozen times a listing, and the
-- Chat page listed them at every redraw.
-- listing: { guilds, correspondent = { [name] = { any, [department] = true } }, rank = { [name] =
-- { [guild] = rank or false } }, options = { [kind] = list } } while one runs, else nil.
local listing
function Rooms.Listing(fn, ...)
	if listing then return fn(...) end
	listing = { correspondent = {}, rank = {}, options = {} }
	local ok, a, b = pcall(fn, ...)
	listing = nil
	if not ok then error(a, 0) end
	return a, b
end

-- The signed leadership list, while it counts (Authority.lua): { guilds = { [fold] = { name, roles } },
-- people = { [fold] = { guild, rank, name } } }, else nil.
local function Manifest()
	local A = ns.Authority
	if type(A) ~= "table" or type(A.Enforced) ~= "function" or not A.Enforced() or type(A.Manifest) ~= "function" then return nil end
	local ok, m = pcall(A.Manifest)
	return ok and type(m) == "table" and type(m.guilds) == "table" and m or nil
end
function Rooms.Enforced()
	local A = ns.Authority
	return type(A) == "table" and type(A.Enforced) == "function" and A.Enforced() == true
end

-- ns.IsFederation, once a listing for each guild (1.2.4: the per-guild rooms ask it of their guild too).
local function Federation(guild)
	if type(guild) ~= "string" then return false end
	local known = listing and listing.federation
	if known and known[guild] ~= nil then return known[guild] end
	local yes = ns.IsFederation(guild) == true
	if listing then
		if not known then known = {}; listing.federation = known end
		known[guild] = yes
	end
	return yes
end

local function Guilds()
	if listing and listing.guilds then return listing.guilds end
	local out, seen = {}, {}
	local function Add(guild)
		if type(guild) == "string" and Federation(guild) and not seen[Lower(guild)] then
			seen[Lower(guild)], out[#out + 1] = true, guild
		end
	end
	Add(OwnGuild())
	if ns.KingGuildName then Add(ns.KingGuildName()) end
	for guild in pairs(ns.rdb and ns.rdb.guilds or {}) do Add(guild) end
	-- (1.2.4: and the signed list's guilds, which the census may not have heard yet.)
	local m = Manifest()
	for _, g in pairs(m and m.guilds or {}) do if type(g) == "table" then Add(g.name) end end
	table.sort(out)
	if listing then listing.guilds = out end
	return out
end

local function Rank(name, guild)
	if guild == OwnGuild() then
		local R = ns.Roster
		if not R or not R.Fresh or not R.Fresh() then return nil end
	end
	local D = ns.Data
	if not (D and D.AuthorizedRank) then return nil end
	-- (1.2.3: once a listing for each name and guild, Rooms.Listing: the masters' and the centurions'
	-- rooms asked every guild of the census each, Data.AuthorizedRank counting its reports' votes.)
	local known
	if listing and guild ~= nil then
		local who = tostring(name)
		known = listing.rank[who]
		if not known then known = {}; listing.rank[who] = known end
		if known[guild] ~= nil then return known[guild] or nil end
	end
	-- Our own roster, the pinned King or the signed list; never the census (two characters could
	-- otherwise invent a guild and vouch for each other into these rooms).
	local rank, source = D.AuthorizedRank(ns.FullName(name), guild)
	if source == "census" then rank = nil end
	if known then known[guild] = rank or false end
	return rank
end

-- Nomination lists are received from proven guild masters, never from a nominee's own claim.
-- Recheck their current authority at every read/send, including the signed enforcement boundary.
local function Nomination(name, guild)
	local N = ns.Nominees
	if not N or not N.ListOf or not N.RoleOf then return nil end
	local list = N.ListOf(guild)
	if not list or type(list.by) ~= "string" then return nil end
	if ns.IsKingGuild(guild) then
		if not ((ns.IsKingCharacter and ns.IsKingCharacter(list.by)) or ns.IsHighCouncillor(list.by)) then return nil end
	elseif Rank(list.by, guild) ~= 0 or not N.Proven or N.Proven(list.by, guild) ~= true then return nil end
	if OwnGuild() == guild then
		local R = ns.Roster
		if not R or not R.Fresh or not R.Fresh() or not R.RankOf or R.RankOf(ns.FullName(name)) == nil then return nil end
	end
	return N.RoleOf(name, guild)
end

local function Correspondent(name, department)
	if listing then
		-- (Every guild's nomination of this name read once a listing: the departments it names.)
		local key = tostring(name)
		local found = listing.correspondent[key]
		if not found then
			found = {}
			for _, guild in ipairs(Guilds()) do
				local role, dept = Nomination(name, guild)
				if role == "correspondent" then
					found.any = true
					local d = DeptNamed(dept)
					if d then found[d] = true end
				end
			end
			listing.correspondent[key] = found
		end
		if department then return found[department] == true end
		return found.any == true
	end
	for _, guild in ipairs(Guilds()) do
		local role, dept = Nomination(name, guild)
		if role == "correspondent" and (not department or DeptNamed(dept) == department) then return true end
	end
	return false
end

local function Centurion(name, guild)
	local rank = Rank(name, guild)
	return rank ~= nil and rank > 0 and rank <= ns.CAPTAIN_RANK
		or Nomination(name, guild) == "centurion"
end

-- 1.2.4: a guild's master: rank 0 by our roster or the signed list, and the pinned King for his own
-- guild (without the signed list another guild's client knows him only from the census, which
-- Rank refuses: the King's guild's rooms would refuse the King).
local function Master(name, guild)
	if ns.IsKingGuild(guild) and IsKing(name) then return true end
	return Rank(name, guild) == 0
end

-- A member of our own guild is no member of another guild's room (1.2.4: the author's rule, a guild
-- master or officer has no power over another guild; a guild's room holds its own people alone).
local function Abroad(name, guild)
	local own = OwnGuild()
	if not own or Same(own, guild) then return false end
	local R = ns.Roster
	return R ~= nil and type(R.RankOf) == "function" and R.RankOf(ns.FullName(name)) ~= nil
end

---------------------------------------------------------------------------
-- 1.2.4: the per-guild rooms' keys
---------------------------------------------------------------------------

local keyOf, guildOfKey, keyCount = {}, {}, 0
local missed, missedCount = {}, 0 -- [key] = when no guild this client lists had it (asked again a minute later)
local function GuildKey(guild)
	if type(guild) ~= "string" or guild == "" then return nil end
	local key = keyOf[guild]
	if key then return key end
	local S = ns.Sign
	if type(S) ~= "table" or type(S.SHA256) ~= "function" then return nil end
	key = S.SHA256(ns.Fold(guild)):sub(1, 6):gsub(".", function(byte) return ("%02x"):format(byte:byte()) end)
	if keyCount < Rooms.GUILD_KEYS_MAX then
		keyOf[guild], keyCount = key, keyCount + 1
		if not guildOfKey[key] then guildOfKey[key] = guild end
	end
	return key
end
Rooms.GuildKey = GuildKey

-- The guilds this client lists: ours, the King's, the approved ones, the census's and the signed
-- list's (each an Olympus guild).
local function KnownGuilds()
	local out, seen = {}, {}
	local function Add(guild)
		if type(guild) == "string" and guild ~= "" and not seen[ns.Fold(guild)] and Federation(guild) then
			seen[ns.Fold(guild)], out[#out + 1] = true, guild
		end
	end
	Add(OwnGuild())
	if ns.KingGuildName then Add(ns.KingGuildName()) end
	if ns.ApprovedGuilds then
		local ok, list = pcall(ns.ApprovedGuilds)
		for _, guild in ipairs(ok and type(list) == "table" and list or {}) do Add(guild) end
	end
	for _, guild in ipairs(Guilds()) do Add(guild) end
	return out
end

-- The guild a key names, among the guilds this client lists; nil for none.
local function GuildOfKey(key)
	if type(key) ~= "string" or not key:match("^%x+$") or #key ~= 12 then return nil end
	local guild = guildOfKey[key]
	if guild and Federation(guild) then return guild end
	local t = missed[key]
	if t and Now() - t < 60 then return nil end
	for _, g in ipairs(KnownGuilds()) do
		if GuildKey(g) == key then return g end
	end
	if missedCount >= 64 then missed, missedCount = {}, 0 end
	missed[key], missedCount = Now(), missedCount + 1
	return nil
end

-- A per-guild room's id for `guild` (prefix gcorr or gcent), or nil.
local function GuildRoom(prefix, guild)
	local key = GuildKey(guild)
	return key and (prefix .. ":" .. key) or nil
end
Rooms.GuildRoom = GuildRoom

---------------------------------------------------------------------------
-- 1.2.4: the kinds of room, in the Roles menu's order
---------------------------------------------------------------------------

-- Each: id (one room) or prefix (one room a department, a guild), the room's kind (Rooms.Options),
-- its label, Access(name, arg), Candidates(add, arg) (each candidate checked again by Access), its
-- group (the menu folds a long list by it) and the previews (View as) that list it.
local KINDS, KIND_BY_ID, KIND_BY_PREFIX = {}, {}, {}
local RETIRED = { treasurers = true, departments = true, centurions = true } -- (1.2.3's rooms, gone in 1.2.4)

local function AnyGuild(name, check)
	for _, guild in ipairs(Guilds()) do if check(name, guild) then return true end end
	return false
end

local Candidates = {} -- shared candidate sources, below (Members)

KINDS[#KINDS + 1] = { id = "council", kind = "authority", label = function() return Text("CHATROOM_COUNCIL", "High Council") end,
	preview = { king = true, councillor = true, treasurer = true },
	Access = function(name) return ns.IsHighCouncillor(name) == true or IsKing(name) or FederalTreasurer(name) end,
	Candidates = function(add) Candidates.Council(add) end }
KINDS[#KINDS + 1] = { id = "secretariat", kind = "authority", label = function() return Text("CHATROOM_SECRETARIAT", "Secretariat") end,
	preview = { king = true },
	Access = function(name) return IsSecretariat(name) end,
	Candidates = function(add)
		if ns.KingCharacter then add(ns.KingCharacter(), 2) end
		for _, name in ipairs(ns.Stewards and ns.Stewards() or {}) do add(name) end
	end }
KINDS[#KINDS + 1] = { id = "masters", kind = "role", label = function() return Text("CHATROOM_MASTERS", "Guild Masters") end,
	preview = { king = true, gm = true }, leaders = true,
	Access = function(name) return IsKing(name) or AnyGuild(name, function(n, g) return Rank(n, g) == 0 end) end,
	Candidates = function(add) Candidates.Leaders(add) end }
KINDS[#KINDS + 1] = { id = "allcenturions", kind = "role", label = function() return Text("CHATROOM_ALLCENTURIONS", "Masters & Centurions") end,
	preview = { king = true, gm = true, officer = true }, leaders = true,
	Access = function(name) return IsKing(name) or AnyGuild(name, function(n, g) return Master(n, g) or Centurion(n, g) end) end,
	Candidates = function(add) Candidates.Leaders(add) end }
KINDS[#KINDS + 1] = { prefix = "dept", kind = "department", group = "dept", leaders = true,
	groupLabel = function() return Text("CHATROOM_GROUP_DEPARTMENTS", "Departments") end,
	Preview = function(role, d) return role == "councillor" or role == "correspondent" or role == "treasurer" and d == TREASURY end,
	Access = function(name, d)
		return DepartmentFor(name) == d or Correspondent(name, d) or (d == TREASURY and FederalTreasurer(name))
	end,
	Candidates = function(add, d)
		if d == TREASURY and ns.TREASURER then add(ns.TREASURER, 3) end
		Candidates.Leaders(add)
		local t = ns.CouncilTitles and ns.CouncilTitles()
		for _, dept in ipairs(t and t.depts or {}) do
			if DeptNamed(dept.name) == d then
				for _, m in ipairs(type(dept.members) == "table" and dept.members or {}) do add(m.name, 3) end
			end
		end
	end }
KINDS[#KINDS + 1] = { prefix = "gcorr", kind = "role", group = "gcorr", perGuild = true,
	groupLabel = function() return Text("CHATROOM_GCORR", "Master & Correspondents") end,
	label = function(guild)
		if Same(guild, OwnGuild()) then return Text("CHATROOM_GCORR", "Master & Correspondents") end
		return Text("CHATROOM_GCORR_OF", "%s: Master & Correspondents"):format(guild)
	end,
	-- (The King's guild has no correspondents, Nominees.lua: no such room for it.)
	Has = function(guild) return not ns.IsKingGuild(guild) end,
	preview = { gm = true, correspondent = true },
	Access = function(name, guild)
		return not Abroad(name, guild) and (Master(name, guild) or Nomination(name, guild) == "correspondent")
	end,
	Candidates = function(add, guild) Candidates.Guild(add, guild, false) end }
KINDS[#KINDS + 1] = { prefix = "gcent", kind = "role", group = "gcent", perGuild = true,
	groupLabel = function() return Text("CHATROOM_GCENT", "Master & Centurions") end,
	label = function(guild)
		if Same(guild, OwnGuild()) then return Text("CHATROOM_GCENT", "Master & Centurions") end
		return Text("CHATROOM_GCENT_OF", "%s: Master & Centurions"):format(guild)
	end,
	preview = { king = true, gm = true, officer = true },
	Access = function(name, guild)
		return not Abroad(name, guild) and (Master(name, guild) or Centurion(name, guild))
	end,
	Candidates = function(add, guild) Candidates.Guild(add, guild, true) end }
for _, k in ipairs(KINDS) do
	if k.id then KIND_BY_ID[k.id] = k end
	if k.prefix then KIND_BY_PREFIX[k.prefix] = k end
end

-- A room id's kind and its argument (the department, the guild), or nil.
local function KindOf(id)
	if type(id) ~= "string" then return nil end
	local k = KIND_BY_ID[id]
	if k then return k end
	local prefix, rest = id:match("^(%l+):(.+)$")
	k = prefix and KIND_BY_PREFIX[prefix]
	if not k then return nil end
	if k.prefix == "dept" then
		Departments()
		local d = DEPT_BY_ID[id]
		return d and k or nil, d
	end
	local guild = GuildOfKey(rest)
	if not guild or (k.Has and not k.Has(guild)) then return nil end
	return k, guild
end

local function AudienceLabel(a, field)
	local ok, label = pcall(function()
		local v = a[field or "label"]
		return type(v) == "function" and v() or v
	end)
	return ok and type(label) == "string" and label or nil
end

local function Restricted(id)
	local a = audiences[id]
	if a then
		return { id = id, kind = id, label = AudienceLabel(a) or "?", scope = "restricted", audience = true,
			group = a.group, groupLabel = a.group and AudienceLabel(a, "groupLabel") or nil }
	end
	local k, arg = KindOf(id)
	if not k then return nil end
	local info = { id = id, kind = k.kind, scope = "restricted", group = k.group, groupLabel = k.groupLabel and k.groupLabel() or nil }
	if k.prefix == "dept" then
		info.label, info.department = Text(arg.labelKey, arg.name), arg
	elseif k.perGuild then
		info.label, info.guild = k.label(arg), arg
	else
		info.label = k.label()
	end
	return info
end

-- The provider whose private room this is, and its description.
local function ProviderFor(id)
	if type(id) ~= "string" then return nil end
	for _, p in ipairs(providers) do
		local ok, info = pcall(p.Info, id)
		if ok and type(info) == "table" then return p, info end
	end
end

-- A later-loaded feature can own private logical rooms without teaching the chat window its
-- transport (1.2: CraftRequests.lua). The provider stays the only authority for its rooms'
-- membership, history and delivery; nothing of a provider room goes over M2.
function Rooms.RegisterProvider(p)
	if type(p) ~= "table" or type(p.Info) ~= "function" or type(p.CanAccess) ~= "function"
		or type(p.History) ~= "function" or type(p.Send) ~= "function" then return false end
	for _, old in ipairs(providers) do if old == p then return true end end
	providers[#providers + 1] = p
	return true
end

-- 1.1.6: a restricted room over M2 whose audience another module keeps (Church.lua). spec.CanAccess(name)
-- says who may read and send; spec.Recipients() who is reached (each still checked by CanAccess,
-- this character left out), and (1.2.4) how many it left out. 1.2.4: spec.group and spec.groupLabel
-- fold it with its kin in a long Roles menu; spec.preview = { [role] = true } lists it under those
-- previews (View as). Never one of the ids above or a provider's. False when refused.
function Rooms.RegisterAudience(id, spec)
	if type(id) ~= "string" or not id:match("^%l+$") or #id > 16 or type(spec) ~= "table"
		or type(spec.CanAccess) ~= "function" or type(spec.Recipients) ~= "function" then return false end
	if id == "guild" or KIND_BY_ID[id] or KIND_BY_PREFIX[id] or RETIRED[id] or ProviderFor(id) or audiences[id] then return false end
	audiences[id] = spec
	audienceOrder[#audienceOrder + 1] = id
	return true
end

function Rooms.Info(id)
	local _, external = ProviderFor(id)
	if external then return external end
	if id == "guild" then return { id = id, kind = "guild", label = L.CHATROOM_GUILD or "Guild", scope = "guild" } end
	return Restricted(id)
end

function Rooms.CanAccess(id, name)
	local provider = ProviderFor(id)
	if provider then return provider.CanAccess(id, name or ns.me) == true end
	if id == "guild" then return ns.IsMember() == true end
	name = name or ns.me
	if audiences[id] then
		local ok, yes = pcall(audiences[id].CanAccess, name)
		return ok and yes == true
	end
	local k, arg = KindOf(id)
	if not k then return false end
	return k.Access(name, arg) == true
end

local function AuthorityOptions()
	local out = {}
	if Rooms.CanAccess("council") then out[#out + 1] = Rooms.Info("council") end
	if Rooms.CanAccess("secretariat") then out[#out + 1] = Rooms.Info("secretariat") end
	return out
end

local function DepartmentOptions()
	local out = {}
	for _, d in ipairs(Departments()) do if Rooms.CanAccess(d.id) then out[#out + 1] = Rooms.Info(d.id) end end
	return out
end

local function PreviewRole()
	local V = ns.ViewAs
	if type(V) == "table" and type(V.Previewing) == "function" and V.Previewing()
		and type(V.Role) == "function" then return V.Role() end
end

-- This menu is presentation only. A preview names a role's possible rooms, never a person's
-- private history; it cannot select one, even when the author's real character has access.
function Rooms.PreviewOnly(id)
	local info = Rooms.Info(id)
	return info ~= nil and info.scope == "restricted" and PreviewRole() ~= nil
end

-- The guilds whose own rooms (gcorr, gcent) this character's menu offers: his own guild's.
local function ListedGuilds()
	local own = OwnGuild()
	return own and Federation(own) and { own } or {}
end

local function RoleOptions()
	local role, out = PreviewRole(), {}
	local function Add(id, preview)
		local info = Rooms.Info(id)
		if info and (role and preview or not role and Rooms.CanAccess(id)) then
			info.disabled = role ~= nil
			out[#out + 1] = info
		end
	end
	for _, k in ipairs(KINDS) do
		if k.prefix == "dept" then
			for _, d in ipairs(Departments()) do Add(d.id, role and k.Preview(role, d)) end
		elseif k.perGuild then
			for _, guild in ipairs(ListedGuilds()) do
				if not k.Has or k.Has(guild) then
					local id = GuildRoom(k.prefix, guild)
					if id then Add(id, role and k.preview[role]) end
				end
			end
		else
			Add(k.id, role and k.preview[role])
		end
	end
	for _, aid in ipairs(audienceOrder) do
		local preview = audiences[aid].preview
		Add(aid, role and type(preview) == "table" and preview[role] == true)
	end
	return out
end

function Rooms.Options(kind)
	if not listing then return Rooms.Listing(Rooms.Options, kind) end
	if kind ~= nil and listing.options[kind] then return listing.options[kind] end
	local out = {}
	if kind == "authority" then
		out = AuthorityOptions()
	elseif kind == "department" then
		out = DepartmentOptions()
	elseif kind == "role" then
		out = RoleOptions()
	end
	-- Later guild-local features own their dynamic audience and revalidate every entry.
	for _, provider in ipairs(providers) do
		if type(provider.Options) == "function" then
			local ok, options = pcall(provider.Options, kind)
			for _, info in ipairs(ok and type(options) == "table" and options or {}) do
				if type(info) == "table" and type(info.id) == "string" and not Rooms.PreviewOnly(info.id)
					and Rooms.CanAccess(info.id) then out[#out + 1] = info end
			end
		end
	end
	if kind ~= nil then listing.options[kind] = out end -- (the same list for the rest of this listing: read only)
	return out
end

-- The compact row's logical destinations after Olympus: Guild, Roles while this character (or the
-- role previewed) has one, then the providers' own tabs. (1.2.3: no Race or Class any more.)
function Rooms.Tabs()
	if not listing then return Rooms.Listing(Rooms.Tabs) end
	local out = { { kind = "guild", id = "guild", label = L.CHATROOM_GUILD or "Guild" } }
	if #Rooms.Options("role") > 0 then
		out[#out + 1] = { kind = "role", label = rawget(L, "CHATROOM_ROLES") or "Roles", dropdown = true }
	end
	for _, p in ipairs(providers) do
		if type(p.Tabs) == "function" then
			local ok, tabs = pcall(p.Tabs)
			if ok and type(tabs) == "table" then for _, tab in ipairs(tabs) do out[#out + 1] = tab end end
		end
	end
	return out
end

function Rooms.Select(id)
	if Rooms.PreviewOnly(id) then return false, "preview" end
	local provider = ProviderFor(id)
	if provider then
		if not Rooms.CanAccess(id) or (type(provider.Select) == "function" and provider.Select(id) == false) then return false, "access" end
		ns.Fire("CHAT_ROOM_SELECTED", id)
		return true
	end
	if not Rooms.Info(id) or not Rooms.CanAccess(id) then return false, "access" end
	ns.Fire("CHAT_ROOM_SELECTED", id)
	return true
end

local function Accepts(id)
	local provider = ProviderFor(id)
	if provider then return Rooms.CanAccess(id) and (type(provider.IsOpen) ~= "function" or provider.IsOpen(id) == true) end
	return Rooms.Info(id) ~= nil and Rooms.CanAccess(id)
end
Rooms.IsOpen = Accepts

-- The rooms' consent; a provider room (named by id) answers for itself: its two parties chose it.
function Rooms.ChatOn(id)
	local provider = ProviderFor(id)
	if provider then return type(provider.ChatOn) ~= "function" or provider.ChatOn(id) == true end
	return ns.db ~= nil and ns.db.chatRooms == true
end
function Rooms.SetChatOn(on)
	if not ns.db then return false end
	ns.db.chatRooms = on and true or false
	if not on and ns.Comm and ns.Comm.Cancel then ns.Comm.Cancel(Rooms) end
	ns.Print(on and (L.CHATROOMS_ON or "Chat rooms on.") or (L.CHATROOMS_OFF_MSG or "Chat rooms off."))
	ns.Fire("CHAT_ROOMS_CHANGED")
	return true
end

local function State(id, make)
	local r = states[id]
	if r or not make then return r end
	local count = 0
	for _ in pairs(states) do count = count + 1 end
	if count >= Rooms.ROOMS_MAX then
		local oldest, at
		for key, one in pairs(states) do
			if key ~= "guild" and (not at or (one.used or 0) < at) then oldest, at = key, one.used or 0 end
		end
		if oldest then states[oldest] = nil end
	end
	r = { id = id, lines = {}, recent = {}, used = Now() }
	states[id] = r
	return r
end

local function Keep(id, e)
	local r = State(id, true)
	if not r then return end
	r.lines[#r.lines + 1] = e
	while #r.lines > Rooms.HISTORY do table.remove(r.lines, 1) end
	r.used = Now()
	ns.Fire("CHAT_ROOM_CHANGED", id)
	-- The window uses CHAT_ROOM_LINE for unread state. A local echo is already visible to
	-- its sender and must not make a background room look unread while the queued send
	-- completes.
	if not e.mine then ns.Fire("CHAT_ROOM_LINE", id, e.sender, e.text) end
end

-- The server's guild event includes guildmates without Olympus. Do not publish it to M2 or
-- echo a send optimistically: the native event is the sole source of the displayed line.
function Rooms.ReceiveGuild(text, sender)
	if not Rooms.ChatOn() or not Accepts("guild") then return false, "off" end
	if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return false, "secret" end
	if type(text) ~= "string" or text == "" or type(sender) ~= "string" or sender == "" then return false, "message" end
	local guild = GetGuildInfo("player")
	if type(guild) ~= "string" or guild == "" then return false, "guild" end
	sender = ns.FullName(sender)
	nextId = (nextId + 1) % 10000
	local lineId, now = nextId, Now()
	local admitted, why = ns.Channels.Admit(sender, guild, text, now, {
		id = "guild:native:" .. lineId, chat = "guild", line = lineId, level = 0,
		buckets = receiveBuckets, seen = receiveSeen, mine = receiveMine, stats = stats, where = "guild",
	})
	if not admitted and why ~= "filtered" then return false, why end
	Keep("guild", { t = ns.Now(), sender = sender, guild = guild, text = text, id = lineId,
		mine = ns.Channels.IsMe(sender), hidden = why == "filtered" or nil, native = true })
	stats.shown = stats.shown + 1
	return true
end

-- 1.2.3: memo (optional, the Chat tab's: ChatWindow.offMemo), line -> left out, as Channels.History
-- keeps it: emptied by its caller whenever what it rests on may have changed (our guild, a word).
function Rooms.History(id, memo)
	if Rooms.PreviewOnly(id) then return {} end
	local provider = ProviderFor(id)
	if provider then
		if not Rooms.ChatOn(id) or not Accepts(id) then return {} end
		local ok, history = pcall(provider.History, id)
		return ok and type(history) == "table" and history or {}
	end
	if not Rooms.ChatOn() or not Accepts(id) then return {} end
	local r = State(id, false)
	if not r then return {} end
	r.used = Now()
	local M = ns.Moderation
	if id ~= "guild" and not (M and M.Any and M.Any()) then return r.lines end
	local out = {}
	for _, e in ipairs(r.lines) do
		local off = memo and memo[e]
		if off == nil then
			off = not ((id ~= "guild" or Same(e.guild, GetGuildInfo("player")))
				and not (M and M.Hides and M.Hides(e.sender, e.guild)))
			if memo then memo[e] = off end
		end
		if not off then out[#out + 1] = e end
	end
	return out
end

-- 1.1.6 (WatchChat.lua): the rooms this session kept lines of, and those lines themselves (a
-- moderator's deletion marks them; nothing else reads them this way).
function Rooms.KeptRooms()
	local out = {}
	for id in pairs(states) do out[#out + 1] = id end
	table.sort(out)
	return out
end
function Rooms.RawHistory(id)
	local r = State(id, false)
	return r and r.lines or {}
end

-- 1.2.0: a restricted room whispers nobody the game says is offline: our roster's offline members,
-- and a name the server just answered "not currently playing" for (ERR_CHAT_PLAYER_NOT_FOUND_S,
-- GONE_FOR). Both are the server's word, never a report's.
local gone, notFound, watchingGone = {}, nil, false
function Rooms.NotFound(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
	if not notFound then
		local f = type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S or nil
		if not f then return end
		notFound = "^" .. (f:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)")) .. "$"
	end
	local who = text:match(notFound)
	if who then gone[Lower(ns.FullName(who))] = Now() end
end
local function WatchGone()
	if watchingGone or not ns.RegisterEvent then return end
	watchingGone = true
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) ns.SafeCall("chat room not found", Rooms.NotFound, text) end)
end
local function Offline(full, roster)
	local key = Lower(full)
	local t = gone[key]
	if t and Now() - t < Rooms.GONE_FOR then return true end
	return roster[key] == false
end

-- 1.2.4: where each kind's candidates come from (Members). Candidate discovery grants nothing:
-- Members' Add checks each candidate's current access again. add(name, order): order 2 the King,
-- 3 a councillor, 4 a guild master (who goes first when a room has more than its share).
function Candidates.Council(add)
	if ns.KingCharacter then add(ns.KingCharacter(), 2) end
	if ns.TREASURER then add(ns.TREASURER, 3) end
	local c = ns.rdb and ns.rdb.council
	for key, display in pairs(type(c) == "table" and type(c.names) == "table" and c.names or {}) do
		-- Current signed lists keep lower-case name -> display name. Older in-memory fixtures used
		-- true for the value; the signed key is still the identity in that representation.
		add(type(display) == "string" and display or key, 3)
	end
end

-- Our roster's guild master and officers (rank CAPTAIN_RANK at most; every member when the roster
-- gives no rank).
local function RosterLeaders(add)
	local R = ns.Roster
	for _, member in ipairs(R and R.members or {}) do
		local rank = type(R.RankOf) == "function" and type(member.name) == "string" and R.RankOf(ns.FullName(member.name)) or nil
		if rank == nil or rank <= ns.CAPTAIN_RANK then add(member.name, rank == 0 and 4 or nil) end
	end
end

-- Every guild's master and officers (our roster, the census's word for a candidate, the signed list),
-- every guild's nominees, the King.
function Candidates.Leaders(add)
	if ns.KingCharacter then add(ns.KingCharacter(), 2) end
	RosterLeaders(add)
	for _, guild in ipairs(Guilds()) do
		local g = ns.Data and ns.Data.Guild and ns.Data.Guild(guild)
		if g then
			if g.leader then add(ns.FullName(g.leader, g.realm), 4) end
			for _, officer in ipairs(g.officers or {}) do add(ns.FullName(officer.name, g.realm)) end
		end
		local N = ns.Nominees
		local list = N and N.ListOf and N.ListOf(guild)
		for _, entry in ipairs(list and list.entries or {}) do add(entry.name) end
	end
	local m = Manifest()
	for _, p in pairs(m and m.people or {}) do
		if type(p) == "table" and type(p.name) == "string" then add(p.name, p.rank == 0 and 4 or nil) end
	end
end

-- One guild's master, its officers when `officers`, and its nominees.
function Candidates.Guild(add, guild, officers)
	if ns.IsKingGuild(guild) and ns.KingCharacter then add(ns.KingCharacter(), 2) end
	if Same(guild, OwnGuild()) then RosterLeaders(add) end
	local g = ns.Data and ns.Data.Guild and ns.Data.Guild(guild)
	if g then
		if g.leader then add(ns.FullName(g.leader, g.realm), 4) end
		if officers then for _, officer in ipairs(g.officers or {}) do add(ns.FullName(officer.name, g.realm)) end end
	end
	local N = ns.Nominees
	local list = N and N.ListOf and N.ListOf(guild)
	for _, entry in ipairs(list and list.entries or {}) do add(entry.name) end
	local m = Manifest()
	for _, p in pairs(m and m.people or {}) do
		if type(p) == "table" and type(p.name) == "string" and Same(p.guild, guild) and (officers or p.rank == 0) then
			add(p.name, p.rank == 0 and 4 or nil)
		end
	end
end

local function Members(id)
	local out, seen = {}, {}
	local roster = {}
	for _, m in ipairs(ns.Roster and ns.Roster.members or {}) do
		if type(m) == "table" and type(m.name) == "string" and m.online ~= nil then roster[Lower(ns.FullName(m.full or m.name))] = m.online == true end
	end
	local function Add(name)
		if type(name) ~= "string" or name == "" then return end
		local full = ns.FullName(name)
		local key = full:lower()
		if not seen[key] and not IsMe(full) and Rooms.CanAccess(id, full) then
			seen[key] = true
			if not Offline(full, roster) then out[#out + 1] = full end
		end
	end
	if audiences[id] then
		local ok, list = pcall(audiences[id].Recipients)
		for _, name in ipairs(ok and type(list) == "table" and list or {}) do Add(name) end
	else
		local k, arg = KindOf(id)
		if k then k.Candidates(Add, arg) end
	end
	table.sort(out)
	return out
end
Rooms.Recipients = Members -- diagnostics/tests: the signed audience, with this character left out

local function CleanGuild(guild)
	return tostring(guild or ""):gsub("[~|%c]", ""):sub(1, 72)
end

local function Cut(text, max)
	if #text <= max then return text end
	local at = max
	while at > 0 do
		local b = text:byte(at + 1)
		if not b or b < 128 or b >= 192 then break end
		at = at - 1
	end
	return text:sub(1, at):gsub("%s+$", "")
end

local function Locked()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() and true or false
end

local function Recent(now)
	for i = #sentTimes, 1, -1 do if now - sentTimes[i] >= 60 then table.remove(sentTimes, i) end end
	return #sentTimes
end

-- (1.2.3: every M2 line this client sends is a restricted room's whisper; Guild goes natively.)
local function Permit(id, recipient)
	return function(_, key, dist, target)
		if not Rooms.ChatOn() or not Rooms.CanAccess(id) then return false, "revoked" end
		-- (1.1.6: a moderator's timeout that came while the line waited.)
		local WC = ns.WatchChat
		if WC and WC.SelfTimeout and WC.SelfTimeout() then return false, "timeout" end
		if dist ~= "WHISPER" or not Same(target, recipient) or not Rooms.CanAccess(id, recipient) then
			return false, "revoked"
		end
		return true
	end
end

local function Echo(id, lineId, guild, text)
	receiveMine[id .. ":" .. lineId .. "#" .. text] = Now()
	Keep(id, { t = ns.Now(), sender = ns.me, guild = guild, text = text, id = lineId, mine = true })
	stats.sent = stats.sent + 1
end

local function SendGuild(text) -- gp:roster-actions
	if not ns.Gate.Allowed("roster-actions") then return false, "gamepad" end
	local C = C_ChatInfo
	local send = type(C) == "table" and C.SendChatMessage or SendChatMessage
	if type(send) ~= "function" then return false, "api" end
	local ok, err = pcall(send, text, "GUILD")
	if not ok then
		if ns.Log then ns.Log("native guild chat send: %s", tostring(err)) end
		return false, "failed"
	end
	return true
end

-- Returns true once the complete, fixed audience was admitted to the queue. Completion callbacks
-- add the local echo only after a game send succeeded and expose a failed/partly failed send to
-- the Chat page without rerouting it.
local function Send(id, text)
	if Rooms.PreviewOnly(id) then return false, "preview" end
	-- 1.1.6: a moderator's timeout (WatchChat.lua) covers every room, a provider's too.
	local WC = ns.WatchChat
	if WC and WC.RefuseSend and WC.RefuseSend() then return false, "timeout" end
	local provider = ProviderFor(id)
	if provider then
		if not Rooms.CanAccess(id) then ns.Print(L.CHATROOM_NO_ACCESS or "You cannot use this room.") return false, "access" end
		return provider.Send(id, text)
	end
	local info = Rooms.Info(id)
	if not info or not Rooms.CanAccess(id) then ns.Print(L.CHATROOM_NO_ACCESS or "You cannot use this room.") return false, "access" end
	if not Rooms.ChatOn() then
		ns.Print(ns.db and ns.db.chatRooms == nil and (L.CHATROOMS_OFF_UNANSWERED or "Choose chat-room consent first.")
			or (L.CHATROOMS_OFF or "Chat rooms are off."))
		if ns.db and ns.db.chatRooms == nil and ns.Consent and ns.Consent.Ask then ns.Consent.Ask("chatrooms") end
		return false, "off"
	end
	if ns.Moderation and ns.Moderation.SelfOff and ns.Moderation.SelfOff() then
		ns.Print(ns.Moderation.YouText(ns.Moderation.SelfOff()))
		return false, "netoff"
	end
	text = Cut(ns.Codec.SanitizeChat(text), Rooms.TEXT_MAX)
	if text == "" then return false, "empty" end
	if WC and WC.RefuseSevere and WC.RefuseSevere(text) then return false, "severe" end -- (1.1.6, WatchChat.SEVERE)
	if Locked() then ns.Print(L.CHAN_LOCKDOWN) return false, "lockdown" end
	local now = Now()
	if now - lastSend < Rooms.SEND_GAP or Recent(now) >= Rooms.PER_MINUTE then
		ns.Print(L.CHAN_TOO_FAST)
		return false, "fast"
	end
	local guild = GetGuildInfo("player")
	if type(guild) ~= "string" or guild == "" then return false, "guild" end
	if id == "guild" then
		local ok, why = SendGuild(text)
		if ok then lastSend = now; sentTimes[#sentTimes + 1] = now; stats.sent = stats.sent + 1 end
		return ok, ok and "ok" or why
	end
	-- The legacy class field stays empty (an old reader takes it for its name colour alone).
	nextId = (nextId + 1) % 10000
	local lineId = nextId
	local msg = ("M2~1~%s~%d~~%s~%s"):format(id, lineId, CleanGuild(guild), text)
	if #msg > 255 then return false, "size" end
	-- (1.2.3: past Guild every room of this file is restricted: one logged whisper to each recipient.)
	local recipients = Members(id)
	WatchGone()
	local count = #recipients
	if ns.Comm.QueueRoom and ns.Comm.QueueRoom() < count then ns.Print(L.CHAN_BUSY) return false, "busy" end

	local guardKey = id .. "#" .. lineId
	local pending, successes, failures = count, 0, 0
	local finished = false
	local function Done(ok, why)
		if finished then return end
		pending = pending - 1
		if ok then successes = successes + 1 else failures = failures + 1 end
		if pending > 0 then return end
		finished = true
		if successes > 0 then Echo(id, lineId, guild, text) end
		if failures > 0 then ns.Fire("CHAT_ROOM_SEND_FAILED", id, why or "failed", text, successes) end
	end
	local accepted = true
	-- A room containing only this character is still a useful local history, and sends no bytes.
	if #recipients == 0 then pending = 0; Echo(id, lineId, guild, text)
	else
		for _, recipient in ipairs(recipients) do
			local ok = ns.Comm.Whisper(recipient, msg, nil, false, true, Done,
				{ owner = Rooms, key = guardKey, permit = Permit(id, recipient) })
			if not ok then accepted = false end
		end
		-- Admission is all-or-none: preflight normally makes every whisper fit, but a
		-- synchronous refusal must not leave an admitted prefix aimed at only part of the
		-- audience. All jobs share this exact capability key; unrelated sends stay queued.
		if not accepted and ns.Comm.CancelQueued then ns.Comm.CancelQueued(Rooms, guardKey, "cancelled") end
	end
	if not accepted then
		if pending == count then finished = true end
		return false, "busy"
	end
	lastSend = now
	sentTimes[#sentTimes + 1] = now
	return true, "ok"
end

function Rooms.Send(id, text) return Send(id, text) end

-- A room's minute: FLOOD lines in all, and (1.2.0) each sender's fair share of it, PER_MINUTE
-- (what an unmodified client sends at most): one sender cannot crowd the others out.
local function Flooded(r, sender, now)
	local who, mine = Lower(sender), 0
	for i = #r.recent, 1, -1 do
		local e = r.recent[i]
		if now - e.t >= 60 then table.remove(r.recent, i) elseif e.who == who then mine = mine + 1 end
	end
	if #r.recent >= Rooms.FLOOD or mine >= Rooms.PER_MINUTE then return true end
	r.recent[#r.recent + 1] = { t = now, who = who }
	return false
end

local function Parse(text)
	local version, id, lineId, class, guild, words = tostring(text or ""):match("^M2~([^~]+)~([^~]+)~([^~]+)~([^~]*)~([^~]*)~(.*)$")
	lineId = tonumber(lineId)
	if version ~= "1" or not Rooms.Info(id) or not lineId or lineId < 0 or lineId > 9999 or lineId ~= math.floor(lineId) then return nil end
	if class ~= "" and not class:match("^%u%u$") then return nil end
	-- (1.2.0: no "|" or control byte in the guild field either, as M1: it reaches the debug log.)
	if guild == "" or guild:find("[|%c]") or not ns.IsFederation(guild) then return nil end
	words = ns.Codec.SanitizeChat(words)
	if words == "" or #words > Rooms.TEXT_MAX then return nil end
	-- ("RQ", the old race/class rooms' outsider-request marker, is no class: no name colour.)
	return id, lineId, class == "RQ" and "" or class, guild, words
end

-- 1.2.3: the race and class rooms are gone. A line an older client still sends to one ("race:<n>",
-- "class:<code>") is dropped without a word to the player, and said in the debug log once a
-- session (Rooms.Reset), its kind alone: nothing of the wire's words goes there.
-- 1.2.4: so are the treasurers', all the departments' and one guild's centurions' rooms (RETIRED:
-- the Federal Treasury's room holds the Treasurer now; a guild's master and centurions have a room
-- of their own, gcent): an older client's line to one is dropped the same way, said once a session.
local retiredSaid, retired124Said = false, false
local function Retired(text)
	text = tostring(text or "")
	local id = text:match("^M2~[^~]*~([^~]+)~")
	if id and RETIRED[id] then
		if not retired124Said and ns.Log then
			retired124Said = true
			ns.Log("chat rooms: a line to the %s room dropped (gone since 1.2.4)", id)
		end
		return true
	end
	local kind = text:match("^M2~[^~]*~(%l+):")
	if kind ~= "race" and kind ~= "class" then return false end
	if not retiredSaid and ns.Log then
		retiredSaid = true
		ns.Log("chat rooms: a line to a %s room dropped (the race and class rooms are gone since 1.2.3)", kind)
	end
	return true
end

function Rooms.Receive(dist, sender, text, now)
	if not Rooms.ChatOn() then return Drop("off") end
	if Retired(text) then return Drop("retired") end
	local id, lineId, class, guild, words = Parse(text)
	if not id then return Drop("shape") end
	if ProviderFor(id) then return Drop("provider") end
	if not Accepts(id) then return Drop("unselected") end
	local info = Rooms.Info(id)
	local expected = info.scope == "guild" and "GUILD" or "WHISPER"
	if dist ~= expected then return Drop("lane") end
	sender = ns.FullName(sender)
	if info.scope == "restricted" and not Rooms.CanAccess(id, sender) then return Drop("audience") end
	if info.scope == "guild" then
		local own = GetGuildInfo("player")
		if not Same(guild, own) then return Drop("guild") end
		guild = own
	end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then return Drop("unlogged") end
	now = now or Now()
	local admitted, why = ns.Channels.Admit(sender, guild, words, now, {
		id = id .. ":" .. lineId, chat = id, line = lineId, level = info.scope == "guild" and 0 or 1,
		buckets = receiveBuckets, seen = receiveSeen, mine = receiveMine, stats = stats, where = id,
	})
	if not admitted and why ~= "filtered" then return Drop(why) end
	local r = State(id, true)
	if Flooded(r, sender, now) then return Drop("flood") end
	Keep(id, { t = ns.Now(), sender = sender, guild = guild, class = class ~= "" and class or nil,
		text = words, id = lineId, hidden = why == "filtered" or nil })
	stats.shown = stats.shown + 1
	return true, "ok"
end

function Rooms.Stats() return stats end

-- A signed authority replacement revokes visibility immediately and cancels queued restricted
-- whispers through their permits. Histories no longer authorized are discarded, not merely hidden.
function Rooms.RefreshAuthority()
	local changed = false
	for id in pairs(states) do
		local info = Rooms.Info(id)
		if info and info.scope == "restricted" and not Rooms.CanAccess(id) then states[id], changed = nil, true end
	end
	if changed then ns.Fire("CHAT_ROOMS_CHANGED") end
	return changed
end

function Rooms.Reset()
	states = {}
	nextId = 0
	lastSend, sentTimes = -math.huge, {}
	receiveBuckets, receiveSeen, receiveMine = {}, {}, {}
	gone = {}
	stats = { sent = 0, shown = 0, dropped = {} }
	held, writing = nil, {}
	retiredSaid, retired124Said = false, false
	-- (1.2.3: the race and class rooms' saved choices and outsider-request records go with them; a
	-- Chat page last left on one of them opens on its channel, ChatWindow's Pick.)
	if ns.db then ns.db.chatRoomChoices, ns.db.chatRoomRequests = nil, nil end
end

---------------------------------------------------------------------------
-- 1.2: one pattern for every pending conversation (the owner's decision)
---------------------------------------------------------------------------

-- A matter that may stay unresolved for a while (a match found in Bones or the Arena, a crafting
-- deal, any later transaction between players) gets a tab of its own on the Chat page. Olympus
-- opens that tab, brings the Olympus window to the front on it (over the other windows; a pop-up
-- of Olympus's above it whose work the matter ends gives way: CHAT_MATTER_SHOWN), and keeps it
-- pinned while the matter is open; the matter's own page (the match card, the request) reopens it
-- with this same call. Two kinds of room exist and this is their one door: a provider's private
-- room (m.room, Rooms.RegisterProvider: a crafting request, which keeps its own tab until its deal
-- is over and the player removes it) or one of the Arena's dynamic rooms (m.spec,
-- ChatWindow.OpenDynamicRoom's contract: a matched duel or Bones game, a fight, pinned here and
-- unpinned when the Arena says it ended). It only uses the Chat page's own room and tab calls: nothing here sends a word, draws a
-- tab or decides who belongs to a room (the room's owner does).
--   m = { room = <provider room id> } or { spec = <spec, or a function giving the current one> },
--   m.auto: Olympus opens it by itself, not a click, as every window that opens by itself: in an
--   instance or Busy it waits with the held alerts (ns.Alert, m.kind its sound's switch: its line on
--   the Decrees tab, and it opens when the player is back), in a fight until the fight's end
--   (ns.OutOfCombat), while the player writes in the Chat page's own box until he is done; each
--   matter on its own, and it opens then only while the matter is still open (m.live(), else the
--   spec's active, else the provider's room still open).
--   m.keep = false: a room the player only watches (a spectator's fight), not a matter of his:
--   its tab and the window in front, no pin.
Rooms.WRITING_WAIT = 2            -- seconds between two looks at the Chat page's box while he writes
Rooms.MATTER_PIN_KEEP = 7 * 86400 -- a pin of the door's, kept over reloads this long at most

local function MatterSpec(m)
	local spec = m.spec
	if type(spec) == "function" then
		local ok, current = pcall(spec)
		spec = ok and current or nil
	end
	return type(spec) == "table" and spec or nil
end

local function MatterLive(m, spec)
	if type(m.live) == "function" then
		local ok, live = pcall(m.live)
		return ok and live == true
	end
	if spec then return spec.active == true end
	return Accepts(m.room) == true
end

-- The matter as it is now: its current spec (a dynamic room's), and whether it is still open.
local function MatterNow(m)
	local spec = m.spec ~= nil and MatterSpec(m) or nil
	return spec, (m.spec == nil or spec ~= nil) and MatterLive(m, spec)
end

-- The pins made here, saved as the Chat page saves the pin itself (ChatWindow.PinDynamicRoom): a
-- room restored pinned after a reload is still the matter's, and its end takes the pin back; it
-- never passes for one of the player's own. Each with when it was made; one older than
-- MATTER_PIN_KEEP is forgotten (a match never outlives the session, and the Chat page drops a room
-- past its retention, pinned or not).
local function Held()
	if held then return held end
	local t = ns.db and type(ns.db.chatMatterPins) == "table" and ns.db.chatMatterPins or {}
	local now = ns.Now()
	for key, at in pairs(t) do
		if type(key) ~= "string" or type(at) ~= "number" or now - at > Rooms.MATTER_PIN_KEEP then t[key] = nil end
	end
	held = t
	if ns.db then ns.db.chatMatterPins = next(t) and t or nil end
	return held
end
local function Hold(key, on)
	local t = Held()
	t[key] = on and ns.Now() or nil
	if ns.db then ns.db.chatMatterPins = next(t) and t or nil end
end

-- The Chat page's pin call, made here. The page tells every pin and unpin (CHAT_DYNAMIC_PIN): one
-- that does not come from here is the player's own pin button, and the pin is his from then on.
local pinning = false
local function Pin(C, key, on)
	if type(C.PinDynamicRoom) ~= "function" then return false end
	pinning = true
	local ok, done = pcall(C.PinDynamicRoom, key, on)
	pinning = false
	return ok and done == true
end
function Rooms.PinChanged(key)
	if pinning or type(key) ~= "string" or not Held()[key] then return false end
	Hold(key, false)
	return true
end

-- The player writing in the Chat page's own box (it has the keyboard): a room selected under his
-- hands would take the rest of his line, the page swapping the box's words but not its focus.
local function Writing(C)
	local f = type(C.Frame) == "function" and C.Frame() or nil
	local eb = type(f) == "table" and f.input or nil
	if type(eb) ~= "table" or type(eb.HasFocus) ~= "function" then return false end
	local ok, focused = pcall(eb.HasFocus, eb)
	return ok and focused == true
end

-- The matter's tab shown on the Chat page, the Olympus window in front: that pane, else false and why.
local function Show(m, spec)
	local C = rawget(ns, "ChatWindow")
	if type(C) ~= "table" or C.missing then return false, "window" end
	local pane
	if spec then
		if type(C.OpenDynamicRoom) ~= "function" then return false, "window" end
		pane = C.OpenDynamicRoom(spec)
		-- (A pin the player made himself stays his: only a pin made here goes with the matter.)
		local room = pane and type(C.DynamicRoom) == "function" and C.DynamicRoom(spec.key) or nil
		if pane and spec.active == true and m.keep ~= false and not (room and room.pinned) and Pin(C, spec.key, true) then Hold(spec.key, true) end
	else
		if not Rooms.Info(m.room) or not Rooms.CanAccess(m.room) then return false, "access" end
		if type(C.Open) ~= "function" or type(C.SelectLogical) ~= "function" then return false, "window" end
		local frame = C.Open()
		if frame and C.SelectLogical(m.room) then pane = frame end
	end
	if not pane then return false, "window" end
	local host = type(C.Window) == "function" and C.Window() or nil
	if host and host.Raise then host:Raise() end
	-- (Raise orders the window among those of its own strata alone: a sheet of Olympus's above it
	-- whose work this matter ends, as the Find sheet whose search found the match, hears it here.)
	ns.Fire("CHAT_MATTER_SHOWN", spec and spec.key or m.room)
	return pane
end

-- Olympus's own opening (m.auto), each matter waiting on its own (its key): with the held alerts
-- (shown when the player is back, while the matter is still open), then out of combat, then while
-- the player writes, a look at his box every WRITING_WAIT seconds; m.ifOpen, only into the Olympus
-- window the player has open (1.2.3). Its sound is the matter's own switch (m.kind: "craft" a
-- crafting deal's, else "arena"), at most one with the caller's own just before (ns.PlayAlert's
-- 15 seconds).
local function Arrive(m, key, title)
	local wait = "room:" .. key
	local pane, why = nil, "combat"
	local Try
	local function Wait()
		return ns.Alert(m.kind == "craft" and "craft" or "arena", "soft", { what = L.CHATROOM_MATTER_HELD:format(title), key = wait,
			open = function() return select(2, MatterNow(m)) == true end,
			show = function() ns.OutOfCombat(wait, Try) end })
	end
	Try = function()
		local spec, live = MatterNow(m)
		if not live then why = "over" return end
		-- (1.2.3, the King's stream: "the window opened by itself".) A matter the player did not
		-- just start (m.ifOpen: another member's claim on his request) comes only into the Olympus
		-- window he has open: closed, it stays closed (its line and sound tell it; its page opens it).
		local UI = rawget(ns, "UI")
		if m.ifOpen and not (type(UI) == "table" and type(UI.IsShown) == "function" and UI.IsShown()) then why = "closed" return end
		local C = rawget(ns, "ChatWindow")
		if type(C) == "table" and not C.missing and Writing(C) then
			why = "writing"
			if not writing[key] then
				writing[key] = true
				-- (Gone into an instance or Busy meanwhile, it waits with the held alerts after all.)
				ns.After(Rooms.WRITING_WAIT, "chat matter", function()
					writing[key] = nil
					if ns.Quiet() then Wait() else ns.OutOfCombat(wait, Try) end
				end)
			end
			return
		end
		pane, why = Show(m, spec)
	end
	if not Wait() then return false, "held" end
	if pane then return pane end
	return false, why
end

-- The Chat tab shown on the matter's room: that pane, else false and why ("held", "combat" and
-- "writing": Olympus's own opening waits; "closed": an m.ifOpen matter with the window closed;
-- "over": it is no longer open).
function Rooms.OpenMatter(m)
	if type(m) ~= "table" then return false, "matter" end
	local spec = m.spec ~= nil and MatterSpec(m) or nil
	if m.spec ~= nil and not spec then return false, "expired" end
	if not m.auto then return Show(m, spec) end
	if not MatterLive(m, spec) then return false, "over" end
	local info = not spec and Rooms.Info(m.room) or nil
	local title = spec and spec.title or info and info.label or "?"
	return Arrive(m, spec and spec.key or m.room, ns.Codec.Plain(tostring(title)))
end

-- The Arena's word that a room's matter changed (ARENA_CHAT_ROOM, one spec): a pin OpenMatter made
-- goes once the matter is no longer open, so the ended room can be removed and expires as any other.
function Rooms.MatterChanged(spec)
	if type(spec) ~= "table" or type(spec.key) ~= "string" or not Held()[spec.key] or spec.active == true then return false end
	Hold(spec.key, false)
	local C = rawget(ns, "ChatWindow")
	if type(C) == "table" and not C.missing then Pin(C, spec.key, false) end
	return true
end

ns.Comm.Handle("M2", function(dist, sender, text)
	Rooms.Receive(dist, sender, text)
end)

if ns.Consent and ns.Consent.Register then
	ns.Consent.Register({
		key = "chatrooms", label = "CONSENT_CHATROOMS", text = "CONSENT_CHATROOMS_TEXT",
		get = function() return ns.db and ns.db.chatRooms end,
		set = function(on) Rooms.SetChatOn(on) end,
	})
end

ns.On("DATA_CHANGED", Rooms.RefreshAuthority)
ns.RegisterEvent("CHAT_MSG_GUILD", Rooms.ReceiveGuild)
ns.On("INIT", Rooms.Reset)
ns.On("ARENA_CHAT_ROOM", function(spec) Rooms.MatterChanged(spec) end)
ns.On("CHAT_DYNAMIC_PIN", function(key) Rooms.PinChanged(key) end)
