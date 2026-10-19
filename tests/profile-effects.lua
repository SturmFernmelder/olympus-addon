-- Generic, host-owned profile presentation: consent-side ownership, authenticated leases and
-- the short target-only display. The approved sentence is kept out of readable public fixtures;
-- production callers supply it and the host accepts only its digest.
local base, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]profile%-effects%.lua$")) or "./"
local function Unhex(value)
	return (value:gsub("..", function(byte) return string.char(tonumber(byte, 16)) end))
end
local CAPTION = Unhex("416e204f6c796d7069616e207374616e6473206265666f726520796f752e2059657420746865697220736861646f77207365656d7320746f2066616c6c20696e20746865206f70706f7369746520646972656374696f6e2e")

local function Full(name, realm)
	if type(name) ~= "string" or name == "" or name:find("-", 1, true) then return name end
	return name .. "-" .. (realm or "Realm")
end

local function WithWorld(fn)
	local names = { "GetTime", "GetServerTime", "GetGuildInfo", "CreateFrame", "UIParent", "TargetFrame",
		"UnitExists", "UnitIsPlayer", "SetPortraitTexture", "InCombatLockdown", "C_Map", "issecretvalue" }
	local saved = {}
	for _, name in ipairs(names) do saved[name] = _G[name] end
		local w = { clock = 1000, current = nil, after = {}, frames = {}, created = {}, fonts = {}, textures = {}, portraits = 0 }
	local ok, err = pcall(function()
		GetTime = function() return w.clock end
		GetServerTime = function() return w.clock end
		GetGuildInfo = function() return w.current and w.current.guild or nil end
		UnitExists = function(unit) return unit == "target" and w.current and w.current.target ~= nil or false end
		UnitIsPlayer = function(unit) return unit == "target" and w.current and w.current.target ~= nil or false end
		InCombatLockdown = function() return false end
		issecretvalue = nil

		local function Noop() end
		local function Texture()
			local texture
			texture = { shown = true, SetAtlas = function() return true end, SetPoint = Noop, SetSize = Noop,
				SetVertexColor = function(self, r, g, b, a) self.color = { r, g, b, a } end, SetBlendMode = Noop, SetDesaturated = Noop, SetAllPoints = Noop,
				SetColorTexture = Noop, SetHeight = Noop, AddMaskTexture = Noop,
				SetTexture = function() return true end, SetMask = Noop,
				Hide = function(self) self.shown = false end, Show = function(self) self.shown = true end }
			w.textures[#w.textures + 1] = texture
			return texture
		end
		local function Frame()
			local frame = { shown = true }
			frame.SetAllPoints, frame.SetFrameStrata, frame.EnableMouse, frame.SetSize, frame.SetPoint = Noop, Noop, Noop, Noop, Noop
			frame.CreateTexture = function() return Texture() end
			frame.CreateMaskTexture = function() return Texture() end
			frame.CreateFontString = function()
				local font = { SetPoint = Noop, SetJustifyH = Noop, SetJustifyV = Noop, SetTextColor = Noop,
					GetFont = function() return "Fonts\\FRIZQT__.TTF", 16, "" end,
					SetFont = function(self, path, size) self.size = size end,
					SetText = function(self, value) self.text = value end }
				w.fonts[#w.fonts + 1] = font
				return font
			end
			frame.Hide = function(self) self.shown = false end
			frame.Show = function(self) self.shown = true end
			frame.IsShown = function(self) return self.shown end
			w.frames[#w.frames + 1] = frame
			return frame
		end
		UIParent = Frame()
		TargetFrame = Frame()
		TargetFrame.TargetFrameContainer = Frame()
		TargetFrame.TargetFrameContainer.parent = TargetFrame
		CreateFrame = function(_, _, parent)
			local frame = Frame()
			frame.parent = parent
			w.created[#w.created + 1] = frame
			return frame
		end
		SetPortraitTexture = function(texture, unit) texture.unit = unit; w.portraits = w.portraits + 1 end
		C_Map = {
			GetBestMapForUnit = function(unit)
				w.bestMapUnit = unit
				return unit == "target" and 1453 or nil
			end,
			GetPlayerMapPosition = function(_, unit)
				w.positionUnit = unit
				local point = w.current and w.current.targetCoordinates
				return point and { GetXY = function() return point[1], point[2] end } or nil
			end,
			GetMapInfo = function() return { name = "Stormwind City" } end,
		}

		function w.use(client, call, ...)
			local prior = w.current
			w.current = client
			local packed = { pcall(call, ... ) }
			w.current = prior
			if not packed[1] then error(packed[2], 0) end
			return unpack(packed, 2)
		end

		function w.client(name, issuer)
			local c = { me = Full(name), guild = "Olympus II", target = nil, targetCoordinates = { 0.42, 0.61 },
				jobs = {}, handlers = {}, events = {}, listeners = {}, gateHooks = {}, remote = {}, hidden = {},
				issuers = {}, member = true, selfOff = false, gamepad = false }
			if issuer ~= false then c.issuers[c.me:lower()] = true end
			c.Now = function() return w.clock end
			c.FullName = Full
			c.Fold = function(value) return type(value) == "string" and Full(value):lower() or nil end
			c.UnitFullName = function(unit) return unit == "target" and c.target or nil end
			c.IsFederation = function(guild) return guild == "Olympus II" end
			c.IsMember = function() return c.member == true end
			c.Sign = base.Sign
			c.Data = { ServerTime = function() return w.clock end }
			c.Moderation = {
				SelfOff = function() return c.selfOff and { off = true } or nil end,
				Hides = function(sender) return c.hidden[Full(sender):lower()] and { off = true } or nil end,
				IsIssuer = function(sender) return c.issuers[Full(sender):lower()] == true end,
			}
			c.Workshop = { IsAuthorName = function(who)
				return type(who) == "string" and w.author ~= nil and Full(who):lower() == Full(w.author):lower()
			end }
			c.Channels = { Admit = function(sender, guild, _, _, options)
				if type(options) == "table" and type(options.buckets) == "table"
					and options.buckets[sender] == nil then
					options.buckets[sender] = { tokens = 6, t = w.clock }
				end
				return guild == "Olympus II" and c.remote[Full(sender):lower()] == true
					and type(options) == "table" and options.where == "profile effect"
			end }
			c.Comm = {
				Handle = function(kind, call) c.handlers[kind] = call end,
				Send = function(dist, message, key, _, _, _, options)
					c.jobs[#c.jobs + 1] = { dist = dist, message = message, key = key, options = options }
					return true
				end,
			}
			c.After = function(seconds, _, call) w.after[#w.after + 1] = { at = w.clock + seconds, call = call, client = c } end
			c.tickers = {}
			c.Every = function(_, where, call)
				local handle = { call = call, cancelled = false }
				function handle.Cancel() handle.cancelled = true end
				c.tickers[where] = handle -- (1.2.5.1: a test beats one by its name)
				return handle
			end
			-- (1.2.5.1: the quiet presence, Core.lua's answer for this client: c.quiet.)
			c.QuietPresence = function() return c.quiet == true end
			c.RegisterEvent = function(event, call) c.events[event] = call end
			c.On = function(event, call) c.listeners[event] = call end
			c.Fire = function(event, ...)
				if c.listeners[event] then return c.listeners[event](...) end
			end
			c.GamepadUI = function() return c.gamepad end
			c.Gate = {
				Allowed = function(id) return id == "borders" and not c.gamepad end,
				Hooks = function(id, hooks) c.gateHooks[id] = hooks end,
			}
			assert(loadfile(ROOT .. "Olympus/ProfileEffects.lua"))("Olympus", c)
			return c
		end

		function w.trust(receiver, sender, issuer)
			local key = sender.me:lower()
			receiver.remote[key] = true
			if issuer ~= false then receiver.issuers[key] = true end
		end

		function w.deliver(from, to, index)
			local job = table.remove(from.jobs, index or 1)
			assert(job, "no queued profile-effect word")
			if job.options and job.options.guard then
				local allowed = w.use(from, job.options.guard)
				if not allowed then return false, "guard" end
			end
			return w.use(to, to.handlers.FX, job.dist, from.me, job.message)
		end

		function w.openFor(issuer, clients)
			assert(w.use(issuer, issuer.ProfileEffects.OpenSession, "session-owner", "shadow"))
			local job = table.remove(issuer.jobs, 1)
			assert(job and job.message:match("^FX~2~G~s~"), job and job.message or "no grant word")
			if job.options and job.options.guard then assert(w.use(issuer, job.options.guard)) end
			for _, client in ipairs(clients or {}) do
				w.trust(client, issuer, true)
				assert(w.use(client, client.handlers.FX, job.dist, issuer.me, job.message))
			end
			return job.message
		end

		function w.closeFor(issuer, clients)
			assert(w.use(issuer, issuer.ProfileEffects.CloseSession, "session-owner"))
			local job = table.remove(issuer.jobs, 1)
			assert(job and job.message:match("^FX~2~C~s~"), job and job.message or "no close word")
			if job.options and job.options.guard then assert(w.use(issuer, job.options.guard)) end
			for _, client in ipairs(clients or {}) do
				assert(w.use(client, client.handlers.FX, job.dist, issuer.me, job.message))
			end
			return job.message
		end

		function w.advance(seconds)
			w.clock = w.clock + seconds
			local pending = w.after
			w.after = {}
			for _, timer in ipairs(pending) do
				if timer.at <= w.clock then w.use(timer.client, timer.call) else w.after[#w.after + 1] = timer end
			end
		end

		fn(w)
	end)
	for _, name in ipairs(names) do _G[name] = saved[name] end
	if not ok then error(err, 0) end
end

test("profile effects: only an issuer opens the bounded session and its surface accepts one host-owned presentation", function()
	WithWorld(function(w)
		local ordinary = w.client("Ordinary", false)
		local ok, why = w.use(ordinary, ordinary.ProfileEffects.OpenSession, "owner", "shadow")
		eq(ok, false)
		eq(why, "authority")
		ok, why = w.use(ordinary, ordinary.ProfileEffects.Set, "owner", "shadow", true, CAPTION)
		eq(ok, false)
		eq(why, "session")

		local issuer = w.client("Council")
		eq(w.use(issuer, issuer.ProfileEffects.OpenSession, "session-owner", "other"), false)
		assert(w.use(issuer, issuer.ProfileEffects.OpenSession, "session-owner", "shadow"))
		assert(issuer.jobs[1].message:match("^FX~2~G~s~"), issuer.jobs[1].message)
		assert(w.use(issuer, issuer.ProfileEffects.Session).style == "shadow")
		eq(w.use(issuer, issuer.ProfileEffects.Set, "effect-owner", "other", true, CAPTION), false)
		eq(w.use(issuer, issuer.ProfileEffects.Set, "effect-owner", "shadow", true, "arbitrary remote text"), false)
		assert(w.use(issuer, issuer.ProfileEffects.Set, "effect-owner", "shadow", true, CAPTION))
		assert(issuer.jobs[2].message:match("^FX~2~S~s~"), issuer.jobs[2].message)
		eq(w.use(issuer, issuer.ProfileEffects.Set, "another-owner", "shadow", true, CAPTION), false)
		assert(w.use(issuer, issuer.ProfileEffects.Set, "effect-owner", "shadow", false))
		assert(issuer.jobs[3].message:match("^FX~2~X~s~"), issuer.jobs[3].message)
		assert(w.use(issuer, issuer.ProfileEffects.CloseSession, "session-owner"))
		assert(issuer.jobs[4].message:match("^FX~2~C~s~"), issuer.jobs[4].message)
		eq(w.use(issuer, issuer.ProfileEffects.Session), nil)
	end)
end)

test("profile effects: the addon's author opens a session like an issuer, without moderation power", function()
	WithWorld(function(w)
		w.author = "Author"
		local author = w.client("Author", false)
		local receiver = w.client("Observer", false)
		eq(w.use(author, author.Moderation.IsIssuer, author.me), false, "the author is not a moderation issuer")
		assert(w.use(author, author.ProfileEffects.OpenSession, "owner", "shadow"))
		local grantWord = author.jobs[1].message
		w.trust(receiver, author, false)
		assert(w.use(receiver, receiver.handlers.FX, "CHANNEL", author.me, grantWord), "receivers accept the author's grant")
		assert(w.use(author, author.ProfileEffects.Set, "owner", "shadow", true, CAPTION))
		assert(w.deliver(author, receiver, 2))
		local active = w.use(receiver, receiver.ProfileEffects.Active, author.me)
		assert(active and active.style == "shadow")
		assert(w.use(author, author.ProfileEffects.Set, "owner", "shadow", false))
		assert(w.use(author, author.ProfileEffects.CloseSession, "owner"))
		author.hidden[author.me:lower()] = true
		eq(w.use(author, author.ProfileEffects.OpenSession, "owner", "shadow"), false, "a hidden author is refused")
	end)
end)

test("profile effects: one authenticated grant lets an admitted ordinary member present only themself", function()
	WithWorld(function(w)
		local issuer = w.client("Council")
		local sender, receiver = w.client("UnitMember", false), w.client("Observer", false)
		local grantWord = w.openFor(issuer, { sender, receiver })
		assert(w.use(sender, sender.ProfileEffects.Session))
		w.trust(receiver, sender, false)
		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION))
		local first = sender.jobs[1].message
		assert(w.deliver(sender, receiver))
		local active = w.use(receiver, receiver.ProfileEffects.Active, sender.me)
		assert(active and active.style == "shadow")
		eq(w.use(receiver, receiver.handlers.FX, "CHANNEL", sender.me, first), false, "the same word cannot replay")

		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", false))
		assert(w.deliver(sender, receiver))
		eq(w.use(receiver, receiver.ProfileEffects.Active, sender.me), nil)

		local stranger = w.client("Stranger", false)
		w.trust(stranger, issuer, true)
		assert(w.use(stranger, stranger.handlers.FX, "CHANNEL", issuer.me, grantWord))
		-- The real grant is installed explicitly, but the receiver has no admission for this sender.
		assert(w.use(stranger, stranger.ProfileEffects.Set, "two", "shadow", true, CAPTION))
		eq(w.deliver(stranger, receiver), false, "a grant does not replace member admission")

		-- Re-stamping a valid grant as an ordinary member cannot create a session.
		w.trust(receiver, stranger, false)
		eq(w.use(receiver, receiver.handlers.FX, "CHANNEL", stranger.me, grantWord), false)
	end)
end)

test("profile effects: an authenticated close or grant expiry removes member effects everywhere", function()
	WithWorld(function(w)
		local issuer = w.client("Council")
		local sender, receiver = w.client("UnitMember", false), w.client("Observer", false)
		w.openFor(issuer, { sender, receiver })
		w.trust(receiver, sender, false)
		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION))
		assert(w.deliver(sender, receiver))
		assert(w.use(receiver, receiver.ProfileEffects.Active, sender.me))
		w.closeFor(issuer, { sender, receiver })
		eq(w.use(sender, sender.ProfileEffects.Outgoing), nil)
		eq(w.use(receiver, receiver.ProfileEffects.Session), nil)
		eq(w.use(receiver, receiver.ProfileEffects.Active, sender.me), nil)

		local issuer2 = w.client("CouncilTwo")
		w.openFor(issuer2, { sender, receiver })
		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION))
		assert(w.deliver(sender, receiver))
		w.advance(sender.ProfileEffects.SESSION_TTL + 0.1)
		eq(w.use(sender, sender.ProfileEffects.Session), nil)
		eq(w.use(sender, sender.ProfileEffects.Outgoing), nil)
		eq(w.use(receiver, receiver.ProfileEffects.Active, sender.me), nil)
	end)
end)

test("profile effects: targeting shows the short non-chat presentation and screenshot start hides it", function()
	WithWorld(function(w)
		local issuer = w.client("Council")
		local sender, receiver = w.client("UnitMember", false), w.client("Observer", false)
		w.openFor(issuer, { sender, receiver })
		w.trust(receiver, sender, false)
		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION))
		assert(w.deliver(sender, receiver))
		receiver.target = sender.me
		assert(w.use(receiver, receiver.ProfileEffects.Refresh))
		eq(w.use(receiver, receiver.ProfileEffects.Visible), true)
		eq(w.bestMapUnit, "target")
		eq(w.positionUnit, "target")
		eq(w.fonts[#w.fonts].text, "Stormwind City  |  42.0, 61.0")
		eq(w.created[1].parent, TargetFrame.TargetFrameContainer, "the portrait overlay follows TargetFrame")
		eq(w.created[2].parent, TargetFrame.TargetFrameContainer, "the message follows TargetFrame")
		w.use(receiver, receiver.ProfileEffects._ScreenshotStart)
		eq(w.use(receiver, receiver.ProfileEffects.Visible), false)
		w.use(receiver, receiver.ProfileEffects._ScreenshotEnd)
		w.advance(0.1)
		eq(w.use(receiver, receiver.ProfileEffects.Visible), true, "restored only after a timely client event")
		w.advance(receiver.ProfileEffects.DISPLAY_FOR)
		eq(w.use(receiver, receiver.ProfileEffects.Visible), false, "the presentation never persists")
	end)
end)

test("profile effects: the tuned look is a black winged frame with a violet glow and no portrait shade", function()
	WithWorld(function(w)
		local issuer = w.client("Council")
		local sender, receiver = w.client("UnitMember", false), w.client("Observer", false)
		w.openFor(issuer, { sender, receiver })
		w.trust(receiver, sender, false)
		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION))
		assert(w.deliver(sender, receiver))
		receiver.target = sender.me
		assert(w.use(receiver, receiver.ProfileEffects.Refresh))
		eq(w.use(receiver, receiver.ProfileEffects.Visible), true)
		local colors = {}
		for _, texture in ipairs(w.textures) do
			if texture.color then colors[#colors + 1] = table.concat(texture.color, ",") end
		end
		eq(table.concat(colors, " "), "0,0,0,1 0.19,0.2,0.69,1", "only the dark and light layers are tinted")
		local sizes = {}
		for _, font in ipairs(w.fonts) do sizes[#sizes + 1] = tostring(font.size) end
		eq(sizes[1], "19", "the caption is drawn at the tuned size")
		eq(w.portraits, 0, "the target's portrait is not copied")
	end)
end)

test("profile effects: an unavailable target position is omitted instead of showing the player's position", function()
	WithWorld(function(w)
		local issuer = w.client("Council")
		local sender, receiver = w.client("UnitMember", false), w.client("Observer", false)
		w.openFor(issuer, { sender, receiver })
		w.trust(receiver, sender, false)
		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION))
		assert(w.deliver(sender, receiver))
		receiver.target = sender.me
		receiver.targetCoordinates = nil
		assert(w.use(receiver, receiver.ProfileEffects.Refresh))
		eq(w.bestMapUnit, "target")
		eq(w.positionUnit, "target")
		eq(w.fonts[#w.fonts].text, "")
	end)
end)

test("profile effects: moderation and membership fail closed on both ends", function()
	WithWorld(function(w)
		local issuer = w.client("Council")
		local sender, receiver = w.client("UnitMember", false), w.client("Observer", false)
		w.openFor(issuer, { sender, receiver })
		sender.selfOff = true
		eq(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION), false)
		sender.selfOff = false
		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION))
		w.trust(receiver, sender, false)
		receiver.hidden[sender.me:lower()] = true
		local word = sender.jobs[1].message
		eq(w.deliver(sender, receiver), false)
		receiver.hidden[sender.me:lower()] = nil
		receiver.member = false
		eq(w.use(receiver, receiver.handlers.FX, "CHANNEL", sender.me, word), false)
	end)
