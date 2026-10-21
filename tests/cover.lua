-- Embrace Anonymity (Cover.lua): a moderator's cover name, shown in place of the real one to those who
-- accepted moderator protection, and the moderator off the Olympus network while it is on.
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]cover%.lua$")) or "./"
local ADDON_DIR = ROOT .. "Olympus/"
local FreshComm, WithGamepadUI = extra.FreshComm, extra.WithGamepadUI

-- (Loaded once into the harness's ns, by whichever test file needs it first: tests/roster.lua too.)
if not ns.Cover then
	assert(loadfile(ADDON_DIR .. "Locales/CoverText.lua"))("Olympus", ns)
	assert(loadfile(ADDON_DIR .. "Cover.lua"))("Olympus", ns)
end
local Cover, L = ns.Cover, ns.L

local MOD = "Watch Keeper-Realm"
local NOW = 1000000

-- A scene: the signed council naming MOD, this client's answer, the covers heard, a clock, and the
-- messages Olympus sends (ns.Comm.Send) and its prints. Everything put back after.
local function Scene(fn, opts)
	opts = opts or {}
	local saved = { council = ns.rdb.council, covers = ns.rdb.covers, consent = ns.db.coverConsent, cover = ns.db.cover,
		me = ns.me, now = ns.Now, send = ns.Comm.Send, print = ns.Print, gi = GetGuildInfo, uip = UnitIsPlayer,
		ufn = ns.UnitFullName, iig = IsInGuild, allowed = ns.QuietPresenceAllowed, member = ns.IsMember }
	local s = { sent = {}, printed = {}, now = NOW }
	ns.rdb.council = { at = 1, names = { ["watch keeper"] = "Watch Keeper", ["other keeper"] = "Other Keeper" } }
	ns.rdb.covers = {}
	ns.db.coverConsent = opts.consent
	ns.db.cover = nil
	ns.me = opts.me or "Tester-Realm"
	ns.Now = function() return s.now end
	ns.Comm.Send = function(dist, msg) s.sent[#s.sent + 1] = dist .. " " .. msg return true end
	ns.Print = function(msg) s.printed[#s.printed + 1] = tostring(msg) end
	GetGuildInfo = function() return "Olympus II", "Member", 3 end
	IsInGuild = function() return true end
	-- Who may go quiet is quiet presence's rule (Core.lua: a current signed issuer, or the author),
	-- with its own tests; here, whether this character passes it (opts.issuer), and an accepted Accord.
	ns.QuietPresenceAllowed = function(name) return opts.issuer == true and name == ns.me end
	ns.IsMember = function() return true end
	local ok, err = pcall(fn, s)
	for _, owner in ipairs({ Cover.QUIET_OWNER, "other addon" }) do ns.SetQuietPresence(false, owner) end
	ns.QuietPresenceAllowed, ns.IsMember = saved.allowed, saved.member
	ns.rdb.council, ns.rdb.covers, ns.db.coverConsent, ns.db.cover = saved.council, saved.covers, saved.consent, saved.cover
	ns.me, ns.Now, ns.Comm.Send, ns.Print, GetGuildInfo = saved.me, saved.now, saved.send, saved.print, saved.gi
	UnitIsPlayer, ns.UnitFullName, IsInGuild = saved.uip, saved.ufn, saved.iig
	if not ok then error(err, 0) end
end

-- A font string of the game's: its text, and how often it was written.
local function FontString(text)
	local fs = { text = text, writes = 0 }
	function fs:GetText() return self.text end
	function fs:SetText(t) self.text = t; self.writes = self.writes + 1 end
	return fs
end

test("cover: a cover name is a first name and a surname of letters, its words capitalised; anything else is refused", function()
	eq(Cover.Clean("  aldric   stonebrook "), "Aldric Stonebrook")
	eq(Cover.Clean("Ana"), "Ana", "one word")
	eq(Cover.Clean("Élise Dawnmere"), "Élise Dawnmere", "Latin-1 accented letters")
	eq(Cover.Clean("A Stonebrook"), nil, "a word under 2 letters")
	eq(Cover.Clean("Abcdefghijklm Stone"), nil, "a word over 12 letters")
	eq(Cover.Clean("Al Ric Stone"), nil, "three words")
	eq(Cover.Clean("Al|cffff0000x"), nil, "an escape")
	eq(Cover.Clean("Al~ric"), nil, "the message separator")
	eq(Cover.Clean("Al1ric"), nil, "a digit")
	eq(Cover.Clean(""), nil); eq(Cover.Clean(nil), nil)
end)

test("cover: the privacy page asks for moderator protection explicitly, and only a Yes shows cover names", function()
	Scene(function(s)
		eq(ns.Consent.Answer(Cover.CONSENT_KEY), nil, "unanswered")
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		eq(Cover.AliasOf(MOD), nil, "no answer: the real name")
		ns.Consent.Choose(Cover.CONSENT_KEY, false)
		eq(Cover.AliasOf(MOD), nil, "No: the real name")
		ns.Consent.Choose(Cover.CONSENT_KEY, true)
		eq(Cover.AliasOf(MOD), "Aldric Stonebrook", "Yes: the cover name")
		eq(Cover.AliasOf("Watch Keeper"), "Aldric Stonebrook", "the short name on our realm")
		eq(ns.CoverSwap("Watch Keeper"), "Aldric Stonebrook")
		eq(ns.CoverSwap("Someone Else"), "Someone Else", "anyone else as given")
		local text = L.COVER_CONSENT_TEXT
		assert(text:find("good faith", 1, true) and text:find("report", 1, true) and text:find("/who", 1, true), text)
	end)
end)

test("cover: only the King, a councillor of the signed list or the author give a cover, on the channel or the guild", function()
	Scene(function()
		Cover.Handle("CHANNEL", "Random Player-Realm", "MC~Aldric Stonebrook")
		eq(Cover.AliasOf("Random Player-Realm"), nil, "not a moderator")
		Cover.Handle("WHISPER", MOD, "MC~Aldric Stonebrook")
		eq(Cover.AliasOf(MOD), nil, "a whisper")
		Cover.Handle("GUILD", MOD, "MC~Aldric Stonebrook")
		eq(Cover.AliasOf(MOD), "Aldric Stonebrook", "over the guild")
		Cover.Handle("CHANNEL", ns.KingCharacter() .. "-Realm", "MC~Bran Oakfield")
		eq(Cover.AliasOf(ns.KingCharacter() .. "-Realm"), "Bran Oakfield", "the King")
		Cover.Handle("CHANNEL", MOD, "MC~0")
		eq(Cover.AliasOf(MOD), nil, "ended")
	end, { consent = true })
end)

test("cover: a cover name can't be a real name we know or another moderator's cover", function()
	Scene(function()
		Cover.Handle("CHANNEL", MOD, "MC~Other Keeper")
		eq(Cover.AliasOf(MOD), nil, "a councillor's name")
		Cover.Handle("CHANNEL", MOD, "MC~" .. ns.KingCharacter())
		eq(Cover.AliasOf(MOD), nil, "the King's name")
		Cover.Handle("CHANNEL", MOD, "MC~Tester")
		eq(Cover.AliasOf(MOD), nil, "our own name")
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		Cover.Handle("CHANNEL", "Other Keeper-Realm", "MC~aldric stonebrook")
		eq(Cover.AliasOf("Other Keeper-Realm"), nil, "another holder's cover")
		Cover.Handle("CHANNEL", MOD, "MC~Al|Hx")
		eq(Cover.AliasOf(MOD), "Aldric Stonebrook", "a bad one changes nothing")
	end, { consent = true })
end)

test("cover: a cover is kept a while after it was last heard, and goes with its holder's place on the council", function()
	Scene(function(s)
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		s.now = NOW + Cover.KEEP - 1
		eq(Cover.AliasOf(MOD), "Aldric Stonebrook", "still kept")
		s.now = NOW + Cover.KEEP + 1
		eq(Cover.AliasOf(MOD), nil, "too old")
		s.now = NOW
		eq(Cover.AliasOf(MOD), "Aldric Stonebrook")
		ns.rdb.council = { at = 2, names = { ["other keeper"] = "Other Keeper" } }
		eq(Cover.AliasOf(MOD), nil, "no longer a councillor")
		Cover.Prune()
		eq(ns.rdb.covers[MOD], nil, "pruned")
	end, { consent = true })
end)

test("cover: the moderator sees their own name; a reporter gives them offline whatever its own answer", function()
	Scene(function()
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		eq(Cover.AliasOf(MOD), nil, "not consented")
		eq(Cover.Offline(MOD), true, "offline in the census we send all the same")
		eq(Cover.Offline("Someone Else-Realm"), false)
	end)
	Scene(function()
		ns.rdb.covers[MOD] = { alias = "Aldric Stonebrook", t = NOW }
		eq(Cover.AliasOf(MOD), nil, "our own cover: our own name")
		eq(Cover.Offline(MOD), false)
	end, { consent = true, me = MOD })
end)

test("cover: only a moderator may embrace anonymity; it is said on the channel and the guild, and ending it too", function()
	Scene(function(s)
		eq(Cover.Enable("Aldric Stonebrook"), false)
		eq(s.printed[1], L.COVER_ONLY); eq(#s.sent, 0)
	end)
	Scene(function(s)
		eq(Cover.Enable("Al1"), false, "a bad name"); eq(s.printed[1], L.COVER_BAD)
		eq(Cover.Enable("Other Keeper"), false, "a real name"); eq(s.printed[2], L.COVER_TAKEN)
		eq(Cover.Enable("aldric stonebrook"), true)
		eq(Cover.Active(), "Aldric Stonebrook")
		eq(s.sent[1], "CHANNEL MC~Aldric Stonebrook"); eq(s.sent[2], "GUILD MC~Aldric Stonebrook")
		eq(Cover.Say(), false, "not again before ANNOUNCE_EVERY")
		s.now = NOW + Cover.ANNOUNCE_EVERY
		eq(Cover.Say(), true, "again every ANNOUNCE_EVERY")
		eq(Cover.Disable(), true)
		eq(Cover.Active(), nil)
		eq(s.sent[#s.sent - 1], "CHANNEL MC~0"); eq(s.sent[#s.sent], "GUILD MC~0")
		s.now = NOW + 2 * Cover.ANNOUNCE_EVERY
		eq(Cover.Say(), true, "the end said again for a while")
		s.now = NOW + Cover.ANNOUNCE_EVERY + Cover.OFF_REPEAT + 1
		eq(Cover.Say(), false, "then nothing")
	end, { me = MOD, issuer = true })
end)

test("cover: embracing anonymity is quiet presence (Olympus's one silence path): on with the cover, again at each login, off with it, and never another owner's", function()
	Scene(function(s)
		-- A councillor quiet presence refuses (not a current signed issuer): no cover either.
		eq(Cover.Enable("Aldric Stonebrook"), false)
		eq(s.printed[1], L.COVER_ONLY); eq(#s.sent, 0); eq(ns.QuietPresence(), false)
	end, { me = MOD, issuer = false })
	Scene(function()
		eq(Cover.Enable("Aldric Stonebrook"), true)
		eq(ns.QuietPresence(), true, "quiet with the cover")
		eq(ns.QuietPresenceOwnedBy(Cover.QUIET_OWNER), true)
		-- A /reload: quiet presence is gone, the cover kept; the login asks for it again.
		ns.SetQuietPresence(false, Cover.QUIET_OWNER)
		eq(ns.QuietPresence(), false)
		eq(Cover.Resume(), true)
		eq(ns.QuietPresence(), true, "quiet again at login")
		eq(Cover.Disable(), true)
		eq(ns.QuietPresence(), false, "back on the network with the cover off")
		-- Another owner made us quiet first: the cover counts it, and its end leaves it on.
		eq(ns.SetQuietPresence(true, "other addon"), true)
		eq(Cover.Enable("Aldric Stonebrook"), true)
		eq(Cover.Disable(), true)
		eq(ns.QuietPresence(), true, "another owner's quiet stays")
		eq(ns.QuietPresenceOwnedBy("other addon"), true)
	end, { me = MOD, issuer = true })
end)

test("cover: a covered client says no hello, sends no census and no position (quiet presence at the transport); its moderation still goes", function()
	local savedChat = C_ChatInfo
	Scene(function()
		local cns = FreshComm()
		local sent = {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
		eq(Cover.Enable("Aldric Stonebrook"), true)
		sent = {}
		cns.Comm.Hello(true)
		cns.Comm.Broadcast({ guild = "Olympus II", total = 1, online = 1 })
		eq(cns.Comm.Send("GUILD", "P1~1~2"), false, "a position held")
		cns.Comm.Send("GUILD", "MW~x")
		cns.Comm.Pump()
		local said = table.concat(sent, " | ")
		assert(not said:find("H1~", 1, true) and not said:find("P1~", 1, true) and not said:find("R2", 1, true), "nothing of presence: " .. said)
		assert(said:find("GUILD MW~x", 1, true), "moderation goes: " .. said)
	end, { me = MOD, issuer = true })
	C_ChatInfo = savedChat
end)

test("cover: the game's name texts show the cover, give the game's name back when it ends, and leave the game's own writes alone", function()
	Scene(function()
		UnitIsPlayer = function() return true end
		ns.UnitFullName = function(unit) return unit == "nameplate1" and MOD or "Someone Else-Realm" end
		local plate = { unit = "nameplate1", name = FontString("Watch Keeper") }
		Cover.NameUpdated(plate)
		eq(plate.name.text, "Watch Keeper", "no cover heard")
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		Cover.NameUpdated(plate)
		eq(plate.name.text, "Aldric Stonebrook", "the cover")
		Cover.NameUpdated(plate)
		eq(plate.name.writes, 1, "written once")
		local other = { unit = "nameplate2", name = FontString("Someone Else") }
		Cover.NameUpdated(other)
		eq(other.name.text, "Someone Else", "anyone else untouched"); eq(other.name.writes, 0)
		-- The plate goes to another unit: the game writes its name, ours is forgotten, nothing written.
		plate.unit, plate.name.text = "nameplate2", "Someone Else"
		Cover.NameUpdated(plate)
		eq(plate.name.text, "Someone Else"); eq(plate.name.writes, 1)
		-- Back on the moderator, then the cover ends: the game's name back.
		plate.unit, plate.name.text = "nameplate1", "Watch Keeper"
		Cover.NameUpdated(plate)
		eq(plate.name.text, "Aldric Stonebrook")
		Cover.Handle("CHANNEL", MOD, "MC~0")
		Cover.NameUpdated(plate)
		eq(plate.name.text, "Watch Keeper", "the real name back")
		-- A forbidden frame, a name the client hides: left alone.
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		local forbidden = { unit = "nameplate1", name = FontString("Watch Keeper"), IsForbidden = function() return true end }
		Cover.NameUpdated(forbidden)
		eq(forbidden.name.text, "Watch Keeper", "forbidden")
	end, { consent = true })
end)

test("cover: without a Yes, the game's name texts are never written", function()
	Scene(function()
		UnitIsPlayer = function() return true end
		ns.UnitFullName = function() return MOD end
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		local plate = { unit = "nameplate1", name = FontString("Watch Keeper") }
		Cover.NameUpdated(plate)
		eq(plate.name.text, "Watch Keeper"); eq(plate.name.writes, 0)
	end, { consent = false })
end)

test("cover: the target frame's name shows the cover", function()
	local saved = rawget(_G, "TargetFrame")
	Scene(function()
		UnitIsPlayer = function() return true end
		ns.UnitFullName = function(unit) return unit == "target" and MOD or nil end
		TargetFrame = { name = FontString("Watch Keeper") }
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		Cover.FrameUpdated("target")
		eq(TargetFrame.name.text, "Aldric Stonebrook")
		-- Forever's frame without .name: its content's Name.
		TargetFrame = { TargetFrameContent = { TargetFrameContentMain = { Name = FontString("Watch Keeper") } } }
		Cover.FrameUpdated("target")
		eq(TargetFrame.TargetFrameContent.TargetFrameContentMain.Name.text, "Aldric Stonebrook")
	end, { consent = true })
	TargetFrame = saved
end)

test("cover: with the gamepad UI nothing of the game's is written, and a switch to it gives every name text back", function()
	Scene(function()
		UnitIsPlayer = function() return true end
		ns.UnitFullName = function() return MOD end
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		local plate = { unit = "nameplate1", name = FontString("Watch Keeper") }
		Cover.NameUpdated(plate)
		eq(plate.name.text, "Aldric Stonebrook")
		WithGamepadUI(true, function()
			ns.Gate.Park("cover-names")
			eq(plate.name.text, "Watch Keeper", "given back at the switch")
			local again = { unit = "nameplate1", name = FontString("Watch Keeper") }
			Cover.NameUpdated(again)
			eq(again.name.writes, 0, "nothing written with the gamepad UI")
		end)
	end, { consent = true })
end)

test("cover: the tooltip's first line says the cover, without the council's lines or mark", function()
	local saved = { tip = GameTooltip, left = rawget(_G, "GameTooltipTextLeft1"), uip = UnitIsPlayer, ufn = UnitFullName,
		ggi = GetGuildInfo }
	Scene(function()
		local lines = {}
		GameTooltipTextLeft1 = FontString("Watch Keeper")
		GameTooltip = { GetName = function() return "GameTooltip" end, GetUnit = function() return "Watch Keeper", "mouseover" end,
			AddLine = function(_, t) lines[#lines + 1] = tostring(t) end }
		UnitIsPlayer = function() return true end
		UnitFullName = function() return "Watch Keeper", "Realm" end
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		ns.Inspect.TooltipUnit(GameTooltip)
		eq(GameTooltipTextLeft1.text, "Aldric Stonebrook")
		for _, line in ipairs(lines) do assert(not line:find(L.COUNCIL_PERSON, 1, true), "no council line: " .. line) end
		-- A title around the name stays.
		GameTooltipTextLeft1 = FontString("Sergeant Watch Keeper")
		ns.Inspect.TooltipUnit(GameTooltip)
		eq(GameTooltipTextLeft1.text, "Sergeant Aldric Stonebrook")
	end, { consent = true })
	GameTooltip, GameTooltipTextLeft1, UnitIsPlayer, UnitFullName, GetGuildInfo = saved.tip, saved.left, saved.uip, saved.ufn, saved.ggi
end)

test("cover: Olympus's pages show the cover name: the census's coloured names and the chat lines, without the council's colour", function()
	Scene(function()
		Cover.Handle("CHANNEL", MOD, "MC~Aldric Stonebrook")
		local colored = ns.Views.ClassColored("Watch Keeper", "WARRIOR")
		assert(colored:find("Aldric Stonebrook", 1, true) and not colored:find("Watch Keeper", 1, true), colored)
		local line = ns.Channels.FormatLine("A", MOD, "Olympus II", nil, "hello", true)
		-- (The link under the name keeps the real one: a click whispers the player the server finds.)
		assert(line:find("[Aldric Stonebrook]", 1, true), line)
		assert(not line:find("[Watch Keeper]", 1, true), "the real name not shown: " .. line)
		assert(not line:find(ns.HIGH_COUNCIL_COLOR, 1, true), "no council colour: " .. line)
		ns.db.coverConsent = false
		line = ns.Channels.FormatLine("A", MOD, "Olympus II", nil, "hello", true)
		assert(line:find("Watch Keeper|r]", 1, true) and not line:find("Aldric", 1, true), "without a Yes, the real name: " .. line)
	end, { consent = true })
end)
