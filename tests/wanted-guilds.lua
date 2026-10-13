-- 1.2.4: Most Wanted across Olympus guilds, with the real trust chain on every receiver.
-- Every client here runs the real Olympus/Wanted.lua over the harness's real Channels
-- (VerifiedLevel), Data (the census: ClaimGuild, AuthorizedRank), Roster, Moderation and Authority;
-- each client's own guild roster is put in place while the game runs it. The game's API is shaped as
-- the Forever client's own UI source documents it (wow-ui-source, branch forever, 1.60.1.70338,
-- Interface/AddOns/Blizzard_APIDocumentationGenerated): C_DeathRecap.HasRecapEvents/GetRecapEvents
-- with an optional recap ID (DeathRecapDocumentation.lua), rows newest first with the killing blow
-- first (Blizzard_DeathRecap.lua); PARTY_KILL's attackerGUID and targetGUID (UnitDocumentation.lua);
-- GetPlayerInfoByGUID's eight returns, MayReturnNothing: only players this client's game met
-- (PlayerScriptDocumentation.lua); UnitTokenFromGUID, a token only for a unit this client has
-- (UnitDocumentation.lua); GetGuildInfo for a unit; GetServerTime (SystemTimeDocumentation.lua);
-- C_DeathInfo with its five functions and no recap reader (DeathInfoDocumentation.lua); no combat
-- log (COMBAT_LOG_EVENT_UNFILTERED HasRestrictions, CombatLogDocumentation.lua).
-- Until 1.2.4 a member's row counted only where its sender was proven: on his guildmates' clients
-- (their roster) and for a leader or officer his guild's census names. An ordinary member of another
-- guild, the most of the army, was refused "olympus" by every other client, the author's and the
-- reviewers' too, so nothing was relayed and Most Wanted stayed empty. Every name here is made up.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]wanted%-guilds%.lua$")) or "./"

local DIALOGS = { "OLYMPUS_WANTED_ADD", "OLYMPUS_WANTED_REMOVE", "OLYMPUS_WANTED_SEND", "OLYMPUS_WANTED_REVIEW",
	"OLYMPUS_WANTED_WITHDRAW", "OLYMPUS_WANTED_PUBLISH", "OLYMPUS_WANTED_REVOKE", "OLYMPUS_WANTED_CORRECT",
	"OLYMPUS_WANTED_REVIEWER", "OLYMPUS_WANTED_AVENGED" }

local function StandIn(kind)
	local o = { kind = kind, shown = false }
	function o:Show() self.shown = true end
	function o:Hide() self.shown = false end
	function o:IsShown() return self.shown end
	function o:CreateTexture() return StandIn("texture") end
	function o:CreateFontString() return StandIn("font") end
	function o:SetText(t) self.text = t end
	function o:GetText() return self.text end
	return setmetatable(o, { __index = function() return function() end end })
end

local GLOBALS = { "UnitGUID", "UnitIsPlayer", "UnitFactionGroup", "GetGuildInfo", "GetRealZoneText", "UnitIsDeadOrGhost",
	"C_DateAndTime", "C_DeathInfo", "C_DeathRecap", "GetFileIDFromPath", "C_ChatInfo", "GetTime", "GetChannelName",
	"GetPlayerInfoByGUID", "UnitTokenFromGUID", "IsInInstance", "UnitLevel", "GetMaxPlayerLevel", "InCombatLockdown",
	"GetServerTime", "issecretvalue", "CombatLogGetCurrentEventInfo", "C_DamageMeter", "UnitName", "UnitFullName" }

local G1, G2, G3 = "Olympus Wgone", "Olympus Wgtwo", "Olympus Wgthree"

