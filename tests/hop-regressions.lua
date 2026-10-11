-- Exercise the real hop and layer modules through the upstream WoW fixture.
local ns, test, eq, WithHop = ...

local function Join(w, H)
	w.see(7)
	H.Ask(1453, 8, "destination")
	H.HandleOffer("WHISPER", "Helper-Realm", "LO~1~0~0")
	w.clock = w.clock + H.WINDOW
	H.Tick()
	H.OnInvite("Helper")
	w.group, w.party.party1 = 2, "Helper"
	H.OnRoster()
end

test("hop regression: a different wrong layer is not successful and never auto-leaves", function()
	WithHop(function(w, H)
		Join(w, H)
		w.see(9); H.OnLayer()
		eq(w.left, 0); eq(H.Stats().moves, 0); eq(H.State().phase, "joined")
		w.see(8); H.OnLayer()
		eq(w.left, 1); eq(H.Stats().moves, 1); eq(H.State().phase, "done")
	end)
end)

test("hop regression: seeing the destination before the roster event still completes", function()
	WithHop(function(w, H)
		w.see(7); H.Ask(1453, 8, "destination")
		H.HandleOffer("WHISPER", "Helper-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW; H.Tick(); H.OnInvite("Helper")
		w.see(8); H.OnLayer()
		eq(w.left, 0, "not in the helper's group yet")
		w.group, w.party.party1 = 2, "Helper"; H.OnRoster()
		eq(w.left, 1); eq(H.Stats().moves, 1)
	end)
end)

test("hop regression: delayed offers recheck location and sharing before sending", function()
	for _, change in ipairs({
		function(w) w.see(8) end,
		function(w) w.map = 1429 end,
		function() ns.db.shareLocation = false end,
		function(w) w.combat = true end,
	}) do
		WithHop(function(w, H)
			w.see(7)
			local later
			H.after = function(_, _, fn) later = fn end
			H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
			assert(later, "offer was scheduled")
			change(w); later()
			eq(#w.whispered, 0, "the old offer must not go out")
			H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
			eq(#w.invited, 0); eq(#w.popups, 0)
		end)
	end
end)

test("hop regression: requests recheck the exact layer offered and the helper's opt-in", function()
	for _, change in ipairs({
		function(w) w.see(8) end,
		function(w) w.map = 1429 end,
		function() ns.db.layerHelp = false end,
		function() ns.db.shareLocation = false end,
		function(w, H) w.clock = w.clock + H.LAYER_FRESH + 1 end,
	}) do
		WithHop(function(w, H)
			w.see(7); ns.db.layerAutoInvite = true
			H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
			change(w, H)
			H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
			eq(#w.invited, 0); eq(#w.popups, 0)
		end)
	end
end)

test("hop regression: an Invite button rechecks capacity, combat, opt-in, layer and age", function()
	for _, change in ipairs({
		function(w) w.group, w.lead = 5, true end,
		function(w) w.combat = true end,
		function() ns.db.layerHelp = false end,
		function() ns.db.shareLocation = false end,
		function(w) w.see(8) end,
		function(w, H) w.clock = w.clock + H.WAIT + 1 end,
	}) do
		WithHop(function(w, H)
			w.see(7); H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
			H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
			local data = w.popups[1].data
			change(w, H)
			H.Answer(data, true)
			eq(#w.invited, 0); eq(w.whispered[#w.whispered], "Asker-Realm LN~42")
		end)
	end
end)

test("hop regression: queued requests stop after a zone change or joining another party", function()
	for _, change in ipairs({ function(w) w.map = 1429 end, function(w) w.group = 2 end }) do
		WithHop(function(w, H)
			w.see(7)
			for i = 1, H.BRAKE_ASKS + 1 do H.Hear(1453, 8, "Player" .. i, w.clock) end
			H.Ask(1453, 8, "busy layer"); eq(H.State().phase, "queued")
			local before = #w.sent
			change(w); w.clock = H.State().sendAt; H.Tick()
			eq(#w.sent, before); eq(H.State().phase, "done")
		end)
	end
end)

test("hop regression: an early decline waits for late offers within the original window", function()
	WithHop(function(w, H)
		w.see(7); H.Ask(1453, 8, "destination")
		H.HandleOffer("WHISPER", "Early-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW; H.Tick()
		H.HandleNo("WHISPER", "Early-Realm", "LN~1")
		assert(H.State().phase ~= "done", "late offers still have time")
		w.clock = w.clock + 2
		H.HandleOffer("WHISPER", "Late-Realm", "LO~1~0~0"); H.Tick()
		eq(H.State().helper, "Late-Realm"); eq(w.whispered[#w.whispered], "Late-Realm LR~1")
	end)
end)

test("hop regression: a stale reading does not block an explicit request as already there", function()
	WithHop(function(w, H)
		w.see(8); w.clock = w.clock + H.LAYER_FRESH + 1
		H.Ask(1453, 8, "destination")
		assert(H.State() and H.State().phase == "asking")
	end)
end)

test("hop regression: a replaced group is never left by a running hop", function()
	WithHop(function(w, H)
		Join(w, H)
		w.party.party1 = "Friend"; H.OnRoster()
		w.see(8); H.OnLayer()
		eq(w.left, 0); eq(H.State().phase, "done")
	end)
end)

test("hop regression: one border NPC or repeated sightings of it cannot confirm a hop", function()
	WithHop(function(w, H)
		Join(w, H)
		w.npc, w.spawn = 8, 20
		ns.Layers.Observe("target"); H.OnLayer()
		eq(w.left, 0, "one target-layer NPC is provisional")
		ns.Layers.Observe("target"); H.OnLayer()
		eq(w.left, 0, "the same NPC twice is not independent evidence")
		w.spawn = 21; ns.Layers.Observe("target"); H.Tick()
		eq(w.left, 1); eq(H.Stats().moves, 1)
	end)
end)

test("hop controls: list and status are local; any selects the freshest alternative", function()
	WithHop(function(w, H)
		w.see(7)
		ns.Layers.Receive("Older-Realm", { mapID = 1453, zoneUID = 8, guild = "Olympus" })
		w.clock = w.clock + 10
		ns.Layers.Receive("Fresh-Realm", { mapID = 1453, zoneUID = 9, guild = "Olympus" })
		local before, whispers = #w.sent, #w.whispered
		H.Command("list"); H.Command("status"); H.Command("bogus"); H.Command("12345")
		eq(#w.sent, before); eq(#w.whispered, whispers)
		H.Command(" ANY ")
		eq(H.State().zoneUID, 9); eq(w.sent[#w.sent], "CHANNEL LQ~1~1453~9")
		assert(H.ProgressText():find("0", 1, true), "offers appear in progress")
	end)
end)

test("hop controls: explicit UID uses the current zone and cancel never leaves a group", function()
	WithHop(function(w, H)
		w.see(7)
		ns.Layers.Receive("Helper-Realm", { mapID = 1453, zoneUID = 8, guild = "Olympus" })
		SlashCmdList.OLYMPUS("hop #8")
		eq(H.State().zoneUID, 8)
		H.HandleOffer("WHISPER", "Helper-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW; H.Tick()
		SlashCmdList.OLYMPUS("hop cancel")
		H.OnInvite("Helper"); eq(w.accepted, 0, "late invite stays manual")
		eq(H.State().phase, "done"); eq(w.left, 0)
		w.clock = w.clock + H.ASK_GAP
		Join(w, H); eq(H.State().phase, "joined")
		H.Command("cancel"); w.see(8); H.OnLayer()
		eq(w.left, 0, "cancel while joined retains the player's group")
	end)
end)

test("hop controls: any needs a fresh local reading and skips old remote reports", function()
	WithHop(function(w, H)
		ns.Layers.Receive("Helper-Realm", { mapID = 1453, zoneUID = 8, guild = "Olympus" })
		H.Command("any"); eq(H.State(), nil, "own layer unknown")
		w.see(7); w.clock = w.clock + H.LAYER_FRESH + 1
		H.Command("any"); eq(H.State(), nil, "own layer stale")
		w.see(7); H.Command("any"); eq(H.State(), nil, "only remote report is stale")
	end)
end)

test("hop controls: Realm rows show progress, cancel and the age of layer reports", function()
	WithHop(function(w, H)
		w.see(7)
		ns.Layers.Receive("Helper-Realm", { mapID = 1453, zoneUID = 8, guild = "Olympus" })
		local function Find(text, right)
			for _, row in ipairs(ns.Views.Build("realm")) do
				if (right and row.right == text) or (not right and row.text and row.text:find(text, 1, true)) then return row end
			end
		end
		local any = Find(ns.L.HOP_ANY_BUTTON)
		assert(any and any.onClick); any.onClick()
		eq(H.State().zoneUID, 8)
		local cancel = Find(ns.L.HOP_CANCEL_BUTTON, true)
		assert(cancel and cancel.onClick); cancel.onClick()
		eq(H.State().phase, "done"); eq(w.left, 0)
		local row = Find("#8")
		assert(row and row.tooltip)
		local tips = {}
		row.tooltip({ AddLine = function(_, line) tips[#tips + 1] = line end })
		assert(table.concat(tips, "\n"):find("Latest layer report:", 1, true))
	end)
end)

test("hop evidence: two NPC readings outside the confirmation window do not auto-leave", function()
	WithHop(function(w, H)
		Join(w, H)
		w.npc, w.spawn = 8, 20; ns.Layers.Observe("target")
		w.clock = w.clock + ns.Layers.EVIDENCE_WINDOW + 1
		w.spawn = 21; ns.Layers.Observe("target"); H.OnLayer()
		eq(w.left, 0)
		w.spawn = 22; ns.Layers.Observe("target"); H.OnLayer()
		eq(w.left, 1)
	end)
end)

test("hop regression: a release arriving before the roster event never leaves a friend's group", function()
	WithHop(function(w, H)
		Join(w, H)
		w.party.party1 = "Friend"
		H.HandleRelease("WHISPER", "Helper-Realm", "LX~1")
		eq(w.left, 0); eq(H.State().phase, "done")
	end)
end)

test("hop regression: a dismissed leave dialog cannot leave after cancellation", function()
	WithHop(function(w, H)
		Join(w, H)
		w.clock = w.clock + H.JOIN_WAIT; H.Tick()
		local data = w.popups[#w.popups].data
		H.Cancel()
		StaticPopupDialogs.OLYMPUS_HOP_LEAVE.OnAccept(nil, data)
		eq(w.left, 0); eq(H.State().phase, "done")
	end)
end)

test("hop adversarial: an offer capability is bound to its sender and consumed once", function()
	WithHop(function(w, H)
		w.see(7)
		H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
		eq(w.whispered[1], "Asker-Realm LO~42~0~0")
		H.HandleRequest("WHISPER", "Spoof-Realm", "LR~42")
		eq(#w.invited, 0); eq(#w.popups, 0, "same id from another sender has no authority")
		H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
		eq(#w.popups, 1)
		H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
		eq(#w.popups, 1, "a replay cannot create a second prompt or invitation")
	end)
end)

test("hop mixed versions: the established LQ LO LR LN wire remains strict and interoperable", function()
	WithHop(function(w, H)
		w.see(7)
		H.Ask(1453, 8, "destination")
		eq(w.sent[1], "CHANNEL LQ~1~1453~8", "an older helper sees the unchanged request")
		H.HandleOffer("WHISPER", "Old-Realm", "LO~1~0~0")
		H.HandleOffer("WHISPER", "Junk-Realm", "LO~1~0~0~extra")
		eq(H.State().count, 1, "a canonical old offer is accepted; an extended spoof is not")
		w.clock = w.clock + H.WINDOW; H.Tick()
		eq(w.whispered[1], "Old-Realm LR~1", "the old helper sees the unchanged invite request")
		H.HandleNo("WHISPER", "Old-Realm", "LN~1")
		assert(H.State().phase ~= "requested", "the unchanged decline is understood")
	end)
end)

test("hop adversarial: reset or cancellation revokes every old invite authorization", function()
	for _, reset in ipairs({ false, true }) do
		WithHop(function(w, H)
			w.see(7); H.Ask(1453, 8, "destination")
			H.HandleOffer("WHISPER", "Helper-Realm", "LO~1~0~0")
			w.clock = w.clock + H.WINDOW; H.Tick()
			if reset then H.Reset() else H.Cancel() end
			H.OnInvite("Helper")
			eq(w.accepted, 0, reset and "reload/reset" or "cancel")
			eq(w.left, 0)
		end)
	end
end)

test("issue 50: Always invite is automatic alone and with hop guests, manual in ordinary groups and raids", function()
	WithHop(function(w, H)
		w.see(7); ns.db.layerAutoInvite = true
		H.HandleAsk("CHANNEL", "First-Realm", "LQ~41~1453~7")
		H.HandleRequest("WHISPER", "First-Realm", "LR~41")
		eq(w.invited[1], "First"); eq(#w.popups, 0, "alone")

		w.clock = w.clock + H.HELP_GAP + 1
		w.group, w.lead, w.party.party1 = 2, true, "First"
		H.HandleAsk("CHANNEL", "Second-Realm", "LQ~42~1453~7")
		H.HandleRequest("WHISPER", "Second-Realm", "LR~42")
		eq(w.invited[2], "Second"); eq(#w.popups, 0, "a party containing only addon hop guests")
	end)
	for _, raid in ipairs({ false, true }) do
		WithHop(function(w, H)
			w.see(7); ns.db.layerAutoInvite = true
			w.group, w.lead = raid and 6 or 2, true
			w.party[raid and "raid1" or "party1"] = "Friend"
			H.HandleAsk("CHANNEL", "Asker-Realm", "LQ~42~1453~7")
			H.HandleRequest("WHISPER", "Asker-Realm", "LR~42")
			eq(#w.invited, 0, raid and "ordinary raid" or "ordinary party")
			eq(#w.popups, 1, "the player must click")
			eq(H.Stats().autoBlocked, 1, "diagnosable without broadening the policy")
		end)
	end
end)

test("hop adversarial (1.2.0): a stranger on the channel gets no offer, and his request no window or invite, even with Always invite", function()
	WithHop(function(w, H)
		w.see(7)
		ns.db.layerAutoInvite = true
		w.strangers["Stranger-Realm"] = true
		H.HandleAsk("CHANNEL", "Stranger-Realm", "LQ~42~1453~7")
		eq(#w.whispered, 0, "no offer to a stranger")
		H.HandleRequest("WHISPER", "Stranger-Realm", "LR~42")
		eq(#w.invited, 0); eq(#w.popups, 0)
		-- A member of another federation guild the channel verified (Channels.VerifiedLevel's
		-- level, verified: here an officer the census names) is helped: the offer and the window.
		-- (Changed on purpose, 1.2.1: the stub returned 1, false, a guild only claimed, and expected
		-- an invite; such a claim is anyone's word now, its own test below.)
		w.strangers["Ally-Realm"] = true
		local guildOf, level = ns.Moderation.GuildOf, ns.Channels.VerifiedLevel
		ns.Moderation.GuildOf = function(n) return ns.FullName(n) == "Ally-Realm" and "Olympus III" or guildOf(n) end
		ns.Channels.VerifiedLevel = function(n, g) if ns.FullName(n) == "Ally-Realm" then return 2, true, 1 end return level(n, g) end
		ns.db.layerAutoInvite = nil
		local ok, err = pcall(function()
			H.HandleAsk("CHANNEL", "Ally-Realm", "LQ~43~1453~7")
			eq(w.whispered[1], "Ally-Realm LO~43~0~0")
			H.HandleRequest("WHISPER", "Ally-Realm", "LR~43")
			eq(#w.popups, 1, "the window")
			H.Answer(w.popups[1].data, true)
			eq(w.invited[1], "Ally", "invited on the click")
		end)
		ns.Moderation.GuildOf, ns.Channels.VerifiedLevel = guildOf, level
		ns.db.layerAutoInvite = nil
		if not ok then error(err, 0) end
	end)
end)

-- Review of 1.2.1: a guild named in the sender's own messages (Moderation.GuildOf) is only his
-- word, and anyone on the channel can write "Olympus" into one: Channels.VerifiedLevel answers
-- 1, false for it. Not membership: no offer (it tells him who helps on that layer), no window and
-- no invite, even with Always invite.
test("hop security (1.2.1): a claimed Olympus guild gets no offer, window or invite, even with Always invite", function()
	WithHop(function(w, H)
		w.see(7)
		w.strangers["Claimer-Realm"] = true
		local guildOf = ns.Moderation.GuildOf
		ns.Moderation.GuildOf = function(n) if ns.FullName(n) == "Claimer-Realm" then return "Olympus Claimed" end return guildOf(n) end
		local ok, err = pcall(function()
			local level, verified = ns.Channels.VerifiedLevel("Claimer-Realm", "Olympus Claimed")
			eq(level, 1); eq(verified, false, "the channel's own answer: a claim, not verified")
			ns.db.layerAutoInvite = true
			H.HandleAsk("CHANNEL", "Claimer-Realm", "LQ~42~1453~7")
			eq(#w.whispered, 0, "no offer")
			H.HandleRequest("WHISPER", "Claimer-Realm", "LR~42")
			eq(#w.invited, 0, "no invite"); eq(#w.popups, 0, "no window")
			eq(H.Stats().strangers, 2)
		end)
		ns.Moderation.GuildOf = guildOf
		if not ok then error(err, 0) end
	end)
end)

-- The asker's side (HandleOffer had no check): the ask's id is on the channel, so anyone could
-- answer it with an offer and be asked for the invite.
test("hop security (1.2.1): the asker takes no offer from a claimed guild; a verified member of another guild still helps", function()
	WithHop(function(w, H)
		w.see(7)
		w.strangers["Claimer-Realm"], w.strangers["Stranger-Realm"], w.strangers["Ally-Realm"] = true, true, true
		local guildOf, level = ns.Moderation.GuildOf, ns.Channels.VerifiedLevel
		ns.Moderation.GuildOf = function(n)
			local full = ns.FullName(n)
			if full == "Claimer-Realm" then return "Olympus Claimed" end
			if full == "Ally-Realm" then return "Olympus III" end
			return guildOf(n)
		end
		ns.Channels.VerifiedLevel = function(n, g) if ns.FullName(n) == "Ally-Realm" then return 2, true, 1 end return level(n, g) end
		local ok, err = pcall(function()
			H.Ask(1453, 8, "destination")
			H.HandleOffer("WHISPER", "Stranger-Realm", "LO~1~0~0")
			H.HandleOffer("WHISPER", "Claimer-Realm", "LO~1~0~0")
			eq(H.State().count, 0, "neither offer is taken")
			w.clock = w.clock + H.WINDOW; H.Tick()
			eq(#w.whispered, 0, "nobody is asked for the invite")
			H.HandleOffer("WHISPER", "Ally-Realm", "LO~1~0~0")
			eq(H.State().count, 1, "a verified member of another guild")
			H.Tick()
			eq(w.whispered[1], "Ally-Realm LR~1")
		end)
		ns.Moderation.GuildOf, ns.Channels.VerifiedLevel = guildOf, level
		if not ok then error(err, 0) end
	end)
end)

-- Review of 1.2.1: Hop.Trusted counted a Lord or Captain the census names, and while signed
-- enforcement is off (as 1.2.1 ships) two cooperating characters can forge one in their guild's
-- reports. That trust accepted his invite for the player (AcceptGroup) and let "Always invite" or
-- "For Olympus!" invite him without a click. Now only our roster, signed or pinned people; a
-- census officer of another guild (Channels.VerifiedLevel's 2, true) still hops by a click.
local RealTrusted = ns.Hop.Trusted
local function WithCensusOfficer(w, H, fn)
	H.Trusted = RealTrusted -- (WithHop puts it back)
	w.strangers["Officer-Realm"] = true
	local guildOf, known, guilds = ns.Moderation.GuildOf, ns.Data.KnownRank, ns.rdb.guilds
	ns.rdb.guilds = { ["Olympus III"] = { total = 40, online = 4, zones = {}, t = w.clock, leader = "Leadperson",
		leaderOnline = false, officers = { { name = "Officer" } }, top = {} } }
	-- The census's word that "Officer" is an officer there (two reports, Data.KnownRank).
	ns.Data.KnownRank = function(n, g, soft)
		if ns.FullName(n) == "Officer-Realm" and g == "Olympus III" then return 1, 2 end
		return known(n, g, soft)
	end
	ns.Moderation.GuildOf = function(n) if ns.FullName(n) == "Officer-Realm" then return "Olympus III" end return guildOf(n) end
	local ok, err = pcall(function()
		local level, verified = ns.Channels.VerifiedLevel("Officer-Realm", "Olympus III")
		eq(level, 2); eq(verified, true, "the census verifies him: a member")
		fn()
	end)
	ns.Moderation.GuildOf, ns.Data.KnownRank, ns.rdb.guilds = guildOf, known, guilds
	if not ok then error(err, 0) end
end

test("hop security (1.2.1): Always invite and For Olympus! invite a census officer of another guild only on a click", function()
	for _, mode in ipairs({ "always", "king" }) do
		WithHop(function(w, H)
			WithCensusOfficer(w, H, function()
				local S, saved = ns.HopSightings, ns.HopSightings.LocalKingLayer
				local ok, err = pcall(function()
					w.see(7)
					if mode == "always" then ns.db.layerAutoInvite = true
					else
						S.LocalKingLayer = function(mapID, zoneUID) return mapID == 1453 and zoneUID == 7 end
						H.ChooseKing("auto")
					end
					eq(RealTrusted("Officer-Realm"), false, "the census alone vouches for nobody")
					H.HandleAsk("CHANNEL", "Officer-Realm", "LQ~42~1453~7")
					eq(w.whispered[1], "Officer-Realm LO~42~0~0", "still offered")
					H.HandleRequest("WHISPER", "Officer-Realm", "LR~42")
					eq(#w.invited, 0, mode .. ": not invited on its own")
					eq(#w.popups, 1, mode .. ": the window")
					H.Answer(w.popups[1].data, true)
					eq(w.invited[1], "Officer", "invited on the click")
					-- A guildmate is still invited on its own (alone with a hop guest: OnlyGuests).
					w.group, w.lead, w.party.party1 = 2, true, "Officer"
					w.clock = w.clock + H.HELP_GAP + 1
					H.HandleAsk("CHANNEL", "Mate-Realm", "LQ~43~1453~7")
					H.HandleRequest("WHISPER", "Mate-Realm", "LR~43")
					eq(w.invited[2], "Mate", mode .. ": a guildmate, on its own"); eq(#w.popups, 1)
				end)
				S.LocalKingLayer = saved
				if not ok then error(err, 0) end
			end)
		end)
	end
end)

test("hop security (1.2.1): a census officer's invite is never accepted for the player; a guildmate's is", function()
	WithHop(function(w, H)
		WithCensusOfficer(w, H, function()
			w.see(7)
			H.Ask(1453, 8, "destination")
			H.HandleOffer("WHISPER", "Officer-Realm", "LO~1~0~0")
			eq(H.State().count, 1, "his offer is taken: a verified member")
			w.clock = w.clock + H.WINDOW; H.Tick()
			eq(w.whispered[1], "Officer-Realm LR~1")
			H.OnInvite("Officer")
			eq(w.accepted, 0, "the game's invite window: the player clicks")
			eq(H.State().phase, "requested")
			-- The player accepts by hand: the hop goes on as the officer's.
			w.group, w.party.party1 = 2, "Officer"; H.OnRoster()
			eq(H.State().phase, "joined")
		end)
	end)
	WithHop(function(w, H)
		H.Trusted = RealTrusted
		w.see(7)
		H.Ask(1453, 8, "destination")
		H.HandleOffer("WHISPER", "Mate-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW; H.Tick()
		H.OnInvite("Mate")
		eq(w.accepted, 1, "a guildmate's invite is accepted for the player")
	end)
end)

test("hop security (1.2.1): trust is asked again at the invite, and a pinned or signed title still counts", function()
	WithHop(function(w, H)
		H.Trusted = RealTrusted
		w.see(7)
		H.Ask(1453, 8, "destination")
		H.HandleOffer("WHISPER", "Mate-Realm", "LO~1~0~0")
		assert(H.State().offers["Mate-Realm"].trusted, "a guildmate when he offered")
		w.clock = w.clock + H.WINDOW; H.Tick()
		w.strangers["Mate-Realm"] = true -- (out of our roster before his invite)
		H.OnInvite("Mate")
		eq(w.accepted, 0, "not one of ours any more: the player clicks")
		local K, saved = ns.King, ns.King.IsStewardName
		K.IsStewardName = function(n) return ns.FullName(n) == "Stewardy-Realm" end
		local ok, err = pcall(function()
			w.strangers["Stewardy-Realm"] = true
			eq(RealTrusted("Stewardy-Realm"), true, "the signed titles' Steward")
			eq(RealTrusted("Nobody-Realm"), true, "(a guildmate in this harness)")
			w.strangers["Nobody-Realm"] = true
			eq(RealTrusted("Nobody-Realm"), false, "anyone else")
		end)
		K.IsStewardName = saved
		if not ok then error(err, 0) end
	end)
end)

-- Review of 1.2.1: the helper we asked was matched by his short name, so a namesake on another
-- realm of our group ("Helper-Otherrealm") had his invite accepted for the player as the helper's,
-- and his LN or LX (the ask's id is on the channel) moved our ask on or took us out of the group.
test("hop security (1.2.1): a namesake on another realm is not the helper we asked: invite, no and release", function()
	WithHop(function(w, H)
		w.see(7)
		H.Ask(1453, 8, "destination")
		H.HandleOffer("WHISPER", "Helper-Realm", "LO~1~0~0")
		H.HandleOffer("WHISPER", "Second-Realm", "LO~1~0~0")
		w.clock = w.clock + H.WINDOW; H.Tick()
		eq(H.State().helper, "Helper-Realm")
		H.OnInvite("Helper-Otherrealm")
		eq(w.accepted, 0, "a namesake's invite is not accepted for the player")
		eq(H.State().invitedBy, nil, "nor taken as the helper's")
		H.HandleNo("WHISPER", "Helper-Otherrealm", "LN~1")
		eq(H.State().helper, "Helper-Realm", "a namesake's no does not move the ask on")
		eq(H.State().phase, "requested")
		H.OnInvite("Helper")
		eq(w.accepted, 1, "the helper of our realm, named without it by the game")
		w.group, w.party.party1 = 2, "Helper"; H.OnRoster()
		eq(H.State().phase, "joined")
		H.HandleRelease("WHISPER", "Helper-Otherrealm", "LX~1")
		eq(w.left, 0, "a namesake's release does not take us out of the group")
		eq(H.State().phase, "joined")
		H.HandleRelease("WHISPER", "Helper-Realm", "LX~1")
		eq(w.left, 1, "the helper's own does")
	end)
end)

-- Review of 1.2.1, after 52b7a66: with Always invite or For Olympus! on, a member of another guild
-- the addon cannot vouch for gets the window. Two of those windows left unanswered (a helper away
-- from the keyboard, For Olympus!'s very case) paused all helping for 5 minutes, a guildmate's
-- automatic invite too, and one census officer could keep automatic helpers switched off that way
-- with two requests every 5 minutes. Such a window's no is still a no to him, never a step towards
-- the pause: before 52b7a66 he was invited without one, so it could not pause the helper either.
test("hop security (1.2.1): unanswered windows of members we cannot vouch for never pause an automatic helper", function()
	for _, mode in ipairs({ "always", "king" }) do
		WithHop(function(w, H)
			WithCensusOfficer(w, H, function()
				local S, saved = ns.HopSightings, ns.HopSightings.LocalKingLayer
				local ok, err = pcall(function()
					w.see(7)
					if mode == "always" then ns.db.layerAutoInvite = true
					else
						S.LocalKingLayer = function(mapID, zoneUID) return mapID == 1453 and zoneUID == 7 end
						H.ChooseKing("auto")
					end
					for i = 1, H.DECLINES do
						H.HandleAsk("CHANNEL", "Officer-Realm", ("LQ~%d~1453~7"):format(40 + i))
						H.HandleRequest("WHISPER", "Officer-Realm", ("LR~%d"):format(40 + i))
						eq(#w.popups, i, mode .. ": window " .. i)
						-- Not answered: its timeout (OnCancel), as Escape or Not now.
						StaticPopupDialogs.OLYMPUS_HOP_REQUEST.OnCancel(nil, w.popups[i].data)
						eq(w.whispered[#w.whispered], ("Officer-Realm LN~%d"):format(40 + i), mode .. ": still a no to him")
						w.clock = w.clock + H.HELP_GAP + 1
					end
					eq(#w.invited, 0)
					eq(H.CanHelp(1453, 7), true, mode .. ": no pause")
					H.HandleAsk("CHANNEL", "Mate-Realm", "LQ~50~1453~7")
					eq(w.whispered[#w.whispered], "Mate-Realm LO~50~0~0", mode .. ": a guildmate is offered")
					H.HandleRequest("WHISPER", "Mate-Realm", "LR~50")
					eq(w.invited[1], "Mate", mode .. ": and invited on his own"); eq(#w.popups, H.DECLINES)
				end)
				S.LocalKingLayer = saved
				if not ok then error(err, 0) end
			end)
		end)
	end
	-- The pause itself stays for windows the player has to answer: no automatic mode.
	WithHop(function(w, H)
		WithCensusOfficer(w, H, function()
			w.see(7)
			for i = 1, H.DECLINES do
				H.HandleAsk("CHANNEL", "Officer-Realm", ("LQ~%d~1453~7"):format(40 + i))
				H.HandleRequest("WHISPER", "Officer-Realm", ("LR~%d"):format(40 + i))
				StaticPopupDialogs.OLYMPUS_HOP_REQUEST.OnCancel(nil, w.popups[i].data)
				w.clock = w.clock + H.HELP_GAP + 1
			end
			eq(H.CanHelp(1453, 7), false, "two unanswered windows: a break")
			w.clock = w.clock + H.PAUSE
			w.see(7)
			eq(H.CanHelp(1453, 7), true, "over after the pause")
		end)
	end)
end)

