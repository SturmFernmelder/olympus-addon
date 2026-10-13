local _, ns = ...
local J = {}; ns.JusticeTasks = J
-- Deliberate expulsion requests, not new kick powers. Only the two original actors exchange
-- facts by logged private whisper. An API attempt or subsequent absence is never completion.
J.MAX, J.KEEP, J.MAX_ISSUERS, J.EVERY = 60, 30 * 86400, 128, 60
J.RETRY_MAX = 20
local pending, observations = {}, {}
local function Now() return math.floor(GetServerTime and GetServerTime() or ns.Now()) end
local function Word(key, fallback) return ns.L and rawget(ns.L, key) or fallback end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and ns.Fold(a) == ns.Fold(b) end
local function Name(s)
	if type(s) ~= "string" or s == "" or #s > 72 or s:find("[~|%c]") then return nil end
	local full = ns.FullName(s)
	return type(full) == "string" and #full <= 72 and full or nil
end
local function Number(x)
	x = tonumber(x); return x and x == math.floor(x) and x >= 0 and x <= 2147483647 and x or nil
end
local function Preview()
	local V = ns.ViewAs; local K = ns.King
	return (V and V.Previewing and V.Previewing()) or (K and K.Preview and K.Preview()) or false
end
local function Roster()
	local R = ns.IsMember() == true and ns.Roster and ns.Roster.Fresh and ns.Roster.Fresh() or nil
	return R and R.complete == true and R or nil
end
local function Guild() local R = Roster(); return R and R.guild end
local function Member(name, guild)
	local who, R = Name(name), Roster()
	return who and R and Same(R.guild, guild) and R.byName[who] ~= nil and who or nil
end
local function InGroup(name)
	local realm = ns.RealmOf and ns.RealmOf(name)
	return realm and ns.GroupOf(realm) == ns.group
end
local function Issuer(name)
	name = Name(name)
	if not name or not InGroup(name) then return false end
	local M, W = ns.Moderation, ns.WatchChat
	if M and M.Hides and M.Hides(name, nil, true) then return false end
	if W and W.PowersBarred and W.PowersBarred(name) then return false end
	return (ns.IsKingCharacter(name) == true and ns.KingRealm and ns.KingRealm() ~= nil) or ns.IsHighCouncillor(name) == true
end
function J.CanIssue() return not Preview() and Roster() ~= nil and Issuer(ns.me) end
function J.Staff()
	return not Preview() and Roster() ~= nil and (Issuer(ns.me) or (ns.Workshop and ns.Workshop.IsAuthor and ns.Workshop.IsAuthor() == true)) or false
end
local function Correspondent(name, guild)
	name = Name(name)
	if not name or type(guild) ~= "string" or #guild > 72 or not ns.IsFederation(guild) then return false end
	local N, W = ns.Nominees, ns.WatchChat
	if Same(guild, Guild()) then
		if not Member(name, guild) then return false end
		return W and W.Justice and Same(W.Justice(), name) or false
	end
	-- A census-claimed title or guild is never enough to address another guild's correspondent.
	local rank, source = ns.Data.AuthorizedRank(name, guild)
	if rank == nil or (source ~= "signed" and source ~= "pinned") then return false end
	local list = N and N.ListOf and N.ListOf(guild)
	local master, origin
	if list then master, origin = ns.Data.AuthorizedRank(list.by, guild) end
	return master == 0 and (origin == "signed" or origin == "pinned") and N.IsCorrespondent(name, guild, "Council of Justice") == true or false