end)

test("profile effects: membership loss and the local hold immediately clear sessions, leases and UI", function()
	WithWorld(function(w)
		local issuer = w.client("Council")
		local sender, receiver = w.client("UnitMember", false), w.client("Observer", false)
		w.openFor(issuer, { sender, receiver })
		w.trust(receiver, sender, false)
		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION))
		assert(w.deliver(sender, receiver))
		receiver.target = sender.me
		assert(w.use(receiver, receiver.ProfileEffects.Refresh))
		receiver.member = false
		w.use(receiver, receiver.events.PLAYER_GUILD_UPDATE, "player")
		eq(w.use(receiver, receiver.ProfileEffects.Visible), false)
		eq(w.use(receiver, receiver.ProfileEffects.Active, sender.me), nil)
		local empty = w.use(receiver, receiver.ProfileEffects.Stats)
		eq(empty.active, 0)
		eq(empty.sessions, 0)
		eq(empty.order, 0)
		eq(empty.senders, 0)

		local issuer2 = w.client("CouncilTwo")
		receiver.member = true
		w.openFor(issuer2, { receiver })
		receiver.selfOff = true
		w.use(receiver, receiver.listeners.NETOFF_CHANGED)
		eq(w.use(receiver, receiver.ProfileEffects.Session), nil)
		empty = w.use(receiver, receiver.ProfileEffects.Stats)
		eq(empty.sessions, 0)
		eq(empty.sessionOrder, 0)
	end)
