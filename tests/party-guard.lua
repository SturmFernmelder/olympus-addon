-- Party Guard: bounded local invite-request inbox, trusted guild evidence and manual party actions.
local ns, test, eq, H = ...
local G = ns.PartyGuard
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]party%-guard%.lua$")) or "./"

local function Scene(fn)
	local saved = {
		king = ns.King, roster = ns.Roster, who = ns.Who, hop = ns.Hop, now = ns.Now,
		member = ns.IsMember, gamepad = ns.GamepadUI, print = ns.Print, dialog = ns.Dialog.Show,
		guild = GetGuildInfo, combat = InCombatLockdown, party = C_PartyInfo, oldInvite = InviteUnit,
		isPlayer = UnitIsPlayer, full = UnitFullName, secret = issecretvalue, off = ns.db.partyGuardOff,
	}
	local w = {
		now = 2000000000, kingAt = true, localKing = false, member = true, gamepad = false,
		rosterName = nil, rosterAt = nil, ownGuild = "Olympus Test", seen = {}, searches = {},
		seenReads = 0, room = true, combat = false, invited = {}, printed = {}, dialog = nil, units = {},
	}
	local ok, err = pcall(function()
		ns.db.partyGuardOff = nil
		ns.Now = function() return w.now end
		ns.IsMember = function() return w.member end
		ns.GamepadUI = function() return w.gamepad end
		ns.Print = function(s) w.printed[#w.printed + 1] = s end
		ns.King = setmetatable({
			IsKing = function() return w.localKing end,
			Location = function() return w.kingAt and { name = "King-Realm", t = w.now } or nil end,
		}, { __index = saved.king })
		ns.Roster = setmetatable({
			Fresh = function() return w.rosterAt and { snapshotAt = w.rosterAt } or nil end,
			RankOf = function(name) return name == w.rosterName and "Member" or nil end,
		}, { __index = saved.roster })
		ns.Who = setmetatable({
			ROUND_TTL = 900,
			SeenGuild = function(name)
				w.seenReads = w.seenReads + 1
				local e = w.seen[name]
				return e and e.guild, e and e.age
			end,
			Search = function(quiet, guild, name)
				w.searches[#w.searches + 1] = { quiet, guild, name }
				if w.searchError then error(w.searchError) end
				return w.searchResult ~= false
			end,
		}, { __index = saved.who })
		ns.Hop = setmetatable({ GroupState = function() return 0, w.room end }, { __index = saved.hop })
		ns.Dialog.Show = function(which, a, b, data)
			w.dialog = { which = which, a = a, b = b, data = data }
			return w.dialog
		end
		GetGuildInfo = function(unit) return unit == "player" and w.ownGuild or (w.units[unit] and w.units[unit].guild) end
		InCombatLockdown = function() return w.combat end
		C_PartyInfo = { InviteUnit = function(name) w.invited[#w.invited + 1] = name end }
		InviteUnit = nil
		UnitIsPlayer = function(unit) return w.units[unit] ~= nil end
		UnitFullName = function(unit)
			local u = w.units[unit]
			return u and u.name, u and u.realm
		end
		issecretvalue = function(v) return type(v) == "table" and v.secret == true end
		G.ResetForTests()
		fn(w)
	end)
	G.ResetForTests()
	ns.King, ns.Roster, ns.Who, ns.Hop, ns.Now = saved.king, saved.roster, saved.who, saved.hop, saved.now
	ns.IsMember, ns.GamepadUI, ns.Print, ns.Dialog.Show = saved.member, saved.gamepad, saved.print, saved.dialog
	GetGuildInfo, InCombatLockdown, C_PartyInfo, InviteUnit = saved.guild, saved.combat, saved.party, saved.oldInvite
	UnitIsPlayer, UnitFullName, issecretvalue = saved.isPlayer, saved.full, saved.secret
	ns.db.partyGuardOff = saved.off
	if not ok then error(err, 0) end
end

local function Candidate(name)
	for _, c in ipairs(G.Candidates()) do if c.name == name then return c end end
end

local function Has(lines, needle)
	for _, line in ipairs(lines) do
		if tostring(line.text):find(needle, 1, true) then return line end
	end
end

test("party guard: only clear party requests while the King is online; candidates are secret-safe, deduplicated, bounded and expiring", function()
	Scene(function(w)
		w.kingAt = false
		eq(G.OnWhisper("invite me please", "Quiet-Realm"), false, "no King evidence: inert")
		w.localKing = true
		for _, text in ipairs({ "inv", "Invite me please", "can you invite me to the group?", "me convida pro grupo?" }) do
			assert(G.InviteIntent(text), text)
		end
		for _, text in ipairs({ "the party was fun", "invite sent", "who is in group?", "guild invite please", "do not invite me",
			"why did you invite me?", "did you invite me already?" }) do
			eq(G.InviteIntent(text), false, text)
		end
		assert(G.OnWhisper("invite me please", "Same-Realm"))
		eq(#w.printed, 1, "a new sender gets one non-modal chat notice")
		eq(w.printed[1], ns.L.PARTY_GUARD_NEW:format(ns.DisplayName("Same-Realm") or "Same-Realm"))
		assert(G.OnWhisper("inv", "Same-Realm"))
		eq(#w.printed, 1, "repeat whispers update the row without repeating the notice")
		local same = assert(Candidate("Same-Realm"))
		eq(same.count, 2); eq(same.text, nil, "the whisper body is never retained")

		local secret = { secret = true }
		local ok, accepted = pcall(G.OnWhisper, secret, "Secret-Realm")
		assert(ok); eq(accepted, false)
		ok, accepted = pcall(G.OnWhisper, "inv", secret)
		assert(ok); eq(accepted, false)

		for i = 1, G.CANDIDATE_MAX + 5 do
			w.now = w.now + 1
			assert(G.OnWhisper("inv", "Crowd" .. i .. "-Realm"))
		end
		eq(#G.Candidates(), G.CANDIDATE_MAX, "bounded")
		eq(Candidate("Same-Realm"), nil, "oldest evicted")
		local collapsed = G.Lines()
		eq(Has(collapsed, "Crowd6"), nil, "older guarded requests start collapsed")
		local more = assert(Has(collapsed, ns.L.PARTY_GUARD_MORE:format(15)))
		assert(more.onClick, "the remaining count is an actionable row")
		more.onClick()
		assert(Has(G.Lines(), "Crowd6"), "expanding makes every retained request accessible")
		local less = assert(Has(G.Lines(), ns.L.PARTY_GUARD_LESS))
		less.onClick()
		eq(Has(G.Lines(), "Crowd6"), nil, "the long list can be collapsed again")
		local moreAgain = assert(Has(G.Lines(), ns.L.PARTY_GUARD_MORE:format(15)))
		moreAgain.onClick()
		w.localKing, w.kingAt = false, false
		G.OnKingLocationChanged()
		w.localKing = true
		for i = 1, 6 do
			w.now = w.now + 1
			assert(G.OnWhisper("inv", "Restart" .. i .. "-Realm"))
		end
		eq(Has(G.Lines(), "Restart1"), nil, "a later King-online session starts collapsed again")
		w.now = w.now + G.CANDIDATE_TTL + 1
		eq(#G.Candidates(), 0, "TTL")

		assert(G.OnWhisper("inv", "Toggle-Realm"))
		assert(G.SetEnabled(false)); eq(#G.Candidates(), 0); eq(G.OnWhisper("inv", "Off-Realm"), false)
		assert(G.SetEnabled(true)); assert(G.OnWhisper("inv", "On-Realm"))
	end)
end)

test("party guard: guild status only comes from fresh roster, explicit who, or an exact direct unit", function()
	Scene(function(w)
		assert(G.OnWhisper("invite me", "Unknown-Realm"))
		local unknown = assert(Candidate("Unknown-Realm"))
		eq(unknown.evidence, nil)
		w.seen[unknown.name] = { guild = "Olympus Test", age = 0 }
		eq(assert(Candidate(unknown.name)).evidence, nil, "an older global /who cache is never evidence")
		eq(w.seenReads, 0, "Party Guard never reads the global /who cache")
		eq(G.OnWhoSeen(unknown.name, "Olympus Test"), false, "an unsolicited /who row is not evidence")
		local verify = assert(Has(G.Lines(), ns.L.PARTY_GUARD_VERIFY))
		assert(verify.text:find("manually", 1, true), "the row says verification is manual")
		assert(Has(ns.Views.Build("census"), ns.L.PARTY_GUARD_TITLE:format(1)), "the non-modal rows are in the Census")
		local sentAt = w.now
		verify.onClick()
		eq(#w.searches, 1); eq(w.searches[1][1], true); eq(w.searches[1][3], "Unknown-Realm")
		eq(unknown.evidence, nil, "sending /who alone proves nothing")
		w.now = sentAt - 1
		eq(G.OnWhoSeen(unknown.name, "Olympus Test"), false, "a result older than the request and verification is rejected")
		w.now = sentAt
		assert(G.OnWhoSeen(unknown.name, "Olympus Test"))
		local found = assert(Candidate(unknown.name))
		eq(found.evidence.status, "olympus"); eq(found.evidence.source, "who")
		assert(Has(G.Lines(), ns.L.PARTY_GUARD_SOURCE_WHO), "source and age are visible")
		found.who.at = w.now - G.EVIDENCE_TTL - 1
		eq(assert(Candidate(unknown.name)).evidence, nil, "stale who becomes Unknown")

		G.ResetForTests()
		assert(G.OnWhisper("inv", "First-Realm")); assert(G.OnWhisper("inv", "Second-Realm"))
		local first, second = assert(Candidate("First-Realm")), assert(Candidate("Second-Realm"))
		assert(G.Verify(first))
		eq(G.OnWhoSeen(second.name, "Olympus Test"), false, "verification is exact to one candidate")
		assert(G.OnWhoSeen(first.name, "Olympus Test"))
		eq(G.OnWhoSeen(first.name, "Other Guild"), false, "one verification cannot authorize later rows")

		G.ResetForTests()
		assert(G.OnWhisper("inv", "Failed-Realm"))
		local failed = assert(Candidate("Failed-Realm"))
		w.searchResult = false
		eq(G.Verify(failed), false)
		eq(G.OnWhoSeen(failed.name, "Olympus Test"), false, "a refused search leaves no pending verification")
		w.searchResult = true
		w.searchError = "send failed"
		local ok = pcall(G.Verify, failed)
		eq(ok, false)
		eq(G.OnWhoSeen(failed.name, "Olympus Test"), false, "a failed search leaves no pending verification")
		w.searchError = nil
		assert(G.Verify(failed))
		w.now = w.now + G.VERIFY_TTL + 1
		eq(G.OnWhoSeen(failed.name, "Olympus Test"), false, "a late unrelated /who row cannot satisfy an expired verification")

		G.ResetForTests()
		w.rosterName, w.rosterAt = "Member-Realm", w.now
		assert(G.OnWhisper("inv", w.rosterName))
		local member = assert(Candidate(w.rosterName))
		eq(member.evidence.status, "olympus"); eq(member.evidence.source, "roster")
		w.rosterAt = nil
		eq(assert(Candidate(w.rosterName)).evidence, nil, "stale roster is not authority")

		G.ResetForTests()
		assert(G.OnWhisper("group invite please", "Visible-Realm"))
		w.units.target = { name = "SomeoneElse", realm = "Realm", guild = "Olympus Test" }
		eq(G.ObserveUnit("target"), false, "a different target cannot verify the requester")
		w.units.target = { name = "Visible", realm = "Realm", guild = "Other Guild" }
		assert(G.ObserveUnit("target"))
		local visible = assert(Candidate("Visible-Realm"))
		eq(visible.evidence.status, "outsider"); eq(visible.evidence.source, "direct")

		G.ResetForTests()
		assert(G.OnWhisper("inv", "Pad-Realm"))
		local pad = assert(Candidate("Pad-Realm"))
		w.gamepad = true
		local searched = #w.searches
		eq(G.Verify(pad), false); eq(#w.searches, searched, "gamepad never sends a quiet name /who")
		assert(Has(G.Lines(), ns.L.PARTY_GUARD_VERIFY_GAMEPAD))
	end)
end)

test("party guard: invitations are manual and recheck King, identity, evidence, group room, combat and client API", function()
	Scene(function(w)
		w.rosterName, w.rosterAt = "Member-Realm", w.now
		assert(G.OnWhisper("inv", w.rosterName))
		local member = assert(Candidate(w.rosterName))
		eq(#w.invited, 0, "no automatic invite")
		assert(G.RequestInvite(member)); eq(#w.invited, 1)

		local function Member(name)
			G.ResetForTests(); w.rosterName, w.rosterAt = name, w.now
			assert(G.OnWhisper("invite me", name))
			return assert(Candidate(name))
		end
		local before = #w.invited
		local blocked = Member("Combat-Realm"); w.combat = true
		eq(G.RequestInvite(blocked), false); eq(#w.invited, before); w.combat = false
		blocked = Member("Full-Realm"); w.room = false
		eq(G.RequestInvite(blocked), false); eq(#w.invited, before); w.room = true
		blocked = Member("Offline-Realm"); w.kingAt, w.localKing = false, false
		eq(G.RequestInvite(blocked), false); eq(#w.invited, before); w.kingAt = true
		blocked = Member("Api-Realm"); C_PartyInfo, InviteUnit = nil, nil
		eq(G.RequestInvite(blocked), false); eq(#w.invited, before)
		C_PartyInfo = { InviteUnit = function(name) w.invited[#w.invited + 1] = name end }
		blocked = Member("Exact-Realm"); blocked.name = "Other-Realm"
		eq(G.RequestInvite(blocked), false); eq(#w.invited, before, "identity is rechecked at the click")

		G.ResetForTests(); w.rosterName, w.rosterAt = nil, nil
		assert(G.OnWhisper("party invite", "Outsider-Realm"))
		local outsider = assert(Candidate("Outsider-Realm"))
		assert(G.Verify(outsider)); assert(G.OnWhoSeen(outsider.name, "Other Guild"))
		assert(G.RequestInvite(outsider)); eq(#w.invited, before, "warning is not an invite")
		eq(w.dialog.which, "OLYMPUS_PARTY_GUARD_OUTSIDER")
		w.now = w.now + 30
		assert(G.ConfirmOutsider(w.dialog.data)); eq(#w.invited, before + 1, "manual override")

		G.ResetForTests(); w.dialog = nil
		assert(G.OnWhisper("inv", "Changed-Realm"))
		local changed = assert(Candidate("Changed-Realm"))
		assert(G.Verify(changed)); assert(G.OnWhoSeen(changed.name, "Other Guild"))
		assert(G.RequestInvite(changed))
		local decision = w.dialog.data
		w.now = w.now + 1
		w.seen[changed.name] = { guild = "Olympus Test", age = 0 }
		changed.who = { guild = "Olympus Test", at = w.now }
		eq(G.ConfirmOutsider(decision), false, "stale confirmation cannot invite after evidence changes")
		eq(#w.invited, before + 1)
	end)
end)

test("party guard: English and pt-BR user-facing copy have matching format contracts", function()
	local pt = { L = setmetatable({}, { __index = ns.L }) }
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", pt) end)
	GetLocale = savedLocale
	if not ok then error(err, 0) end
	pt = pt.L
	local keys = {
		"HELP_PARTY_GUARD", "PARTY_GUARD_TITLE", "PARTY_GUARD_TIP", "PARTY_GUARD_NEW", "PARTY_GUARD_UNKNOWN",
		"PARTY_GUARD_OLYMPUS", "PARTY_GUARD_OUTSIDER", "PARTY_GUARD_GUILD_UNKNOWN",
		"PARTY_GUARD_NO_GUILD", "PARTY_GUARD_SOURCE_NONE", "PARTY_GUARD_SOURCE_ROSTER",
		"PARTY_GUARD_SOURCE_WHO", "PARTY_GUARD_SOURCE_DIRECT", "PARTY_GUARD_DETAIL",
		"PARTY_GUARD_VERIFY", "PARTY_GUARD_VERIFY_GAMEPAD", "PARTY_GUARD_INVITE",
		"PARTY_GUARD_REVIEW", "PARTY_GUARD_DISMISS", "PARTY_GUARD_MORE", "PARTY_GUARD_LESS", "PARTY_GUARD_TURN_OFF",
		"PARTY_GUARD_ON", "PARTY_GUARD_OFF", "PARTY_GUARD_CANNOT_INVITE", "PARTY_GUARD_RECHECK",
		"PARTY_GUARD_OUTSIDER_PROMPT", "PARTY_GUARD_INVITE_ANYWAY",
	}
	local function Codes(s)
		local out = {}
		for c in s:gmatch("%%[sd]") do out[#out + 1] = c end
		return table.concat(out)
	end
	for _, key in ipairs(keys) do
		local en, br = ns.L[key], pt[key]
		assert(type(en) == "string" and en ~= "", "English " .. key)
		assert(type(br) == "string" and br ~= "" and (key == "PARTY_GUARD_DETAIL" or br ~= en), "pt-BR " .. key)
		eq(Codes(br), Codes(en), key)
	end
end)
