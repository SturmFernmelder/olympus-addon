local ADDON, ns = ...
local Church, C = ns.Church, ns.Codec
local F = {}
ns.ChurchFullness = F

-- Client-observed guild fullness, not a census estimate or a server-certified 24h claim.
-- A correspondent may send only a live observation of his own complete native roster.
-- Keepers relay retained individual observations they admitted, only when asked privately.
-- Old evidence folds locally into a checkpoint; checkpoints are NEVER accepted over the wire.
local DAY = 86400
F.DAYS_KEEP, F.FACTS_MAX, F.DAY_MAX, F.GUILDS_MAX = 7, 20000, 4096, 128
F.REPLY_MAX, F.ASK_GAP, F.ASK_WINDOW = 150, 120, 600
local asked, replied, cursors, generation = {}, {}, {}, nil
local function Key(n) return Church.Key(n) end
local function Same(a, b) return ns.Fold(ns.Normal(ns.FullName(a))) == ns.Fold(ns.Normal(ns.FullName(b))) end
local function Keeper(n)
	if not Church.IsKeeper(n) then return false end
	if Church.IsAuthor(n) then return true end
	local a = Church.State().apostle[Key(n)]
	return a and Same(a.n, n) or false
end
local function Audience(n)
	if not Church.InAudience(n) then return false end
	if Church.IsAuthor(n) then return true end
	if Church.IsKing(n) then return Same(n, Church.HeadName()) end
	if ns.IsHighCouncillor(ns.FullName(n)) then return true end
	local s, k = Church.State(), Key(n)
	local p = s.apostle[k] or s.miss[k]
	if p and Same(p.n, n) then return true end
	local g = s.corrOf[k]; return g and Same(s.corr[g].n, n) or false
end
local function GKey(g) return ns.Fold(g) end
local function Clock()
	local t = type(GetServerTime) == "function" and GetServerTime()
	if type(t) == "number" and t == math.floor(t) and t > 0 then return t end
end
local function Int(n, lo, hi)
	n = tonumber(n)
	return n and n == math.floor(n) and n >= lo and n <= hi and n or nil
end
local function Preview() return ns.ViewAs and ns.ViewAs.Previewing and ns.ViewAs.Previewing() end
local function Active() return ns.IsMember() == true and not Preview() and not (ns.Moderation and ns.Moderation.SelfOff and ns.Moderation.SelfOff()) end
local function Book()
	if not ns.rdb then return nil end
	if type(ns.rdb.churchFullness) ~= "table" then ns.rdb.churchFullness = { guilds = {}, seq = 0 } end
	local b = ns.rdb.churchFullness
	if type(b.guilds) ~= "table" then b.guilds = {} end
	b.seq = Int(b.seq, 0, 1000000000) or 0
	return b
end
F.Book = Book
local function Correspondent(sender, guild, appt)
	local s = Church.State(); local gk = GKey(guild); local c = s.corr[gk]
	return c and not s.corrCensus[gk] and Same(c.n, sender) and c.at == appt
end
local function Guild(guild, create)
	local b = Book(); if not b then return nil end
	local k = GKey(guild); local g = b.guilds[k]
	if not g and create then
		local n = 0; for _ in pairs(b.guilds) do n = n + 1 end
		if n >= F.GUILDS_MAX then return nil end
		g = { name = guild, days = {}, base = { days = 0, sum = 0, known = false } }; b.guilds[k] = g
	end
	return g
end
local function DayValue(d)
	local n, sum, bad = 0, 0, d.bad == true
	for _, r in pairs(d.r) do
		local weight = (r.upto or r.seq) - r.seq + 1
		n, sum, bad = n + weight, sum + r.n * weight, bad or r.n <= 950
	end
	if bad then return "break", nil end
	if d.overflow or n == 0 then return "unknown", nil end
	return "full", sum / n
end
local function Apply(s, d)
	local state, avg = DayValue(d)
	if state == "break" then s.days, s.sum, s.known = 0, 0, true
	elseif state == "full" then s.days, s.sum, s.known = s.days + 1, s.sum + avg, true end
	return state