end)

test("profile effects: revoking the session issuer clears ordinary members' accepted leases", function()
	WithWorld(function(w)
		local issuer = w.client("Council")
		local sender, receiver = w.client("UnitMember", false), w.client("Observer", false)
		w.openFor(issuer, { sender, receiver })
		w.trust(receiver, sender, false)
		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION))
		assert(w.deliver(sender, receiver))
		receiver.target = sender.me
		assert(w.use(receiver, receiver.ProfileEffects.Refresh))
		receiver.issuers[issuer.me:lower()] = nil
		w.use(receiver, receiver.listeners.DATA_CHANGED)
		eq(w.use(receiver, receiver.ProfileEffects.Visible), false)
		eq(w.use(receiver, receiver.ProfileEffects.Active, sender.me), nil)
		eq(w.use(receiver, receiver.ProfileEffects.Stats).sessions, 0)
	end)
end)

test("profile effects: gamepad parking and the live gate prevent cached or screenshot restoration", function()
	WithWorld(function(w)
		local issuer = w.client("Council")
		local sender, receiver = w.client("UnitMember", false), w.client("Observer", false)
		w.openFor(issuer, { sender, receiver })
		w.trust(receiver, sender, false)
		assert(w.use(sender, sender.ProfileEffects.Set, "one", "shadow", true, CAPTION))
		assert(w.deliver(sender, receiver))
		receiver.target = sender.me
		assert(w.use(receiver, receiver.ProfileEffects.Refresh))
		receiver.gamepad = true
		eq(w.use(receiver, receiver.ProfileEffects.Refresh), false, "the gate precedes the cached target shortcut")
		eq(w.use(receiver, receiver.ProfileEffects.Visible), false)
		w.use(receiver, receiver.gateHooks.borders.park)
		w.use(receiver, receiver.ProfileEffects._ScreenshotEnd)
		w.advance(0.1)
		eq(w.use(receiver, receiver.ProfileEffects.Visible), false)

		receiver.gamepad = false
		w.use(receiver, receiver.gateHooks.borders.install)
		eq(w.use(receiver, receiver.ProfileEffects.Visible), true)
		w.use(receiver, receiver.ProfileEffects._ScreenshotStart)
		receiver.gamepad = true
		w.use(receiver, receiver.ProfileEffects._ScreenshotEnd)
		w.advance(0.1)
		eq(w.use(receiver, receiver.ProfileEffects.Visible), false, "screenshot completion cannot bypass the live gate")
	end)
end)