end
function J.Own() return not Preview() and Correspondent(ns.me, Guild()) end
function J.Visible() return J.Staff() or J.Own() end
local function Bucket(make)
	if type(ns.rdb) ~= "table" or type(ns.group) ~= "string" or type(ns.faction) ~= "string" then return nil end
	local all = ns.rdb.justiceTasks
	if all == nil and make then all = {}; ns.rdb.justiceTasks = all end
	if type(all) ~= "table" then return nil end
	local key = ns.group .. "|" .. ns.faction
	local s = all[key]
	if s == nil and make then
		local count = 0; for _ in pairs(all) do count = count + 1 end
		if count >= 8 then return nil end
		s = { tasks = {}, floors = {}, seq = 0 }; all[key] = s
	end
	return type(s) == "table" and type(s.tasks) == "table" and type(s.floors) == "table" and Number(s.seq) and s or nil
end
local function Key(issuer, seq) return ns.Fold(issuer) .. "#" .. seq end
local function Valid(t)
	return type(t) == "table" and Name(t.issuer) == t.issuer and Name(t.assignee) == t.assignee and Name(t.subject) == t.subject
		and type(t.guild) == "string" and t.guild ~= "" and #t.guild <= 72 and not t.guild:find("[~|%c]")
		and Number(t.seq) and t.seq > 0 and Number(t.createdAt) and t.createdAt > 0
		and Number(t.receivedAt or 0) and Number(t.attemptedAt or 0) and Number(t.absentAt or 0)
		and (t.cancelledAt == nil or Number(t.cancelledAt)) and (t.confirmedAt == nil or (Number(t.confirmedAt) and Same(t.confirmedBy, t.issuer)))
end
local function Retire(s, key, t)
	local actor = ns.Fold(t.issuer)
	s.floors[actor] = math.max(s.floors[actor] or 0, t.seq); s.tasks[key] = nil
end
function J.Prune()
	local s = Bucket(false); if not s then return end
	for key, t in pairs(s.tasks) do
		if Valid(t) and Now() - t.createdAt > J.KEEP then Retire(s, key, t) end
	end
end
local function Room(s, issuer)
	if s.floors[ns.Fold(issuer)] == nil then
		local count = 0; for _ in pairs(s.floors) do count = count + 1 end
		if count >= J.MAX_ISSUERS then return false end
	end
	local count = 0; for _ in pairs(s.tasks) do count = count + 1 end
	return count < J.MAX
end
local function Live(t)
	return Valid(t) and not t.cancelledAt and not t.confirmedAt and Now() - t.createdAt <= J.KEEP and Issuer(t.issuer)
end
local function OwnTask(t)
	return Live(t) and J.Own() and Same(t.assignee, ns.me) and Same(t.guild, Guild()) and not Same(t.subject, ns.me)
end
local function Changed() ns.Fire("WATCH_CHANGED") end
local function Code() return ns.faction == "Horde" and "H" or "A" end
local function Wire(op, ...) return "JT~1~" .. op .. "~" .. Code() .. "~" .. table.concat({ ... }, "~") end
local function Send(to, text, t, role)
	if #text > 255 then return false end
	local identity, group, faction = Key(t.issuer, t.seq), ns.group, ns.faction
	return ns.Comm.Whisper(to, text, "justice:" .. identity .. ":" .. role, false, true, nil,
		{ owner = J, key = identity .. ":" .. role, permit = function(owner, key, dist, target, payload)
			if owner ~= J or key ~= identity .. ":" .. role or dist ~= "WHISPER" or not Same(to, target) or payload ~= text
				or Preview() or ns.group ~= group or ns.faction ~= faction then return false end
			local s = Bucket(false); if not s or s.tasks[identity] ~= t or not Issuer(t.issuer) then return false end
			if role == "receipt" then return OwnTask(t) and Same(to, t.issuer) end
			if role == "terminal-ack" then return Valid(t) and J.Own() and Same(t.assignee, ns.me) and Same(t.guild, Guild())
				and Same(to, t.issuer) and (t.cancelledAt ~= nil or t.confirmedAt ~= nil) end
			return J.CanIssue() and Same(ns.me, t.issuer) and Correspondent(t.assignee, t.guild)
				and ((role == "issue" and Live(t)) or (role == "cancel" and t.cancelledAt ~= nil) or (role == "confirm" and t.confirmedAt ~= nil))
		end })