local function WithGuilds(fn)
	local saved = {}
	for _, name in ipairs(GLOBALS) do saved[name] = _G[name] end
	local dialogs = {}
	for _, which in ipairs(DIALOGS) do dialogs[which] = StaticPopupDialogs[which] end
	local R = ns.Roster
	local savedRoster = { R.byName, R.complete, R.generation, R.guild, R.group, R.faction, R.snapshotAt }
	local savedNow, savedMe, savedLogin, savedGuilds = ns.Now, ns.me, ns.Comm and ns.Comm.loginAt, ns.rdb.guilds
	local savedEnforced, savedHides = ns.Authority and ns.Authority.Enforced, ns.Moderation.Hides
	local realEd = ns.Ed25519
	local world = { epoch = 1800000000, clients = {}, queue = {}, jobs = {}, timers = {}, members = {}, log = {}, hidden = {} }
	local current
	local ok, err = pcall(function()
		ns.Now = function() return world.epoch end
		if ns.Comm then ns.Comm.loginAt = world.epoch - 7200 end
		ns.rdb.guilds = {}
		local realHides = ns.Moderation.Hides
		-- (A moderators' word on a character, as Moderation.Hides answers it: world.hidden.)
		ns.Moderation.Hides = function(sender, ...)
			if type(sender) == "string" and world.hidden[ns.Fold(ns.FullName(sender))] then return { word = "off" }, sender end
			return realHides(sender, ...)
		end
		local function U(unit) return current and current.units[unit] end
		UnitGUID = function(unit) return U(unit) and U(unit).guid end
		UnitIsPlayer = function(unit) return U(unit) ~= nil end
		UnitFactionGroup = function(unit) local u = U(unit) if u then return u.faction, u.faction end end
		UnitName = function(unit) local u = U(unit) if u then return ns.ShortName(u.name), nil end end
		UnitFullName = function(unit) local u = U(unit) if u then return ns.ShortName(u.name), "Realm" end end
		UnitIsDeadOrGhost = function(unit) return unit == "player" and current ~= nil and current.dead == true end
		GetGuildInfo = function(unit)
			local u = U(unit or "player")
			if u and u.guild then return u.guild, "Rank" .. (u.rank or 9), u.rank or 9, nil end
		end
		UnitLevel = function(unit) return U(unit) and U(unit).level end
		GetMaxPlayerLevel = function() return 60 end
		InCombatLockdown = function() return false end
		GetRealZoneText = function() return "Arathi Highlands" end
		C_DateAndTime = { GetCurrentCalendarTime = function() return { year = 2027, month = 1 } end }
		C_DeathInfo = { GetCorpseMapPosition = function() end, GetDeathReleasePosition = function() end,
			GetGraveyardsForMap = function() return {} end, GetSelfResurrectOptions = function() return {} end,
			UseSelfResurrectOption = function() end }
		C_DeathRecap = { HasRecapEvents = function() return current ~= nil and current.recap ~= nil end,
			GetRecapEvents = function() return current and current.recap or {} end }
		IsInInstance = function() return false, "none" end
		GetServerTime = function() return math.floor(world.epoch) end
		issecretvalue = function() return false end
		CombatLogGetCurrentEventInfo = nil
		C_DamageMeter = nil
		UnitTokenFromGUID = function(guid)
			if not current then return nil end
			for unit, u in pairs(current.units) do if u.guid == guid then return unit end end
			return nil
		end
		GetPlayerInfoByGUID = function(guid)
			if not current then return nil end
			local function Ret(name, race) return "Warrior", "WARRIOR", race, race, 2, ns.ShortName(name), "", 60 end
			for _, u in pairs(current.units) do if u.guid == guid then return Ret(u.name, u.race or "Human") end end
			local c = current.cache[guid]
			if c then return Ret(c.name, c.race) end
			return nil
		end
		GetFileIDFromPath = function() return nil end
		GetTime = function() return world.epoch end
		GetChannelName = function() return 7, "OlympusNet" end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() return true end }
		local function Fold(name) return ns.Fold(ns.FullName(name)) end

		-- The real modules' state for the client the game runs now: its own guild's roster (fresh and
		-- complete), its name. The census (ns.rdb.guilds) is what every receiver heard alike.
		local function Enter(cl)
			local byName = {}
			for full, m in pairs(world.members) do if m.guild == cl.guild then byName[full] = m.rank end end
			R.byName, R.complete, R.generation, R.guild = byName, true, 1, cl.guild
			R.group, R.faction, R.snapshotAt = ns.group, ns.faction, world.epoch
			ns.me = cl.name
		end
		function world:As(cl, f, ...)
			local was = current
			current = cl
			Enter(cl)
			local res = { pcall(f, ...) }
			current = was
			if was then Enter(was) end
			if not res[1] then error(res[2], 0) end
			return unpack(res, 2)
		end
		function world:Load(cl)
			local c = setmetatable({ L = ns.L, db = cl.db, rdb = cl.rdb, realm = "Realm", group = cl.group or "RealmGroup",
				faction = "Alliance" }, { __index = function(_, key) if key ~= "me" then return ns[key] end end })
			c.Now = function() return world.epoch end
			c.IsMember = function() return ns.IsFederation(cl.units.player.guild) end
			-- (c.Channels, c.Roster, c.Data, c.Moderation, c.Authority: the real modules, by __index.)
			c.Workshop = { IsAuthor = function() return cl.role == "author" end, IsAuthorName = function(name)
				local o = world:Find(name) return o ~= nil and o.role == "author" end }
			c.IsKingCharacter = function() return false end
			c.IsHighCouncillor = function(name) local o = world:Find(name) return o ~= nil and o.role == "council" end
			c.Ed25519 = { ToB64 = realEd.ToB64, FromB64 = realEd.FromB64, ValidPublicKey = realEd.ValidPublicKey,
				Verify = realEd.Verify, Busy = function() return 0 end,
				Run = function(job, done) world.jobs[#world.jobs + 1] = { cl = cl, owner = c, job = job, done = done } return true end }
			c.Debts = { MyKey = function() return "gk", cl.pk, "fp" end, Sign = function(msg) return realEd.Sign(cl.seed, msg, cl.pk) end,
				B64 = realEd.ToB64, UnB64 = realEd.FromB64,
				-- (Debts.InfoName as Debts.lua reads the game's lookup: its 6th and 7th returns.)
				InfoName = function(guid)
					local okI, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
					if not okI or type(name) ~= "string" or name == "" then return nil end
					return ns.FullName(name, type(realm) == "string" and realm ~= "" and realm or nil)
				end }
			c.Comm = { Handle = function(kind, call) cl.handlers[kind] = call end,
				Whisper = function(to, text) world.queue[#world.queue + 1] = { from = cl, to = to, dist = "WHISPER", text = text } return true end,
				Send = function(dist, text, key, _, _, done, options)
					world.queue[#world.queue + 1] = { from = cl, dist = dist, text = text, key = key, done = done, options = options } return true
				end,
				SendChunked = function(text, _, _, done, options)
					world.queue[#world.queue + 1] = { from = cl, dist = "CHANNEL", text = text, done = done, options = options } return true
				end }
			c.UnitFullName = function(unit) return U(unit) and U(unit).name end
			c.RegisterEvent = function(name, call) cl.events[name] = call end
			c.Fire = function() end
			c.On = function(name, call) cl.listeners[name] = call end
			c.Print = function(message) cl.prints[#cl.prints + 1] = tostring(message) end
			c.Ago = function(at) return tostring(world.epoch - (tonumber(at) or 0)) .. "s" end
			c.ShowDialog = function() return true end
			c.After = function(seconds, _, f) world.timers[#world.timers + 1] = { at = world.epoch + seconds, cl = cl, owner = c, fn = f } end
			c.Every, c.Log = function() end, function() end
			c.SafeCall = function(_, f, ...) return f(...) end
			c.UI = { Refresh = function() end, RefreshSoon = function() end, IsShown = function() return false end,
				ShowCopy = function(title, text) cl.copies[#cl.copies + 1] = { title = title, text = text } end,
				WhisperText = function() return true end, ShowPerson = function() return true end }
			c.Consent = { Waiting = function() return false end }
			c.Window = function() return StandIn("window") end
			c.Dialog = { Show = function() return StandIn("dialog") end, Find = function() return nil end }
			c.HonorsNet = { QueueLetter = function() end, LetterToSender = function() return false end,
				LetterFrame = function() return nil end, WaitForWindow = function() end }
			cl.handlers, cl.listeners, cl.events, cl.ns, cl.copies = {}, {}, {}, c, {}
			world:As(cl, function() assert(loadfile(ROOT .. "Olympus/Wanted.lua"))("Olympus", c) end)
			cl.W = c.Wanted
			if cl.listeners.INIT then world:As(cl, cl.listeners.INIT) end
			c.me = cl.name
			if cl.listeners.LOGIN then world:As(cl, cl.listeners.LOGIN) end
			return cl
		end
		local serial = 0
		-- A client: o.rank (4, an ordinary member, by default), o.role ("author", "council"), o.group
		-- (its realm group), o.roster (false: not in its guild's roster, or the guild whose roster has him).
		function world:Client(name, guild, o)
			o = o or {}
			name = ns.FullName(name)
			serial = serial + 1
			local guid = ("Player-1-0E%06X"):format(serial)
			local seed = ns.Sign.SHA256("guilds seed " .. name)
			local rank = o.rank or 4
			local cl = { name = name, guid = guid, guild = guild, rank = rank, role = o.role, group = o.group, online = true, cache = {},
				db = {}, rdb = {}, prints = {}, seed = seed, pk = realEd.PublicKey(seed),
				units = { player = { name = name, guid = guid, faction = "Alliance", guild = guild, rank = rank, level = 60 } } }
			if o.roster ~= false then world.members[name] = { guild = o.roster or guild, rank = rank } end
			world.clients[#world.clients + 1] = cl
			return world:Load(cl)
		end
		function world:Find(to)
			local key = Fold(to)
			for _, o in ipairs(world.clients) do if Fold(o.name) == key then return o end end
			return nil
		end
		function world:Deliver()
			local guard = 0
			while #world.queue > 0 or #world.jobs > 0 do
				guard = guard + 1
				assert(guard < 5000, "the world settles")
				local m = table.remove(world.queue, 1)
				if m then
					local permitted = not m.options or not m.options.guard or world:As(m.from, m.options.guard)
					if permitted then
						world.log[#world.log + 1] = m
						if m.done then world:As(m.from, m.done, true) end
						if m.dist == "WHISPER" then
							local to = world:Find(m.to)
							if to and to.online and to.handlers[m.text:sub(1, 2)] then world:As(to, to.handlers[m.text:sub(1, 2)], "WHISPER", m.from.name, m.text) end
						else
							for _, o in ipairs(world.clients) do
								local handler = o.handlers[m.text:sub(1, 2)]
								if o ~= m.from and o.online and handler then world:As(o, handler, "CHANNEL", m.from.name, m.text) end
							end
						end
					elseif m.done then world:As(m.from, m.done, false, "guard") end
				else
					local j = table.remove(world.jobs, 1)
					if j.cl.online and j.cl.ns == j.owner then
						world:As(j.cl, function() local good, valid = pcall(j.job) j.done(good, valid) end)
					end
				end
			end
		end
		function world:Run(seconds)
			local stop = world.epoch + seconds
			world:Deliver()
			while true do
				table.sort(world.timers, function(a, b) return a.at < b.at end)
				local t = world.timers[1]
				if not t or t.at > stop then break end
				table.remove(world.timers, 1)
				world.epoch = math.max(world.epoch, t.at)
				if t.cl.online and t.cl.ns == t.owner then world:As(t.cl, t.fn) end
				world:Deliver()
			end
			world.epoch = stop
		end
		-- Two members of `guild` report its census (its master and officers: Codec's R2 line), heard
		-- by every receiver (taken while the game runs `listener`, who is not of that guild).
		function world:Census(listener, guild, leader, officers, reporters)
			local list = {}
			for _, who in ipairs(officers) do list[#list + 1] = ns.ShortName(who) .. ":1:0" end
			for _, who in ipairs(reporters) do
				local line = "R2~" .. guild .. "~120~30~" .. ns.ShortName(leader) .. "~1~9~~~0,0,0,0,0,0,0~~" .. table.concat(list, ",")
				local r = assert(ns.Codec.DecodeReport(line), "a census line")
				assert(world:As(listener, ns.Data.Receive, r, who), "census taken from " .. who)
			end
		end
		-- A Horde player kills `victim` in the open world: Forever's recap rows (no destGUID, flags
		-- given or not), PLAYER_DEAD on his client, whose game met him (its lookup knows his GUID).
		-- o.targeted: on the victim's target too.
		function world:Death(victim, hordeName, hordeGuid, o)
			o = o or {}
			victim.cache[hordeGuid] = { name = hordeName, race = o.race or "Orc" }
			if o.targeted then victim.units.target = { name = hordeName, guid = hordeGuid, faction = "Horde", level = 60, race = o.race or "Orc" } end
			local short = ns.ShortName(hordeName) .. "-Realm"
			victim.dead = true
			victim.recap = {
				{ event = "SPELL_DAMAGE", timestamp = world.epoch - 0.2, overkill = 120, amount = 900, sourceName = short,
					hideCaster = false, sourceGUID = hordeGuid, sourceFlags = o.flags },
				{ event = "SWING_DAMAGE", timestamp = world.epoch - 3, overkill = -1, amount = 300, sourceName = short,
					hideCaster = false, sourceGUID = hordeGuid, sourceFlags = o.flags } }
			world:As(victim, victim.events.PLAYER_DEAD)
			world:Run(3)
			victim.dead, victim.recap, victim.units.target = false, nil, nil
			world:Deliver()
		end
		-- `slayer`'s own killing blow on a Horde player on his target (his level seen, 60): the
		-- native PARTY_KILL.
		function world:Kill(slayer, hordeName, hordeGuid, o)
			o = o or {}
			slayer.cache[hordeGuid] = { name = hordeName, race = o.race or "Troll" }
			slayer.units.target = { name = hordeName, guid = hordeGuid, faction = "Horde", level = 60, race = o.race or "Troll" }
			local good, why = world:As(slayer, slayer.events.PARTY_KILL, slayer.guid, hordeGuid)
			slayer.units.target = nil
			world:Deliver()
			return good, why
		end
		function world:Target(cl, guid) return world:As(cl, cl.W.Target, nil, guid) end
		function world:Status(cl) return world:As(cl, cl.W.StatusText) end
		-- The last line /oly wanted status lists about one Horde player's name.
		function world:Line(cl, horde)
			for line in world:Status(cl):gmatch("[^\n]+") do
				if line:find("^%s+%d%d:%d%d:%d%d") and line:find(horde, 1, true) then return line end
			end
			return nil
		end
		function world:Relays(from)
			local n = 0
			for _, m in ipairs(world.log) do if m.from == from and m.text:find("^WK~R~") then n = n + 1 end end
			return n
		end
		fn(world)
	end)
	for _, name in ipairs(GLOBALS) do _G[name] = saved[name] end
	for _, which in ipairs(DIALOGS) do StaticPopupDialogs[which] = dialogs[which] end
	R.byName, R.complete, R.generation, R.guild, R.group, R.faction, R.snapshotAt = unpack(savedRoster, 1, 7)
	ns.Now, ns.me, ns.rdb.guilds = savedNow, savedMe, savedGuilds
	if ns.Comm then ns.Comm.loginAt = savedLogin end
	if ns.Authority then ns.Authority.Enforced = savedEnforced end
	ns.Moderation.Hides = savedHides
	if not ok then error(err, 0) end
end

-- The scene: an ordinary member of <G1> and his guildmate; the author's character (a reviewer) in
-- <G2>; an ordinary member of <G3>. <G1>'s census (its master and one officer, two reporters) is
-- heard everywhere, and names neither member.
local function Scene(world, tag)
	local sender = world:Client("Wgsender" .. tag .. "-Realm", G1)
	local mate = world:Client("Wgmate" .. tag .. "-Realm", G1)
	local author = world:Client("Wgscribe" .. tag .. "-Realm", G2, { role = "author" })
	local third = world:Client("Wgthird" .. tag .. "-Realm", G3)
	world:Census(author, G1, "Wgmaster" .. tag .. "-Realm", { "Wgofficer" .. tag .. "-Realm" },
		{ "Wgreporter" .. tag .. "a-Realm", "Wgreporter" .. tag .. "b-Realm" })
	return sender, mate, author, third
end

for _, enforced in ipairs({ false, true }) do
	local tag = enforced and "e" or "c"
	test("wanted 1.2.4 guilds: an ordinary member of another Olympus guild, whom no census names, counts on every member's client at once, his death and his kill (the real trust chain on every receiver" .. (enforced and ", the signed leadership manifest enforced" or "") .. ")", function()
		WithGuilds(function(world)
			if enforced then ns.Authority.Enforced = function() return true end end
			local sender, mate, author, third = Scene(world, tag)
			local level, verified = world:As(author, ns.Channels.VerifiedLevel, sender.name, G1)
			eq(level, 1, "a member as the [Olympus] chat takes one"); eq(verified, false, "proven by nothing this client holds")
			-- His death to a Horde player nobody listed or targeted (the recap's rows without flags).
			local killer = "Player-1-0F00" .. (enforced and "A001" or "C001")
			world:Death(sender, "Wgganker" .. tag .. "-Realm", killer)
			for _, cl in ipairs({ sender, mate, author, third }) do
				local t = world:Target(cl, killer)
				assert(t, ns.ShortName(cl.name) .. " has him at once")
				eq(t.current, 60, ns.ShortName(cl.name) .. ": a member's death, his office 0 and his level 60"); eq(t.victims[1].name, sender.name)
			end
			-- His own killing blow on another one (the native PARTY_KILL): his claim on every client.
			world.epoch = world.epoch + 30
			local victim = "Player-1-0F00" .. (enforced and "A002" or "C002")
			assert(world:Kill(sender, "Wgprey" .. tag .. "-Realm", victim))
			for _, cl in ipairs({ sender, mate, author, third }) do
				local t = world:Target(cl, victim)
				assert(t, ns.ShortName(cl.name) .. " has his kill")
				eq(t.claims[1].slayer, sender.name, ns.ShortName(cl.name)); eq(t.claims[1].points, 120, "twice the level-60 Horde player's level")
			end
			-- The author's /oly wanted status: counted, and the guild the row names.
			local line = assert(world:Line(author, "Wgganker" .. tag), "a line about the death")
			assert(line:find(ns.L.WANTED_STATUS_BOUNTY:format(60), 1, true), line)
			assert(line:find(sender.name .. " <" .. G1 .. ">", 1, true), line)
		end)
	end)
end

test("wanted 1.2.4 guilds: the author's client relays such a row once, the relay a 1.2.3 client takes, so a client that has not updated counts it too", function()
	WithGuilds(function(world)
		local sender, _, author, third = Scene(world, "r")
		world:Death(sender, "Wgrelayed-Realm", "Player-1-0F00B001")
		world:Run(15)
		eq(world:Relays(author), 1, "one relay, the reviewer's")
		local relay
		for _, m in ipairs(world.log) do if m.from == author and m.text:find("^WK~R~") then relay = m.text end end
		-- (The relay's wire is the 1.2.3 one: WK~R~2~<scope>~<from>~<bound>~<digest>~..., Share.Parse.)
		assert(relay:find("^WK~R~2~%x+~" .. sender.name:gsub("%-", "%%-") .. "~[01]~%x+~"), relay)
		eq(world:As(third, third.W.Target, nil, "Player-1-0F00B001").current, 60, "once, the relay a replay here")
	end)
end)

test("wanted 1.2.4 guilds: the rules against forged rows stay, each refusal with its own reason in /oly wanted status", function()
	WithGuilds(function(world)
		local sender, mate, author = Scene(world, "f")
		-- A row the sender's own client sent (WK~2): the model of the hand-written ones below.
		world:Death(sender, "Wgmodel-Realm", "Player-1-0F00F000")
		local model
		for _, m in ipairs(world.log) do if m.from == sender and m.text:find("^WK~2~") then model = m.text end end
		assert(model, "his row")
		local forged = 0
		local function Forge(from, guild, name)
			local f = {}
			for part in (model .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
			forged = forged + 1
			-- (WK, 2, scope, guild, digest, at, month, kind, Horde GUID, own GUID, office, level, Horde level, name)
			f[4], f[5], f[9], f[14] = guild, ("%016x"):format(0xf0f000 + forged), ("1.0f00f1%02x"):format(forged), name
			f[10] = "1." .. from.guid:match("%-(%x+)$"):lower()
			return table.concat(f, "~")
		end
		-- A character of no Olympus guild: his own client sends nothing (Share.Send), and a row he
		-- writes by hand is refused, whether it names a guild of no Olympus name or his claim to an
		-- Olympus guild meets that guild's own roster.
		local outsider = world:Client("Wgoutsider-Realm", "Silver Hand Lodge")
		local function Hand(to, text) return select(2, world:As(to, to.handlers.WK, "CHANNEL", outsider.name, text)) end
		eq(Hand(author, Forge(outsider, "Silver Hand Lodge", "Wgnobody-Realm")), "stranger", "no Olympus guild")
		eq(Hand(mate, Forge(outsider, G1, "Wgnobody-Realm")), "stranger", "not in the roster of the guild he names")
		assert(world:Line(author, "Wgnobody"):find(ns.L.WANTED_STATUS_REFUSAL:format("stranger"), 1, true))
		-- One whose own census report spoke for <G3> a moment ago, now naming <G1>: one guild a sender.
		local bound = world:Client("Wgbound-Realm", G1, { roster = G3 })
		world:Census(author, G3, "Wgthreemaster-Realm", {}, { bound.name })
		world:Death(bound, "Wgbinder-Realm", "Player-1-0F00F002")
		eq(world:Target(author, "Player-1-0F00F002"), nil)
		assert(world:Line(author, "Wgbinder"):find(ns.L.WANTED_STATUS_REFUSAL:format("stranger"), 1, true))
		-- One who names the author's own guild, <G2>, and is not in its roster.
		local claimer = world:Client("Wgclaimer-Realm", G2, { roster = false })
		world:Death(claimer, "Wgclaimed-Realm", "Player-1-0F00F003")
		eq(world:Target(author, "Player-1-0F00F003"), nil, "the roster decides for our own guild")
		assert(world:Line(author, "Wgclaimed"):find(ns.L.WANTED_STATUS_REFUSAL:format("stranger"), 1, true))
		-- One the moderators hide.
		local hidden = world:Client("Wghidden-Realm", G1)
		world.hidden[ns.Fold(hidden.name)] = true
		world:Death(hidden, "Wgmuted-Realm", "Player-1-0F00F004")
		eq(world:Target(author, "Player-1-0F00F004"), nil)
		assert(world:Line(author, "Wgmuted"):find(ns.L.WANTED_STATUS_REFUSAL:format("hidden"), 1, true))
		-- A "Horde player" by the name of one of the author's guildmates: an Olympian is never one.
		world:Client("Wgguildmate-Realm", G2)
		world:Death(sender, "Wgguildmate-Realm", "Player-1-0F00F005")
		eq(world:Target(sender, "Player-1-0F00F005") ~= nil, true, "his own client has no such member")
		eq(world:Target(author, "Player-1-0F00F005"), nil)
		assert(world:Line(author, "Wgguildmate"):find(ns.L.WANTED_STATUS_REFUSAL:format("olympian"), 1, true))
		-- Another realm group: never counted here.
		local away = world:Client("Wgaway-Realm", G1, { group = "OtherGroup" })
		world:Death(away, "Wgfaraway-Realm", "Player-1-0F00F006")
		eq(world:Target(author, "Player-1-0F00F006"), nil)
		assert(world:Line(author, "Wgfaraway"):find(ns.L.WANTED_STATUS_REFUSAL:format("scope"), 1, true))
		-- The flood limit: 8 rows a minute from one member (his deaths DEATH_WINDOW apart, each to
		-- another Horde player), the 9th refused.
		world.epoch = world.epoch + 120
		for i = 1, 9 do
			world:Death(sender, ("Wgflood%d-Realm"):format(i), ("Player-1-0F00E%03X"):format(i))
			world.epoch = world.epoch + 3
		end
		eq(world:Target(sender, "Player-1-0F00E009") ~= nil, true, "his own client counts his own")
		eq(world:Target(author, "Player-1-0F00E008") ~= nil, true, "the 8th")
		eq(world:Target(author, "Player-1-0F00E009"), nil, "the 9th")
		assert(world:Line(author, "Wgflood9"):find(ns.L.WANTED_STATUS_REFUSAL:format("rate"), 1, true))
		-- The reasons, each its own, explained in English and pt-BR.
		for _, reason in ipairs({ "hidden", "stranger", "olympian" }) do
			assert(ns.L.WANTED_STATUS_KEY:find(reason .. " = ", 1, true), reason)
		end
		assert(not ns.L.WANTED_STATUS_KEY:find("cannot verify as a member", 1, true), "the old reason's words are gone")
	end)
end)

test("wanted 1.2.4 guilds: a reviewer's relay never overrules what a client proves: a false claim to a guild is refused by that guild's own clients, at once and in the relay", function()
	WithGuilds(function(world)
		local _, _, author, third = Scene(world, "x")
		local council = world:Client("Wgcouncilx-Realm", G3, { role = "council" })
		local plain = world:Client("Wgplainx-Realm", G2)
		-- He names <G2> (the author's guild) and is not in its roster.
		local claimer = world:Client("Wgclaimerx-Realm", G2, { roster = false })
		world:Death(claimer, "Wgfalsex-Realm", "Player-1-0F00D001")
		world:Run(15)
		eq(world:Target(third, "Player-1-0F00D001") ~= nil, true, "a client of another guild cannot tell")
		eq(world:Target(council, "Player-1-0F00D001") ~= nil, true, "nor can the councillor of another guild")
		eq(world:Relays(council), 1, "who relays it")
		eq(world:Target(plain, "Player-1-0F00D001"), nil, "the guild he names refuses him")
		eq(world:Target(author, "Player-1-0F00D001"), nil)
		local line = assert(world:Line(plain, "Wgfalsex"))
		assert(line:find(ns.L.WANTED_STATUS_RELAY, 1, true) and line:find(ns.L.WANTED_STATUS_REFUSAL:format("stranger"), 1, true), line)
	end)
end)