test("profile effects: admitted member churn cannot grow effect replay or rate registries without bound", function()
	WithWorld(function(w)
		local issuer, receiver = w.client("Council"), w.client("Observer", false)
		local grantWord = w.openFor(issuer, { receiver })
		local initialSenders = w.use(receiver, receiver.ProfileEffects.Stats).senders
		local accepted = 0
		for i = 1, receiver.ProfileEffects.RATE_SENDERS + 20 do
			local sender = w.client("Member" .. i, false)
			w.trust(sender, issuer, true)
			assert(w.use(sender, sender.handlers.FX, "CHANNEL", issuer.me, grantWord))
			w.trust(receiver, sender, false)
			assert(w.use(sender, sender.ProfileEffects.Set, "owner", "shadow", true, CAPTION))
			if w.deliver(sender, receiver) == true then
				accepted = accepted + 1
				assert(w.use(sender, sender.ProfileEffects.Set, "owner", "shadow", false))
				assert(w.deliver(sender, receiver))
			end
		end
		local stats = w.use(receiver, receiver.ProfileEffects.Stats)
		eq(accepted, receiver.ProfileEffects.RATE_SENDERS - initialSenders)
		assert(stats.order <= receiver.ProfileEffects.ORDER_MAX, tostring(stats.order))
		assert(stats.senders <= receiver.ProfileEffects.RATE_SENDERS, tostring(stats.senders))
		eq(stats.active, 0)
	end)
end)