end
function F.Prune()
	local t, b = Clock(), Book(); if not t or not b then return end
	local today, total = math.floor(t / DAY), 0
	if b.pruned == today and type(b.count) == "number" then return end
	for _, g in pairs(b.guilds) do
		local days = {}; for day in pairs(g.days) do days[#days + 1] = day end; table.sort(days)
		for _, day in ipairs(days) do
			local d = g.days[day]
			if day < today - F.DAYS_KEEP then
				if not g.base.last or day > g.base.last then Apply(g.base, d); g.base.last = day end
				g.days[day] = nil
			else d.count = 0; for _ in pairs(d.r) do total, d.count = total + 1, d.count + 1 end end
		end
	end
	b.count, b.pruned = total, today
end
local function Put(guild, actor, appt, at, seq, n, upto, untilAt)
	local t = Clock(); if not t then return false end
	upto, untilAt = upto or seq, untilAt or at
	local day = math.floor(at / DAY); local today = math.floor(t / DAY)
	if day > today or day < today - F.DAYS_KEEP then return false end
	local g = Guild(guild, true); if not g or (g.base.last and day <= g.base.last) then return false end
	local d = g.days[day]; if not d then d = { r = {} }; g.days[day] = d end
	local prefix = Key(actor) .. ":" .. appt .. ":"
	local merge = {}
	for key, old in pairs(d.r) do
		if Key(old.actor) == Key(actor) and old.appt == appt then
			local finish = old.upto or old.seq
			local overlaps = seq <= finish and upto >= old.seq
			if overlaps and old.n ~= n then
				d.overflow = true; if n <= 950 then d.bad = true end
				ns.Fire("CHURCH_FULLNESS_CHANGED")
				return false
			end
			if old.n == n and seq <= finish + 1 and upto >= old.seq - 1 then
				if seq >= old.seq and upto <= finish then return false end -- replay/subset
				merge[#merge + 1] = key
				if old.seq < seq then seq, at = old.seq, old.at end
				if finish > upto then upto, untilAt = finish, old.untilAt or old.at end
			end
		end
	end
	local b = Book()
	if #merge == 0 and ((d.count or 0) >= F.DAY_MAX or (b.count or 0) >= F.FACTS_MAX) then
		d.overflow = true; if n <= 950 then d.bad = true end
		ns.Fire("CHURCH_FULLNESS_CHANGED")
		return false
	end
	for _, key in ipairs(merge) do d.r[key] = nil end
	d.r[prefix .. seq] = { actor = actor, appt = appt, at = at, seq = seq, n = n, guild = guild, upto = upto, untilAt = untilAt }
	d.count = (d.count or 0) + 1 - #merge
	b.count = (b.count or 0) + 1 - #merge
	ns.Fire("CHURCH_FULLNESS_CHANGED")
	return true
end
local function Wire(r, kind, nonce)
	if r.uncertain then return table.concat({ "NF", "1", "u", nonce, r.guild, C.Base36(r.day), r.bad and "1" or "0" }, "~") end
	local fields = { "NF", "1", kind, nonce or "-", r.guild, ns.FullName(r.actor), C.Base36(r.appt), C.Base36(r.at), C.Base36(r.seq), C.Base36(r.n) }
	if kind == "r" then fields[#fields + 1], fields[#fields + 2] = C.Base36(r.upto or r.seq), C.Base36(r.untilAt or r.at) end
	return table.concat(fields, "~")
end
local function AllowedSend(target)
	return Active() and Keeper(ns.me) and not Church.IsKing(ns.me) and Audience(target)
		and not (ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(target))
end
function F.Observe()
	if not Active() then return false end
	local t = Clock(); local R = ns.Roster and ns.Roster.Fresh and ns.Roster.Fresh()
	if not t or not R or not R.complete or generation == R.generation then return false end
	local stats = R.lastStats
	-- Never substitute #online, filtered rows, Data.Guild.total, or a stale cached census.
	local n = stats and Int(stats.numTotal, 0, C.GUILD_CAP)
	if not n or stats.seen ~= n or type(R.members) ~= "table" or #R.members ~= n then return false end
	local guild = Church.OwnGuild(); if not guild or R.guild ~= guild or not ns.IsFederation(guild) then return false end
	local c = Church.State().corr[GKey(guild)]
	if not c or not Correspondent(ns.me, guild, c.at) or not R.byName[ns.FullName(ns.me)] then return false end
	local captured = Int(R.serverAt, c.at, t + Church.DATE_AHEAD)
	if not captured then return false end
	generation = R.generation; F.Prune()
	local b = Book(); if not b or b.seq >= 1000000000 then return false end
	b.seq = b.seq + 1
	local r = { guild = guild, actor = ns.FullName(ns.me), appt = c.at, at = captured, seq = b.seq, n = n }
	Put(guild, r.actor, r.appt, captured, r.seq, n)
	local desk = Church.Desk()
	if desk and Key(desk) ~= Key(ns.me) then
		ns.Comm.Whisper(desk, Wire(r, "o"), "church-fullness-observe:" .. b.seq, false, false, nil, { guard = function()
			local now = Clock()
			return Active() and now and now - r.at <= Church.DATE_AHEAD and Keeper(desk)
				and Correspondent(ns.me, guild, r.appt) and Church.OwnGuild() == guild
		end })
	end
	return true
end
function F.Ask()
	if not Active() or not Audience(ns.me) then return false end
	local t = Clock(); local desk = Church.Desk(); if not t or not desk or Key(desk) == Key(ns.me) then return false end
	local k = Key(desk); if asked[k] and t - asked[k].at < F.ASK_GAP then return false end
	local nonce = C.Base36(t)
	asked[k] = { at = t, nonce = nonce }
	return ns.Comm.Whisper(desk, "NF~1~q~" .. nonce, "church-fullness-ask", false, false, nil, { guard = function()
		return Active() and Audience(ns.me) and Keeper(desk)
	end })
end
local function Answer(sender, nonce)
	if not AllowedSend(sender) then return false end
	local t = Clock(); local k = Key(sender); if not t or (replied[k] and t - replied[k] < F.ASK_GAP) then return false end
	replied[k] = t; F.Prune()
	local facts = {}; for _, g in pairs(Book().guilds) do for day, d in pairs(g.days) do
		for _, r in pairs(d.r) do facts[#facts + 1] = r end
		if d.overflow or d.bad then facts[#facts + 1] = { uncertain = true, guild = g.name, day = day, at = day * DAY, bad = d.bad } end
	end end
	table.sort(facts, function(a, b) if a.at ~= b.at then return a.at < b.at end return Wire(a, "r", nonce) < Wire(b, "r", nonce) end)
	local cap = math.min(F.REPLY_MAX, ns.Comm.QueueRoom())
	local start = cursors[k] or 0
	for i = 1, math.min(cap, #facts) do
		local r = facts[(start + i - 1) % #facts + 1]
		ns.Comm.Whisper(sender, Wire(r, "r", nonce), "church-fullness-reply:" .. k .. ":" .. i, false, false, nil,
			{ guard = function() return AllowedSend(sender) end })
	end
	if #facts > 0 then cursors[k] = (start + math.min(cap, #facts)) % #facts end
	return true
end
function F.Receive(dist, sender, text)
	if dist ~= "WHISPER" or not Active() or not Audience(ns.me) or (ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(sender)) then return false end
	local nonce = tostring(text):match("^NF~1~q~([0-9a-z]+)$")
	if nonce then return Answer(sender, nonce) end
	local request, guild, day, bad = tostring(text):match("^NF~1~u~([0-9a-z]+)~([^~]+)~([0-9a-z]+)~([01])$")
	if request then
		local t = Clock(); local a = asked[Key(sender)]; day = #day <= 8 and tonumber(day, 36) or nil
		if not t or not a or a.nonce ~= request or t - a.at > F.ASK_WINDOW or not Keeper(sender)
			or #guild > 64 or not ns.IsFederation(guild) or not Int(day, math.floor(t / DAY) - F.DAYS_KEEP, math.floor(t / DAY)) then return false end
		F.Prune(); local g = Guild(guild, true); if not g or (g.base.last and day <= g.base.last) then return false end
		local d = g.days[day] or { r = {}, count = 0 }; g.days[day] = d
		d.overflow = true; if bad == "1" then d.bad = true end
		ns.Fire("CHURCH_FULLNESS_CHANGED")
		return true
	end
	local kind, actor, appt, at, seq, n, upto, untilAt
	kind, request, guild, actor, appt, at, seq, n = tostring(text):match("^NF~1~(o)~([^~]+)~([^~]+)~([^~]+)~([0-9a-z]+)~([0-9a-z]+)~([0-9a-z]+)~([0-9a-z]+)$")
	if not kind then kind, request, guild, actor, appt, at, seq, n, upto, untilAt = tostring(text):match("^NF~1~(r)~([^~]+)~([^~]+)~([^~]+)~([0-9a-z]+)~([0-9a-z]+)~([0-9a-z]+)~([0-9a-z]+)~([0-9a-z]+)~([0-9a-z]+)$") end
	local t = Clock(); if not kind or not t or #guild > 64 or #actor > 72 or not ns.IsFederation(guild) then return false end
	if #appt > 8 or #at > 8 or #seq > 8 or #n > 8 then return false end
	appt, at, seq, n = tonumber(appt, 36), tonumber(at, 36), tonumber(seq, 36), tonumber(n, 36)
	if not Int(appt, 1, t) or not Int(at, appt, t + Church.DATE_AHEAD) or not Int(seq, 1, 1000000000) or not Int(n, 0, C.GUILD_CAP)
		or not Church.InputName(actor) then return false end
	if kind == "o" then
		if request ~= "-" or not Keeper(ns.me) or Church.IsKing(ns.me) or not Same(sender, actor)
			or t - at > Church.DATE_AHEAD or math.floor(at / DAY) ~= math.floor(t / DAY) or not Correspondent(sender, guild, appt) then return false end
	else
		local a = asked[Key(sender)]
		if not Keeper(sender) or not a or a.nonce ~= request or t - a.at > F.ASK_WINDOW then return false end
		if #upto > 8 or #untilAt > 8 then return false end
		upto, untilAt = tonumber(upto, 36), tonumber(untilAt, 36)
		if not Int(upto, seq, math.min(1000000000, seq + 4319)) or not Int(untilAt, at, t + Church.DATE_AHEAD)
			or math.floor(untilAt / DAY) ~= math.floor(at / DAY) then return false end
	end
	F.Prune()
	return Put(guild, ns.FullName(actor), appt, at, seq, n, upto, untilAt)
end
function F.Ranking()
	F.Prune(); local t, rows = Clock(), {}
	for _, c in pairs(Church.State().corr) do
		local g = Guild(c.g); local s = { days = 0, sum = 0, known = false }
		local latest, state
		if g then
			for k, v in pairs(g.base) do s[k] = v end
			local days = {}; for day in pairs(g.days) do if t and day < math.floor(t / DAY) then days[#days + 1] = day end end; table.sort(days)
			for _, day in ipairs(days) do state = Apply(s, g.days[day]); latest = day end
		end
		local yesterday = t and math.floor(t / DAY) - 1
		if not yesterday or latest ~= yesterday then state = "unknown" end
		rows[#rows + 1] = { guild = c.g, name = c.n, key = GKey(c.g), days = s.known and s.days or nil,
			average = s.days > 0 and s.sum / s.days or nil, state = state or "unknown", completed = yesterday }
	end
	table.sort(rows, function(a, b)
		if a.days ~= b.days then return (a.days or -1) > (b.days or -1) end
		if a.average ~= b.average then return (a.average or -1) > (b.average or -1) end
		return a.key < b.key
	end)
	for i, row in ipairs(rows) do row.rank = i end
	return rows
end
ns.Comm.Handle("NF", F.Receive)
ns.On("DATA_CHANGED", F.Observe)
ns.On("LOGIN", function()
	local lastDay
	ns.Every(30, "Church fullness", function()
		local t = Clock(); local day = t and math.floor(t / DAY)
		if day and day ~= lastDay then lastDay = day; ns.Fire("CHURCH_FULLNESS_CHANGED") end
		F.Observe()
	end)
end)
