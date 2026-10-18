local ADDON, ns = ...
local L = ns.L

-- Party Guard keeps a small, short-lived inbox of clear party-invite requests while the King is
-- demonstrably online. A whisper is only the request: it is never evidence of the sender's guild.
-- Guild evidence comes from a fresh local roster, a recent explicit /who answer or a player the
-- user can directly target/mouse over. Verification and every invite remain explicit clicks.

local Guard = {}
ns.PartyGuard = Guard

Guard.CANDIDATE_TTL = 10 * 60
Guard.CANDIDATE_MAX = 20
Guard.CANDIDATE_SHOWN = 5
Guard.DIRECT_TTL = 5 * 60
Guard.EVIDENCE_TTL = 15 * 60

local candidates = {} -- [folded Name-Realm] = { name, firstAt, lastAt, count, direct?, evidence? }

local function Secret(v)
	return type(issecretvalue) == "function" and issecretvalue(v)
end

local function Key(name)
	if Secret(name) or type(name) ~= "string" or name == "" then return nil end
	local full = ns.FullName(ns.Normal and ns.Normal(name) or name)
	if type(full) ~= "string" or full == "" or #full > 80 then return nil end
	return ns.Fold(full), full
end

local function Changed()
	ns.Fire("DATA_CHANGED")
end

function Guard.Enabled()
	return not (ns.db and ns.db.partyGuardOff == true)
end

-- Location() already applies the King's freshness and location-sanction gates. The local King is
-- online by definition even before his first location broadcast.
function Guard.KingOnline()
	if not (ns.IsMember and ns.IsMember()) then return false end
	if ns.King and ns.King.IsKing and ns.King.IsKing() then return true end
	return ns.King and ns.King.Location and type(ns.King.Location()) == "table" or false
end

local function Active()
	return Guard.Enabled() and Guard.KingOnline()
end

local function Drop(candidate)
	local key = type(candidate) == "table" and candidate.key or candidate
	if key and candidates[key] then
		candidates[key] = nil
		Changed()
		return true
	end
	return false
end

local function Prune(now)
	local changed = false
	for key, candidate in pairs(candidates) do
		if now - (candidate.lastAt or 0) > Guard.CANDIDATE_TTL then
			candidates[key] = nil
			changed = true
		end
	end
	if changed then Changed() end
end

local function Current(candidate)
	if type(candidate) ~= "table" or candidates[candidate.key] ~= candidate then return nil end
	local key = Key(candidate.name)
	if key ~= candidate.key then return nil end
	local now = ns.Now()
	if now - (candidate.lastAt or 0) > Guard.CANDIDATE_TTL then
		Drop(candidate)
		return nil
	end
	return candidate, now
end

local function Count()
	local n = 0
	for _ in pairs(candidates) do n = n + 1 end
	return n
end

local function Oldest()
	local found
	for _, candidate in pairs(candidates) do
		if not found or candidate.lastAt < found.lastAt then found = candidate end
	end
	return found
end

-- Conservative intent recognition. A bare "inv" or "invite" in a whisper is an established
-- party request; longer text must explicitly ask to be invited or name a party/group. Guild-invite
-- and negative phrases are deliberately rejected.
function Guard.InviteIntent(text)
	if Secret(text) or type(text) ~= "string" then return false end
	local s = ns.Fold(text):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	if s == "" or #s > 500 then return false end
	if s:find("guild", 1, true) or s:find("guilda", 1, true) then return false end
	if s:find("don't invite", 1, true) or s:find("do not invite", 1, true)
		or s:find("dont invite", 1, true) or s:find("no invite", 1, true)
		or s:find("invite sent", 1, true)
		or s:find("nao me convida", 1, true) or s:find("não me convida", 1, true) then return false end
	if s:match("^inv[%s%p]*$") or s:match("^invite[%s%p]*$") then return true end
	local phrases = {
		"invite me", "inv me", "please invite me", "pls invite me", "can you invite me", "could you invite me",
		"party invite", "group invite", "invite to party", "invite to the party", "invite to group",
		"invite to the group", "need inv", "inv pls", "inv please",
		"me convida", "pode me convidar", "poderia me convidar", "convite pro grupo",
		"convite para o grupo", "convida pro grupo", "convida para o grupo", "me chama pro grupo",
		"me chama para o grupo", "inv grupo", "inv por favor",
	}
	for _, phrase in ipairs(phrases) do
		if s:find(phrase, 1, true) then return true end
	end
	return false