test("profile effects: issuer session churn is replay checked and both grant registries stay bounded", function()
	WithWorld(function(w)
		local receiver = w.client("Observer", false)
		local firstWord, firstIssuer
		for i = 1, receiver.ProfileEffects.SESSION_ORDER_MAX + 8 do
			local issuer = w.client("Council" .. i)
			w.trust(receiver, issuer, true)
			assert(w.use(issuer, issuer.ProfileEffects.OpenSession, "owner", "shadow"))
			local job = table.remove(issuer.jobs, 1)
			assert(w.use(receiver, receiver.handlers.FX, "CHANNEL", issuer.me, job.message))
			if i == 1 then firstWord, firstIssuer = job.message, issuer end
		end
		local stats = w.use(receiver, receiver.ProfileEffects.Stats)
		assert(stats.sessions <= receiver.ProfileEffects.MAX_SESSIONS, tostring(stats.sessions))
		assert(stats.sessionOrder <= receiver.ProfileEffects.SESSION_ORDER_MAX, tostring(stats.sessionOrder))
		-- If the first issuer's replay state was retained it is refused; if bounded eviction made room,
		-- accepting it still cannot exceed either cap.
		w.use(receiver, receiver.handlers.FX, "CHANNEL", firstIssuer.me, firstWord)
		stats = w.use(receiver, receiver.ProfileEffects.Stats)
		assert(stats.sessions <= receiver.ProfileEffects.MAX_SESSIONS, tostring(stats.sessions))
		assert(stats.sessionOrder <= receiver.ProfileEffects.SESSION_ORDER_MAX, tostring(stats.sessionOrder))
	end)
end)