end
local function IssueWire(t) return Wire("I", t.seq, t.createdAt, t.guild, t.assignee, t.subject) end
local function Receipt(t)
	return Send(t.issuer, Wire("R", t.issuer, t.seq, t.receivedAt or 0, t.attemptedAt or 0, t.absentAt or 0), t, "receipt")
end
local function Terminal(t)
	if t.terminalAck or (t.terminalTries or 0) >= J.RETRY_MAX then return false end
	t.terminalTries = (t.terminalTries or 0) + 1
	return Send(t.assignee, t.cancelledAt and Wire("X", t.seq, t.cancelledAt) or Wire("F", t.seq, t.confirmedAt), t, t.cancelledAt and "cancel" or "confirm")
end
local function TerminalAck(t)
	return Send(t.issuer, Wire("A", t.issuer, t.seq, t.cancelledAt and "X" or "F", t.cancelledAt or t.confirmedAt), t, "terminal-ack")
end
function J.Retry(key)
	local s = Bucket(false); local t = s and s.tasks[key]
	if not J.CanIssue() or not Valid(t) or not Same(t.issuer, ns.me) or not Issuer(t.issuer) or not (t.cancelledAt or t.confirmedAt) then return false end
	t.terminalTries = 0; return Terminal(t)
end
function J.Issue(guild, assignee, subject)
	if not J.CanIssue() or type(guild) ~= "string" or guild == "" or #guild > 72 or guild:find("[~|%c]") then return false, "authority" end
	assignee, subject = Name(assignee), Name(subject)
	if not assignee or not subject or not Correspondent(assignee, guild) or Same(subject, assignee) or ns.IsKingCharacter(subject) then return false, "identity" end
	if Same(guild, Guild()) and not Member(subject, guild) then return false, "member" end
	J.Prune(); local s = Bucket(true)
	if not s or not Room(s, ns.me) then return false, "full" end
	for _, old in pairs(s.tasks) do if Live(old) and Same(old.guild, guild) and Same(old.subject, subject) then return false, "already" end end
	s.seq = math.max(Now(), s.seq + 1)
	local t = { issuer = ns.FullName(ns.me), seq = s.seq, createdAt = Now(), guild = guild, assignee = assignee, subject = subject }
	local key = Key(t.issuer, t.seq); s.tasks[key] = t; s.floors[ns.Fold(t.issuer)] = s.floors[ns.Fold(t.issuer)] or 0
	Send(assignee, IssueWire(t), t, "issue"); Changed(); return true, key