end

local function Evidence(candidate)
	local _, now = Current(candidate)
	if not now then return nil end
	local best
	local function Take(guild, source, at)
		if type(guild) ~= "string" or type(at) ~= "number" or at > now or now - at > Guard.EVIDENCE_TTL then return end
		if not best or at > best.at then best = { guild = guild, source = source, at = at } end
	end

	local roster = ns.Roster and ns.Roster.Fresh and ns.Roster.Fresh()
	if roster and ns.Roster.RankOf and ns.Roster.RankOf(candidate.name) ~= nil then
		local guild = type(GetGuildInfo) == "function" and GetGuildInfo("player") or nil
		if not Secret(guild) and type(guild) == "string" and guild ~= "" then
			Take(guild, "roster", tonumber(roster.snapshotAt) or now)
		end
	end
	local direct = candidate.direct
	if direct and now - (direct.at or 0) <= Guard.DIRECT_TTL then Take(direct.guild, "direct", direct.at) end
	local who = candidate.who
	if who then Take(who.guild, "who", who.at) end
	if ns.Who and ns.Who.SeenGuild then
		local guild, age = ns.Who.SeenGuild(candidate.name)
		if not Secret(guild) and not Secret(age) and type(guild) == "string" and type(age) == "number"
			and age >= 0 and age <= Guard.EVIDENCE_TTL then Take(guild, "who", now - age) end
	end
	candidate.evidence = best
	if best then best.status = ns.IsFederation(best.guild) and "olympus" or "outsider" end
	return best
end

local function Fingerprint(candidate)
	local e = Evidence(candidate)
	return e and table.concat({ e.status, e.guild, e.source, tostring(e.at) }, "\031") or nil
end