-- 1.2.5.1, review of the quiet presence (Core.lua): each heartbeat (a member's presentation, an
-- issuer's session) says its sender is online every 10 seconds, and the issuers are the very people
-- who may turn it on.
test("profile effects: while the quiet presence is on, no heartbeat, stop or close leaves; nothing new starts (\"quiet\"); the others drop the leases; once off they beat again", function()
	WithWorld(function(w)
		local issuer = w.client("Council")
		local receiver = w.client("Observer", false)
		w.openFor(issuer, { receiver })
		w.trust(receiver, issuer, true)
		assert(w.use(issuer, issuer.ProfileEffects.Set, "effect-owner", "shadow", true, CAPTION))
		assert(w.deliver(issuer, receiver))
		assert(w.use(receiver, receiver.ProfileEffects.Active, issuer.me), "shown, before")
		eq(#issuer.jobs, 0)
		issuer.quiet = true
		for _ = 1, 4 do
			w.advance(issuer.ProfileEffects.HEARTBEAT)
			w.use(issuer, issuer.tickers["profile effect session"].call)
			w.use(issuer, issuer.tickers["profile effect"].call)
		end
		eq(#issuer.jobs, 0, "no heartbeat while it is on: " .. tostring(issuer.jobs[1] and issuer.jobs[1].message))
		assert(w.use(issuer, issuer.ProfileEffects.Session), "his own session is kept here")
		eq(w.use(receiver, receiver.ProfileEffects.Active, issuer.me), nil, "the others drop it, as after a logout")
		eq(w.use(receiver, receiver.ProfileEffects.Session), nil)
		-- Nothing new: another session or presentation waits until it is off.
		local other = w.client("CouncilTwo")
		other.quiet = true
		local ok, why = w.use(other, other.ProfileEffects.OpenSession, "owner", "shadow")
		eq(ok, false); eq(why, "quiet"); eq(#other.jobs, 0)
		assert(w.use(issuer, issuer.ProfileEffects.Set, "effect-owner", "shadow", true, CAPTION), "the live one: still on, nothing to do")
		-- Off: both beat again, and the others take them.
		issuer.quiet = false
		w.advance(issuer.ProfileEffects.HEARTBEAT)
		w.use(issuer, issuer.tickers["profile effect session"].call)
		w.use(issuer, issuer.tickers["profile effect"].call)
		eq(#issuer.jobs, 2, "the session and the presentation beat again")
		assert(issuer.jobs[1].message:match("^FX~2~G~s~"), issuer.jobs[1].message)
		assert(w.deliver(issuer, receiver))
		assert(w.deliver(issuer, receiver))
		assert(w.use(receiver, receiver.ProfileEffects.Active, issuer.me), "shown again")
		-- Quiet again: a stop and a close end it here at once; their words are handed to Comm, which
		-- keeps every FX~ home while it is on (Comm.QUIET_WORDS, the transport's own test).
		issuer.quiet = true
		assert(w.use(issuer, issuer.ProfileEffects.Set, "effect-owner", "shadow", false))
		assert(w.use(issuer, issuer.ProfileEffects.CloseSession, "session-owner"))
		eq(#issuer.jobs, 2)
		assert(issuer.jobs[1].message:match("^FX~2~X~") and issuer.jobs[2].message:match("^FX~2~C~"), issuer.jobs[1].message)
		eq(w.use(issuer, issuer.ProfileEffects.Session), nil)
		eq(w.use(issuer, issuer.ProfileEffects.Outgoing), nil)
	end)
end)
