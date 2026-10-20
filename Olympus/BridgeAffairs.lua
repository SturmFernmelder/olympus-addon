local ADDON, ns = ...

-- The Companion's sections for the tabs of affairs (931, Daniel: "quero as features igual do addon,
-- rankings etc"; companion/BRIDGE-SECTIONS.md): crafting, crafters, treasury, decrees, agenda,
-- notices, watch and chatRooms, in Bridge.lua's registry beside BridgeSections.lua's. Each reads only
-- what this character's own client already shows on that page, through the module's public
-- functions, with the page's own audience (the Watch's only on a moderation team client or for the
-- desk's own staff), and builds every row field by field: a field a module adds later never reaches
-- the Companion by itself. Nothing until this account accepted the Olympus Accord and while this
-- character is no member (ns.IsMember). Never chat text or a chat-strike line, a crafting deal's
-- terms or its request chat, a treasury item, a reporter's name or note, an evidence line, a
-- moderator's reason, a GUID or a BattleTag. Lists are cut from their end (the oldest, the lowest).
-- A module that errors leaves its own section nil (Bridge.GetSection's pcall); the others go on.
-- Small read-only accessors: for chatRooms, ChatWindow.Unread (the tab's unread counts) and
-- ChatRooms.KnownRecipientCount (a room's member count as the page last counted it); for notices,
-- OfficerMuster.Authorized (who may call whom, for an ended call's reach); for watch, Watch.Upheld
-- (a case a finding upheld, whose accused the stream names whole).
if type(OlympusBridge) ~= "table" or type(OlympusBridge.RegisterSection) ~= "function" then return end

local B = OlympusBridge
local L = ns.L

local CRAFT_BOARD, CRAFT_OWN = 100, 30
local CRAFTERS = 300
local DECREES, DECREE_TEXT = 30, 500
local AGENDA = 30
local NOTICES, NOTICE_TITLE, NOTICE_TEXT = 30, 60, 120
local NOTICE_ENDED_FOR = 86400 -- an ended muster stays a withdrawn notice this long
local WATCH_ROWS = 100
local ROOMS = 100

-- A loaded module (not a stand-in for a file that failed: Core.lua's StandIn marks those missing).
local function Live(name)
	local m = ns[name]
	if type(m) ~= "table" or m.missing then return nil end
	return m
end

local function Yes(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	return ok and v == true
end

local function Whole(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v < 0 then return 0 end
	return math.floor(v)
end

local function Int(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then return 0 end
	return v < 0 and -math.floor(-v) or math.floor(v)
end

-- One line of plain text: the game's escape codes taken out (a colour's code whole, a link's words
-- kept), control bytes and runs of spaces made one space, cut to `max` bytes; nil when empty.
local function Text(v, max)
	if type(v) ~= "string" then return nil end
	local s = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
		:gsub("|H.-|h(.-)|h", "%1"):gsub("|n", " ")
	s = s:gsub("[|%c]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if max and #s > max then s = ns.Cut(s, max):gsub(" $", "") end
	return s ~= "" and s or nil
end

-- A player's name as the pages show it (ns.DisplayName: the realm only when it is another's).
local function Name(v)
	if type(v) ~= "string" or v == "" then return nil end
	local ok, shown = pcall(ns.DisplayName, v)
	return Text(ok and type(shown) == "string" and shown or v, 64)
end

local function Same(a, b)
	return type(a) == "string" and type(b) == "string" and a ~= "" and ns.FullName(a):lower() == ns.FullName(b):lower()
end

-- A zone's name for a map id (Zones.NameForKey), nil for one the client cannot name.
local function Zone(mapID)
	local Z = Live("Zones")
	if not Z or type(Z.NameForKey) ~= "function" or not tonumber(mapID) then return nil end
	local ok, name = pcall(Z.NameForKey, "m" .. math.floor(tonumber(mapID)))
	if not ok or type(name) ~= "string" or name:find("^m%d+$") then return nil end
	return Text(name, 60)
end

-- Times as the server's epoch seconds: times this client stamped with its own clock (ns.Now) move by
-- the server's offset (Data.ServerTime), none where the client has no server clock.
local function Offset()
	local D = Live("Data")
	local server = D and type(D.ServerTime) == "function" and D.ServerTime() or nil
	local now = ns.Now()
	if type(server) == "number" and type(now) == "number" then return server - now end
	return 0
end
local function At(t, offset)
	t = tonumber(t)
	if not t or t ~= t then return nil end
	return Whole(t + (offset or 0))
end

-- A short, stable digest of a text (for ids that every client works out alike).
local function Digest(s)
	local h = 5381
	s = tostring(s or "")
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
	return ("%08x"):format(h)
end

-- The King's screen while the councillors' names are hidden there (ns.CouncilMasked, his stream):
-- nobody is named a councillor, as in the chats (Bridge.lua's Masked).
local function Masked()
	if type(ns.CouncilMasked) ~= "function" then return false end
	local ok, masked = pcall(ns.CouncilMasked)
	return not ok or masked == true
end

-- The role a poster speaks with, in the self section's words (BridgeSections.lua's roles): crown
-- (the King, his Steward, his Hands; and for the whole army, the King's guild's own officers),
-- council (the signed High Council), author, and for one guild alone its master (guildMaster) or
-- another of its officers (officer). On the King's screen while the councillors' names are hidden
-- (Masked) a councillor has none (nil): "council" would mark him, and the Crown's is not his.
local function RoleOf(name, scope)
	if type(name) ~= "string" or name == "" then return nil end
	local full = ns.FullName(name)
	local K, W = Live("King"), Live("Workshop")
	if Yes(ns.IsKingCharacter, full) or (K and (Yes(K.IsStewardName, full) or Yes(K.IsHandName, full))) then return "crown" end
	if Yes(ns.IsHighCouncillor, full) then
		if Masked() then return nil end
		return "council"
	end
	if W and Yes(W.IsAuthorName, full) then return "author" end
	if scope == "guild" then
		local R = Live("Roster")
		local ok, rank = false, nil
		if R and type(R.RankOf) == "function" then ok, rank = pcall(R.RankOf, full) end
		return ok and rank == 0 and "guildMaster" or "officer"
	end
	return "crown"
end

-- Registered with the Accord and membership checked first: nothing at all before them.
local function Register(name, limits, exporter)
	B.RegisterSection(name, 1, function()
		if type(ns.AccordAccepted) ~= "function" or ns.AccordAccepted() ~= true then return nil end
		if type(ns.IsMember) ~= "function" or ns.IsMember() ~= true then return nil end
		return exporter()
	end, limits)
end

---------------------------------------------------------------------------
-- crafting: the Crafters tab's request board (open cards, as every member sees them) and this
-- character's own open deals (the board's Mine and Accepted pages). Never the terms, the price,
-- the settlement or the request's chat. A card as its board line and opened card show it: the
-- item, its quantity, its guild, the "you can make it" mark, its state and age; no requester (the
-- board names none: its search alone matches him). His own deal: the same, and the other party,
-- whom the deal's chat names.
---------------------------------------------------------------------------

local TERMINAL = { completed = true, cancelled = true, expired = true }
Register("crafting", { values = 2000 }, function()
	local R = Live("CraftRequests")
	if not R or type(R.All) ~= "function" then return nil end
	local all = R.All()
	if type(all) ~= "table" then return nil end
	local off, board, own = Offset(), {}, {}
	for _, r in ipairs(all) do
		local item = type(r) == "table" and Text(r.itemName, 60)
		if item then
			local id, guild, at = Text(r.id, 24), Text(r.guild, 72), At(r.updated or r.created, off)
			if r.state == "open" and #board < CRAFT_BOARD then
				board[#board + 1] = { id = id, item = item, quantity = Whole(r.quantity), guild = guild,
					status = "open", at = at, canMake = Yes(R.CanFulfill, r) }
			end
			local asked, making = Same(r.requester, ns.me), Same(r.crafter, ns.me)
			if (asked or making) and not TERMINAL[r.state] and #own < CRAFT_OWN then
				own[#own + 1] = { id = id, item = item, quantity = Whole(r.quantity), status = Text(r.state, 16), guild = guild, at = at,
					role = asked and "requester" or "crafter", crafter = asked and Name(r.crafter) or nil,
					requester = (making and not asked) and Name(r.requester) or nil }
			end
		end
	end
	return { board = board, own = own }
end)

---------------------------------------------------------------------------
-- crafters: the directory of listed crafters (Crafters.Board, the tab's lower part): each one's
-- name, guild and professions with their skill, its cap and how many recipes he listed. The best
-- skill first, so the cut takes the lowest.
---------------------------------------------------------------------------

Register("crafters", { values = 8000 }, function()
	local C = Live("Crafters")
	if not C or type(C.Board) ~= "function" then return nil end
	local list = C.Board()
	if type(list) ~= "table" then return nil end
	local off, rows = Offset(), {}
	for _, c in ipairs(list) do
		local name = type(c) == "table" and Name(c.name)
		if name and type(c.profs) == "table" then
			local profs, best = {}, 0
			for _, p in ipairs(c.profs) do
				if type(p) == "table" and #profs < (C.PROFS_MAX or 4) then
					local key = type(C.CanonicalProfessionKey) == "function" and C.CanonicalProfessionKey(p.key, p.name) or p.key
					local label = type(C.ProfessionLabel) == "function" and C.ProfessionLabel(key, p.name) or p.name
					local skill = Whole(p.rank)
					if skill > best then best = skill end
					profs[#profs + 1] = { name = Text(label, 40) or Text(p.name, 40), skill = skill, max = Whole(p.max), recipes = Whole(p.n) }
				end
			end
			if #profs > 0 then rows[#rows + 1] = { name = name, guild = Text(c.guild, 72), at = At(c.t, off), professions = profs, best = best } end
		end
	end
	table.sort(rows, function(a, b)
		if a.best ~= b.best then return a.best > b.best end
		return a.name < b.name
	end)
	while #rows > CRAFTERS do rows[#rows] = nil end
	for _, r in ipairs(rows) do r.best = nil end
	return rows
end)

---------------------------------------------------------------------------
-- treasury: the public numbers alone, and only while the King shows the balance
-- (Treasury.PublicShows): the balance, what came in and went out, this week's donations and donors,
-- as the treasury may go out (Treasury.Report's shared, public form). Never an item, a book line, a
-- donor's name or a keeper's own book. While the King keeps the balance private: shown = false.
---------------------------------------------------------------------------

Register("treasury", nil, function()
	local T = Live("Treasury")
	if not T or type(T.PublicShows) ~= "function" or type(T.Report) ~= "function" then return nil end
	if T.PublicShows("balance") ~= true then return { shown = false } end
	local r = T.Report(true, true)
	if type(r) ~= "table" then return { shown = true } end
	return { shown = true, balanceCopper = Int(r.balance), collectedCopper = Whole(r.allIn), spentCopper = Whole(r.allOut),
		weekCopper = Whole(r.week), weekDonors = Whole(r.donors), at = At(r.t, Offset()) }
end)

---------------------------------------------------------------------------
-- decrees: the Decrees tab's list (Decree.Active, newest first): a decree's kind, whom it reaches
-- (the whole army, or one guild alone), who sent it and with what role (none for a councillor's
-- while his name is hidden: RoleOf), its zone, its words (as the page shows them: hidden by the
-- player's block terms until he shows them) and when it ends. Never a local preview
-- (Decree.Preview: nothing was sent).
---------------------------------------------------------------------------

local function PreviewDecree(d)
	return Same(d.sender, ns.me) and d.text == L.DECREE_PREVIEW_TEXT
end
-- The same id on every client that heard it: the decree's own fields, never this client's clock.
local function DecreeId(d)
	return ("decree:%s:%s:%d:%d:%d:%s"):format(tostring(d.kind):lower(), ns.Fold(ns.FullName(tostring(d.sender or "?"))),
		Whole(d.mapID), Whole((tonumber(d.x) or 0) * 1000 + 0.5), Whole((tonumber(d.y) or 0) * 1000 + 0.5), Digest(d.text))
end
local function DecreeRole(d, scope)
	if scope == "guild" then return Whole(d.rank) == 0 and d.rank ~= nil and "guildMaster" or "officer" end
	return RoleOf(d.sender, "army")
end
local function Decrees()
	local D = Live("Decree")
	if not D or type(D.Active) ~= "function" then return nil end
	local list = D.Active()
	return type(list) == "table" and list or nil, D
end

Register("decrees", { string = DECREE_TEXT }, function()
	local list, D = Decrees()
	if not list then return nil end
	local off, out = Offset(), {}
	for _, d in ipairs(list) do
		if #out >= DECREES then break end
		if type(d) == "table" and type(d.kind) == "string" and not PreviewDecree(d) then
			local scope = d.scope == "guild" and "guild" or "army"
			local veiled = d.hidden == true and not d.revealed
			local text = d.text ~= "" and (veiled and L.FILTER_WORDS_HIDDEN_SHORT or d.text) or nil
			out[#out + 1] = { id = DecreeId(d), kind = d.kind:lower(), scope = scope, role = DecreeRole(d, scope),
				title = Text(type(D.Label) == "function" and D.Label(d) or d.kind, 60), zone = Zone(d.mapID),
				text = Text(text, DECREE_TEXT), hidden = veiled or nil, by = Name(d.sender), guild = Text(d.guild, 72),
				at = At(d.t, off), expires = At(d.expires, off) }
		end
	end
	return out
end)

---------------------------------------------------------------------------
-- agenda: the week on top of the Decrees tab (Week.Section's rows): the King's current Agenda and
-- the dated entries (the army's, or this guild's alone), this guild's own events from the game's
-- calendar, and the Arena's dated fights; soonest first. Who set an entry, as the page names him,
-- and with what role. Never a signup's name (the sheet's names stay on its setter's screen).
---------------------------------------------------------------------------

local function Setter(W, e)
	if Same(e.by, ns.me) then return Name(ns.me) end
	if type(W.Setter) == "function" then
		local ok, who = pcall(W.Setter, e)
		if ok and type(who) == "string" then return Text(who, 64) end
	end
	return Name(e.by)
end

Register("agenda", nil, function()
	local W = Live("Week")
	if not W or type(W.Entries) ~= "function" then return nil end
	local now, off = ns.Now(), Offset()
	local rows = {}
	for _, e in ipairs(W.Entries(now) or {}) do
		if type(e) == "table" and not e.preview and Text(e.title, 60) then
			local scope = e.guildOnly and "guild" or "army"
			rows[#rows + 1] = { id = Text(tostring(e.id or ""), 40), title = Text(e.title, 60), zone = Text(e.zone, 40), at = At(e.at, off),
				scope = scope, source = e.agenda and "agenda" or "week", role = RoleOf(e.by, scope), by = Setter(W, e) }
		end
	end
	if type(W.GuildEvents) == "function" then
		for _, e in ipairs(W.GuildEvents(now) or {}) do
			if type(e) == "table" and Text(e.title, 60) then
				rows[#rows + 1] = { id = "calendar:" .. Whole(e.at), title = Text(e.title, 60), at = At(e.at, off), scope = "guild", source = "calendar" }
			end
		end
	end
	if type(W.Provided) == "function" then
		for _, e in ipairs(W.Provided(now) or {}) do
			if type(e) == "table" and Text(e.title, 60) then
				rows[#rows + 1] = { id = "arena:" .. Whole(e.at) .. ":" .. Digest(e.title), title = Text(e.title, 60), zone = Text(e.zone, 40),
					at = At(e.at, off), scope = "army", source = "arena" }
			end
		end
	end
	table.sort(rows, function(a, b)
		if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) < (b.at or 0) end
		return tostring(a.id) < tostring(b.id)
	end)
	while #rows > AGENDA do rows[#rows] = nil end
	return rows
end)

---------------------------------------------------------------------------
-- notices (the shape agreed with the Windows Companion): { items = { { id, kind, role, title, text,
-- zone?, guild?, at, withdrawn, audience } } }, newest first, 30 at most, only what this client holds:
--   muster  the officer musters (OfficerMuster.List: the Crown's for the whole army, this guild's
--           master's for it alone), and those that ended within a day (this client's acts log,
--           Chronicle: withdrawn, expired or replaced) as withdrawn, with the same reach and role
--   king    the decrees of the Crown for the whole army (Decree.Active), and this character's own
--           letters from the King (HonorsNet.Letters; audience "self": his alone, never to fan out)
--   council the High Council's decrees for the whole army (none on the King's screen while the
--           councillors' names are hidden: RoleOf gives such a decree no role to show)
-- An id is the same on every client that heard it ("muster:<sequence>:<poster key>", a decree's own
-- fields); a letter's is this character's own.
---------------------------------------------------------------------------

local function MusterTitle(title)
	local F = Live("Filter")
	if F and Yes(F.Hides, title) then return L.FILTER_WORDS_HIDDEN_SHORT end
	return title
end

-- A muster's role: the channel's calls are the Crown's alone (OfficerMuster's Authorized: the King,
-- his Steward, his Hands, the King's guild's master), whoever else the poster is; a guild's, its
-- master's. The same on every client, whatever the King's screen hides.
local function MusterRole(audience) return audience == "guild" and "guildMaster" or "crown" end

-- An ended muster's reach. The acts log keeps no guild and no distribution, and it is this
-- account's on the realm group (ns.rdb), whichever character heard the call: the reach is the one
-- the poster has now under the rule his call was heard by (OfficerMuster.Authorized), the channel's
-- first as Muster.CanPost chooses it: the whole army for the Crown; this character's guild alone,
-- named, for its master as this roster has him. Anything else (a call another character of this
-- account heard in another guild, a role lost since, the other faction's call) is no notice.
local function EndedReach(M, by, faction)
	if type(M.Authorized) ~= "function" or faction ~= (ns.faction == "Horde" and "H" or ns.faction == "Alliance" and "A" or nil) then return nil end
	local mine = type(GetGuildInfo) == "function" and GetGuildInfo("player") or nil
	local king = type(ns.KingGuildName) == "function" and ns.KingGuildName() or nil
	if Yes(M.Authorized, by, mine, "CHANNEL") or (king ~= mine and Yes(M.Authorized, by, king, "CHANNEL")) then return "army" end
	if Yes(M.Authorized, by, mine, "GUILD") then return "guild", mine end
	return nil
end

local function Musters(items, off)
	local M = Live("OfficerMuster")
	if not M or type(M.List) ~= "function" then return false end
	for _, row in ipairs(M.List() or {}) do
		if type(row) == "table" and type(row.by) == "string" and tonumber(row.seq) then
			local audience = row.dist == "GUILD" and "guild" or "army"
			local who = Name(row.by) or "?"
			local by = audience == "guild" and L.OFFICER_MUSTER_BY_GUILD and L.OFFICER_MUSTER_BY_GUILD:format(who, tostring(row.guild or "?"))
				or (L.OFFICER_MUSTER_BY and L.OFFICER_MUSTER_BY:format(who)) or who
			items[#items + 1] = { id = ("muster:%d:%s"):format(Whole(row.seq), ns.Fold(row.by)), kind = "muster",
				role = MusterRole(audience), title = Text(MusterTitle(row.title), NOTICE_TITLE),
				text = Text(by, NOTICE_TEXT), zone = Zone(row.zone), guild = audience == "guild" and Text(row.guild, 72) or nil,
				at = Whole(row.at), withdrawn = false, audience = audience }
		end
	end
	-- Those that ended: the acts log keeps each once (its id: muster:<faction>:<poster key>:<sequence>).
	local C = Live("Chronicle")
	local now = ns.Now() + off
	for _, e in ipairs(C and type(C.Entries) == "function" and C.Entries() or {}) do
		local faction, key, seq
		if type(e) == "table" and e.kind == "muster" and type(e.id) == "string" and type(e.by) == "string" then
			faction, key, seq = e.id:match("^muster:([AH]):(.+):(%d+)$")
		end
		local st = key and (tonumber(e.st) or At(e.t, off))
		if st and now - st <= NOTICE_ENDED_FOR then
			local audience, guild = EndedReach(M, e.by, faction)
			if audience then
				items[#items + 1] = { id = ("muster:%d:%s"):format(Whole(seq), key), kind = "muster", role = MusterRole(audience),
					title = Text(MusterTitle(e.words or L.OFFICER_MUSTER_TITLE), NOTICE_TITLE), text = Text(e.what, NOTICE_TEXT),
					guild = audience == "guild" and Text(guild, 72) or nil, at = Whole(st), withdrawn = true, audience = audience }
			end
		end
	end
	return true
end

local function DecreeNotices(items, off)
	local list, D = Decrees()
	if not list then return false end
	for _, d in ipairs(list) do
		local role = type(d) == "table" and type(d.kind) == "string" and d.scope ~= "guild" and not PreviewDecree(d) and DecreeRole(d, "army")
		if role then
			local veiled = d.hidden == true and not d.revealed
			items[#items + 1] = { id = DecreeId(d), kind = role == "council" and "council" or "king", role = role,
				title = Text(type(D.Label) == "function" and D.Label(d) or d.kind, NOTICE_TITLE),
				text = Text(veiled and L.FILTER_WORDS_HIDDEN_SHORT or d.text, NOTICE_TEXT), zone = Zone(d.mapID),
				at = At(d.t, off), withdrawn = false, audience = "army" }
		end
	end
	return true
end

-- The King's letters to this character (HonorsNet: queued once per honour, kept to read again in his
-- profile's Edit), in their words, one line. Their times are already the server's (Arena.Now).
local function Letters(items)
	local H = Live("HonorsNet")
	if not H or type(H.Letters) ~= "function" or type(H.LetterText) ~= "function" then return false end
	for _, x in ipairs(H.Letters() or {}) do
		if type(x) == "table" and type(x.key) == "string" and tonumber(x.t) then
			local text, title = H.LetterText(x.key)
			if type(text) == "string" then
				-- (A Slayer letter's key is long and names its Horde player: its digest instead.)
				local key = #x.key <= 40 and x.key:find("^[%w%-]+$") and x.key or Digest(x.key)
				items[#items + 1] = { id = ("letter:%s:%d"):format(key, Whole(x.t)), kind = "king", role = "crown",
					title = Text(type(title) == "string" and title or L.HONOR_LETTER_HEAD, NOTICE_TITLE) or Text(L.HONOR_LETTER_HEAD, NOTICE_TITLE),
					text = Text(text, NOTICE_TEXT), at = Whole(x.t), withdrawn = false, audience = "self" }
			end
		end
	end
	return true
end

Register("notices", { string = 160 }, function()
	local off, items = Offset(), {}
	local any = Musters(items, off)
	any = DecreeNotices(items, off) or any
	any = Letters(items) or any
	if not any then return nil end
	table.sort(items, function(a, b)
		if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
		return a.id < b.id
	end)
	local out, seen = {}, {}
	for _, item in ipairs(items) do
		if #out >= NOTICES then break end
		if not seen[item.id] then seen[item.id], out[#out + 1] = true, item end
	end
	return { items = out }
end)

---------------------------------------------------------------------------
-- watch: The Watch's staff pages, only on a moderation team client (WatchChat.InRoom) or for the
-- desk's own staff (Watch.DeskShown: the guild's officers and Watchers, the King, the High Council,
-- the author). Counts, and the lists the pages show as their own gates let them: the cases (the
-- reported name, open or handled, how many reported it and for what, when), the guild's records
-- (status, warnings, timeout), the Tabards' inspected players and the untabarded list. Never a
-- reporter's name or note, an evidence line, a moderator's reason or name, a chat line or a
-- chat-strike line, a BattleTag or a GUID. On the King's stream (Masked, as Watch.OnStream) the
-- cases as the page shows them there (Watch.lua's CaseRow): the accused's name cut short until a
-- finding upheld the case (Watch.Accused, Watch.Upheld), and neither how many reported him nor
-- when (alts could inflate it), so no open reports' count either.
---------------------------------------------------------------------------

-- The accused's name as the case's row shows it: on the stream cut short until a finding upheld
-- the case (a module without Watch.Accused or Watch.Upheld: cut short always).
local function AccusedName(W, c, stream)
	if not stream then return Name(c.target) end
	local upheld = type(W.Upheld) == "function" and W.Upheld(c) == true
	local shown = type(W.Accused) == "function" and Text(W.Accused(c.target, upheld), 64)
	return shown or Text(ns.MaskName(Name(c.target) or "?"), 64)
end

local function CaseRows(W, out, open, handled, council, stream)
	for _, list in ipairs({ open or {}, handled or {} }) do
		for _, c in ipairs(list) do
			if #out >= WATCH_ROWS then return end
			if type(c) == "table" and type(c.target) == "string" then
				out[#out + 1] = { name = AccusedName(W, c, stream), open = c.open == true, reports = not stream and Whole(c.reporters) or nil,
					categories = type(W.CatsText) == "function" and type(c.cats) == "table" and Text(W.CatsText(c.cats), 120) or nil,
					firstAt = not stream and Whole(c.firstAt) or nil, lastAt = not stream and Whole(c.lastAt) or nil, council = council or nil }
			end
		end
	end
end

local function Untabarded()
	local I, K = Live("Inspect"), Live("King")
	if not I then return nil end
	if K and (Yes(K.IsKing) or Yes(K.Preview)) then return type(I.ShameList) == "function" and I.ShameList() or nil end
	if type(I.ShameOpen) == "function" and not Yes(I.ShameOpen) then return nil end
	local shame = type(I.Shame) == "function" and I.Shame() or nil
	return type(shame) == "table" and shame.list or nil
end

Register("watch", { values = 4000 }, function()
	local W = Live("Watch")
	if not W then return nil end
	local WC = Live("WatchChat")
	local team = WC ~= nil and Yes(WC.InRoom, ns.me)
	if not team and not Yes(W.DeskShown) then return nil end
	local stream = Masked()
	local counts = { reportsOpen = not stream and 0 or nil, casesOpen = 0, casesHandled = 0 }
	local out = { counts = counts, cases = {}, records = {}, inspected = {}, untabarded = {} }
	local function CountCases(open, handled)
		counts.casesOpen, counts.casesHandled = counts.casesOpen + #(open or {}), counts.casesHandled + #(handled or {})
		if stream then return end
		for _, c in ipairs(open or {}) do counts.reportsOpen = counts.reportsOpen + Whole(type(c) == "table" and c.reporters) end
	end
	if Yes(W.CanRead) then
		local open, handled = W.Cases()
		CountCases(open, handled)
		CaseRows(W, out.cases, open, handled, nil, stream)
		local banned, watched, warned = 0, 0, 0
		for _, e in ipairs(W.Records() or {}) do
			if type(e) == "table" and type(e.name) == "string" then
				local status = e.status == "ban" and "ban" or e.status == "watch" and "watch" or Whole(e.warnings) > 0 and "warn" or "clear"
				if status == "ban" then banned = banned + 1 elseif status == "watch" then watched = watched + 1 elseif status == "warn" then warned = warned + 1 end
				if #out.records < WATCH_ROWS then
					local untilAt = Whole(e.timeoutUntil)
					out.records[#out.records + 1] = { name = Name(e.name), status = status, warnings = Whole(e.warnings),
						interventions = Whole(e.interventions), timeoutUntil = untilAt > 0 and untilAt or nil,
						at = Whole(e.updatedAt or e.statusAt or e.warningAt) }
				end
			end
		end
		counts.banned, counts.watched, counts.warned = banned, watched, warned
	end
	if Yes(W.CouncilDeskShown) and type(W.CouncilCases) == "function" then
		local open, handled = W.CouncilCases()
		CountCases(open, handled)
		CaseRows(W, out.cases, open, handled, true, stream)
	end
	local I = Live("Inspect")
	if I and type(I.Summary) == "function" and (type(W.TabardsShown) ~= "function" or Yes(W.TabardsShown)) then
		local s, off = I.Summary(), Offset()
		local c = type(s) == "table" and type(s.counts) == "table" and s.counts or {}
		counts.inspected, counts.tabarded = Whole(s and s.total), Whole(c.GUILD)
		counts.untabarded, counts.otherTabard = Whole(c.NONE), Whole(c.OTHER)
		counts.tabardsCaught = counts.untabarded + counts.otherTabard
		for _, p in ipairs(type(s) == "table" and s.players or {}) do
			if #out.inspected >= WATCH_ROWS then break end
			if type(p) == "table" and type(p.name) == "string" then
				out.inspected[#out.inspected + 1] = { name = Text(ns.ShortName(p.name), 64), guild = Text(p.guild, 72),
					status = Text(p.status or "UNKNOWN", 16), level = tonumber(p.level) and Whole(p.level) or nil, at = At(p.t, off) }
			end
		end
		local list = Untabarded() or {}
		counts.wallOfShame = #list
		for _, p in ipairs(list) do
			if #out.untabarded >= WATCH_ROWS then break end
			if type(p) == "table" and type(p.name) == "string" then out.untabarded[#out.untabarded + 1] = { name = Text(p.name, 64), guild = Text(p.guild, 72) } end
		end
	end
	return out
end)

---------------------------------------------------------------------------
-- chatRooms: the Chat tab's rooms this character is in (the Olympus channels his rank reads, his
-- guild, his role rooms), each with its member count where the page counts one (his guild's roster;
-- a role room's audience as the page last counted it, ChatRooms.KnownRecipientCount) and the tab's
-- unread count (ChatWindow.Unread). No chat text, no sender, no line: Daniel has not decided on
-- the chats yet. Never a room a preview of another role lists (its rows are disabled), a crafting
-- deal's or a game's room (their names say who deals or plays with whom).
---------------------------------------------------------------------------

local function GuildCount()
	if type(GetNumGuildMembers) ~= "function" then return nil end
	local ok, n = pcall(GetNumGuildMembers)
	n = ok and tonumber(n) or nil
	return n and n > 0 and Whole(n) or nil
end

Register("chatRooms", nil, function()
	local C, R = Live("Channels"), Live("ChatRooms")
	if not C and not R then return nil end
	local CW = Live("ChatWindow")
	local function Unread(key)
		if not CW or type(CW.Unread) ~= "function" then return 0 end
		return Whole(CW.Unread(key))
	end
	local rows = {}
	if C and type(C.CanUse) == "function" and type(C.TIERS) == "table" then
		for _, t in ipairs(C.ORDER or {}) do
			local tier = C.TIERS[t]
			if tier and C.CanUse(t) == true then
				rows[#rows + 1] = { id = t, room = Text(L[tier.label], 60) or t, kind = "channel", unread = Unread(t) }
			end
		end
	end
	if R and type(R.Info) == "function" and type(R.CanAccess) == "function" then
		local guild = R.Info("guild")
		if type(guild) == "table" and R.CanAccess("guild") == true then
			rows[#rows + 1] = { id = "guild", room = Text(guild.label, 60) or "Guild", kind = "guild", members = GuildCount(), unread = Unread("guild") }
		end
		for _, info in ipairs(type(R.Options) == "function" and R.Options("role") or {}) do
			if #rows >= ROOMS then break end
			if type(info) == "table" and type(info.id) == "string" and not info.disabled and Text(info.label, 60) then
				local n = type(R.KnownRecipientCount) == "function" and R.KnownRecipientCount(info.id) or nil
				rows[#rows + 1] = { id = Text(info.id, 40), room = Text(info.label, 60), kind = "role",
					members = tonumber(n) and Whole(n) or nil, unread = Unread(info.id) }
			end
		end
	end
	while #rows > ROOMS do rows[#rows] = nil end
	return rows
end)
