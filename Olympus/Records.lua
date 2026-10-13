local ADDON, ns = ...
local L = ns.L

-- 1.2.4, the shared records (the author's ask, 2026-10-12: rankings "acumulativas, propagar pela
-- rede e serem relateadas por todo mundo que tenha essa informação, tipo P2P"). A game or a duel
-- that counts is a record: its two players' signed halves, under an id that never changes. Every
-- client that holds a record keeps it and tells it to whoever lacks it; the rankings are worked out
-- from what a client holds; a month is closed by the author's signed seal, and only a seal ever
-- lets a record go.
--
-- Records (ns.rdb.records[letter], the core's saved data, per realm group and faction): a type
-- registers itself (Records.Register: FarkleTable "b", the Bones games; ArenaLedger "d", the duels)
-- with how to read its records (Read: the id, the time, what it says, its signed parts), what to do
-- with one taken here (Took: its ranking takes it), with one whose id another record holds already
-- with another result (Conflict: neither counts), the month's totals (Totals) and a seal's (Sealed).
--   days   = { [server day] = { [id] = body } }: the records, a grow-only union. The same id again
--            is left out; the same id saying another result is a conflict (clash), kept for review
--            and counted nowhere.
--   clash  = { [id] = { body, ... } }
--   pend   = { [id] = { b = body, d = day, at, by } }: a record one of whose players' keys this
--            client does not hold yet: kept (PENDING_MAX, the oldest heard going only when full) and
--            taken once the key arrives.
--   seals  = { [month] = { s = the signed seal, h = its totals' hash, n, at, r = the totals once
--            this client holds them } }
--   drafts = { [month] = { r, h, n, at } }: this client's own totals of a closed month (SEAL_AFTER
--            after its end): the author's seal request, and what any client compares a seal with.
--   keys (ns.rdb.records.keys) = { [player, lower case] = { k = his newest key, o = older ones,
--            g = gk, at } }: the ranking keys this client heard from their own players.
-- A record counts only when each of its parts is signed with the key its own player declared to
-- this client first-hand (RK, the server stamps the sender; or his own half heard from him, the
-- types' pins), and every signature holds (Arena.Check's queue, CHECKS_MAX records at once).
--
-- Anti-entropy. About RELAYS clients of the army (as the signed authority's answers draw:
-- King.AddonsOnline), every DIGEST_EVERY, send for each type a digest of what they hold: each
-- day's count and the sum of its ids' short hashes, the newest DIGEST_DAYS days, and each sealed
-- month's totals' hash. A client whose day differs asks for it (RA, with the PREFIX-character
-- prefixes of the ids it holds of that day), ASK_DAYS days a digest at most, the newest first; a
-- client that holds what the digest lacks sends its own digest (PUSH_GAP apart at most). Any
-- holder drawn answers with what the asker lacks, ANSWER_MIN to ANSWER_MIN + ANSWER_SPREAD later,
-- unless another answer of that day went out within ANSWER_GAP. Every answer goes on the arena's
-- low lane (a message a second at most, while Comm's queue has room), the newest days first, on
-- the channel: whoever lacks the same takes it too.
--
-- The seal (the author's, signed as the council lists are, scripts/council-sign.py seal): SEAL_AFTER
-- after a month ends each client works its totals out (a draft); `/oly arena records` shows them
-- as the author's seal requests, and the signed seal is pasted back (`/oly arena records seal`).
-- A client whose totals say the same hash keeps its own; any other takes the seal's totals (RT,
-- from any holder) once they hash to it. Once a month is sealed, its records older than
-- COMPACT_DAYS go and its totals stay for good. No seal: nothing is deleted.
--
-- Messages (numbers in base 36 unless said):
--   RK gk~pk~t~sig                         a player's ranking key (sig: "OLYK1|<Name-Realm>|gk|pk|t")
--   RD letter~day.n.sum,...~month.hash8,...  a digest
--   RA letter~d~day~prefixes                 an ask for a day's records (the prefixes it holds)
--   RA letter~s~month~hash8|-                an ask for a month's seal and its totals
--   RR letter~body                           a record
--   RS RS1~at~group~faction~letter~month~n~hash~sig   a seal (decimal; sig: RSA, Sign.lua)
--   RT letter~month~hash8~i~k~rows           a seal's totals, part i of k ("Name-Realm,games,won,lost;...")
local Records = {}
ns.Records = Records
local R = Records

R.TYPES = {}             -- [letter] = the type's spec (Register)
R.DIGEST_EVERY = 600     -- a drawn holder's digest, this often
R.RELAYS = 3             -- ...about this many holders each time, whatever the army's size
R.DIGEST_DAYS = 70       -- the newest days a digest names
R.DIGEST_MONTHS = 24     -- ...and the newest sealed months
R.ASK_DAYS = 3           -- days asked for from one digest at most
R.ASK_GAP = 300          -- a day asked for again from here this long after at the soonest
R.ANSWER_GAP = 60        -- one answer per day this often (anyone's)
R.ANSWER_MIN, R.ANSWER_SPREAD = 1, 6
R.PUSH_GAP = 120         -- our own digest sent back to one that lacks something, this often at most
R.OUT_MAX = 400          -- messages waiting on the low lane at most
R.FROM_DAY_MAX = 500     -- new records (kept or waiting for a key) one relayer brings in a server day
R.PENDING_MAX = 500      -- records waiting for a key
R.CHECKS_MAX = 20        -- records whose signatures are checked at once (FarkleTable's HALVES_CHECKS)
R.WAIT_MAX = 200         -- ...and waiting for their turn
R.LATER = 30             -- the signature queue full: checked again this much later
R.KEYS_MAX = 5000        -- players' keys kept
R.KEYS_EACH = 3          -- keys of one player kept (a new account key after a wiped saved data)
R.KEY_DELAY, R.KEY_SPREAD = 30, 60 -- a player named in records declares his key this long after login
R.KEY_EVERY = 3600       -- ...and again this often while online
R.LOAD_DELAY = 10        -- this long after login: each type's own records taken in, the pins
R.PREFIX = 16            -- 64 bits of SHA-256 over the stable id and result (not signature bytes)
R.AHEAD = 120            -- a record's time this far ahead of the clock at most
R.CLASH_EACH = 3         -- other bodies kept for one id in conflict
R.BODY_MAX = 1200
R.SEAL_AFTER = 7 * 86400 -- a month's totals worked out this long after it ends
R.COMPACT_DAYS = 62      -- a sealed month's records older than this go (the totals stay)
R.SEAL_ROWS_MAX = 5000
R.CHUNK = 3000           -- bytes of totals in one RT at most
R.ASM_TTL = 7200         -- bounded signed totals can take an hour on Comm's paced low lane
R.ASM_MAX = 8
R.CHECK_DAY_MAX = 1000   -- attempted checks per relay, reserved before asynchronous verification
R.CONTROL_MAX = 256     -- remembered remote day/month requests, per type
R.ASK_PREFIX_MAX = 350   -- 5,600 bytes, below Arena's 6,600-byte assembly limit
R.random = math.random

local floor, max, min = math.floor, math.max, math.min
local stats = { refused = {}, kept = 0, again = 0, pending = 0, clash = 0, sent = 0, asked = 0, answered = 0, digests = 0, keys = 0, sealed = 0, compacted = 0 }
local function Count(why) stats.refused[why] = (stats.refused[why] or 0) + 1 return false, why end
function R.Stats() return stats end

local function A() return ns.Arena end
local function Now() return A().Now() end
local function B36(n) return A().B36(n) end
local function N36(s, lo, hi) return A().N(s, lo, hi) end
local function Low(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.FullName(name):lower()
end
local function Same(a, b) return Low(a) ~= nil and Low(a) == Low(b) end
local function Me() return ns.me end

-- The month of server time t (Honors.MonthOf's numbering: year * 12 + month - 1, UTC).
local function DaysFromCivil(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = floor(y / 400)
	local yoe = y - era * 400
	local mp = m > 2 and m - 3 or m + 9
	local doy = floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
function R.MonthOf(t)
	local H = ns.Honors
	if type(H) == "table" and type(H.MonthOf) == "function" then return H.MonthOf(t) end
	local d = date("!*t", floor(tonumber(t) or 0))
	return d.year * 12 + d.month - 1
end
-- When month n starts (server time, UTC).
function R.MonthStart(n)
	n = floor(tonumber(n) or 0)
	return DaysFromCivil(floor(n / 12), n % 12 + 1, 1) * 86400
end

-- An id's short hash (32 bits: two of Comm's Hash36 accumulators) and its prefix.
function R.Short(id)
	local h1, h2 = 5381, 52711
	for i = 1, #id do
		local c = id:byte(i)
		h1 = (h1 * 33 + c) % 2147483647
		h2 = (h2 * 31 + c * 7) % 2147483647
	end
	return (h1 % 1048576) * 4096 + h2 % 4096
end
local PREFIX_SPAN = 36 ^ R.PREFIX
function R.Prefix(n)
	local s = B36(n % PREFIX_SPAN)
	return ("0"):rep(R.PREFIX - #s) .. s
end
-- The two players an id names ("<game>:<player>:<player>", lower case).
local function Players(id)
	local a, b = tostring(id):match("^[^:]+:([^:]+):([^:]+)$")
	return a, b
end
local function Names(id, low)
	local a, b = Players(id)
	return low ~= nil and (a == low or b == low)
end

---------------------------------------------------------------------------
-- The store and its index
---------------------------------------------------------------------------

local function Root(make)
	local Ar = A()
	if not Ar or Ar.Sim() or type(ns.rdb) ~= "table" then return nil end
	local root = ns.rdb.records
	if type(root) ~= "table" then
		if not make then return nil end
		root = { v = 2 }
		ns.rdb.records = root
	end
	local side = tostring(ns.faction or "Alliance")
	-- Preserve the unreleased flat store when upgrading it, in its original client's faction.
	if root.v == 1 then
		local legacy = {}
		for k, v in pairs(root) do if k ~= "v" then legacy[k] = v end end
		root[side], root.v = legacy, 2
	end
	local s = root[side]
	if type(s) ~= "table" then
		if not make then return nil end
		s = {} root[side] = s
	end
	if type(s.keys) ~= "table" then s.keys = {} end
	return s
end
local function Store(letter, make)
	if not R.TYPES[letter] then return nil end
	local s = Root(make)
	local t = s and s[letter]
	if type(t) ~= "table" then
		if not (s and make) then return nil end
		t = {}
		s[letter] = t
	end
	for _, k in ipairs({ "days", "clash", "pend", "seals", "drafts" }) do
		if type(t[k]) ~= "table" then t[k] = {} end
	end
	return t
end
R.Store = Store

-- [letter] = { store, ids = { [id] = day }, dig = { [day] = { n, x } }, per = { [day] = { [player] = n } } },
-- worked out from the store at the first need.
local idx = {}
local function Add(x, d, id, body)
	if x.ids[id] then return end
	x.ids[id] = d
	local g = x.dig[d]
	if not g then g = { n = 0, x = 0 } x.dig[d] = g end
	local hash = R.Short(R.Fingerprint(x.letter, body, true))
	x.hash[id] = hash
	g.n, g.x = g.n + 1, (g.x + hash) % 4294967296
	local per = x.per[d]
	if per then
		local a, b = Players(id)
		if a then per[a] = (per[a] or 0) + 1 end
		if b then per[b] = (per[b] or 0) + 1 end
	end
end
local function Remove(x, d, id)
	if x.ids[id] ~= d then return end
	x.ids[id] = nil
	local g = x.dig[d]
	if g then
		g.n, g.x = g.n - 1, (g.x - (x.hash[id] or 0)) % 4294967296
		if g.n <= 0 then x.dig[d] = nil end
	end
	x.per[d] = nil
	x.hash[id] = nil
end
local function Index(letter)
	local s = Store(letter)
	local x = idx[letter]
	if x and x.store == s then return x end
	x = { letter = letter, store = s, ids = {}, hash = {}, dig = {}, per = {} }
	idx[letter] = x
	if s then
		for d, list in pairs(s.days) do
			if type(d) ~= "number" or type(list) ~= "table" then s.days[d] = nil
			else
				for id, body in pairs(list) do
					Add(x, d, id, body)
					for _, other in ipairs(s.clash[id] or {}) do
						local g = x.dig[d]
						g.n, g.x = g.n + 1, (g.x + R.Short(R.Fingerprint(letter, other, true))) % 4294967296
					end
				end
			end
		end
	end
	return x
end
-- A day's records per player (a type's DAY_MAX).
local function PerDay(x, s, d)
	local per = x.per[d]
	if per then return per end
	per = {}
	for id in pairs(s.days[d] or {}) do
		local a, b = Players(id)
		if a then per[a] = (per[a] or 0) + 1 end
		if b then per[b] = (per[b] or 0) + 1 end
	end
	x.per[d] = per
	return per
end

-- A seal whose totals this client holds (adopted), its month's old records then gone.
local function Adopted(seal) return type(seal) == "table" and type(seal.r) == "string" and type(seal.h) == "string" end
local function CompactBefore() return floor((Now() - R.COMPACT_DAYS * 86400) / 86400) end
local function Compacted(s, d)
	return s ~= nil and d < CompactBefore() and Adopted(s.seals[R.MonthOf(d * 86400)])
end

function R.Has(letter, id) return Index(letter).ids[id] ~= nil end
-- The records held of a type (tests, the status): their number, and the days.
function R.Count(letter)
	local n = 0
	for _ in pairs(Index(letter).ids) do n = n + 1 end
	return n
end
function R.Body(letter, id)
	local d = Index(letter).ids[id]
	local s = d and Store(letter)
	return s and s.days[d] and s.days[d][id] or nil
end
local fingerprints = {}
function R.Fingerprint(letter, body, save)
	local cache = fingerprints[letter]
	if cache and cache[body] then return cache[body] end
	local spec = R.TYPES[letter]
	local ok, rec = pcall(spec.Read, body)
	local text = ok and rec and (rec.id .. "|" .. tostring(rec.content)) or body
	local hash = (ns.Sign.SHA256(text):sub(1, 8):gsub(".", function(c) return ("%02x"):format(c:byte()) end))
	if save then cache = cache or {} fingerprints[letter] = cache cache[body] = hash end
	return hash
end
function R.Bodies(letter, first, last)
	local s, out = Store(letter), {}
	for d, list in pairs(s and s.days or {}) do
		if (not first or d >= first) and (not last or d <= last) then
			for id, body in pairs(list) do if not s.clash[id] then out[#out + 1] = body end end
		end
	end
	return out
end
function R.ContainsMonth(letter, month)
	local x = Index(letter)
	for d = floor(R.MonthStart(month) / 86400), floor(R.MonthStart(month + 1) / 86400) - 1 do
		if x.dig[d] and x.dig[d].n > 0 then return true end
	end
	return false
end
function R.Pending(letter)
	local s = Store(letter)
	local n = 0
	for _ in pairs(s and s.pend or {}) do n = n + 1 end
	return n
end
function R.Clashes(letter)
	local s = Store(letter)
	local out = {}
	for id in pairs(s and s.clash or {}) do out[#out + 1] = id end
	table.sort(out)
	return out
end
-- Whether any record of a type names that player (the key declaration's reason).
local function Named(low)
	if not low then return false end
	for letter in pairs(R.TYPES) do
		for id in pairs(Index(letter).ids) do if Names(id, low) then return true end end
		local s = Store(letter)
		for id, p in pairs(s and s.pend or {}) do if Names(p.id or id, low) then return true end end
	end
	return false
end

---------------------------------------------------------------------------
-- Keys: each player's own word (RK) or his own half heard from him (the types' pins)
---------------------------------------------------------------------------

local Take -- (below)
local Unpend -- (below)
local function KeyShape(pk64) return type(pk64) == "string" and #pk64 == 43 and pk64:find("^[%w%-_]+$") ~= nil end
local function Raw(text, len)
	local Ed = ns.Ed25519
	local ok, r = pcall(function() return type(text) == "string" and type(Ed) == "table" and Ed.FromB64 and Ed.FromB64(text) or nil end)
	return ok and type(r) == "string" and #r == len and r or nil
end
local function B64(raw)
	local Ed = ns.Ed25519
	return type(raw) == "string" and type(Ed) == "table" and Ed.ToB64 and Ed.ToB64(raw) or nil
end

-- The keys this client holds for a player: a set { [pk base64url] = true }, or nil.
function R.KeysOf(name)
	local low = Low(name)
	if not low then return nil end
	local out
	local root = Root(false)
	local k = root and root.keys[low]
	if type(k) == "table" then
		if KeyShape(k.k) then out = out or {} out[k.k] = true end
		for _, v in ipairs(type(k.o) == "table" and k.o or {}) do if KeyShape(v) then out = out or {} out[v] = true end end
	end
	-- (a claim Debts verified: the wallet's, ZT; none while the Wallet is off)
	local D = ns.Debts
	if type(D) == "table" and type(D.KeyOf) == "function" then
		local ok, raw = pcall(D.KeyOf, name)
		local v = ok and type(raw) == "string" and #raw == 32 and B64(raw) or nil
		if v then out = out or {} out[v] = true end
	end
	return out
end
function R.HasKey(name, pk64)
	local set = KeyShape(pk64) and R.KeysOf(name)
	return set ~= nil and set[pk64] == true
end
function R.KeyOf(name)
	local root = Root(false)
	local k = root and root.keys[Low(name) or ""]
	return type(k) == "table" and KeyShape(k.k) and k.k or nil
end

-- A player's key, heard from him (his RK whose signature held, or his own half: the types' pins).
-- True when new for him. quiet: no records looked at again (the caller does it once, RecheckPending).
function R.Pin(name, pk64, gk, quiet)
	local low = Low(name)
	if not low or not KeyShape(pk64) then return false end
	local root = Root(true)
	if not root then return false end
	local k = root.keys[low]
	if type(k) == "table" and k.k == pk64 then
		k.at = Now()
		return false
	end
	if type(k) ~= "table" then
		local n, oldest, at = 0, nil, nil
		for key, v in pairs(root.keys) do
			n = n + 1
			local t = type(v) == "table" and tonumber(v.at) or 0
			if not at or t < at then oldest, at = key, t end
		end
		if n >= R.KEYS_MAX and oldest then root.keys[oldest] = nil end
		k = {}
		root.keys[low] = k
	end
	local old = {}
	if KeyShape(k.k) then old[1] = k.k end
	for _, v in ipairs(type(k.o) == "table" and k.o or {}) do
		if v ~= pk64 and KeyShape(v) and #old < R.KEYS_EACH - 1 then old[#old + 1] = v end
	end
	k.k, k.o, k.g, k.at = pk64, old, type(gk) == "string" and gk or k.g, Now()
	stats.keys = stats.keys + 1
	if not quiet then Unpend(low) end
	return true
end

local function KeyText(name, gk, pk64, t) return ("OLYK1|%s|%s|%s|%s"):format(ns.FullName(name), gk, pk64, t) end
local keySentAt
-- This player's ranking key on the channel (RK, signed with it): once a session after login when
-- records name him, again KEY_EVERY while online, never from a player no record names.
function R.SendKey()
	local D = ns.Debts
	if type(D) ~= "table" or type(D.MyKey) ~= "function" or type(D.Sign) ~= "function" then return false end
	local ok, gk, pk = pcall(D.MyKey)
	if not ok or not gk or type(pk) ~= "string" or #pk ~= 32 then return false end
	local pk64, t = B64(pk), B36(Now())
	local signed, sig = pcall(D.Sign, KeyText(Me(), gk, pk64, t))
	if not signed or type(sig) ~= "string" or #sig ~= 64 then return false end
	keySentAt = Now()
	R.Pin(Me(), pk64, gk, true)
	return A().Send("RK", "L", table.concat({ gk, pk64, t, B64(sig) }, "~"), { dist = "CHANNEL", key = "records key", low = true }) == true
end
local keyDue = false
local function KeyLater()
	if keySentAt or keyDue then return end
	keyDue = true
	ns.After(R.KEY_DELAY + R.random() * R.KEY_SPREAD, "records key", function()
		keyDue = false
		if not keySentAt then R.SendKey() end
	end)
end

local function OnKey(dist, sender, mode, body)
	if mode ~= "L" or (dist ~= "CHANNEL" and dist ~= "WHISPER") then return Count("lane") end
	local gk, pk64, t, sig64 = A().Fields(body, 4)
	local at = N36(t, 0, 4294967295)
	if not sig64 or not KeyShape(pk64) or #sig64 ~= 86 or not A().GuidOf(gk) or not at or at > Now() + R.AHEAD then return Count("key-shape") end
	sender = ns.FullName(sender)
	if R.HasKey(sender, pk64) then
		local root = Root(false)
		local k = root and root.keys[Low(sender)]
		if type(k) == "table" and k.k == pk64 then k.at = Now() end
		return
	end
	local pk, sig = Raw(pk64, 32), Raw(sig64, 64)
	if not pk or not sig then return Count("key-shape") end
	A().Check("rk " .. sig64, { pk = pk, msg = KeyText(sender, gk, pk64, t), sig = sig }, function(good)
		if good then R.Pin(sender, pk64, gk) elseif good == false then Count("key-signature") end
	end)
end
ns.Comm.Handle("RK", ns.Arena.Handle("RK", OnKey))

---------------------------------------------------------------------------
-- Taking a record
---------------------------------------------------------------------------

local ticker
local function EnsureTicker()
	if ticker or not Root(false) then return end
	ticker = ns.Every(R.DIGEST_EVERY, "records", function() R.Tick() end)
end

-- Records one relayer brought in today: [sender lower] = n (memory, one server day).
local from, attempts, fromDay = {}, {}, -1
local function FromCount(sender, add)
	local d = floor(Now() / 86400)
	if d ~= fromDay then from, attempts, fromDay = {}, {}, d end
	local k = Low(sender) or "?"
	if add then from[k] = (from[k] or 0) + 1 end
	return from[k] or 0
end

local checking, inflight, waitq = {}, 0, {}
local PumpWait -- (below)

local function Clash(letter, s, rec, body)
	local list = s.clash[rec.id]
	if type(list) ~= "table" then list = {} s.clash[rec.id] = list end
	for _, b in ipairs(list) do if b == body then return false, "conflict" end end
	if #list < R.CLASH_EACH then
		list[#list + 1] = body
		local x = Index(letter)
		local d = x.ids[rec.id]
		local g = d and x.dig[d]
		if g then g.n, g.x = g.n + 1, (g.x + R.Short(R.Fingerprint(letter, body, true))) % 4294967296 end
	end
	s.drafts[R.MonthOf(rec.t)] = nil
	local originalDay = Index(letter).ids[rec.id]
	if originalDay then s.drafts[R.MonthOf(originalDay * 86400)] = nil end
	stats.clash = stats.clash + 1
	local spec = R.TYPES[letter]
	if spec.Conflict then ns.SafeCall("records conflict", spec.Conflict, rec) end
	ns.Fire("RECORDS_CHANGED", letter)
	return false, "conflict"
end

local function Pend(letter, s, rec, body, d, sender)
	local key = rec.id .. "|" .. A().Hash36(body, 8)
	if s.pend[key] then return false, "pending" end
	local n, oldest, at = 0, nil, nil
	for id, p in pairs(s.pend) do
		n = n + 1
		local t = type(p) == "table" and tonumber(p.at) or 0
		if not at or t < at then oldest, at = id, t end
	end
	if n >= R.PENDING_MAX and oldest then
		s.pend[oldest] = nil
		Count("pending-out")
	end
	s.pend[key] = { id = rec.id, b = body, d = d, at = Now(), by = Low(sender) }
	stats.pending = stats.pending + 1
	EnsureTicker()
	return false, "pending"
end

-- A record checked (each signature good): kept, told to its type, our key declared if it names us.
local function Keep(letter, rec, body, sender, how)
	local s = Store(letter, true)
	local x = Index(letter)
	if not s then return false, "store" end
	local d = floor(rec.t / 86400)
	if Compacted(s, d) then return false, "sealed" end
	-- All mutation, including conflicts, is after both signatures and their identity pins held.
	for _, p in ipairs(rec.parts) do if not R.HasKey(p.name, p.pk64) then return Count("pin") end end
	local held = x.ids[rec.id]
	if held then
		local hb = s.days[held] and s.days[held][rec.id]
		local ok, old = pcall(R.TYPES[letter].Read, hb)
		if hb == body or (ok and old and old.content == rec.content) then
			if R.Accepted then R.Accepted(letter, d) end
			return false, "again"
		end
		if how == "relay" then FromCount(sender, true) end
		return Clash(letter, s, rec, body)
	end
	if s.clash[rec.id] then return Clash(letter, s, rec, body) end
	-- Recheck quotas here: checks may have been started before any of their callbacks completed.
	if how == "relay" and FromCount(sender) >= R.FROM_DAY_MAX then return Count("flood") end
	local cap = tonumber(R.TYPES[letter].DAY_MAX)
	local a, b = Players(rec.id)
	local per = PerDay(x, s, d)
	if cap and ((a and (per[a] or 0) >= cap) or (b and (per[b] or 0) >= cap)) then return Count("full") end
	s.days[d] = s.days[d] or {}
	s.days[d][rec.id] = body
	Add(x, d, rec.id, body)
	for key, p in pairs(s.pend) do if key == rec.id or p.id == rec.id then s.pend[key] = nil end end
	s.drafts[R.MonthOf(rec.t)] = nil -- a late valid record invalidates an unsigned draft
	if how == "relay" then FromCount(sender, true) end
	stats.kept = stats.kept + 1
	if R.Accepted then R.Accepted(letter, d) end
	EnsureTicker()
	if Names(rec.id, Low(Me())) then KeyLater() end
	local spec = R.TYPES[letter]
	if spec.Took then ns.SafeCall("records took", spec.Took, rec, how, body) end
	ns.Fire("RECORDS_CHANGED", letter)
	return true
end

-- Each part's signature through the arena's queue (Arena.Check), CHECKS_MAX records at once; the
-- rest wait their turn (WAIT_MAX), and a full queue tries again LATER.
local function Check(letter, rec, body, sender, how)
	local key = letter .. "|" .. rec.id
	if checking[key] then return false, "checking" end
	if inflight >= R.CHECKS_MAX then
		if #waitq >= R.WAIT_MAX then
			table.remove(waitq, 1)
			Count("busy")
		end
		waitq[#waitq + 1] = { letter, body, sender, how }
		return false, "waiting"
	end
	checking[key] = true
	inflight = inflight + 1
	local left, bad, later = #rec.parts, false, false
	for _, p in ipairs(rec.parts) do
		A().Check("rec " .. p.sig64 .. A().Hash36(p.msg, 8), { pk = p.pk, msg = p.msg, sig = p.sig }, function(ok)
			if ok == nil then later = true elseif not ok then bad = true end
			left = left - 1
			if left > 0 then return end
			checking[key] = nil
			inflight = inflight - 1
			if bad then
				Count("signature")
			elseif later then
				if #waitq < R.WAIT_MAX then waitq[#waitq + 1] = { letter, body, sender, how } else Count("busy") end
				A().After(R.LATER, "records later", function() PumpWait() end)
				return -- a full verifier must not synchronously retry its own deferred work
			else
				Keep(letter, rec, body, sender, how)
			end
			PumpWait()
		end)
	end
	return true, "checking"
end
PumpWait = function()
	while waitq[1] and inflight < R.CHECKS_MAX do
		local w = table.remove(waitq, 1)
		Take(w[1], w[2], w[3], w[4])
	end
end

-- A record of type letter heard from sender. how: "self" (this client's own module made it from
-- halves it heard), "relay" (RR), "pending" (its key arrived). Returns ok, why, and its day.
Take = function(letter, body, sender, how)
	local spec = R.TYPES[letter]
	if not spec then return Count("type") end
	if type(body) ~= "string" or #body > R.BODY_MAX then return Count("shape") end
	local ok, rec, why = pcall(spec.Read, body)
	if not ok or type(rec) ~= "table" then return Count(ok and (why or "shape") or "read") end
	if type(rec.id) ~= "string" or type(rec.t) ~= "number" or type(rec.parts) ~= "table" or not rec.parts[1] then return Count("shape") end
	if rec.t > Now() + R.AHEAD then return Count("time") end
	local d = floor(rec.t / 86400)
	local s = Store(letter, true)
	if not s then return Count("store") end
	local x = Index(letter)
	if Compacted(s, d) then return false, "sealed", d end
	local held = x.ids[rec.id]
	if held then
		local hb = s.days[held] and s.days[held][rec.id]
		if hb == body then stats.again = stats.again + 1 return false, "again", d end
		local okHeld, hr = pcall(spec.Read, hb)
		if okHeld and type(hr) == "table" and hr.content == rec.content then stats.again = stats.again + 1 return false, "again", d end
	end
	if how == "relay" and FromCount(sender) >= R.FROM_DAY_MAX then return Count("flood") end
	local cap = tonumber(spec.DAY_MAX)
	if cap and not held then
		local per = PerDay(x, s, d)
		local a, b = Players(rec.id)
		if (a and (per[a] or 0) >= cap) or (b and (per[b] or 0) >= cap) then return Count("full") end
	end
	for _, p in ipairs(rec.parts) do
		local keys = R.KeysOf(p.name)
		if not keys then
			if how == "relay" then FromCount(sender, true) end
			local _, w = Pend(letter, s, rec, body, d, sender)
			return false, w, d
		end
		if not keys[p.pk64] then return Count("pin") end
	end
	if how == "relay" then
		FromCount(sender)
		local key = Low(sender) or "?"
		if (attempts[key] or 0) >= R.CHECK_DAY_MAX then return Count("checks-full") end
		attempts[key] = (attempts[key] or 0) + 1
	end
	local started, w = Check(letter, rec, body, sender, how)
	return started, w, d
end
R.Take = function(...) return Take(...) end

-- The records waiting for a key that names this player, taken again (his key just came).
Unpend = function(low)
	for letter in pairs(R.TYPES) do
		local s = Store(letter)
		if s then
			local list = {}
			for id, p in pairs(s.pend) do
				if type(p) ~= "table" or type(p.b) ~= "string" then s.pend[id] = nil
				elseif not low or Names(p.id or id, low) then list[#list + 1] = { id = id, p = p } end
			end
			table.sort(list, function(a, b) return (tonumber(a.p.at) or 0) < (tonumber(b.p.at) or 0) end)
			for _, e in ipairs(list) do Take(letter, e.p.b, e.p.by or "?", "pending") end
		end
	end
end
function R.RecheckPending() Unpend(nil) end

---------------------------------------------------------------------------
-- Telling: the digest, the ask, the answer (anti-entropy)
---------------------------------------------------------------------------

local function Users()
	local C, K = ns.Comm, ns.King
	local users = 1
	if type(C) == "table" and type(C.PeerCount) == "function" then
		local ok, n = pcall(C.PeerCount, true)
		if ok and tonumber(n) then users = tonumber(n) + 1 end
	end
	if type(K) == "table" and type(K.AddonsOnline) == "function" then
		local ok, n = pcall(K.AddonsOnline)
		if ok and tonumber(n) then users = max(users, tonumber(n)) end
	end
	return users
end
local function Drawn() return R.random() <= min(1, R.RELAYS / Users()) end
R.Drawn = Drawn

-- What waits on the low lane: { kind, k (what makes it the same), body, day }, the newest days first.
local outq, outSet = {}, {}
local function Producer()
	local item = table.remove(outq, 1)
	if not item then return nil end
	outSet[item.k] = nil
	stats.sent = stats.sent + 1
	return { item.kind, "L", item.body, { dist = "CHANNEL" } }
end
local function Out(kind, k, body, day)
	if outSet[k] then return false end
	if #outq >= R.OUT_MAX then return Count("out-full") end
	outSet[k] = true
	local item = { kind = kind, k = k, body = body, day = day or math.huge }
	local at = #outq + 1
	for i, o in ipairs(outq) do
		if (o.day or 0) < item.day then at = i break end
	end
	table.insert(outq, at, item)
	A().Later("records", Producer)
	return true
end
function R.OutSize() return #outq end

local lastDigest, heardDigest = {}, {}
local askedAt, heardAsk, answeredAt, answering, askCursor = {}, {}, {}, {}, {}
local function Per(t, letter)
	local x = t[letter]
	if not x then x = {} t[letter] = x end
	local n, oldest, at = 0, nil, math.huge
	for k, v in pairs(x) do n = n + 1 if type(v) == "number" and v < at then oldest, at = k, v end end
	if n >= R.CONTROL_MAX and oldest then x[oldest] = nil end
	return x
end
function R.Accepted(letter, day) Per(answeredAt, letter)[day] = Now() end

-- This client's digest of a type: "letter~day.n.sum,...~month.hash8,...", or nil when it holds
-- nothing of it.
function R.DigestBody(letter)
	local s = Store(letter)
	if not s then return nil end
	local x = Index(letter)
	local days = {}
	for d in pairs(x.dig) do days[#days + 1] = d end
	table.sort(days, function(a, b) return a > b end)
	local parts = {}
	for i = 1, min(#days, R.DIGEST_DAYS) do
		local g = x.dig[days[i]]
		parts[#parts + 1] = B36(days[i]) .. "." .. B36(g.n) .. "." .. B36(g.x)
	end
	local months = {}
	for m, seal in pairs(s.seals) do if type(m) == "number" and Adopted(seal) then months[#months + 1] = m end end
	table.sort(months, function(a, b) return a > b end)
	local mparts = {}
	for i = 1, min(#months, R.DIGEST_MONTHS) do mparts[#mparts + 1] = B36(months[i]) .. "." .. s.seals[months[i]].h:sub(1, 8) end
	if not parts[1] and not mparts[1] then return nil end
	return letter .. "~" .. table.concat(parts, ",") .. "~" .. table.concat(mparts, ",")
end
function R.SendDigest(letter)
	local body = R.DigestBody(letter)
	if not body then return false end
	lastDigest[letter] = Now()
	stats.digests = stats.digests + 1
	return A().Send("RD", "L", body, { dist = "CHANNEL", key = "records digest " .. letter, low = true }) == true
end

-- An ask for one day's records: the prefixes of the ids this client holds of it.
function R.Ask(letter, d, remoteCount)
	local s = Store(letter)
	local held = {}
	for id, body in pairs(s and s.days[d] or {}) do
		held[#held + 1] = R.Fingerprint(letter, body)
		for _, other in ipairs(s.clash[id] or {}) do held[#held + 1] = R.Fingerprint(letter, other) end
	end
	-- (and the ones waiting here for a key: their bodies are here already)
	for id, p in pairs(s and s.pend or {}) do
		if type(p) == "table" and tonumber(p.d) == d then held[#held + 1] = R.Fingerprint(letter, p.b) end
	end
	table.sort(held)
	-- Large days are requested in hash buckets. The packet and the receiver's scan stay bounded;
	-- repeated requests advance the bucket rather than repeatedly sending a truncated prefix list.
	local bucket = ""
	if max(#held, tonumber(remoteCount) or 0) > R.ASK_PREFIX_MAX then
		local width = max(#held, tonumber(remoteCount) or 0) > R.ASK_PREFIX_MAX * 16 and 2 or 1
		local cursors = Per(askCursor, letter)
		local value = cursors[d] or 0
		local span = 16 ^ width
		bucket = ("%0" .. width .. "x"):format(value % span)
		cursors[d] = value + 1
		local selected = {}
		for _, prefix in ipairs(held) do if prefix:sub(1, width) == bucket and #selected < R.ASK_PREFIX_MAX then selected[#selected + 1] = prefix end end
		held = selected
	end
	Per(askedAt, letter)[d] = Now()
	stats.asked = stats.asked + 1
	return A().Send("RA", "L", letter .. "~d~" .. B36(d) .. "~" .. (bucket ~= "" and bucket .. ":" or "") .. table.concat(held), { dist = "CHANNEL", key = "records ask " .. letter .. d, low = true }) == true
end

local AskSeal -- (below)
local function OnDigest(dist, sender, mode, body)
	if mode ~= "L" or dist ~= "CHANNEL" then return Count("lane") end
	if type(body) ~= "string" or #body > 6000 then return Count("shape") end
	local letter, days, months = A().Fields(body, 3)
	if not (letter and R.TYPES[letter]) then return Count("type") end
	local now = Now()
	heardDigest[letter] = now
	local s = Store(letter)
	local x = Index(letter)
	local listed, nListed, oldest, need, counts, push = {}, 0, math.huge, {}, {}, false
	for item in (days .. ","):gmatch("([^,]*),") do
		local d, n, h = item:match("^([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)$")
		d, n, h = N36(d, 0, 400000), N36(n, 0, 1000000), N36(h, 0, 4294967295)
		if d and n and h and not listed[d] then
			listed[d], nListed = true, nListed + 1
			oldest = min(oldest, d)
			if not Compacted(s, d) then
				local g = x.dig[d]
				local mn, mx = g and g.n or 0, g and g.x or 0
				if mn ~= n or mx ~= h then
					if n > 0 then need[#need + 1] = d counts[d] = n end
					if mn > 0 then push = true end
				end
			end
		end
	end
	-- (days held here that its digest does not name, within what it names: it lacks them)
	for d in pairs(x.dig) do
		if not listed[d] and (d >= oldest or nListed < R.DIGEST_DAYS) then push = true break end
	end
	table.sort(need, function(a, b) return a > b end)
	local asks = 0
	for _, d in ipairs(need) do
		if asks >= R.ASK_DAYS then break end
		if now - (Per(askedAt, letter)[d] or -math.huge) >= R.ASK_GAP and now - (Per(heardAsk, letter)[d] or -math.huge) >= R.ANSWER_GAP then
			R.Ask(letter, d, counts[d])
			asks = asks + 1
		end
	end
	-- Sealed months: one held elsewhere and not here (or another seal of it) asked for.
	local mlisted = {}
	for item in (tostring(months or "") .. ","):gmatch("([^,]*),") do
		local m, h8 = item:match("^([0-9a-z]+)%.(%x+)$")
		m = N36(m, 0, 100000)
		if m and h8 and #h8 == 8 then
			mlisted[m] = true
			local seal = s and s.seals[m]
			if not (Adopted(seal) and seal.h:sub(1, 8) == h8:lower()) then AskSeal(letter, m) end
		end
	end
	for m, seal in pairs(s and s.seals or {}) do if Adopted(seal) and not mlisted[m] then push = true end end
	-- It lacks what this client holds: our own digest, drawn, a few seconds later (another
	-- digest of that type heard meanwhile tells it as well).
	if push and s and now - (lastDigest[letter] or -math.huge) >= R.PUSH_GAP and not answering["digest" .. letter] and Drawn() then
		answering["digest" .. letter] = true
		A().After(2 + R.random() * 8, "records push " .. letter, function()
			answering["digest" .. letter] = nil
			if (heardDigest[letter] or 0) > now then return end
			R.SendDigest(letter)
		end)
	end
end
ns.Comm.Handle("RD", ns.Arena.Handle("RD", OnDigest))

local SendSeal -- (below)
local function OnAsk(dist, sender, mode, body)
	if mode ~= "L" or dist ~= "CHANNEL" then return Count("lane") end
	if type(body) ~= "string" or #body > 9000 then return Count("shape") end
	local letter, kind, what, rest = A().Fields(body, 4)
	if not (letter and R.TYPES[letter]) or not rest then return Count("type") end
	local now = Now()
	local s = Store(letter)
	if kind == "d" then
		local d = N36(what, 0, 400000)
		local bucket, prefixes = rest:match("^([0-9a-z]+):(.*)$")
		if bucket then if #bucket > 2 then return Count("shape") end rest = prefixes else bucket = "" end
		if not d or #rest % R.PREFIX ~= 0 or #rest > R.ASK_PREFIX_MAX * R.PREFIX or rest:find("[^0-9a-z]") then return Count("shape") end
		Per(heardAsk, letter)[d] = now
		local list = s and s.days[d]
		if not list or not next(list) then return end
		local has = {}
		for i = 1, #rest, R.PREFIX do has[rest:sub(i, i + R.PREFIX - 1)] = true end
		local missing = {}
		for id, record in pairs(list) do
			local prefix = R.Fingerprint(letter, record)
			if prefix:sub(1, #bucket) == bucket and not has[prefix] then missing[#missing + 1] = { id, record } end
			for _, other in ipairs(s.clash[id] or {}) do
				prefix = R.Fingerprint(letter, other)
				if prefix:sub(1, #bucket) == bucket and not has[prefix] then missing[#missing + 1] = { id, other } end
			end
		end
		if not missing[1] then return end
		local key = "d" .. letter .. d
		if answering[key] or now - (Per(answeredAt, letter)[d] or -math.huge) < R.ANSWER_GAP or not Drawn() then return end
		answering[key] = true
		A().After(R.ANSWER_MIN + R.random() * R.ANSWER_SPREAD, "records answer " .. key, function()
			answering[key] = nil
			if (Per(answeredAt, letter)[d] or -math.huge) > now then return end
			Per(answeredAt, letter)[d] = Now()
			stats.answered = stats.answered + 1
			table.sort(missing, function(a, b) return a[1] < b[1] end)
			local held = s.days[d] or {}
			for _, item in ipairs(missing) do
				if held[item[1]] then Out("RR", letter .. item[1] .. A().Hash36(item[2], 8), letter .. "~" .. item[2], d) end
			end
		end)
	elseif kind == "s" then
		local m = tonumber(N36(what, 0, 100000))
		local seal = m and s and s.seals[m]
		if not Adopted(seal) or (rest ~= "-" and seal.h:sub(1, 8) == rest:lower()) then return end
		local key = "s" .. letter .. m
		if answering[key] or now - (Per(answeredAt, letter)["s" .. m] or -math.huge) < R.ANSWER_GAP or not Drawn() then return end
		answering[key] = true
		A().After(R.ANSWER_MIN + R.random() * R.ANSWER_SPREAD, "records answer " .. key, function()
			answering[key] = nil
			if (Per(answeredAt, letter)["s" .. m] or -math.huge) > now then return end
			SendSeal(letter, m)
		end)
	end
end
ns.Comm.Handle("RA", ns.Arena.Handle("RA", OnAsk))

local function Hidden(sender)
	local M = ns.Moderation
	return M ~= nil and not M.missing and M.Hides ~= nil and M.Hides(sender) == true
end
local function OnRecord(dist, sender, mode, body)
	if mode ~= "L" or (dist ~= "CHANNEL" and dist ~= "WHISPER") then return Count("lane") end
	if Hidden(sender) then return Count("hidden") end
	local letter, rest = A().Fields(body, 2)
	if not (letter and R.TYPES[letter]) or not rest then return Count("type") end
	Take(letter, rest, sender, "relay") -- cancellation follows actual verification in Keep
end
ns.Comm.Handle("RR", ns.Arena.Handle("RR", OnRecord))

---------------------------------------------------------------------------
-- The seal (the author's, signed as the council lists are)
---------------------------------------------------------------------------

local function Hex(bytes) return (tostring(bytes):gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
local function HashOf(text) return Hex(ns.Sign.SHA256(text)) end
R.HashOf = HashOf

-- A month's totals as the seal hashes them: "Name-Realm,games,won,lost" (decimal) by name, ";" apart.
function R.RowsText(rows)
	local list = {}
	for _, r in ipairs(type(rows) == "table" and rows or {}) do
		local name = type(r) == "table" and type(r.name) == "string" and ns.FullName(r.name) or nil
		local g, w, l = r and tonumber(r.games), r and tonumber(r.won), r and tonumber(r.lost)
		if name and not name:find("[,;~|]") and g and w and l then
			list[#list + 1] = { k = name:lower(), s = ("%s,%d,%d,%d"):format(name, floor(g), floor(w), floor(l)) }
		end
	end
	table.sort(list, function(a, b) return a.k < b.k end)
	local out, seen = {}, {}
	for _, x in ipairs(list) do
		if not seen[x.k] then seen[x.k] = true out[#out + 1] = x.s end
	end
	return table.concat(out, ";"), #out
end
function R.ReadRows(text)
	local out = {}
	for part in (tostring(text or "") .. ";"):gmatch("([^;]*);") do
		local name, g, w, l = part:match("^([^,]+),(%d+),(%d+),(%d+)$")
		if name then out[#out + 1] = { name = name, games = tonumber(g), won = tonumber(w), lost = tonumber(l) } end
	end
	return out
end

-- This client's totals of a closed month (a draft), worked out once SEAL_AFTER after it ended: one
-- month a tick at most. The months its records name.
function R.Drafts(force)
	local now = Now()
	for letter, spec in pairs(R.TYPES) do
		local s = Store(letter)
		if s and spec.Totals then
			local months = {}
			for d in pairs(s.days) do months[R.MonthOf(d * 86400)] = true end
			local list = {}
			for m in pairs(months) do
				if (force or now >= R.MonthStart(m + 1) + R.SEAL_AFTER) and m < R.MonthOf(now) and not s.drafts[m] and not Adopted(s.seals[m]) then
					list[#list + 1] = m
				end
			end
			table.sort(list)
			if list[1] then
				local m = list[1]
				local ok, rows = pcall(spec.Totals, m)
				local text, n = R.RowsText(ok and rows or {})
				s.drafts[m] = { r = text, h = HashOf(text), n = n, at = now }
				if not force then return m end
			end
		end
	end
end
-- The seal requests the author signs: one line per closed month drafted and not sealed here.
function R.SealRequests()
	local out = {}
	for letter in pairs(R.TYPES) do
		local s = Store(letter)
		local months = {}
		for m, d in pairs(s and s.drafts or {}) do if type(d) == "table" and not Adopted(s.seals[m]) then months[#months + 1] = m end end
		table.sort(months)
		for _, m in ipairs(months) do
			local d = s.drafts[m]
			out[#out + 1] = ("RS1~%d~%s~%s~%s~%d~%d~%s"):format(Now(), tostring(ns.group or ns.realm), tostring(ns.faction or "Alliance"), letter, m, d.n, d.h)
		end
	end
	return out
end

local asm = {} -- [letter .. month] = { h8, k, parts, got, at }
local Adopt -- (below)
-- A signed seal (the text scripts/council-sign.py seal prints). how: "paste" (the author's, in
-- game), "relay" (RS). True when taken.
function R.TakeSeal(text, sender, how)
	if type(text) ~= "string" or #text > 900 then return Count("seal-shape") end
	text = text:match("^%s*(.-)%s*$")
	local signed, at, group, faction, letter, m, n, h, sig = text:match("^(RS1~(%d+)~([^~]+)~(%a+)~(%l)~(%d+)~(%d+)~(%x+))~(%x+)$")
	at, m, n = tonumber(at), tonumber(m), tonumber(n)
	if not (signed and at and m and n) or not R.TYPES[letter] or #h ~= 64 or n > R.SEAL_ROWS_MAX then return Count("seal-shape") end
	if group ~= tostring(ns.group or ns.realm) or faction ~= tostring(ns.faction or "Alliance") then return Count("seal-group") end
	if m >= R.MonthOf(Now()) or at > Now() + 86400 then return Count("seal-time") end
	local s = Store(letter, true)
	if not s then return Count("store") end
	local held = s.seals[m]
	if type(held) == "table" and (tonumber(held.at) or 0) >= at then return false, "held" end
	if not (ns.Sign.Plausible(sig) and ns.Sign.Verify(signed, sig)) then return Count("seal-signature") end
	h = h:lower()
	s.seals[m] = { s = text, h = h, n = n, at = at }
	stats.sealed = stats.sealed + 1
	EnsureTicker()
	-- Our own totals, when they hash the same: kept; else the seal's, from whoever holds them.
	local d = s.drafts[m]
	local rows = type(d) == "table" and d.h == h and d.r or nil
	if not rows then
		local spec = R.TYPES[letter]
		local ok, list = pcall(spec.Totals or function() return {} end, m)
		local mine = R.RowsText(ok and list or {})
		if HashOf(mine) == h then rows = mine end
	end
	if rows then Adopt(letter, m, rows) else AskSeal(letter, m) end
	if how == "paste" and Adopted(s.seals[m]) then SendSeal(letter, m) end
	return true
end
-- A seal's totals held: the type's months take them (the month's list for good), and the month's
-- old records go.
Adopt = function(letter, m, rows)
	local s = Store(letter, true)
	local seal = s and s.seals[m]
	if not seal or #rows > R.SEAL_ROWS_MAX * 100 or HashOf(rows) ~= seal.h then return false end
	local parsed = R.ReadRows(rows)
	local canonical, n = R.RowsText(parsed)
	if canonical ~= rows or n ~= seal.n then return false end
	seal.r = rows
	s.drafts[m] = nil
	asm[letter .. m] = nil
	local spec = R.TYPES[letter]
	if spec.Sealed then ns.SafeCall("records sealed", spec.Sealed, m, R.ReadRows(rows), seal) end
	R.Compact(letter)
	ns.Fire("RECORDS_CHANGED", letter)
	return true
end
function R.Sealed(letter, m)
	local s = Store(letter)
	local seal = s and s.seals[m]
	if not Adopted(seal) then return nil end
	return R.ReadRows(seal.r), seal
end
-- The seal and its totals on the low lane (an answer, the author's paste).
SendSeal = function(letter, m)
	local s = Store(letter)
	local seal = s and s.seals[m]
	if not Adopted(seal) then return false end
	Per(answeredAt, letter)["s" .. m] = Now()
	Out("RS", "s" .. letter .. m, seal.s, math.huge)
	local chunks, cur, size = {}, {}, 0
	for part in (seal.r .. ";"):gmatch("([^;]*);") do
		if part ~= "" then
			if size + #part + 1 > R.CHUNK and cur[1] then
				chunks[#chunks + 1] = table.concat(cur, ";")
				cur, size = {}, 0
			end
			cur[#cur + 1] = part
			size = size + #part + 1
		end
	end
	chunks[#chunks + 1] = table.concat(cur, ";")
	for i, c in ipairs(chunks) do
		Out("RT", "t" .. letter .. m .. "." .. i, table.concat({ letter, B36(m), seal.h:sub(1, 8), B36(i), B36(#chunks), c }, "~"), math.huge)
	end
	return true
end
local askedSeal, heardSealAsk = {}, {}
AskSeal = function(letter, m)
	local key, now = letter .. m, Now()
	if now - (askedSeal[key] or -math.huge) < R.ASK_GAP or now - (heardSealAsk[key] or -math.huge) < R.ANSWER_GAP then return false end
	askedSeal[key] = now
	local s = Store(letter)
	local seal = s and s.seals[m]
	return A().Send("RA", "L", ("%s~s~%s~%s"):format(letter, B36(m), Adopted(seal) and seal.h:sub(1, 8) or "-"),
		{ dist = "CHANNEL", key = "records seal ask " .. key, low = true }) == true
end

local function OnSeal(dist, sender, mode, body)
	if mode ~= "L" or (dist ~= "CHANNEL" and dist ~= "WHISPER") then return Count("lane") end
	local m = tonumber(tostring(body):match("^RS1~%d+~[^~]+~%a+~%l~(%d+)~"))
	local letter = tostring(body):match("^RS1~%d+~[^~]+~%a+~(%l)~")
	local accepted = R.TakeSeal(body, sender, "relay")
	local s = letter and R.TYPES[letter] and Store(letter)
	local held = s and s.seals[m]
	if accepted or (held and held.s == body) then
		Per(answeredAt, letter)["s" .. m] = Now()
		heardSealAsk[letter .. m] = Now()
	end
end
ns.Comm.Handle("RS", ns.Arena.Handle("RS", OnSeal))

local function OnTotals(dist, sender, mode, body)
	if mode ~= "L" or (dist ~= "CHANNEL" and dist ~= "WHISPER") then return Count("lane") end
	local letter, m, h8, i, k, rows = A().Fields(body, 6)
	m, i, k = N36(m, 0, 100000), N36(i, 1, 200), N36(k, 1, 200)
	if not (letter and R.TYPES[letter] and m and i and k and h8 and rows) or #h8 ~= 8 or not h8:find("^%x+$") or i > k or #rows > R.CHUNK then return Count("shape") end
	Per(answeredAt, letter)["s" .. m] = Now()
	local s = Store(letter)
	local seal = s and s.seals[m]
	if type(seal) ~= "table" or Adopted(seal) or seal.h:sub(1, 8) ~= h8:lower() then return end
	-- A forged chunk from another holder cannot occupy an honest holder's assembly slots.
	local key, now = letter .. m .. ":" .. (Low(sender) or "?"), Now()
	local a = asm[key]
	if not a or a.h8 ~= h8 or a.k ~= k or now - a.at > R.ASM_TTL then
		local n = 0
		for id, part in pairs(asm) do if now - part.at > R.ASM_TTL then asm[id] = nil else n = n + 1 end end
		if not a and n >= R.ASM_MAX then return Count("totals-full") end
		a = { h8 = h8, k = k, parts = {}, got = 0, at = now }
		asm[key] = a
	end
	if not a.parts[i] then a.parts[i], a.got = rows, a.got + 1 end
	if a.got < k then return end
	asm[key] = nil
	local text = table.concat(a.parts, ";", 1, k)
	if not Adopt(letter, m, text) then Count("seal-rows") end
end
ns.Comm.Handle("RT", ns.Arena.Handle("RT", OnTotals))

-- A sealed month's records older than COMPACT_DAYS go (its totals stay); nothing else ever does.
-- The number gone.
function R.Compact(letter)
	local s = Store(letter)
	if not s then return 0 end
	local x = Index(letter)
	local n = 0
	for d, list in pairs(s.days) do
		if Compacted(s, d) then
			for id, body in pairs(type(list) == "table" and list or {}) do
				Remove(x, d, id)
				if fingerprints[letter] then
					fingerprints[letter][body] = nil
					for _, other in ipairs(s.clash[id] or {}) do fingerprints[letter][other] = nil end
				end
				n = n + 1
			end
			s.days[d] = nil
			x.dig[d] = nil
		end
	end
	for id, p in pairs(s.pend) do
		if type(p) == "table" and tonumber(p.d) and Compacted(s, tonumber(p.d)) then s.pend[id] = nil end
	end
	stats.compacted = stats.compacted + n
	return n
end

---------------------------------------------------------------------------
-- The clock, the login, the slash
---------------------------------------------------------------------------

-- Every DIGEST_EVERY while this client holds anything: its digests (drawn), its key again, a
-- month's draft, the sealed months' old records, the records waiting their turn.
function R.Tick()
	for letter in pairs(R.TYPES) do
		if Drawn() then R.SendDigest(letter) end
	end
	if keySentAt and Now() - keySentAt >= R.KEY_EVERY and Named(Low(Me())) then R.SendKey() end
	R.Drafts()
	for letter in pairs(R.TYPES) do R.Compact(letter) end
	PumpWait()
end

-- A type's records (FarkleTable "b", ArenaLedger "d"): spec = { Read(body) -> { id, t, content,
-- parts = { { name, pk64, pk, sig64, sig, msg } } } | nil, why; Took(rec, how); Conflict(rec);
-- Totals(month) -> { { name, games, won, lost } }; Sealed(month, rows, seal); Mine() -> bodies of
-- its own records to take in at login; Pins() -> { [player] = pk base64url } heard first-hand;
-- Has() -> whether this client holds anything of it; DAY_MAX: records naming one player a day }.
function R.Register(letter, spec)
	if type(letter) ~= "string" or not letter:find("^%l$") or type(spec) ~= "table" or type(spec.Read) ~= "function" then return false end
	R.TYPES[letter] = spec
	idx[letter] = nil
	return true
end

-- After login: each type's own records and first-hand pins taken in, the records waiting for a
-- key looked at again, the sealed months' old records gone, the clock started, our key declared
-- when records name us.
function R.Load()
	for letter, spec in pairs(R.TYPES) do
		if spec.Pins then
			local ok, list = pcall(spec.Pins)
			for name, pk in pairs(ok and type(list) == "table" and list or {}) do R.Pin(name, pk, nil, true) end
		end
		if spec.Mine then
			local ok, list = pcall(spec.Mine)
			for _, body in ipairs(ok and type(list) == "table" and list or {}) do Take(letter, body, Me(), "self") end
		end
	end
	R.RecheckPending()
	for letter in pairs(R.TYPES) do R.Compact(letter) end
	EnsureTicker()
	if Named(Low(Me())) then KeyLater() end
end
ns.On("LOGIN", function()
	local any = Root(false) ~= nil
	for _, spec in pairs(R.TYPES) do
		if not any and spec.Has then
			local ok, has = pcall(spec.Has)
			any = ok and has == true
		end
	end
	if any then ns.After(R.LOAD_DELAY, "records load", R.Load) end
end)

-- `/oly arena records`: what this client holds, and the author's seal requests, in a window to copy
-- from; `/oly arena records seal`: the box to paste a signed seal in.
function R.StatusText()
	local lines = { L.RECORDS_TITLE }
	for _, letter in ipairs({ "b", "d" }) do
		if R.TYPES[letter] then
			local s = Store(letter)
			local sealed = 0
			for _, seal in pairs(s and s.seals or {}) do if Adopted(seal) then sealed = sealed + 1 end end
			lines[#lines + 1] = L.RECORDS_LINE:format(L["RECORDS_TYPE_" .. letter] or letter, R.Count(letter), R.Pending(letter), #R.Clashes(letter), sealed)
		end
	end
	local keys = 0
	for _ in pairs((Root(false) or {}).keys or {}) do keys = keys + 1 end
	lines[#lines + 1] = L.RECORDS_KEYS:format(keys)
	R.Drafts(true)
	local req = R.SealRequests()
	if req[1] then
		lines[#lines + 1] = ""
		lines[#lines + 1] = L.RECORDS_REQUESTS
		for _, r in ipairs(req) do lines[#lines + 1] = r end
	end
	return table.concat(lines, "\n")
end
function R.Paste(text)
	local ok = R.TakeSeal(text, Me(), "paste")
	ns.Print(ok and L.RECORDS_SEAL_TAKEN or L.RECORDS_SEAL_BAD)
	return ok
end
function R.Slash(args)
	if tostring(args or ""):lower():match("^%s*seal") then return ns.ShowDialog("OLYMPUS_RECORDS_SEAL") end
	local text = R.StatusText()
	local UI = ns.UI
	if type(UI) == "table" and type(UI.ShowCopy) == "function" then return UI.ShowCopy(L.RECORDS_TITLE, text, nil, { key = "records" }) end
	for line in text:gmatch("[^\n]+") do ns.Print(line) end
end
ns.Arena.Slash("records", function(args) R.Slash(args) end, L.RECORDS_HELP)

StaticPopupDialogs["OLYMPUS_RECORDS_SEAL"] = {
	text = L.RECORDS_SEAL_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 320,
	maxLetters = 900,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText("") end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("records seal", R.Paste, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local text = self:GetText()
		self:GetParent():Hide()
		ns.SafeCall("records seal", R.Paste, text)
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Tests only: a clean state (a new world's client starts clean anyway).
function R.Reset()
	idx, checking, inflight, waitq = {}, {}, 0, {}
	outq, outSet = {}, {}
	lastDigest, heardDigest, askedAt, heardAsk, answeredAt, answering, askCursor = {}, {}, {}, {}, {}, {}, {}
	askedSeal, heardSealAsk, asm = {}, {}, {}
	from, attempts, fromDay = {}, {}, -1
	keySentAt, keyDue = nil, false
	fingerprints = {}
	if ticker and ticker.Cancel then ticker.Cancel() end
	ticker = nil
end
