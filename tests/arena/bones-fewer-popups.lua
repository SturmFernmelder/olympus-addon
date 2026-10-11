-- 1.2.1 (a player's report: "I don't wanna play bones every time I go to an inn. Or ever, for that
-- matter."): Bones's pop-ups. Invitations from other players (KI) keep their pop-up, but from two
-- different players within ten minutes one question asks whether to stop them; the privacy page's
-- "Bones invitations" line (on until the player says No) refuses them quietly when off, with a
-- reason the inviter sees. The innkeeper's offer is the quiet line in his conversation; where that
-- line cannot show, his Olympus window opens only for a player who asked for him on the Bones
-- page, and the privacy page's "Bones at innkeepers" line hides it. On the test world with the
-- Bones tables' additions (tests/arena/lib/farkle-world.lua). Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = H.World.NAMES

local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end
local function FT(w, c)
	return setmetatable({}, { __index = function(_, k)
		local v = c.ns.FarkleTable[k]
		if type(v) == "function" then return function(...) return w:As(c, v, ...) end end
		return v
	end })
end
local function Has(list, text)
	for _, l in ipairs(list or {}) do
		local s = type(l) == "table" and l.text or l
		if tostring(s):find(text, 1, true) then return true end
	end
	return false
end

-- A guest and the players who invite him (all at the Goldshire inn, trained unless told). What
-- the guest's screens would show is counted at their two doors: the invitation's own pop-up
-- (FarkleTable.ShowUI "invite") and Olympus's dialogs (ns.ShowDialog).
local function World(o)
	o = o or {}
	local w = FW.New({ seed = 11 })
	local guest = w:Player(N.fighterB, { bonesTrained = o.guestTrained })
	local hosts = {}
	for i, name in ipairs({ N.fighterA, N.bettor1, N.bettor2 }) do hosts[i] = w:Player(name) end
	local seen = { invites = {}, dialogs = {}, printed = {} }
	guest.ns.FarkleTable.ShowUI = function(what, id) if what == "invite" then seen.invites[#seen.invites + 1] = id end return true end
	rawset(guest.ns, "ShowDialog", function(which, text, _, data) seen.dialogs[#seen.dialogs + 1] = { which = which, text = text, data = data } end)
	local print = guest.ns.Print
	guest.ns.Print = function(msg) seen.printed[#seen.printed + 1] = tostring(msg); return print(msg) end
	return w, guest, hosts, seen
end
local function Invite(w, host, guest)
	local id, why = FT(w, host).Create({ guest = guest.name, target = 2000, rehearsal = true })
	assert(id, "the host's invitation: " .. tostring(why))
	w:Run(0)
	return id
end
-- The guest's click on the question's buttons (the dialog's own handlers, as the game calls them).
local function Answer(w, guest, button)
	local def = assert(guest.popups.OLYMPUS_BONES_INVITES, "the question's dialog")
	w:As(guest, function()
		if button == "stop" then def.OnAccept(nil, nil)
		elseif button == "keep" then def.OnCancel(nil, nil, "clicked")
		else def.OnCancel(nil, nil, nil) end
	end)
	w:Run(0)
end

test("1.2.1 Bones invitations: from a second player within ten minutes, one question in place of its pop-up; Stop them refuses what waits and every later one quietly, the inviters told why; the privacy page turns them back on", function()
	local w, b, hosts, seen = World()
	local L = b.ns.L
	local first = Invite(w, hosts[1], b)
	eq(#seen.invites, 1, "the first invitation: its pop-up"); eq(#seen.dialogs, 0)
	w:Run(120) -- (two minutes later; the first has expired by now)
	local second = Invite(w, hosts[2], b)
	eq(#seen.invites, 1, "the second player's: no pop-up of its own")
	eq(#seen.dialogs, 1, "one question"); eq(seen.dialogs[1].which, "OLYMPUS_BONES_INVITES")
	eq(seen.dialogs[1].text, L.FARKLE_INVITES_ASK:format(2))
	assert(seen.dialogs[1].text:find("/oly privacy", 1, true), "it says where to turn them back on")
	local def = b.popups.OLYMPUS_BONES_INVITES
	eq(def.button1, L.FARKLE_INVITES_STOP); eq(def.button2, L.FARKLE_INVITES_KEEP)
	eq(b.ns.FarkleTable.Get(second).state, "invite", "the invitation waits meanwhile")
	Answer(w, b, "stop")
	eq(b.db.bonesInvites, false, "off")
	eq(seen.printed[#seen.printed], L.FARKLE_INVITES_OFF)
	eq(hosts[2].ns.FarkleTable.Get(second).state, "declined", "the waiting one refused")
	eq(hosts[2].ns.FarkleTable.Get(second).why, "i")
	eq(hosts[1].ns.FarkleTable.Get(first).state ~= "invite", true)
	-- Off: a third player's invitation is refused quietly, and he reads why on his table.
	local before = #seen.printed
	local third = Invite(w, hosts[3], b)
	eq(#seen.invites, 1, "no pop-up"); eq(#seen.dialogs, 1, "no question again"); eq(#seen.printed, before, "not a line in chat")
	eq(b.ns.FarkleTable.Get(third), nil, "nothing kept of it")
	local ka = w:Sent({ from = b, type = "KA" })
	assert(ka[#ka].msg:find("~0~i~", 1, true), ka[#ka].msg)
	local t3 = hosts[3].ns.FarkleTable.Get(third)
	eq(t3.state, "declined"); eq(t3.why, "i")
	assert(Has(t3.log, L.FARKLE_LOG_DECLINED:format(hosts[3].ns.DisplayName(b.name), L.FARKLE_WHY_I)), "the inviter's table says why")
	-- The privacy page's line: off; its Yes turns them back on, and an invitation shows again.
	local C = b.Consent
	local line
	for _, item in ipairs(C.Items()) do if item.key == "bonesInvites" then line = item end end
	assert(line, "the Bones invitations line on the privacy page")
	eq(C.Answer("bonesInvites"), false)
	for _, item in ipairs(C.Pending()) do assert(item.key ~= "bonesInvites", "it never opens the page by itself") end
	eq(C.Choose("bonesInvites", true), true)
	eq(b.db.bonesInvites, true); eq(seen.printed[#seen.printed], L.FARKLE_INVITES_ON)
	w:Run(61)
	Invite(w, hosts[3], b)
	eq(#seen.invites, 2, "on again: its pop-up"); eq(#seen.dialogs, 1, "answered: never asked again")
	NoErrors(w)
end)

test("1.2.1 Bones invitations: Keep them keeps them and shows the waiting invitation; the question never comes again; Escape answers nothing and it waits for another session", function()
	local w, b, hosts, seen = World()
	Invite(w, hosts[1], b)
	w:Run(61) -- (one invitation waits at a time: another one meanwhile is refused as busy, unseen)
	local second = Invite(w, hosts[2], b)
	eq(#seen.dialogs, 1)
	Answer(w, b, "keep")
	eq(b.db.bonesInvites, true, "kept: answered")
	eq(seen.invites[#seen.invites], second, "the waiting invitation's pop-up")
	w:Run(61)
	Invite(w, hosts[3], b)
	w:Run(61)
	Invite(w, hosts[1], b)
	eq(#seen.dialogs, 1, "never asked again"); eq(#seen.invites, 4)
	-- Escape: nothing answered; not again this session.
	local w2, b2, hosts2, seen2 = World()
	Invite(w2, hosts2[1], b2)
	w2:Run(61)
	Invite(w2, hosts2[2], b2)
	Answer(w2, b2, "escape")
	eq(b2.db.bonesInvites, nil, "not answered")
	eq(#seen2.invites, 2, "the waiting invitation shows")
	w2:Run(61)
	Invite(w2, hosts2[3], b2)
	eq(#seen2.dialogs, 1, "not again this session"); eq(#seen2.invites, 3)
	NoErrors(w); NoErrors(w2)
end)

test("1.2.1 Bones invitations: one player's invitations, or two players' more than ten minutes apart, ask nothing", function()
	local w, b, hosts, seen = World()
	Invite(w, hosts[1], b)
	w:Run(61)
	Invite(w, hosts[1], b)
	eq(#seen.dialogs, 0, "the same player twice"); eq(#seen.invites, 2)
	w:Run(b.ns.FarkleTable.INVITES_WINDOW + 1)
	Invite(w, hosts[2], b)
	eq(#seen.dialogs, 0, "another player, past the window"); eq(#seen.invites, 3)
	eq(b.ns.FarkleTable.INVITES_WINDOW, 600); eq(b.ns.FarkleTable.INVITES_BURST, 2)
	NoErrors(w)
end)

test("1.2.1 Bones invitations: a player who never played the innkeeper is asked too, after the second player's invitation", function()
	local w, b, hosts, seen = World({ guestTrained = false })
	local L = b.ns.L
	Invite(w, hosts[1], b)
	Invite(w, hosts[2], b)
	eq(#seen.invites, 0, "untrained: no invitation pop-up, as before")
	assert(Has(seen.printed, L.FARKLE_INVITED_NOT_TRAINED:match("^%%s(.-)%.")), "told in chat, as before")
	eq(#seen.dialogs, 1, "the question")
	Answer(w, b, "stop")
	local third = Invite(w, hosts[3], b)
	eq(hosts[3].ns.FarkleTable.Get(third).why, "i", "off: the reason is the switch, not the first game")
	NoErrors(w)
end)

test("1.2.1 Bones invitations: off, a matched partner's invitation still comes (the player searched); /oly farkle invites on|off is the same switch", function()
	local w, b, hosts, seen = World()
	w:As(b, function() SlashCmdList.OLYMPUS("farkle invites off") end)
	eq(b.db.bonesInvites, false, "/oly farkle invites off")
	eq(seen.printed[#seen.printed], b.ns.L.FARKLE_INVITES_OFF)
	rawset(b.ns, "ArenaMatch", { MatchedWith = function(sender) return b.ns.FarkleTable.Same(sender, hosts[1].name) end,
		Vet = function() return true, "M9" end })
	local id = Invite(w, hosts[1], b)
	eq(b.ns.FarkleTable.Get(id).state, "invite", "the match's invitation")
	eq(#seen.invites, 1)
	w:Run(1) -- (a table's id is its host's second and count: another second, another id)
	local other = Invite(w, hosts[2], b)
	eq(hosts[2].ns.FarkleTable.Get(other).why, "i", "anyone else's: refused")
	eq(#seen.dialogs, 0)
	w:As(b, function() SlashCmdList.OLYMPUS("farkle invites on") end)
	eq(b.db.bonesInvites, true, "/oly farkle invites on")
	w:As(b, function() SlashCmdList.OLYMPUS("farkle keeper off") end)
	eq(b.db.bonesKeeper, false, "/oly farkle keeper off")
	w:As(b, function() SlashCmdList.OLYMPUS("farkle keeper") end)
	eq(seen.printed[#seen.printed], b.ns.L.FARKLE_KEEPER_OFFER_OFF, "alone, it says which")
	NoErrors(w)
end)

test("1.2.1 Bones at innkeepers: talking to an innkeeper whose conversation can't hold the Bones line opens nothing by itself; the Bones page's ask opens it once; the privacy page's No hides the offer", function()
	for _, pad in ipairs({ false, true }) do
		H.WithGamepadUI(pad, function()
			local w = FW.New({ seed = 3, compliance = "shipped" })
			local a = w:Player(N.fighterA, { bonesTrained = false })
			w:Stand(a.name, FW.INN, true)
			a.globals.UnitGUID = function(unit) if unit == "npc" then return "Creature-0-1-0-1-295-00001" end end
			a.globals.UnitName = function(unit) if unit == "npc" then return "Localized Innkeeper" end end
			local shown = {}
			a.ns.FarkleTable.ShowUI = function(what, _, name) shown[#shown + 1] = what .. ":" .. tostring(name) return true end
			local function Talk()
				w:Fire(a, "GOSSIP_SHOW")
				w:Run(0)
			end
			for visit = 1, 3 do
				Talk()
				eq(#shown, 0, "visit " .. visit .. ": nothing opens by itself")
			end
			-- The Bones page's keeper button: the player asked for the innkeeper.
			local own = w:As(a, function() return H.LoadCompanion(a.ns) end)
			a.ns.InnkeeperArrow = { State = function() return { active = false } end,
				Target = function() return nil, "arrived", { innkeeper = "Innkeeper Farley" } end,
				Start = function() return false, "no-inn" end, Cancel = function() end }
			w:As(a, function() own.ArenaUI.BoneFindInnkeeper() end)
			Talk()
			eq(#shown, 1, "asked for: his offer, once"); eq(shown[1], "innkeeper:Localized Innkeeper")
			Talk()
			eq(#shown, 1, "the ask served one conversation")
			-- The privacy page's No: no offer, asked for or not; the native line's own check says so.
			local C = a.Consent
			eq(C.Answer("bonesKeeper"), true, "on until the player says No")
			eq(C.Choose("bonesKeeper", false), true)
			eq(a.db.bonesKeeper, false)
			eq(a.printed[#a.printed], a.ns.L.FARKLE_KEEPER_OFFER_OFF)
			w:As(a, function() a.ns.FarkleTable.WantKeeper() end)
			Talk()
			eq(#shown, 1, "hidden: nothing")
			local ok, why = w:As(a, function() return a.ns.InnkeeperGossip.ShowRow() end)
			eq(ok, false); eq(why, pad and "gamepad" or "off")
			for _, item in ipairs(C.Pending()) do assert(item.key ~= "bonesKeeper", "it never opens the page by itself") end
			eq(C.Choose("bonesKeeper", true), true); eq(a.db.bonesKeeper, true)
			NoErrors(w)
		end)
	end
end)