end
function J.Tasks()
	if not J.Visible() then return {} end
	J.Prune(); local out, s = {}, Bucket(false)
	for key, t in pairs(s and s.tasks or {}) do
		if Valid(t) and (J.Staff() or (Same(t.assignee, ns.me) and Same(t.guild, Guild()))) then out[#out + 1] = { key = key, task = t } end
	end
	table.sort(out, function(a, b) return a.task.createdAt > b.task.createdAt end); return out
end
function J.Cancel(key)
	local s = Bucket(false); local t = s and s.tasks[key]
	if not J.CanIssue() or not Live(t) or not Same(t.issuer, ns.me) then return false end
	t.cancelledAt = Now(); pending[key] = nil
	Terminal(t); Changed(); return true
end
function J.Confirm(key)
	local s = Bucket(false); local t = s and s.tasks[key]
	if not J.CanIssue() or not Live(t) or not Same(t.issuer, ns.me) or not t.receivedAt or t.receivedAt == 0 or not t.attemptedAt or t.attemptedAt == 0 or not t.absentAt or t.absentAt == 0
		or t.attemptedAt < t.receivedAt or t.absentAt < t.attemptedAt then return false end
	t.confirmedAt, t.confirmedBy = Now(), ns.me
	Terminal(t); Changed(); return true
end
function J.AskRemoval(key)
	local s = Bucket(false); local t = s and s.tasks[key]
	if not OwnTask(t) or not t.receivedAt or t.attemptedAt then return false end
	local R, M = Roster(), ns.Members
	if not R or not M or not M.CanRemove() then return false end
	local target
	for _, row in ipairs(R.members or {}) do if Same(ns.FullName(row.raw or row.name or ""), t.subject) then target = row; break end end
	if not target or not M.Removable(target) then return false end
	local copy = {}; for k, v in pairs(target) do copy[k] = v end
	local reference = {}; copy.justiceTask = reference
	pending[key] = { reference = reference, subject = t.subject, guild = t.guild, generation = R.generation, capturedAt = R.snapshotAt }
	return M.AskRemove(copy)
end
function J.MayRemove(row)
	local s, R = Bucket(false), Roster(); if not s or not R then return false end
	for key, p in pairs(pending) do
		local t = s.tasks[key]
		if p.reference == row.justiceTask and OwnTask(t) and not t.attemptedAt and Same(ns.FullName(row.raw), t.subject) then
			local rank = R.byName[t.subject]
			if type(rank) ~= "number" or rank < 1 or rank <= ns.Roster.MyRank() then return false end
			p.generation, p.capturedAt = R.generation, R.snapshotAt
			return true
		end
	end
	return false
end
local function Attempt(row, guild)
	if type(row) ~= "table" or not row.justiceTask then return end
	local s, R = Bucket(false), Roster(); if not s or not R then return end
	for key, p in pairs(pending) do
		local t = s.tasks[key]
		if p.reference == row.justiceTask and OwnTask(t) and Same(guild, t.guild) and Same(ns.FullName(row.raw), t.subject)
			and Member(t.subject, guild) and R.generation == p.generation then
			t.attemptedAt = Now()
			observations[key] = { generation = R.generation, snapshotAt = R.snapshotAt }
			pending[key] = nil; Receipt(t); Changed(); return
		end
	end
end
function J.Observe()
	local s, R = Bucket(false), Roster(); if not s or not R or not J.Own() then return end
	for key, t in pairs(s.tasks) do
		local capture = observations[key]
		-- Generations are process-local: never compare a saved generation to a later login.
		-- Across reload, only a native server-dated complete scan strictly after the attempt
		-- can supply an observation; an unavailable clock leaves it pending.
		local after = capture and R.generation > capture.generation and R.snapshotAt >= capture.snapshotAt
			or (not capture and Number(R.serverAt) and t.attemptedAt and R.serverAt > t.attemptedAt)
		if OwnTask(t) and t.attemptedAt and not t.absentAt and after and not Member(t.subject, t.guild) then
			t.absentAt = Now(); Receipt(t); Changed()
		end
	end
end
function J.Handle(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > 255 or Preview() or not Roster() then return false end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then return false end
	sender = Name(sender); if not sender or not InGroup(sender) then return false end
	local op, code, rest = text:match("^JT~1~([IRXFA])~([AH])~(.*)$")
	if not op or code ~= Code() then return false end
	local f = {}; for part in (rest .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
	J.Prune()
	if op == "I" then
		local seq, at, guild, assignee, subject = Number(f[1]), Number(f[2]), f[3], Name(f[4]), Name(f[5])
		if #f ~= 5 or not Issuer(sender) or not J.Own() or not seq or seq == 0 or not at or at > Now() + 60 or Now() - at > J.KEEP
			or not Same(guild, Guild()) or not Same(assignee, ns.me) or not Member(subject, guild) or Same(subject, ns.me) or ns.IsKingCharacter(subject) then return false end
		local s = Bucket(true); if not s then return false end
		local key = Key(sender, seq); local old = s.tasks[key]
		if old then
			if not Valid(old) or old.createdAt ~= at or not Same(old.guild, guild) or not Same(old.assignee, assignee) or not Same(old.subject, subject) then return false end
			if not OwnTask(old) then return false end
			Receipt(old); return true
		end
		if seq <= (s.floors[ns.Fold(sender)] or 0) or not Room(s, sender) then return false end
		local t = { issuer = sender, seq = seq, createdAt = at, guild = guild, assignee = assignee, subject = subject, receivedAt = Now() }
		s.tasks[key] = t; s.floors[ns.Fold(sender)] = s.floors[ns.Fold(sender)] or 0
		Receipt(t); Changed(); return true
	elseif op == "R" then
		local issuer, seq, received, attempted, absent = Name(f[1]), Number(f[2]), Number(f[3]), Number(f[4]), Number(f[5])
		local s = Bucket(false); local t = issuer and seq and s and s.tasks[Key(issuer, seq)]
		if #f ~= 5 or not J.CanIssue() or not Valid(t) or not Same(t.issuer, ns.me) or not Same(sender, t.assignee) or not Correspondent(sender, t.guild)
			or not received or received < t.createdAt or received > Now() + 60 or not attempted or not absent
			or (attempted > 0 and (attempted < received or attempted > Now() + 60)) or (absent > 0 and (attempted == 0 or absent < attempted or absent > Now() + 60)) then return false end
		if t.cancelledAt or t.confirmedAt then
			if Now() - (t.recoveryAt or 0) >= J.EVERY then t.recoveryAt = Now(); t.terminalTries = 0; Terminal(t) end
			return false
		end
		if t.receivedAt and t.receivedAt ~= received then return false end
		if (t.attemptedAt and t.attemptedAt ~= attempted) or (t.absentAt and t.absentAt ~= absent) then return false end
		t.receivedAt = received
		if attempted > 0 then t.attemptedAt = attempted end
		if absent > 0 then t.absentAt = absent end
		Changed(); return true
	elseif op == "X" or op == "F" then
		local seq = Number(f[1]); local s = Bucket(false); local t = seq and s and s.tasks[Key(sender, seq)]
		if op == "X" and #f == 2 and Number(f[2]) and tonumber(f[2]) <= Now() + 60 and seq and seq > 0 and Issuer(sender) and J.Own() and not t then
			s = Bucket(true); if not s or not Room(s, sender) then return false end
			s.floors[ns.Fold(sender)] = math.max(s.floors[ns.Fold(sender)] or 0, seq); return true
		end
		if not Valid(t) or not J.Own() or not Same(t.assignee, ns.me) or not Same(t.guild, Guild()) or not Same(sender, t.issuer) or not Issuer(sender) then return false end
		if op == "X" and #f == 2 and Number(f[2]) and tonumber(f[2]) >= t.createdAt and tonumber(f[2]) <= Now() + 60 and not t.confirmedAt then
			if t.cancelledAt and t.cancelledAt ~= tonumber(f[2]) then return false end
			t.cancelledAt = tonumber(f[2]); pending[Key(sender, seq)] = nil
		elseif op == "F" and #f == 2 and Number(f[2]) and tonumber(f[2]) <= Now() + 60 and t.attemptedAt and t.absentAt and tonumber(f[2]) >= t.absentAt then
			if t.cancelledAt or (t.confirmedAt and t.confirmedAt ~= tonumber(f[2])) then return false end
			t.confirmedAt, t.confirmedBy = tonumber(f[2]), sender
		else return false end
		TerminalAck(t); Changed(); return true
	elseif op == "A" then
		local issuer, seq, at = Name(f[1]), Number(f[2]), Number(f[4]); local s = Bucket(false)
		local t = issuer and seq and s and s.tasks[Key(issuer, seq)]
		if #f ~= 4 or not J.CanIssue() or not Valid(t) or not Same(t.issuer, ns.me) or not Same(sender, t.assignee) or not Correspondent(sender, t.guild)
			or not at or ((f[3] == "X" and t.cancelledAt ~= at) or (f[3] == "F" and t.confirmedAt ~= at)) or (f[3] ~= "X" and f[3] ~= "F") then return false end
		t.terminalAck = f[3]; Changed(); return true
	end
	return false
end
local cursor = 0
function J.Tick()
	if Preview() then return end
	J.Observe(); J.Prune()
	local tasks = J.Tasks(); if #tasks == 0 then return end
	for _ = 1, math.min(3, #tasks) do
		cursor = cursor % #tasks + 1
		local t = tasks[cursor].task
		if J.CanIssue() and Same(t.issuer, ns.me) and Live(t) and not t.receivedAt then Send(t.assignee, IssueWire(t), t, "issue")
		elseif J.CanIssue() and Same(t.issuer, ns.me) and (t.cancelledAt or t.confirmedAt) then Terminal(t)
		elseif OwnTask(t) then Receipt(t) end
	end
end
function J.ReportMetric()
	if not J.Visible() then return nil end
	local W = ns.Watch; if not W or not W.CouncilStore then return nil end
	if W.PruneCouncil then W.PruneCouncil() end
	local s = W.CouncilStore(false); if not s then return nil end
	local by, n = {}, 0
	for _, r in pairs(s.reports) do if type(r) == "table" and r.council == true and Name(r.reporter) and Number(r.at) and Now() - r.at <= W.REPORT_KEEP then
		if J.Staff() or Same(r.reporter, ns.me) then by[r.reporter] = (by[r.reporter] or 0) + 1; n = n + 1 end
	end end
	return { by = by, retained = n, days = 30, maximum = 200, partial = true }
end
local function Shown(name)
	local text = ns.DisplayName(name) or name
	return ns.CouncilMasked and ns.CouncilMasked() and ns.MaskName and ns.MaskName(text) or ns.Codec.Plain(text)
end
function J.Lines()
	if not J.Visible() then return {} end
	local lines = { { header = true, text = Word("JUSTICE_TASKS_TITLE", "Justice requests — private activity") },
		{ text = Word("JUSTICE_TASKS_EVIDENCE", "Native action attempted and later roster absence are separate observations, not proof of who caused the removal. Completion needs the issuer's explicit human review."), wrap = true },
		{ text = Word("JUSTICE_TASKS_COVERAGE", "Only tasks retained on this client: at most 60, for 30 days. Unknown or offline delivery is not time spent by the correspondent."), wrap = true } }
	if not J.Staff() then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_OWN", "Only your assigned requests and own activity are shown."), wrap = true } end
	if J.CanIssue() then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_NEW", "Request a deliberate guild removal"), onClick = function()
		if J.CanIssue() then ns.ShowDialog("OLYMPUS_JUSTICE_NEW", nil, nil) end
	end } end
	local tasks = J.Tasks()
	for _, e in ipairs(tasks) do
		local t, key = e.task, e.key
		local state = t.cancelledAt and Word("JUSTICE_TASKS_CANCELLED", "Cancelled") or t.confirmedAt and Word("JUSTICE_TASKS_CONFIRMED", "Human-confirmed completion")
			or t.absentAt and Word("JUSTICE_TASKS_ABSENT", "Observed absent; completion pending") or t.attemptedAt and Word("JUSTICE_TASKS_ATTEMPTED", "Native removal attempted; completion pending")
			or t.receivedAt and Word("JUSTICE_TASKS_RECEIVED", "Received; action pending") or Word("JUSTICE_TASKS_WAITING", "Delivery not acknowledged")
		lines[#lines + 1] = { header = true, text = Shown(t.subject) .. " — " .. state }
		lines[#lines + 1] = { text = ("%s · %s → %s"):format(ns.Codec.Plain(t.guild), Shown(t.issuer), Shown(t.assignee)), indent = 1 }
		if t.receivedAt then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_ELAPSED", "Receipt → manual attempt: %s"):format(t.attemptedAt and ((t.attemptedAt - t.receivedAt) .. "s") or Word("JUSTICE_TASKS_PENDING", "pending")), indent = 1 } end
		if J.CanIssue() and Same(t.issuer, ns.me) and (t.cancelledAt or t.confirmedAt) and not t.terminalAck then
			lines[#lines + 1] = { text = Word("JUSTICE_TASKS_RETRY", "Terminal decision delivery unacknowledged — retry privately"), indent = 1, onClick = function() J.Retry(key) end }
		end
		if OwnTask(t) and not t.attemptedAt then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_REMOVE", "Review this member in the existing removal dialog"), indent = 1, onClick = function() return J.AskRemoval(key) end } end
		if J.CanIssue() and Live(t) and Same(t.issuer, ns.me) then
			lines[#lines + 1] = { text = Word("JUSTICE_TASKS_CANCEL", "Cancel request"), indent = 1, onClick = function() J.Cancel(key) end }
			if t.attemptedAt and t.absentAt then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_CONFIRM", "Review and confirm completion (human judgement)"), indent = 1,
				onClick = function() ns.ShowDialog("OLYMPUS_JUSTICE_CONFIRM", Shown(t.subject), nil, key) end } end
		end
	end
	if #tasks == 0 then lines[#lines + 1] = { text = Word("JUSTICE_TASKS_EMPTY", "No retained requests visible to you.") } end
	local metric = J.ReportMetric()
	lines[#lines + 1] = { header = true, text = Word("JUSTICE_TASKS_REPORTS", "Reports — separate retained activity") }
	lines[#lines + 1] = { text = Word("JUSTICE_TASKS_REPORT_COVERAGE", "Only latest accepted reporter/subject pairs held here, at most 200 for 30 days. Partial coverage, not total sent, quality, or lifetime work."), wrap = true }
	if metric then
		lines[#lines + 1] = { text = Word("JUSTICE_TASKS_REPORT_COUNT", "Locally retained accepted report pairs: %d (partial coverage)."):format(metric.retained), wrap = true }
		local names = {}; for name in pairs(metric.by) do names[#names + 1] = name end; table.sort(names)
		for _, name in ipairs(names) do lines[#lines + 1] = { text = Shown(name), right = tostring(metric.by[name]) } end
	else lines[#lines + 1] = { text = Word("JUSTICE_TASKS_UNKNOWN", "No retained council report evidence here; count unknown.") } end
	return lines
end
StaticPopupDialogs["OLYMPUS_JUSTICE_NEW"] = { text = Word("JUSTICE_TASKS_NEW_HINT", "Guild | exact Justice correspondent | member to remove. This is an explicit private request, not an automatic removal."),
	button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel", hasEditBox = true, editBoxWidth = 360, maxLetters = 220,
	OnShow = function(self) local e = self.editBox or self.EditBox; if e then e:SetText(""); e:SetFocus() end end,
	OnAccept = function(self) local edit = self.editBox or self.EditBox; local text = edit and edit:GetText() or ""
		local guild, assignee, subject = text:match("^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
		return J.Issue(guild, assignee, subject)
	end, timeout = 0, whileDead = true, hideOnEscape = true }
StaticPopupDialogs["OLYMPUS_JUSTICE_CONFIRM"] = { text = Word("JUSTICE_TASKS_CONFIRM_HINT", "Confirm completion for %s after your own review? The attempt and observed absence do not certify the actor or cause. This record will be labelled human-confirmed."),
	button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel", OnAccept = function(self, key) return J.Confirm(key or (self and self.data)) end,
	timeout = 0, whileDead = true, hideOnEscape = true }
ns.Comm.Handle("JT", J.Handle)
ns.On("MEMBER_REMOVAL_ATTEMPT", Attempt)
ns.On("DATA_CHANGED", J.Observe)
ns.On("LOGIN", function() ns.Every(J.EVERY, "justice private tasks", J.Tick) end)
