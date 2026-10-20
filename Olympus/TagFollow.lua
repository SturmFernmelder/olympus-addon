local ADDON, ns = ...
local L = ns.L

-- A sanction follows the BattleTag (the author, 2026-10-19: "Com essa sensação, se alguém entrar com
-- a mesma battle tag que uma pessoa foi banida, alguma censura, a mesma coisa vai ser aplicada nesse
-- novo personagem."). The Olympus Accord's BattleTag (Accord.lua) is one Battle.net account, so one
-- person: a sanction on one of his characters reaches the others.
--
-- A follow points at a sanction, it never copies one: "the BattleTag of code H follows character S's
-- sanction". Every client resolves it against S's sanction as it stands at that moment, so a lift,
-- an end or a newer word on S changes it everywhere at once, whoever gives it (a Steward or a Hand
-- who holds no BattleTag included). Two kinds:
--   N  a net-off word on a character (Moderation.lua, O1 c): the followed characters are hidden;
--   T  a moderator's timeout or hold in Olympus or guild scope (WatchChat.lua, MD T): the followed
--      characters are timed out (a guild's only inside that guild).
-- Never a guild's net-off or exile (they aim at guilds), nor a chat warning's hold (ChatStrikes.lua:
-- self-held; it follows once a moderator decides the case with a timeout).
--
-- The code: the first 8 bytes of SHA-256("olympus-tag-2|" .. the folded BattleTag .. "|" .. the
-- game account's follow key), 16 hex digits. The key (Accord.AccountKey: 16 random hex digits made
-- once per game account, at its first accept) reaches the moderation team alone, with the tag (BT),
-- so nobody else can tell from a code whose BattleTag it is, nor match a friend's. And a copied
-- BattleTag gives a code no other account has: a modified addon that sends someone else's tag can
-- only ever reach its own account. One code is one game account's characters (on one computer: the
-- key is in its saved variables). It is what lets an ordinary client recognise its own BattleTag
-- without anyone sending it a BattleTag.
--
-- Who gives one: a moderation team member's client (Accord.TeamMember) that holds the sanctioned
-- player's BattleTag and may give that sanction itself (N: Moderation.CanIssue; T: an Olympus
-- moderator's level, WatchChat.ActorLevel), at most at the weight of the sanction and of its own,
-- and only when every character of that code it knows is within that reach (never the King's: his
-- game account's tag reaches only the King and the author, Accord.MayTell, and a code with the
-- King's own character on it is never followed). It gives it right after its own sanction (G1),
-- when the BattleTag arrives later (G2), and for the others' sanctions (G3: a sweep, once online
-- WARMUP, one a minute), always on that player's own code. Such an automatic follow never re-dates,
-- raises or replaces a word kept here, and is dated at the sanction's own time, so a stop or a
-- freeing word given since stays above it. Another game account that sent the same BattleTag (two
-- computers, two licences, or a copied tag) has another code: a team member follows it there with
-- one click in The Watch. A follow is stopped there, or by `/oly accord unfollow <name>`: his other
-- characters are free, his own sanction stays.
--   TF~1~<N|T>~<1 follow|0 stop>~<server time>~<code>~<sanctioned Name-Realm>~<giver Name-Realm>
-- On the Olympus channel only, logged (the server keeps it), first hand only (the giver's own
-- client: the server stamps the sender), its giver's client repeating it every REPEAT while the
-- sanction stands (a stop every STOP_EVERY, for KEEP). Rate-limited per sender and for all. A
-- word weighs its giver's standing, checked again each minute (Recheck): a giver who lost it takes
-- his words with him. A team client that holds the sanctioned character's BattleTag takes a code
-- only of his own, his previous one, or another account's of the same BattleTag.
--
-- Who keeps it: a team client every word (it holds the BattleTags to match); any other client only
-- the words made from its own player's BattleTag (TagFollow.Mine, read from his own game, cached
-- for the session alone), and then without the code (ns.rdb.tagFollow keeps no code there): the
-- Accord's privacy rule (8 bits of the tag on disk, Accord.lua). While Battle.net can't be read the
-- words wait in memory and are matched once it can.
--
-- What it does: his own client applies it to himself (his chats, his powers, games, map and
-- Crafting, as every sanction: WatchChat.Barred) and tells him in Olympus's own pop-up, never who
-- gave it; a team client hides the followed characters it holds the BattleTag of and marks them in
-- The Watch. Nothing goes out by name on a match alone, and a by-name word shows in every member's
-- Decrees. Only when a followed character's addon shows it does not apply it to itself does a team
-- client that may give that sanction by name give it (DERIVED_REASON): his Olympus chat line
-- (M1, M2, EC: never the game's own guild chat) hidden by the follow, then the follow on the wire
-- here (sent or heard) within ONLINE_WINDOW after such a line (he was online to receive it; the
-- giver's client sends it again on his first such line), then still another line EVADE_AFTER
-- later. At most DERIVE_HOUR an hour, never above the weight the follow reaches him with, never a
-- guild's timeout, and taken back once the follow ends. Never on the King's game account
-- (ns.db.kingAccount), never on anyone whose own rank or protection reaches the follow's weight
-- (his own client also remembers it for the account, ns.db.tagShield). An "on" word or a lift on
-- the followed character's own name frees him until the sanction he was freed of changes. Never
-- logged: a tag or a code; the log names the kind, the sanctioned character and the outcome.

local TF = {}
ns.TagFollow = TF

TF.PREFIX = "olympus-tag-2|"
TF.KINDS = { N = true, T = true }
TF.KEEP = 30 * 86400        -- a follow lapses this long after it was given; a stop is kept (and repeated) this long
TF.STALE = 3 * 86400        -- a follow its giver did not repeat this long lapses (his own client keeps it while he may give it)
TF.REPEAT = 300             -- its giver's client repeats a follow this often (plus its JITTER)...
TF.JITTER = 90
TF.STOP_EVERY = 1800        -- ...and a stop this often
TF.PER_TICK = 2             -- words one client repeats a minute at most
TF.REPEATS_A_MINUTE = 20    -- a long list is repeated less often (Moderation.REPEATS_A_MINUTE)
TF.WARMUP = 600             -- online this long before a client repeats a word held unheard, or follows by itself
TF.DATE_AHEAD = 60
TF.RATE, TF.RATE_ALL = 10, 60 -- a minute: from one sender; from all senders with standing
TF.MAX = 300                -- words a team client keeps
TF.MINE_MAX = 20            -- words another client keeps (its own BattleTag's)
TF.BUFFER_MAX = 300         -- words held in memory while this client's own BattleTag can't be read
TF.SWEEP_EVERY = 600        -- a team client looks for the others' sanctions it may follow
TF.AUTO_EVERY = 60          -- ...and gives one at most this often
TF.EVADE_AFTER = 600        -- a followed character still chatting this long after the follow reached him: his addon does not apply it
TF.ONLINE_WINDOW = 60       -- the follow on the wire this soon after his hidden line: he was online to receive it
TF.RESEND_GAP = 60          -- its giver's client sends a follow again for a hidden line at most this often
TF.CODES_PER_SOURCE = 4     -- codes one client follows a sanctioned character's sanction on by itself, at most
TF.DERIVE_HOUR = 6          -- by-name words one client gives that way in an hour at most
-- (The author's decision: false gives a by-name word only on that evidence; true gives it on the
-- match alone, each minute, to every character a follow reaches here, which would list a possibly
-- innocent player, one whose BattleTag a modified addon sent, in every member's Decrees.)
TF.DERIVE_ON_MATCH = false
TF.NOTICE_WAIT = 30         -- after login, the player is told
TF.DERIVED_REASON = "same BattleTag as a sanctioned player" -- (English on the wire, as every reason)
TF.random = math.random     -- (tests)

local NONE = {}
local stats = { taken = 0, same = 0, refused = 0, other = 0, buffered = 0, sent = 0, given = 0, stopped = 0, derived = 0, lifted = 0, rate = 0 }
local refusedWhy = {}
local rates, rateAll = {}, {}
local buffer = {}       -- words heard while this client's own BattleTag could not be read (memory only)
local memo, memoN = {}, 0 -- [raw name] = code or false: a team client's lookups (TagFollow.Bump empties it)
local kingMemo = {}     -- [code] = true when a row of it is the King's own character (TagFollow.Bump empties it)
local index             -- the kept words by code, rebuilt after any change
local busy = 0          -- a resolver running (Guarded): a nested one resolves no follow
local sentNow = {}      -- keys this client sent this session
local session = { mine = nil, read = false, loginAt = nil, told = {}, under = false, queue = {}, queued = {},
	lastAuto = -math.huge, lastSweep = -math.huge, derivedAt = {}, evidence = {}, resent = {} }

local function Live(t) return type(t) == "table" and not t.missing and t or nil end
local function Acc() return Live(ns.Accord) end
local function Mod() return Live(ns.Moderation) end
local function WC() return Live(ns.WatchChat) end
local function Clock() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or ns.Now() end
local function Now() return ns.Now() end
local function Fold(s) return ns.Fold(tostring(s or "")) end
local function Full(name) return ns.FullName(ns.Normal(name)) end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and a ~= "" and Fold(a) == Fold(b) end
local function Me(name) return type(name) == "string" and type(ns.me) == "string" and Fold(Full(name)) == Fold(ns.me) end
local function Red(s) return "|cffff6060" .. tostring(s or "") .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end

-- A character's name as the server writes it ("Name-Realm"), or nil.
local function CharName(input)
	local M = Mod()
	local name = M and M.CharName and M.CharName(input)
	if type(name) ~= "string" or name == "" or #name > 72 or name:find("[~|%c]") then return nil end
	return name
end

local function ShownName(name)
	local shown = ns.DisplayName(name) or tostring(name or "?")
	if ns.CouncilMasked and ns.CouncilMasked() then return ns.MaskName(shown) end
	return shown
end

---------------------------------------------------------------------------
-- The code
---------------------------------------------------------------------------

local function IsCode(h) return type(h) == "string" and #h == 16 and h:find("^[0-9a-f]+$") ~= nil end
TF.IsCode = IsCode

-- A BattleTag's code with its game account's follow key (see the top), or nil when either is not one.
function TF.Hash(tag, key)
	local A = ns.Accord
	local shape = type(A) == "table" and A.TAG_SHAPE or "^[^#~|%c]+#%d+$"
	if type(tag) ~= "string" or tag == "" or #tag > 64 or not tag:match(shape) then return nil end
	if type(key) ~= "string" or #key ~= 16 or not key:find("^[0-9a-f]+$") then return nil end
	local h = ns.Sign.SHA256(TF.PREFIX .. ns.Fold(tag) .. "|" .. key)
	local out = {}
	for i = 1, 8 do out[i] = ("%02x"):format(h:byte(i)) end
	return table.concat(out)
end

---------------------------------------------------------------------------
-- What this client keeps (ns.rdb.tagFollow: per realm group and faction, as the net-off words)
---------------------------------------------------------------------------

local function Store(make)
	local r = ns.rdb
	if type(r) ~= "table" then return nil end
	local s = r.tagFollow
	if type(s) ~= "table" or s.v ~= 1 or type(s.f) ~= "table" then
		if not make then return nil end
		s = { v = 1, f = {}, derived = {} }
		r.tagFollow = s
		index = nil
	end
	if type(s.derived) ~= "table" then s.derived = {} end
	return s
end
TF.Store = Store

-- A team client: it holds the BattleTags (Accord's store; Accord.Guard drops it off the team).
-- Read directly, never through Accord.TeamMember: that asks WatchChat, which asks this file.
local function TeamClient()
	local r = ns.rdb
	local b = type(r) == "table" and r.battletags
	return type(b) == "table" and type(b.rows) == "table"
end
TF.TeamClient = TeamClient

local function KeyOf(kind, hash, source) return kind .. ":" .. hash .. ":" .. Fold(source) end
local function MineKey(kind, source) return kind .. ":me:" .. Fold(source) end

-- The kept words by code, and this client's own (mine), with how many follows of each kind.
local function Index()
	local s = Store(false)
	if index and index.store == s then return index end
	index = { store = s, N = 0, T = 0, byHash = {}, mine = {} }
	for _, F in pairs(s and s.f or NONE) do
		if type(F) == "table" and TF.KINDS[F.kind] then
			if F.on then index[F.kind] = index[F.kind] + 1 end
			if F.mine then index.mine[#index.mine + 1] = F
			elseif IsCode(F.hash) then
				local list = index.byHash[F.hash] or {}
				index.byHash[F.hash] = list
				list[#list + 1] = F
			end
		end
	end
	return index
end
local function Dirty() index = nil end

-- Any follow of this kind kept at all (cheap: the hot paths ask it first).
function TF.Any(kind) return (Index()[kind] or 0) > 0 end

-- After a change of the BattleTags or the follows: the lookups start again.
function TF.Bump()
	wipe(memo)
	wipe(kingMemo)
	memoN = 0
	Dirty()
end

-- A team client's code for `name` (Accord.HashOf), remembered per raw name until TagFollow.Bump.
local function HashFor(name)
	local m = memo[name]
	if m ~= nil then return m or nil end
	local A = ns.Accord
	local h = type(A) == "table" and not A.missing and type(A.HashOf) == "function" and A.HashOf(name) or nil
	if memoN >= 3000 then wipe(memo) memoN = 0 end
	memo[name], memoN = h or false, memoN + 1
	return h
end

-- A code one of whose rows here is the King's own character: his game account's, never followed
-- (his alts' rows reach only the author's client, which holds his own row too).
local function KingCode(h)
	local m = kingMemo[h]
	if m ~= nil then return m end
	local A, M = ns.Accord, ns.Moderation
	local yes = false
	if type(A) == "table" and not A.missing and type(A.Rows) == "function" and type(M) == "table" and not M.missing then
		for _, r in ipairs(A.Rows(h)) do
			if M.IsKing(r.name) then yes = true break end
		end
	end
	kingMemo[h] = yes
	return yes
end
TF.KingCode = KingCode

---------------------------------------------------------------------------
-- This account's own code (never on disk on an ordinary client)
---------------------------------------------------------------------------

local function DropMine()
	local s = Store(false)
	if not s then return 0 end
	local n = 0
	for key, F in pairs(s.f) do
		if type(F) == "table" and F.mine then s.f[key] = nil n = n + 1 end
	end
	if n > 0 then Dirty() end
	return n
end

local Take -- (below)

-- Battle.net read again (Accord.Check: login, loading screens, Battle.net's events; and the minute's
-- tick while it could not be read). changed: Accord saw this account's BattleTag change, so the
-- follows kept as its own (no code to tell) were another BattleTag's.
function TF.Refresh(changed)
	local A = Acc()
	local tag = A and A.ReadTag and A.ReadTag()
	local key = A and A.AccountKey and A.AccountKey(true)
	local was = session.mine
	session.mine, session.read = tag and TF.Hash(tag, key) or nil, true
	if changed or (was and session.mine and was ~= session.mine) then
		if DropMine() > 0 then ns.Log("tag follow: this account's BattleTag changed, its follows dropped") end
	end
	-- The words that waited for it.
	local mine = TF.Mine()
	if mine and #buffer > 0 then
		local list = buffer
		buffer = {}
		for _, F in ipairs(list) do if F.hash == mine then Take(F) end end
	end
	return session.mine
end

-- This account's code, read once a session (Refresh again on Battle.net's events), or nil.
function TF.Mine()
	if not session.read then TF.Refresh() end
	return session.mine
end

---------------------------------------------------------------------------
-- The follows that reach a name, and how far
---------------------------------------------------------------------------

local function MayGive(kind)
	local A, M, W = Acc(), Mod(), WC()
	if not ns.me or not ns.IsMember() or not A or not M or not W or not A.TeamMember() then return false end
	if kind == "N" then return M.CanIssue() == true end
	if kind == "T" then return (tonumber(W.ActorLevel(ns.me)) or 0) >= W.LEVEL.mod end
	return false
end
TF.MayGive = MayGive

local function Given(F) return type(F) == "table" and not F.mine and IsCode(F.hash) and Me(F.by) end

-- A follow in force: given within KEEP, repeated within STALE (its giver's own client keeps it while
-- he may give it). Whether its sanction stands is the resolver's (Moderation.ByTag, WatchChat.ByTag).
local function Alive(F, now, clock)
	if type(F) ~= "table" or not F.on then return false end
	if (clock or Clock()) - (tonumber(F.at) or 0) > TF.KEEP then return false end
	if (now or Now()) - (tonumber(F.heard) or 0) > TF.STALE and not (Given(F) and MayGive(F.kind)) then return false end
	return true
end
TF.Alive = Alive

-- Does this client resolve follows for `name` at all (cheap)? Its own player, or any name on a team client.
function TF.Watching(name, kind)
	if not TF.Any(kind) or type(name) ~= "string" or name == "" then return false end
	return TeamClient() or Me(name)
end

-- The follows in force of `kind` on the BattleTag of `name` (its own player's on this client, or
-- the BattleTag a team client holds for him), never one whose sanctioned character is `name`.
function TF.Sources(name, kind)
	if not TF.Any(kind) or type(name) ~= "string" or name == "" then return NONE end
	local x = Index()
	local full = Full(name)
	local now, clock = Now(), Clock()
	local out
	local function Add(list)
		for _, F in ipairs(list or NONE) do
			if F.kind == kind and Alive(F, now, clock) and not Same(F.source, full) then
				out = out or {}
				out[#out + 1] = F
			end
		end
	end
	local team = TeamClient()
	if Me(full) then
		Add(x.mine)
		local mine = TF.Mine()
		if mine then Add(x.byHash[mine]) end
	elseif team then
		local h = HashFor(full)
		if h and not KingCode(h) then Add(x.byHash[h]) end
	end
	return out or NONE
end

-- How high `name` stands against a follow of `kind` (a follow applies only above it): his own
-- rank or protection; on his own client also the King's game account (always) and the highest a
-- character of this account held within the last TEAM_GRACE (ns.db.tagShield).
function TF.Shield(name, kind)
	local M, W = Mod(), WC()
	local level
	if kind == "N" then level = M and tonumber(M.TargetRank(name)) or 0
	else level = W and tonumber(W.ProtectLevel(name)) or 0 end
	if not Me(name) or type(ns.db) ~= "table" then return level end
	if ns.db.kingAccount == true then return math.max(level, 99) end
	local m = ns.db.tagShield
	local age = type(m) == "table" and Now() - (tonumber(m.at) or -math.huge) or math.huge
	local keep = Acc() and ns.Accord.TEAM_GRACE or 2 * 86400
	if age >= 0 and age <= keep then level = math.max(level, tonumber(kind == "N" and m.n or m.t) or 0) end
	return level
end

-- This account remembers how high its characters stand (the shield of an alt nobody linked).
local function NoteShield()
	if type(ns.db) ~= "table" or not ns.me then return end
	local M, W = Mod(), WC()
	local n = M and tonumber(M.TargetRank(ns.me)) or 0
	local t = W and tonumber(W.ProtectLevel(ns.me)) or 0
	if n <= 0 and t <= 0 then return end
	local m = ns.db.tagShield
	local fresh = type(m) == "table" and Now() - (tonumber(m.at) or -math.huge) <= (Acc() and ns.Accord.TEAM_GRACE or 2 * 86400)
	ns.db.tagShield = { n = math.max(n, fresh and tonumber(m.n) or 0), t = math.max(t, fresh and tonumber(m.t) or 0), at = Now() }
end
TF.NoteShield = NoteShield

-- Runs a resolver; nested inside another (WatchChat.ProtectLevel asks IsMod, which asks Barred,
-- which asks the timeouts, which ask the shield...) it resolves no follow: nil.
function TF.Guarded(fn, ...)
	if busy > 0 then return nil end
	busy = busy + 1
	local ok, a, b, c = pcall(fn, ...)
	busy = busy - 1
	if not ok then
		if ns.CaptureError then ns.CaptureError("tag follow", a) end
		return nil
	end
	return a, b, c
end
function TF.Busy() return busy > 0 end

---------------------------------------------------------------------------
-- The sanctions a follow points at
---------------------------------------------------------------------------

-- The sanction on `source` itself (never one through a follow: a follow never follows a follow),
-- and its weight: N a net-off word on him, T a timeout or hold in Olympus or guild scope.
local function Direct(kind, source)
	if kind == "N" then
		local M = Mod()
		local w = M and M.Hidden and M.Hidden(source, true)
		if type(w) == "table" and w.off and w.kind == "c" then return w, tonumber(M.Weight(w)) or 0 end
		return nil
	end
	local W = WC()
	local e = W and W.TimeoutOf and W.TimeoutOf(source, nil, true)
	if type(e) == "table" and (e.scope == "O" or e.scope == "G") then return e, tonumber(e.weight) or 0 end
	return nil
end
TF.Direct = Direct

-- Within `weight`'s reach: N one whose rank (his linked names' too) is below it, T one whose
-- protection is.
local function Reaches(kind, name, weight)
	local M, W = Mod(), WC()
	if not M or not W then return false end
	if M.IsKing(name) then return false end
	if kind == "N" then
		local t = tonumber(M.TargetRank(name)) or 0
		return t == 0 or weight > t
	end
	return (tonumber(W.ProtectLevel(name)) or 0) < weight
end

-- One of the derived by-name words, or a word given for one: never followed again.
local function Derived(name, sanction)
	local s = Store(false)
	if s and s.derived[Fold(Full(name))] then return true end
	return type(sanction) == "table" and sanction.reason == TF.DERIVED_REASON
end

---------------------------------------------------------------------------
-- Keeping a word
---------------------------------------------------------------------------

local function Changed(F)
	Dirty()
	ns.Fire(F.kind == "N" and "NETOFF_CHANGED" or "WATCHCHAT_CHANGED", F.kind == "N" and F or "F", F.source)
	ns.Fire("DATA_CHANGED")
end

-- Room for one more: a stop goes first, then the oldest of the lowest weight; never one weighing
-- more than the new word (Moderation's MakeRoom rule).
local function MakeRoom(s, mine, weight)
	local n = 0
	for _, e in pairs(s.f) do if (e.mine == true) == (mine == true) then n = n + 1 end end
	if n < (mine and TF.MINE_MAX or TF.MAX) then return true end
	local drop, d
	for key, e in pairs(s.f) do
		if (e.mine == true) == (mine == true) and (tonumber(e.weight) or 0) <= weight then
			local better = not d or (not e.on and d.on)
				or (e.on == d.on and (e.weight < d.weight or (e.weight == d.weight and e.at < d.at)))
			if better then drop, d = key, e end
		end
	end
	if not drop then return false end
	s.f[drop] = nil
	return true
end

local function SameWord(a, b) return a.at == b.at and a.on == b.on and Same(a.by, b.by) end
-- Two words of the same weight and second: every client keeps the same one.
local function Outranks(e, kept)
	local x, y = Fold(e.by), Fold(kept.by)
	if x ~= y then return x < y end
	return e.on and not kept.on
end

-- Does word F replace the kept one (every client the same)? Two follows or two stops: the higher
-- weight, then the newer, then Outranks. A follow and a stop: the stop when it is the newer (a
-- decision given after that follow, whatever its weight; an automatic follow is dated at its
-- sanction's time, so it never passes a stop given since), and also when it weighs more than a
-- newer follow (a follow by hand from lower down never passes a stop from higher up).
local function Wins(F, kept)
	if F.on ~= kept.on then
		local stop, follow = F.on and kept or F, F.on and F or kept
		local stopWins
		if stop.at ~= follow.at then stopWins = stop.at > follow.at or stop.weight > follow.weight
		else stopWins = stop.weight >= follow.weight end
		return (F == stop) == stopWins
	end
	if F.weight ~= kept.weight then return F.weight > kept.weight end
	if F.at ~= kept.at then return F.at > kept.at end
	return Outranks(F, kept)
end

-- Our own word is newer, or from higher up: our next round answers with it.
local function AnswerOwn(kept)
	if Given(kept) and MayGive(kept.kind) then kept.heard = Now() - TF.REPEAT - TF.JITTER - 1 end
end

-- Where a heard word goes on this client: its key, and whether it is kept as this account's own.
local function Place(F)
	if TeamClient() then return KeyOf(F.kind, F.hash, F.source), false end
	local mine = TF.Mine()
	if not mine then return nil, "buffer" end
	if F.hash == mine then return MineKey(F.kind, F.source), true end
	return nil, "other"
end

-- "taken", "same" (a repeat), "stopped", "older", "tie", "outranked", "full", "buffered" or "other"
-- (Wins: a follow dated before a stop never replaces it, whatever its weight).
Take = function(F)
	local key, mine = Place(F)
	if not key then
		if mine == "buffer" then
			if #buffer >= TF.BUFFER_MAX then table.remove(buffer, 1) end
			F.heard = F.heard or Now()
			buffer[#buffer + 1] = F
			stats.buffered = stats.buffered + 1
			return true, "buffered"
		end
		stats.other = stats.other + 1
		return false, "other"
	end
	local s = Store(true)
	if not s then return false, "store" end
	local kept = s.f[key]
	if type(kept) == "table" then
		if SameWord(F, kept) then
			kept.heard, kept.wired = Now(), Now()
			stats.same = stats.same + 1
			return true, "same"
		end
		if not Wins(F, kept) then
			AnswerOwn(kept)
			if F.on and not kept.on then return false, "stopped" end
			if F.weight < kept.weight then return false, "outranked" end
			return false, F.at < kept.at and "older" or "tie"
		end
	elseif not MakeRoom(s, mine, F.weight) then
		return false, "full"
	end
	F.heard, F.wired = Now(), Now()
	F.firstHeard = (type(kept) == "table" and kept.on and F.on and kept.firstHeard) or Now()
	if mine then F.hash, F.mine = nil, true end
	s.f[key] = F
	stats.taken = stats.taken + 1
	ns.Log("tag follow: %s on %s %s, taken", F.kind, F.source, F.on and "followed" or "stopped") -- (never the code)
	Changed(F)
	return true, "taken"
end

---------------------------------------------------------------------------
-- The word on the channel
---------------------------------------------------------------------------

local function Wire(F)
	return ("TF~1~%s~%s~%d~%s~%s~%s"):format(F.kind, F.on and "1" or "0", F.at, F.hash, F.source, F.by)
end
TF.Wire = Wire

local function Send(F)
	local C = ns.Comm
	local msg = Wire(F)
	if #msg > 255 or type(C) ~= "table" or type(C.Send) ~= "function" then return false end
	local key = KeyOf(F.kind, F.hash, F.source)
	local guardKey = "tf:" .. key
	F.heard, F.wired = Now(), Now() -- (wired: on the wire here, the evidence's clock)
	sentNow[key] = true
	stats.sent = stats.sent + 1
	-- At the game's send: still a member who may give it, and this exact word still the one kept.
	return C.Send("CHANNEL", msg, guardKey, nil, true, nil, { owner = TF, key = guardKey, permit = function(owner, k, dist, _, payload)
		if owner ~= TF or k ~= guardKey or dist ~= "CHANNEL" or payload ~= msg then return false, "guard" end
		if not ns.IsMember() or not MayGive(F.kind) then return false, "revoked" end
		local s = Store(false)
		local now = s and s.f[key]
		if type(now) ~= "table" or now.at ~= F.at or now.on ~= F.on or not Same(now.by, ns.me) then return false, "revoked" end
		return true
	end }) ~= false
end

local function Budget(list, max)
	local now = Now()
	for i = #list, 1, -1 do if now - list[i] >= 60 then table.remove(list, i) end end
	if #list >= max then stats.rate = stats.rate + 1 return false end
	list[#list + 1] = now
	return true
end
local function Rate(sender)
	local key = Fold(sender)
	local list = rates[key] or {}
	rates[key] = list
	return Budget(list, TF.RATE)
end

local function Refuse(why, sender)
	stats.refused = stats.refused + 1
	refusedWhy[why] = (refusedWhy[why] or 0) + 1
	if sender then ns.Log("tag follow from %s refused: %s", tostring(sender), why) end
	return false, why
end

-- A sender's standing for a word of `kind`, as this client knows him: his weight, or nil. On the
-- moderation team (WatchChat.InRoom), and N one who gives net-off words (his rank), T an Olympus
-- moderator or above (his level). A sanctioned one has neither.
local function Standing(kind, name)
	local W, M = WC(), Mod()
	if not W or not M or not W.InRoom(name) then return nil end
	if kind == "N" then
		if not M.IsIssuer(name) then return nil end
		local r = tonumber(M.Rank(name)) or 0
		return r > 0 and r or nil
	end
	local lvl = tonumber(W.ActorLevel(name)) or 0
	return lvl >= W.LEVEL.mod and lvl or nil
end
TF.Standing = Standing

-- May `hash` carry `source`'s sanction here? Anywhere but a team client that holds his BattleTag;
-- there only his code, the one he had before, another game account's code of the same BattleTag (a
-- team member's click), or the new code of a character that had his (his BattleTag changed).
local function CodeOf(source, hash)
	if not TeamClient() then return true end
	local own = HashFor(source)
	if not own or own == hash then return true end
	local A = Acc()
	if not A then return true end
	if A.PrevHashOf and A.PrevHashOf(source) == hash then return true end
	local tag = A.TagOf and A.TagOf(source)
	for _, c in ipairs(tag and A.CodesOf and A.CodesOf(tag) or NONE) do if c == hash then return true end end
	for _, r in ipairs(A.Rows and A.Rows(hash) or NONE) do if r.pcode == own then return true end end
	return false
end

-- TF, heard on the channel (Comm dispatches it to members alone). True and how it was kept, or
-- false and why not.
function TF.Handle(dist, sender, text)
	if dist ~= "CHANNEL" then return Refuse("lane", sender) end
	local C = ns.Comm
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and C and C.DeliveredLogged and not C.DeliveredLogged() then return Refuse("unlogged", sender) end
	if type(text) ~= "string" or #text > 255 then return Refuse("shape", sender) end
	local kind, on, at, hash, source, by = text:match("^TF~1~([NT])~([01])~(%d+)~(%x+)~([^~]+)~([^~]+)$")
	if not kind or not IsCode(hash) then return Refuse("shape", sender) end
	sender = CharName(sender)
	if not sender then return Refuse("sender") end
	local src, giver = CharName(source), CharName(by)
	if not src or src ~= source or not giver or giver ~= by then return Refuse("shape", sender) end
	-- First hand only: the server stamps the sender, and nobody passes another's word on.
	if not Same(giver, sender) then return Refuse("relay", sender) end
	local M = Mod()
	if not M or M.IsKing(src) or Same(src, sender) then return Refuse("source", sender) end
	if not Rate(sender) then return false, "rate" end
	local weight = Standing(kind, sender)
	if not weight then return Refuse("standing", sender) end
	if not Budget(rateAll, TF.RATE_ALL) then return false, "rate" end
	at = tonumber(at)
	local clock = Clock()
	if not at or at < 1 or at > clock + TF.DATE_AHEAD or clock - at > TF.KEEP then return Refuse("time", sender) end
	-- (Its weight, as this client knows him now: never computed again while it resolves.)
	if not Reaches(kind, src, weight) then return Refuse("rank", sender) end
	if not CodeOf(src, hash) then return Refuse("code", sender) end
	return Take({ kind = kind, on = on == "1", at = at, hash = hash, source = src, by = sender, weight = weight })
end

---------------------------------------------------------------------------
-- Giving one (a team member's client)
---------------------------------------------------------------------------

local function MyWeight(kind)
	local M, W = Mod(), WC()
	if kind == "N" then return M and tonumber(M.Rank(ns.me)) or 0 end
	return W and tonumber(W.ActorLevel(ns.me)) or 0
end

-- Keeps this client's own word (a follow or a stop) under the rules every client applies.
local function KeepOwn(s, key, F)
	local kept = s.f[key]
	if type(kept) == "table" then
		if not Wins(F, kept) then return false, "outranked" end
	elseif not MakeRoom(s, false, F.weight) then
		return false, "full"
	end
	F.heard = Now()
	F.firstHeard = (type(kept) == "table" and kept.on and F.on and kept.firstHeard) or Now()
	s.f[key] = F
	Changed(F)
	return true
end

-- Every character of that code (one game account) this client knows, within the reach of `cap`;
-- and how many besides the sanctioned one, and how many other codes of the same BattleTag it holds
-- (other game accounts: a team member's click follows it there, never this by itself).
local function Group(kind, hash, source, cap)
	local A = Acc()
	local rows = A and A.Rows and A.Rows(hash) or NONE
	local others = 0
	if not Reaches(kind, source, cap) then return nil, "reach" end
	for _, r in ipairs(rows) do
		if not Reaches(kind, r.name, cap) then return nil, "reach" end
		if not Same(r.name, source) then others = others + 1 end
	end
	local elsewhere = 0
	local tag = rows[1] and rows[1].tag or (A and A.TagOf and A.TagOf(source))
	for _, c in ipairs(tag and A and A.CodesOf and A.CodesOf(tag) or NONE) do if c ~= hash then elsewhere = elsewhere + 1 end end
	return others, elsewhere
end
TF.Group = Group

-- `source`'s sanction of `kind` (his own, given by anyone) follows his BattleTag. opts.hash: that
-- code instead of his own here (opts.moved: the new code of a character that had his; otherwise
-- another game account's, only by hand); opts.manual: a team member's own click (another game
-- account's code, or one a stop holds), dated now. An automatic one never touches a word kept here
-- (a follow stands: "held"; a stop: "stopped"), is dated at the sanction's own time (at most KEEP -
-- STALE ago), and goes on at most CODES_PER_SOURCE codes of one sanctioned character. True, how
-- many other characters it reaches here, "held" when a follow already stands, and how many other
-- codes of that BattleTag are known here; false and why not.
function TF.Give(kind, source, opts)
	opts = opts or NONE
	if not TF.KINDS[kind] then return false, "kind" end
	source = CharName(source)
	if not source then return false, "name" end
	if not MayGive(kind) then return false, "authority" end
	local A, M = Acc(), Mod()
	if M.IsKing(source) or Me(source) then return false, "source" end
	local own = A.HashOf and A.HashOf(source)
	local hash = opts.hash or own
	if not IsCode(hash) then return false, "tag" end
	if hash ~= own and not opts.manual and not opts.moved then return false, "contested" end
	if KingCode(hash) then return false, "reach" end
	local sanction, sw = Direct(kind, source)
	if not sanction then return false, "none" end
	if not opts.manual and Derived(source, sanction) then return false, "derived" end
	local mine = MyWeight(kind)
	local cap = math.min(mine, sw)
	if cap <= 0 then return false, "authority" end
	local others, elsewhere = Group(kind, hash, source, cap)
	if not others then return false, elsewhere end
	local s = Store(true)
	if not s then return false, "store" end
	local key = KeyOf(kind, hash, source)
	local kept = s.f[key]
	local clock = math.floor(Clock())
	local at
	if opts.manual then
		-- (By hand: a word dated now, so it passes a stop given before it, unless a follow from
		-- higher up already stands.)
		if type(kept) == "table" and kept.on and kept.weight > mine and Alive(kept) then return true, others, "held", elsewhere end
		at = clock
		if type(kept) == "table" and kept.at >= at then at = kept.at + 1 end
	else
		if type(kept) == "table" then
			if kept.on then return true, others, "held", elsewhere end
			return false, "stopped"
		end
		local n = 0
		for _, F in pairs(s.f) do
			if F.on and F.kind == kind and Given(F) and Same(F.source, source) then n = n + 1 end
		end
		if n >= TF.CODES_PER_SOURCE then return false, "many" end
		at = math.min(clock, math.max(math.floor(tonumber(sanction.at) or clock), clock - TF.KEEP + TF.STALE))
	end
	local F = { kind = kind, on = true, at = at, hash = hash, source = source, by = ns.me, weight = mine }
	local ok, why = KeepOwn(s, key, F)
	if not ok then return false, why end
	Send(F)
	stats.given = stats.given + 1
	ns.Log("tag follow: %s on %s given (%d other characters)", kind, source, others)
	return true, others, nil, elsewhere
end

-- By hand (/oly accord follow, The Watch): on his own code, then on every other game account's
-- code of his BattleTag known here. True and how many other characters it reaches, or false and
-- why not (the last refusal).
function TF.GiveByHand(kind, source)
	local A = Acc()
	source = CharName(source)
	if not source or not A then return false, "name" end
	local codes, seen = {}, {}
	local own = A.HashOf and A.HashOf(source)
	if own then codes[1], seen[own] = own, true end
	local tag = A.TagOf and A.TagOf(source)
	for _, c in ipairs(tag and A.CodesOf and A.CodesOf(tag) or NONE) do
		if not seen[c] then seen[c], codes[#codes + 1] = true, c end
	end
	if #codes == 0 then return false, "tag" end
	local done, total, last = false, 0, nil
	for _, c in ipairs(codes) do
		local ok, n = TF.Give(kind, source, { manual = true, hash = c })
		if ok then
			done = true
			total = total + (tonumber(n) or 0)
		else
			last = n
		end
	end
	if done then return true, total end
	return false, last
end

-- A team member stops the follows of `source`'s sanction (his other characters are free, his own
-- sanction stays). True and how many; false and why not.
function TF.Stop(kind, source, quiet)
	source = CharName(source)
	if not source then return false, "name" end
	local kinds = kind and { kind } or { "N", "T" }
	local s = Store(false)
	local n, why = 0, "none"
	for _, k in ipairs(kinds) do
		if not MayGive(k) then
			why = "authority"
		else
			local mine = MyWeight(k)
			local list = {}
			for key, F in pairs(s and s.f or NONE) do
				if F.kind == k and F.on and not F.mine and IsCode(F.hash) and Same(F.source, source) then list[#list + 1] = { key = key, F = F } end
			end
			for _, x in ipairs(list) do
				if x.F.weight > mine then
					why = "rank"
				else
					local at = math.max(math.floor(Clock()), x.F.at + 1)
					local stop = { kind = k, on = false, at = at, hash = x.F.hash, source = x.F.source, by = ns.me, weight = mine }
					if KeepOwn(s, x.key, stop) then
						Send(stop)
						n = n + 1
						stats.stopped = stats.stopped + 1
						ns.Log("tag follow: %s on %s stopped", k, source)
					end
				end
			end
		end
	end
	if n == 0 then return false, why end
	if not quiet then ns.Print(L.ACCORD_FOLLOW_STOPPED:format(ShownName(source))) end
	return true, n
end

-- G1: right after this client's own sanction (Moderation.Set, WatchChat.Act): its follow, and the
-- giver told (nothing when no BattleTag of him is known here); another game account's code of the
-- same BattleTag waits for his click.
function TF.AfterSanction(kind, name, reason)
	if reason == TF.DERIVED_REASON or Derived(name) then return false end
	local A = Acc()
	if not (A and A.HashOf and A.HashOf(name)) then return false end
	local ok, n, _, elsewhere = TF.Give(kind, name)
	if ok then
		ns.Print(L.ACCORD_FOLLOW_DONE:format(n))
		if (tonumber(elsewhere) or 0) > 0 then ns.Print(Gold(L.ACCORD_FOLLOW_CONTESTED)) end
	elseif n == "reach" then ns.Print(L.ACCORD_FOLLOW_SKIPPED) end
	return ok
end

-- G2: a BattleTag a team client just kept (Accord.HandleTag, which keeps its code and the code he
-- had before). A sanctioned sender's follows go; and when his code changed (another BattleTag, or
-- his account's key), the follows on the old code go to the new one too (CODES_PER_SOURCE: a
-- modified addon that sends tag after tag fills no list).
function TF.OnTag(name, row)
	if type(row) ~= "table" then return end
	TF.Bump()
	local A = Acc()
	local code = A and A.HashOf and A.HashOf(name)
	if not code then return end
	local old = IsCode(row.pcode) and row.pcode ~= code and row.pcode or nil
	local s = Store(false)
	for kind in pairs(TF.KINDS) do
		if MayGive(kind) then
			if Direct(kind, name) then TF.Give(kind, name) end
			if old and s then
				local list = {}
				for _, F in pairs(s.f) do if F.kind == kind and F.hash == old and Alive(F) then list[#list + 1] = F.source end end
				for _, source in ipairs(list) do TF.Give(kind, source, { hash = code, moved = true }) end
			end
		end
	end
end

-- G3: the others' sanctions this team client may follow, one at a time.
local function Queue(kind, name)
	if not TeamClient() or type(name) ~= "string" then return end
	local key = kind .. "|" .. Fold(name)
	if session.queued[key] then return end
	session.queued[key] = true
	session.queue[#session.queue + 1] = { kind = kind, name = name }
end
TF.Queue = Queue

local function Sweep()
	local A, M, W = Acc(), Mod(), WC()
	if not A or not M or not W then return end
	for _, e in ipairs(M.List and M.List() or NONE) do
		if e.kind == "c" and e.off and HashFor(e.name) then Queue("N", e.name) end
	end
	local s = W.Store and W.Store()
	local clock = Clock()
	for _, list in pairs(s and s.timeouts or NONE) do
		for _, e in ipairs(type(list) == "table" and list or NONE) do
			if type(e) == "table" and (e.scope == "O" or e.scope == "G") and W.EndOf(e) > clock and HashFor(e.name) then Queue("T", e.name) end
		end
	end
end

local function Auto()
	local now = Now()
	if session.loginAt and now - session.loginAt < TF.WARMUP then return end
	if now - session.lastAuto < TF.AUTO_EVERY or not TeamClient() then return end
	if now - session.lastSweep >= TF.SWEEP_EVERY then
		session.lastSweep = now
		Sweep()
	end
	while #session.queue > 0 do
		local q = table.remove(session.queue, 1)
		session.queued[q.kind .. "|" .. Fold(q.name)] = nil
		if MayGive(q.kind) then
			local ok, _, how = TF.Give(q.kind, q.name)
			if ok and how ~= "held" then
				session.lastAuto = now
				return true
			end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The player's own notices
---------------------------------------------------------------------------

-- Told in Olympus's own pop-up, once a follow and sanction a session, never who gave it; and once
-- it is over.
function TF.TellMine()
	if not ns.me or not ns.IsMember() then return end
	if not session.under and not TF.Any("N") and not TF.Any("T") then return end
	local M, W = Mod(), WC()
	local under = false
	if M and M.SelfOff then
		local e, src, via = M.SelfOff()
		if e and via == "tag" then
			under = true
			local mark = "N:" .. Fold(src) .. ":" .. tostring(e.at)
			if not session.told[mark] then
				session.told[mark] = true
				local reason = e.reason ~= "" and e.reason or "-"
				local text = L.ACCORD_FOLLOW_YOU_NETOFF:format(reason, M.When(e))
				if W and W.TellDecision then W.TellDecision(text) end
				ns.Print(Red(text)) -- (as a net-off word's own notice: the whole of it, the pop-up to copy)
			end
		end
	end
	if W and W.SelfTimeout then
		local e, via = W.SelfTimeout()
		if e and via then
			under = true
			local mark = "T:" .. Fold(via) .. ":" .. Fold(e.by) .. ":" .. tostring(e.seq)
			if not session.told[mark] then
				session.told[mark] = true
				W.RecordFollowed(e)
				W.TellTimeout(e, true)
			end
		end
	end
	if session.under and not under then ns.Print(L.ACCORD_FOLLOW_YOU_BACK) end
	session.under = under
end

---------------------------------------------------------------------------
-- A followed character whose addon does not apply it (evidence), and its by-name word
---------------------------------------------------------------------------

-- Gives `sender` the sanction a follow (`kind`, of `source`'s) reaches him with here, by name, when
-- this client may (once for him, at most DERIVE_HOUR an hour). onMatch: without the evidence (the
-- caller, Evidence, holds that). Never on a code of the King's account (TagFollow.Sources holds
-- none), never a guild's timeout (it binds inside that guild alone, and a by-name word from here
-- would bind everywhere), never above the weight the follow reaches him with (a by-name word weighs
-- its giver's standing on every client: a client standing higher leaves it to one that does not),
-- and never a second by-name timeout for the same evasion.
local function Derive(sender, kind, source, onMatch)
	sender = CharName(sender)
	if not sender or not TF.KINDS[kind] or not TeamClient() then return false, "team" end
	local s = Store(false)
	if not s then return false, "store" end
	local key = Fold(sender)
	if s.derived[key] then return false, "derived" end
	local F
	for _, f in ipairs(TF.Sources(sender, kind)) do
		if Same(f.source, source) and (not F or (tonumber(f.firstHeard) or 0) < (tonumber(F.firstHeard) or 0)) then F = f end
	end
	if not F then return false, "follow" end
	local now = Now()
	local hour = session.derivedAt
	for i = #hour, 1, -1 do if now - hour[i] >= 3600 then table.remove(hour, i) end end
	if #hour >= TF.DERIVE_HOUR then return false, "rate" end
	local M, W = Mod(), WC()
	local ok
	if kind == "N" then
		if not (M and M.CanIssue()) then return false, "authority" end
		local w, sw = Direct("N", F.source)
		if not w then return false, "follow" end
		local applied = math.min(sw, tonumber(F.weight) or 0)
		local mine = tonumber(M.Rank(ns.me)) or 0
		if mine > applied then return false, "weight" end
		local t = tonumber(M.TargetRank(sender)) or 0
		if t > 0 and mine <= t then return false, "reach" end
		ok = M.Set("c", sender, true, TF.DERIVED_REASON)
	else
		if not W then return false, "authority" end
		local direct = W.TimeoutOf(sender, nil, true)
		if type(direct) == "table" and direct.reason == TF.DERIVED_REASON then return false, "derived" end
		local scope, mine = W.CanModerate(sender)
		if scope ~= "O" then return false, "authority" end
		local e, _, applied = TF.Guarded(W.ByTag, sender)
		if not e then return false, "follow" end
		if e.scope ~= "O" then return false, "guild" end
		if (tonumber(mine) or 0) > (tonumber(applied) or 0) then return false, "weight" end
		ok = W.Act("T", sender, { untilAt = tonumber(e.untilAt) or 0, reason = TF.DERIVED_REASON })
	end
	if not ok then return false, "refused" end
	s.derived[key] = { kind = kind, name = sender, source = F.source, at = math.floor(Clock()) }
	hour[#hour + 1] = now
	stats.derived = stats.derived + 1
	ns.Log("tag follow: %s %s while followed, %s given by name", sender, onMatch and "matched" or "still chatting", kind)
	ns.Fire("DATA_CHANGED")
	return true
end

-- Channels.Admit dropped an Olympus chat line of `sender` (M1, M2, EC: his own addon sent it) that
-- only a follow (`kind`, of `source`'s sanction) hides here. It is evidence that his addon does not
-- apply the follow only once the follow reached him: the follow on the wire here (sent or heard)
-- within ONLINE_WINDOW after one such line (he was online then), and another line EVADE_AFTER
-- after that. On a line before that, its giver's client sends the follow again (once in
-- RESEND_GAP), so his next line can show it; an honest addon then sends no more. True when this
-- client gave him the sanction by name; false and why not.
function TF.Evidence(sender, kind, source)
	sender = CharName(sender)
	if not sender or not TF.KINDS[kind] or not TeamClient() or type(source) ~= "string" then return false, "team" end
	local list = {}
	for _, f in ipairs(TF.Sources(sender, kind)) do if Same(f.source, source) then list[#list + 1] = f end end
	if #list == 0 then return false, "follow" end
	local now = Now()
	local key = kind .. "|" .. Fold(sender)
	local ev = session.evidence[key]
	if not ev or not Same(ev.source, source) then
		session.evidenceN = (session.evidenceN or 0) + 1
		if session.evidenceN > TF.MAX then wipe(session.evidence) session.evidenceN = 1 end -- (memory only, bounded)
		ev = { source = source }
		session.evidence[key] = ev
	end
	local prev = ev.line
	if not ev.proof and prev then
		for _, f in ipairs(list) do
			local w = tonumber(f.wired)
			if w and w >= prev and w - prev <= TF.ONLINE_WINDOW and w <= now and (not ev.proof or w < ev.proof) then ev.proof = w end
		end
	end
	ev.line = now
	if not ev.proof then
		for _, f in ipairs(list) do
			local k = KeyOf(f.kind, f.hash, f.source)
			if Given(f) and MayGive(f.kind) and now - (session.resent[k] or -math.huge) >= TF.RESEND_GAP then
				session.resent[k] = now
				Send(f)
				break
			end
		end
		return false, "unproven"
	end
	if now - ev.proof < TF.EVADE_AFTER then return false, "early" end
	return Derive(sender, kind, source, false)
end

-- DERIVE_ON_MATCH (off: see the top): each minute, every character whose BattleTag this team client
-- holds and a follow reaches is given that sanction by name.
local function MatchTick()
	local r = ns.rdb
	local b = type(r) == "table" and r.battletags
	if not TF.DERIVE_ON_MATCH or type(b) ~= "table" or type(b.rows) ~= "table" then return 0 end
	local n = 0
	for _, row in pairs(b.rows) do
		if type(row) == "table" and type(row.name) == "string" then
			local kind, source = TF.ReachedBy(row.name)
			if kind and Derive(row.name, kind, source, true) then n = n + 1 end
		end
	end
	return n
end

-- Each minute: a derived word whose follow no longer reaches its character is taken back.
local function DerivedTick()
	local s = Store(false)
	if not s then return end
	local M, W = Mod(), WC()
	if not M or not W then return end
	for key, d in pairs(s.derived) do
		if type(d) ~= "table" or not CharName(d.name) or not TF.KINDS[d.kind] then
			s.derived[key] = nil
		else
			local still
			if d.kind == "N" then still = TF.Guarded(M.ByTag, d.name) else still = TF.Guarded(W.ByTag, d.name) end
			if not still then
				local done = true
				if d.kind == "N" then
					local own = M.OwnWord(d.name)
					if type(own) == "table" and own.off and own.reason == TF.DERIVED_REASON and Me(own.by) then
						done = M.Set("c", d.name, false, "") == true
					end
				else
					local e = W.TimeoutOf(d.name, nil, true)
					if type(e) == "table" and e.reason == TF.DERIVED_REASON and Me(e.by) then done = W.Lift(d.name) == true end
				end
				if done or Clock() - (tonumber(d.at) or 0) > TF.KEEP then
					s.derived[key] = nil
					stats.lifted = stats.lifted + 1
					ns.Log("tag follow: the by-name %s on %s taken back, its follow ended", d.kind, d.name)
				end
			end
		end
	end
end
TF.DerivedTick = DerivedTick

---------------------------------------------------------------------------
-- Keeping the list alive
---------------------------------------------------------------------------

-- Words past KEEP go; a follow unheard for STALE too, but on its giver's own client while he may
-- give it (he repeats it, after WARMUP).
function TF.Prune()
	local s = Store(false)
	local now, clock, dropped = Now(), Clock(), 0
	if s then
		local may = {}
		for key, F in pairs(s.f) do
			local dead = type(F) ~= "table" or clock - (tonumber(F.at) or 0) > TF.KEEP
			if not dead and F.on and now - (tonumber(F.heard) or 0) > TF.STALE then
				if Given(F) then
					if may[F.kind] == nil then may[F.kind] = MayGive(F.kind) end
					dead = not may[F.kind]
				else
					dead = true
				end
			end
			if dead then s.f[key] = nil dropped = dropped + 1 end
		end
		for key, d in pairs(s.derived) do if type(d) ~= "table" or clock - (tonumber(d.at) or 0) > TF.KEEP then s.derived[key] = nil end end
	end
	for i = #buffer, 1, -1 do if now - (tonumber(buffer[i].heard) or 0) > TF.STALE then table.remove(buffer, i) end end
	for k, list in pairs(rates) do
		local live = false
		for _, t in ipairs(list) do if now - t < 60 then live = true break end end
		if not live then rates[k] = nil end
	end
	if dropped > 0 then
		Dirty()
		ns.Fire("DATA_CHANGED")
	end
	return dropped
end

-- Every minute: its giver's client repeats its own follows while their sanction stands here (and
-- its stops), a few at a time; a word held unheard from an earlier session waits WARMUP.
function TF.Repeat()
	local s = Store(false)
	if not s then return 0 end
	local now, clock, sent = Now(), Clock(), 0
	local warm = session.loginAt == nil or now - session.loginAt >= TF.WARMUP
	local n = 0
	for _ in pairs(s.f) do n = n + 1 end
	local spread = n * 60 / TF.REPEATS_A_MINUTE
	local may = {}
	for key, F in pairs(s.f) do
		if sent >= TF.PER_TICK then break end
		if Given(F) and clock - F.at <= TF.KEEP then
			if may[F.kind] == nil then may[F.kind] = MayGive(F.kind) end
			F.jitter = F.jitter or TF.random(0, TF.JITTER)
			local every = math.max(F.on and TF.REPEAT or TF.STOP_EVERY, spread)
			local age = now - (tonumber(F.heard) or 0)
			if may[F.kind] and age >= every + F.jitter and (warm or sentNow[key] or age <= TF.STALE)
				and (not F.on or (Direct(F.kind, F.source) and Reaches(F.kind, F.source, F.weight))) then
				Send(F)
				sent = sent + 1
			end
		end
	end
	return sent
end

-- Once a minute: each word weighs its giver's standing now (Standing: a councillor off the council,
-- a moderator no longer named, a giver now sanctioned), never more than when it came; a giver with
-- none takes it with him, as a net-off word weighs its giver's rank now (Moderation.Weight). His
-- next word, once he stands again, brings it back.
function TF.Recheck()
	local s = Store(false)
	if not s then return 0 end
	local cache, changed = {}, {}
	for key, F in pairs(s.f) do
		if type(F) == "table" and TF.KINDS[F.kind] then
			local ck = F.kind .. "|" .. Fold(F.by)
			local w = cache[ck]
			if w == nil then
				w = Standing(F.kind, F.by) or false
				cache[ck] = w
			end
			if not w then
				s.f[key] = nil
				changed[#changed + 1] = F
				ns.Log("tag follow: %s on %s dropped, its giver no longer stands", F.kind, tostring(F.source))
			elseif w < (tonumber(F.weight) or 0) then
				F.weight = w
				changed[#changed + 1] = F
			end
		end
	end
	for _, F in ipairs(changed) do Changed(F) end
	return #changed
end

-- `/oly accord forget` (Accord.Forget): the words that carry a forgotten BattleTag's codes go here,
-- so this client never sends them again (the others lapse them after STALE unheard).
function TF.Forget(codes)
	local s = Store(false)
	if not s or type(codes) ~= "table" then return 0 end
	local n = 0
	for key, F in pairs(s.f) do
		if type(F) == "table" and type(F.hash) == "string" and codes[F.hash] then
			s.f[key] = nil
			n = n + 1
		end
	end
	if n > 0 then
		Dirty()
		ns.Log("tag follow: %d words dropped with a forgotten BattleTag", n)
		ns.Fire("DATA_CHANGED")
	end
	return n
end

function TF.Tick()
	TF.Prune()
	TF.Recheck()
	NoteShield()
	if not session.mine then TF.Refresh() end
	TF.TellMine()
	DerivedTick()
	MatchTick()
	TF.Repeat()
	Auto()
end

---------------------------------------------------------------------------
-- The Watch (Accord.TeamLines, Accord.ProfileLines): a team client's own marks
---------------------------------------------------------------------------

local function KindText(F)
	if F.kind == "N" then return L.ACCORD_FOLLOW_KIND_N end
	local e = Direct("T", F.source)
	if e and (tonumber(e.untilAt) or 0) > 0 then return L.ACCORD_FOLLOW_KIND_T:format(date and date("%Y-%m-%d %H:%M", e.untilAt) or tostring(e.untilAt)) end
	return L.ACCORD_FOLLOW_KIND_H
end

-- Does a follow reach `name` here, and through whose sanction: the kind and the source.
local function ReachedBy(name)
	local M, W = Mod(), WC()
	if M and M.Hidden then
		local _, src, via = M.Hidden(name)
		if via == "tag" then return "N", src end
	end
	if W and W.TimeoutOf then
		local e, src = W.TimeoutOf(name)
		if e and src then return "T", src end
	end
	return nil
end
TF.ReachedBy = ReachedBy

-- The lines under a BattleTag's group on the BattleTags page: each follow in force on any of its
-- codes (a click stops it), and when two game accounts sent it (two codes) each sanction not
-- followed on one of them (a click follows it there).
function TF.GroupLines(g, shown)
	local out = {}
	if type(g) ~= "table" or type(g.rows) ~= "table" or not g.rows[1] then return out end
	shown = shown or ShownName
	local A = Acc()
	local codes = A and A.CodesOf and A.CodesOf(g.tag) or NONE
	if #codes == 0 then return out end
	local followed, listed = {}, {}
	for _, hash in ipairs(codes) do
		for _, F in ipairs(Index().byHash[hash] or NONE) do
			if Alive(F) and Direct(F.kind, F.source) then
				followed[F.kind .. Fold(F.source) .. "|" .. hash] = true
				local fk = F.kind .. Fold(F.source)
				if not listed[fk] then
					listed[fk] = true
					local data = { kind = F.kind, source = F.source }
					local may = MayGive(F.kind)
					out[#out + 1] = { indent = 1, text = Red(L.ACCORD_FOLLOW_GROUP:format(shown(F.source), KindText(F))),
						tooltip = function(tt)
							tt:AddLine(L.ACCORD_FOLLOW_GROUP:format(shown(F.source), KindText(F)), 1, 0.4, 0.4, true)
							tt:AddLine(L.ACCORD_FOLLOW_BY:format(shown(F.by), date and date("%Y-%m-%d %H:%M", F.at) or tostring(F.at)), 0.7, 0.7, 0.7)
							if may then tt:AddLine(L.ACCORD_FOLLOW_STOP_TIP, 0.6, 0.6, 0.6, true) end
						end,
						onClick = may and function() ns.ShowDialog("OLYMPUS_TAGFOLLOW_STOP", shown(F.source), nil, data) end or nil }
				end
			end
		end
	end
	-- Two game accounts sent this BattleTag (two codes): each sanction not followed on the other
	-- account's code waits for a click, which follows it there.
	if #codes >= 2 then
		for _, r in ipairs(g.rows) do
			for kind in pairs(TF.KINDS) do
				if MayGive(kind) and Direct(kind, r.name) then
					for _, hash in ipairs(codes) do
						if not followed[kind .. Fold(r.name) .. "|" .. hash] and not KingCode(hash) then
							local name = r.name
							followed[kind .. Fold(r.name) .. "|" .. hash] = true
							out[#out + 1] = { indent = 1, text = Gold(L.ACCORD_FOLLOW_CONTESTED), wrap = true,
								onClick = function()
									local ok, why = TF.Give(kind, name, { manual = true, hash = hash })
									if ok then ns.Print(L.ACCORD_FOLLOW_DONE:format(why))
									elseif why == "reach" then ns.Print(L.ACCORD_FOLLOW_SKIPPED) end
								end }
						end
					end
				end
			end
		end
	end
	return out
end

-- A row's mark: " · same BattleTag as a sanctioned player" when a follow reaches it here; and its
-- tooltip's line when that player was given the sanction by name for evading it.
function TF.RowNote(name)
	local note, tip
	if ReachedBy(name) then note = " · " .. Red(L.ACCORD_FOLLOW_SAME) end
	local s = Store(false)
	if s and s.derived[Fold(Full(name))] then
		tip = L.ACCORD_FOLLOW_DERIVED
		note = note or (" · " .. Red(L.ACCORD_FOLLOW_SAME))
	end
	return note, tip
end

-- The person page: reached through whose sanction, or whose sanction follows his BattleTag.
function TF.ProfileLines(target, shown)
	shown = shown or ShownName
	local out = {}
	local kind, src = ReachedBy(target)
	if kind then
		out[#out + 1] = { id = "watch-profile-tagfollow", text = Red(L.ACCORD_FOLLOW_PROFILE:format(shown(src))), wrap = true }
		return out
	end
	local hash = HashFor(target)
	if not hash then return out end
	for _, F in ipairs(Index().byHash[hash] or NONE) do
		if Same(F.source, target) and Alive(F) and Direct(F.kind, F.source) then
			local others = Group(F.kind, hash, F.source, math.huge)
			out[#out + 1] = { id = "watch-profile-tagfollow", text = Red(L.ACCORD_FOLLOW_PROFILE_SOURCE:format(tonumber(others) or 0)), wrap = true }
			return out
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Commands, status, load
---------------------------------------------------------------------------

-- /oly accord follow <name> and /oly accord unfollow <name> (a team client).
function TF.Slash(verb, rest)
	local name = type(rest) == "string" and rest:match("^%s*(.-)%s*$") or ""
	if name == "" then ns.Print(L.ACCORD_FOLLOW_USAGE) return false end
	local A = Acc()
	if not (A and A.TeamShown and A.TeamShown()) then ns.Print(L.ACCORD_FORGET_TEAM) return false end
	if verb == "unfollow" then
		local ok, why = TF.Stop(nil, name)
		if not ok then ns.Print(L.ACCORD_FOLLOW_NONE:format(name)) end
		return ok, why
	end
	local done, last = false, nil
	local full = CharName(name)
	for _, kind in ipairs({ "N", "T" }) do
		if full and Direct(kind, full) then
			local ok, why = TF.GiveByHand(kind, full)
			if ok then
				done = true
				ns.Print(L.ACCORD_FOLLOW_DONE:format(why))
			else
				last = why
			end
		end
	end
	if not done then
		ns.Print(last == "reach" and L.ACCORD_FOLLOW_SKIPPED or last == "tag" and L.ACCORD_FORGET_NONE:format(name) or L.ACCORD_FOLLOW_NOTHING:format(name))
	end
	return done, last
end

-- For /oly status: counts only (never a code or a BattleTag).
function TF.StatusLine()
	local s = Store(false)
	local n, own = 0, 0
	for _, F in pairs(s and s.f or NONE) do
		if type(F) == "table" and F.on then
			n = n + 1
			if Given(F) then own = own + 1 end
		end
	end
	local derived = 0
	for _ in pairs(s and s.derived or NONE) do derived = derived + 1 end
	return ("follows %d (yours %d), taken %d, refused %d, derived %d"):format(n, own, stats.taken, stats.refused, derived)
end
function TF.Stats() return stats, refusedWhy end

local function Check(F)
	if type(F) ~= "table" or not TF.KINDS[F.kind] then return nil end
	local source, by = CharName(F.source), CharName(F.by)
	if not source or source ~= F.source or not by or by ~= F.by then return nil end
	local at, weight = tonumber(F.at), tonumber(F.weight)
	if not at or at < 1 or at ~= math.floor(at) or at > Clock() + TF.DATE_AHEAD then return nil end
	if not weight or weight < 1 or weight > 99 or weight ~= math.floor(weight) then return nil end
	local mine = F.mine == true
	if not mine and not IsCode(F.hash) then return nil end
	return { kind = F.kind, on = F.on == true, at = at, hash = not mine and F.hash or nil, source = source, by = by, weight = weight,
		heard = tonumber(F.heard) or 0, firstHeard = tonumber(F.firstHeard) or tonumber(F.heard) or 0,
		jitter = tonumber(F.jitter), mine = mine or nil }
end

-- The words kept in an earlier session, checked again (the SavedVariables can be edited): an
-- ordinary client keeps its own alone, and never a code.
function TF.Load()
	TF.Bump()
	local s = Store(false)
	if not s then return end
	local team, clean = TeamClient(), {}
	for key, F in pairs(s.f) do
		local ok = Check(F)
		if ok then
			local want = ok.mine and MineKey(ok.kind, ok.source) or KeyOf(ok.kind, ok.hash, ok.source)
			if want == key and (ok.mine or team) then clean[key] = ok end
		end
	end
	s.f = clean
	for key, d in pairs(s.derived) do
		local name = type(d) == "table" and CharName(d.name)
		if not name or Fold(name) ~= key or not TF.KINDS[d.kind] or not tonumber(d.at) then s.derived[key] = nil end
	end
	Dirty()
end

-- Off the moderation team (Accord.Guard, before its BattleTags go): only this account's own
-- follows stay, without their code, and the by-name words given here (each taken back once its
-- follow ends, on this client's own rounds).
function TF.DropTeam()
	local s = Store(false)
	if not s then return end
	local mine, keep = TF.Mine(), {}
	for key, F in pairs(s.f) do
		if type(F) == "table" then
			if F.mine then keep[key] = F
			elseif mine and F.hash == mine then
				local own = {}
				for k, v in pairs(F) do own[k] = v end
				own.hash, own.mine = nil, true
				keep[MineKey(F.kind, F.source)] = own
			end
		end
	end
	s.f = keep
	TF.Bump()
end

-- Tests start from a clean session (login: a new session begun at that time, for WARMUP).
function TF.ResetForTests(login)
	wipe(rates); wipe(rateAll); wipe(buffer); wipe(sentNow); wipe(refusedWhy)
	for k in pairs(stats) do stats[k] = 0 end
	session.mine, session.read, session.loginAt, session.under = nil, false, tonumber(login), false
	wipe(session.told); wipe(session.queue); wipe(session.queued); wipe(session.derivedAt); wipe(session.evidence); wipe(session.resent)
	session.evidenceN = 0
	session.lastAuto, session.lastSweep = -math.huge, -math.huge
	busy = 0
	TF.Bump()
end

if StaticPopupDialogs then
	StaticPopupDialogs["OLYMPUS_TAGFOLLOW_STOP"] = {
		text = L.ACCORD_FOLLOW_STOP_CONFIRM,
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function(self, data)
			data = data or (self and self.data)
			if type(data) == "table" then ns.SafeCall("tag follow stop", TF.Stop, data.kind, data.source) end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

ns.Comm.Handle("TF", function(...) TF.Handle(...) end)

-- Another moderator's sanction: a team client may follow it (G3); and the player's own notice.
ns.On("NETOFF_CHANGED", function(e)
	if type(e) == "table" and e.kind == "c" and e.off and type(e.name) == "string" then Queue("N", e.name) end
	TF.TellMine()
end)
ns.On("WATCHCHAT_CHANGED", function(op, target)
	if op == "T" and type(target) == "string" then Queue("T", target) end
	TF.TellMine()
end)
ns.On("INIT", function() TF.Load() end)
ns.On("LOGIN", function()
	session.loginAt = Now()
	NoteShield()
	ns.Every(60, "tag follow", TF.Tick)
	ns.After(TF.NOTICE_WAIT, "tag follow notice", function() TF.TellMine() end)
end)