function Guard.Candidates()
	Prune(ns.Now())
	local out = {}
	for _, candidate in pairs(candidates) do
		Evidence(candidate)
		out[#out + 1] = candidate
	end
	table.sort(out, function(a, b) return a.lastAt > b.lastAt end)
	return out
end

function Guard.OnWhisper(text, sender)
	if Secret(text) or Secret(sender) or not Active() or not Guard.InviteIntent(text) then return false end
	local key, full = Key(sender)
	if not key then return false end
	local now = ns.Now()
	Prune(now)
	local candidate = candidates[key]
	if candidate then
		candidate.lastAt, candidate.count = now, (candidate.count or 1) + 1
	else
		while Count() >= Guard.CANDIDATE_MAX do Drop(Oldest()) end
		candidate = { key = key, name = full, firstAt = now, lastAt = now, count = 1 }
		candidates[key] = candidate
	end
	Evidence(candidate)
	Changed()
	return true
end

function Guard.OnWhoSeen(name, guild)
	if Secret(name) or Secret(guild) or type(guild) ~= "string" then return false end
	local key = Key(name)
	local candidate = key and candidates[key]
	if not candidate or not Current(candidate) then return false end
	-- Who.SeenGuild is still consulted by Evidence; this copy lets tests and direct listeners
	-- refresh the line immediately without making a whisper into proof.
	candidate.who = { guild = guild, at = ns.Now() }
	candidate.evidence = { guild = guild, source = "who", at = candidate.who.at, status = ns.IsFederation(guild) and "olympus" or "outsider" }
	Changed()
	return true
end

-- Direct observation is useful only for an already-requesting exact identity. It does not build a
-- people database, and secret unit values are abandoned before any comparison.
function Guard.ObserveUnit(unit)
	if not Active() or type(unit) ~= "string" or not (UnitIsPlayer and UnitIsPlayer(unit)) then return false end
	local full = ns.UnitFullName and ns.UnitFullName(unit) or nil
	if Secret(full) or type(full) ~= "string" or full == "" then return false end
	local key = Key(full)
	local candidate = key and candidates[key]
	if not candidate or not Current(candidate) or type(GetGuildInfo) ~= "function" then return false end
	local guild = GetGuildInfo(unit)
	if Secret(guild) or type(guild) ~= "string" then return false end
	candidate.direct = { guild = guild, at = ns.Now() }
	Evidence(candidate)
	Changed()
	return true
end

-- Explicit-click /who only. Who.Search owns the client's cooldown, window and capability checks.
function Guard.Verify(candidate)
	if not Active() or not Current(candidate) or (ns.GamepadUI and ns.GamepadUI()) then return false end
	if not (ns.Who and ns.Who.Search) then return false end
	return ns.Who.Search(true, nil, candidate.name) == true
end

local function CanInvite(candidate)
	if not Active() or not Current(candidate) then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	local groupSize, room
	if ns.Hop and ns.Hop.GroupState then groupSize, room = ns.Hop.GroupState() end
	if room ~= true then return false end
	local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit -- gp:roster-actions
	if type(invite) ~= "function" then return false end
	return invite
end

local function InviteNow(candidate, expected)
	local invite = CanInvite(candidate)
	if not invite then
		ns.Print(L.PARTY_GUARD_CANNOT_INVITE)
		return false
	end
	local fingerprint = Fingerprint(candidate)
	if not fingerprint or (expected and fingerprint ~= expected) then
		ns.Print(L.PARTY_GUARD_RECHECK)
		return false
	end
	local ok = pcall(invite, ns.TellName(candidate.name)) -- gp:roster-actions
	if not ok then
		ns.Print(L.PARTY_GUARD_CANNOT_INVITE)
		return false
	end
	Drop(candidate)
	return true
end

function Guard.RequestInvite(candidate)
	if not Active() or not Current(candidate) then return false end
	local evidence = Evidence(candidate)
	if not evidence then return false end
	if evidence.status == "olympus" then return InviteNow(candidate) end
	local guild = evidence.guild ~= "" and ("<" .. evidence.guild .. ">") or L.PARTY_GUARD_NO_GUILD
	local data = { candidate = candidate, fingerprint = Fingerprint(candidate) }
	return ns.Dialog.Show("OLYMPUS_PARTY_GUARD_OUTSIDER", ns.DisplayName(candidate.name) or candidate.name, guild, data) ~= nil
end

function Guard.ConfirmOutsider(data)
	local candidate = type(data) == "table" and data.candidate
	local expected = type(data) == "table" and data.fingerprint
	local evidence = candidate and Evidence(candidate)
	if not evidence or evidence.status ~= "outsider" or not expected or Fingerprint(candidate) ~= expected then
		ns.Print(L.PARTY_GUARD_RECHECK)
		return false
	end
	return InviteNow(candidate, expected)
end

function Guard.Dismiss(candidate)
	return Drop(candidate)
end

function Guard.SetEnabled(on)
	if not ns.db then return false end
	if on then ns.db.partyGuardOff = nil else ns.db.partyGuardOff = true end
	if not on then wipe(candidates) end
	ns.Print(on and L.PARTY_GUARD_ON or L.PARTY_GUARD_OFF)
	Changed()
	return true
end

function Guard.Slash(input)
	local word = ns.Fold(input or "")
	if word == "on" then return Guard.SetEnabled(true) end
	if word == "off" then return Guard.SetEnabled(false) end
	ns.Print(Guard.Enabled() and L.PARTY_GUARD_ON or L.PARTY_GUARD_OFF)
	return false
end

local function Detail(candidate, evidence)
	if not evidence then
		return L.PARTY_GUARD_DETAIL:format(L.PARTY_GUARD_UNKNOWN, L.PARTY_GUARD_GUILD_UNKNOWN,
			L.PARTY_GUARD_SOURCE_NONE, ns.Ago(candidate.lastAt))
	end
	local status = evidence.status == "olympus" and L.PARTY_GUARD_OLYMPUS or L.PARTY_GUARD_OUTSIDER
	local guild = evidence.guild ~= "" and ("<" .. evidence.guild .. ">") or L.PARTY_GUARD_NO_GUILD
	local source = L["PARTY_GUARD_SOURCE_" .. evidence.source:upper()] or evidence.source
	return L.PARTY_GUARD_DETAIL:format(status, guild, source, ns.Ago(evidence.at))
end

function Guard.Lines()
	if not Active() then return {} end
	local list = Guard.Candidates()
	if #list == 0 then return {} end
	local V = ns.Views
	local lines = { {
		header = true,
		text = L.PARTY_GUARD_TITLE:format(#list),
		tooltip = function(tt)
			tt:AddLine(L.PARTY_GUARD_TITLE:format(#list), 1, 0.82, 0)
			tt:AddLine(L.PARTY_GUARD_TIP, 1, 1, 1, true)
		end,
	} }
	for i = 1, math.min(#list, Guard.CANDIDATE_SHOWN) do
		local candidate = list[i]
		local evidence = Evidence(candidate)
		lines[#lines + 1] = {
			text = ns.DisplayName(candidate.name) or candidate.name,
			right = V.Grey(ns.Ago(candidate.lastAt)),
		}
		local detail = Detail(candidate, evidence)
		local colour = evidence and (evidence.status == "olympus" and V.Green or V.Gold) or V.Grey
		lines[#lines + 1] = { indent = 1, text = colour(detail) }
		if not evidence then
			if ns.GamepadUI and ns.GamepadUI() then
				lines[#lines + 1] = { indent = 1, text = V.Grey(L.PARTY_GUARD_VERIFY_GAMEPAD) }
			else
				lines[#lines + 1] = { indent = 1, text = V.Gold(L.PARTY_GUARD_VERIFY), onClick = function() Guard.Verify(candidate) end }
			end
		elseif evidence.status == "olympus" then
			lines[#lines + 1] = { indent = 1, text = V.Green(L.PARTY_GUARD_INVITE), onClick = function() Guard.RequestInvite(candidate) end }
		else
			lines[#lines + 1] = { indent = 1, text = V.Gold(L.PARTY_GUARD_REVIEW), onClick = function() Guard.RequestInvite(candidate) end }
		end
		lines[#lines + 1] = { indent = 1, text = V.Grey(L.PARTY_GUARD_DISMISS), onClick = function() Guard.Dismiss(candidate) end }
	end
	if #list > Guard.CANDIDATE_SHOWN then
		lines[#lines + 1] = { indent = 1, text = V.Grey(L.PARTY_GUARD_MORE:format(#list - Guard.CANDIDATE_SHOWN)) }
	end
	lines[#lines + 1] = { indent = 1, text = V.Grey(L.PARTY_GUARD_TURN_OFF), onClick = function() Guard.SetEnabled(false) end }
	lines[#lines].gapAfter = true
	return lines
end

function Guard.ResetForTests()
	wipe(candidates)
end

if ns.Who and ns.Who.OnSaw then ns.Who.OnSaw(Guard.OnWhoSeen) end
ns.On("KING_LOCATION_CHANGED", function()
	if not Guard.KingOnline() then wipe(candidates) end
	Changed()
end)
ns.On("LOGIN", function()
	ns.RegisterEvent("CHAT_MSG_WHISPER", function(text, sender) Guard.OnWhisper(text, sender) end)
	ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Guard.ObserveUnit("target") end)
	ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() Guard.ObserveUnit("mouseover") end)
end)

StaticPopupDialogs["OLYMPUS_PARTY_GUARD_OUTSIDER"] = {
	text = L.PARTY_GUARD_OUTSIDER_PROMPT,
	button1 = L.PARTY_GUARD_INVITE_ANYWAY,
	button2 = CANCEL or "Cancel",
	timeout = 0,
	whileDead = false,
	hideOnEscape = true,
	OnAccept = function(_, data) Guard.ConfirmOutsider(data) end,
}
