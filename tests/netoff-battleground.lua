-- A moderator's net-off inside a battleground (Moderation.lua; the Watch's Ban asks its name the
-- same way). Loaded from the net-off block of tests/run.lua with that block's scene (WithNetoff:
-- the Throne's, a council of one, Test Councillor), so these tests drive the real Moderation.lua,
-- its store and its dialogs, and the real Watch.lua's who dialog.
--
-- What the game does there (Forever's API documentation, as the addon's other guards read it:
-- PlayerMenu.lua, ArenaFights.lua, HopSightings.lua): in a PvP match the game may hide who a unit
-- is from addons. Whether the target is a player, its name and its guild come as secret values,
-- and a secret stops the addon's code with an error on any test or comparison of it.
-- Mock fidelity: a real secret has the type of what it hides ("string" for a name), which no
-- stand-in can have; this one is a table that errors on everything else (indexing, comparing,
-- joining, its length, tostring). A truth test can't be made to fail in Lua, so the hidden
-- "is it a player?" is also tried beside a name the game shows: a hidden answer is never taken
-- for a yes.
local ns, test, eq, H = ...
local M = ns.Moderation
local L = ns.L

local function Boom() error("a secret value was used", 2) end
local SECRET = setmetatable({}, { __index = Boom, __newindex = Boom, __tostring = Boom, __concat = Boom, __lt = Boom, __le = Boom,
	__eq = Boom, __len = Boom, __call = Boom })

-- The player's target as the game gives it now. o.hidden: inside a battleground, the game hides who
-- it is (every answer a secret; o.name: but its name, which the game shows). Else a plain player of
-- <Olympus II>, out in the world.
local function WithTarget(o, fn)
	local saved = { player = UnitIsPlayer, full = UnitFullName, unitName = GetUnitName, guild = GetGuildInfo,
		secret = issecretvalue, inst = IsInInstance }
	local own = GetGuildInfo
	local ok, err = pcall(function()
		issecretvalue = function(v) return rawequal(v, SECRET) end
		IsInInstance = function() if o.hidden then return true, "pvp" end return false, "none" end
		UnitIsPlayer = function(unit)
			if unit ~= "target" then return saved.player and saved.player(unit) end
			if o.hidden then return SECRET end
			return true
		end
		UnitFullName = function(unit)
			if unit ~= "target" then return saved.full(unit) end
			if o.hidden and not o.name then return SECRET, SECRET end
			return o.name or "Spammer Guy", "Realm"
		end
		GetUnitName = function(unit, withRealm)
			if unit ~= "target" then return saved.unitName and saved.unitName(unit, withRealm) end
			if o.hidden and not o.name then return SECRET end
			return o.name or "Spammer Guy"
		end
		GetGuildInfo = function(unit)
			if unit ~= "target" then return own(unit) end
			if o.hidden then return SECRET, SECRET, SECRET end
			return "Olympus II", "Member", 3
		end
		fn()
	end)
	UnitIsPlayer, UnitFullName, GetUnitName, GetGuildInfo, issecretvalue, IsInInstance = saved.player, saved.full, saved.unitName,
		saved.guild, saved.secret, saved.inst
	if not ok then error(err, 0) end
end

-- One of the game's popups as Blizzard_StaticPopup shows it (its edit box, its OnShow, its first
-- button's OnAccept), for a question the addon asked with mouse and keyboard (w.popups: WithThrone's
-- StaticPopup_Show).
local function Popup(w, which)
	local asked = w.popups[#w.popups]
	assert(asked and asked.name == which, "the game's popup " .. which .. ", got " .. tostring(asked and asked.name))
	local def = assert(StaticPopupDialogs[which], which)
	local box = { text = "" }
	function box:SetText(t) self.text = t end
	function box:GetText() return self.text end
	function box:SetFocus() self.focused = true end
	local popup = { which = which, data = asked.data, editBox = box }
	function popup:Hide() self.hidden = true end
	if def.OnShow then def.OnShow(popup, asked.data) end
	return {
		text = box.text,
		Answer = function(text)
			box:SetText(text)
			def.OnAccept(popup, asked.data)
		end,
	}
end

local function Click(label)
	for _, l in ipairs(M.Lines()) do
		if tostring(l.text):find(label, 1, true) and l.onClick then return l.onClick() end
	end
	error("no line " .. label)
end

-- The Watch's Ban (Watch.lua, loaded as the game loads it after UI.lua): its who box as it opens.
local function WatchWho(w)
	local _, uns = H.LoadUI()
	local _, letWatchGo = H.LoadWatch(uns)
	local ok, text = pcall(function()
		ns.ShowDialog("OLYMPUS_WATCH_WHO", L.WATCH_BAN_BTN, nil, { kind = "ban" })
		return Popup(w, "OLYMPUS_WATCH_WHO").text
	end)
	letWatchGo()
	if not ok then error(text, 0) end
	return text
end

local function Printed(w, text)
	for _, p in ipairs(w.printed) do if p:find(text, 1, true) then return true end end
	return false
end

test("1.2.6 net-off in a battleground: while the game hides who the target is, the moderator's questions never test it (each box starts empty, an empty answer asks for the name); the name he types is taken off", function()
	H.WithUI(function()
		H.WithNetoff(function(w)
			H.AsSoldier("Test Councillor")
			WithTarget({ hidden = true }, function()
				-- A character: "Hide a character", who (nothing filled in), an empty answer asks again.
				Click(L.NETOFF_ADD)
				local who = Popup(w, "OLYMPUS_NETOFF_WHO")
				eq(who.text, "", "no name filled in from a hidden target")
				who.Answer("")
				assert(Printed(w, L.NETOFF_WHO_BAD), "asked for a name")
				eq(w.popups[#w.popups].name, "OLYMPUS_NETOFF_WHO", "no next question without a name")
				-- The name typed: why, then the word, logged on the channel.
				Click(L.NETOFF_ADD)
				Popup(w, "OLYMPUS_NETOFF_WHO").Answer("Spammer Guy")
				Popup(w, "OLYMPUS_NETOFF_WHY").Answer("flooding /ol")
				local e = M.Hidden("Spammer Guy-Realm")
				assert(e, "the word, given")
				eq(e.reason, "flooding /ol"); eq(e.by, H.HC)
				local sent = w.sent[#w.sent]
				assert(sent and sent.msg:find("^O1~c~1~%d+~Spammer Guy%-Realm~Test Councillor%-Realm~flooding /ol$"), sent and sent.msg)
				eq(sent.logged, true)
				-- A guild: "Take a guild off" and the exile's notice, nothing filled in, an empty answer asks.
				Click(L.NETOFF_ADD_GUILD)
				local guild = Popup(w, "OLYMPUS_NETOFF_GUILD")
				eq(guild.text, "", "no guild filled in from a hidden target")
				local before = #w.printed
				guild.Answer("")
				eq(w.printed[before + 1], L.NETOFF_GUILD_BAD)
				M.AskExile()
				local exile = Popup(w, "OLYMPUS_EXILE_GUILD")
				eq(exile.text, "")
				before = #w.printed
				exile.Answer("")
				eq(w.printed[before + 1], L.NETOFF_GUILD_BAD)
				-- /oly netoff with no name takes the target: none there, so it asks for one.
				before = #w.printed
				M.Slash(true, ": spam")
				eq(w.printed[before + 1], L.NETOFF_WHO_BAD)
				M.Slash(true, "guild : spam")
				eq(w.printed[before + 2], L.NETOFF_GUILD_BAD)
				eq(M.Guild("Olympus II"), nil, "no guild taken off")
				-- The Watch's Ban asks the name the same way: its box starts empty too.
				eq(WatchWho(w), "", "the Ban's who: nothing filled in")
			end)
			-- The game shows the name but hides whether the unit is a player: a hidden answer is no yes.
			WithTarget({ hidden = true, name = "Spammer Guy" }, function()
				eq(M.CharName("", true), nil)
				Click(L.NETOFF_ADD)
				eq(Popup(w, "OLYMPUS_NETOFF_WHO").text, "")
				eq(WatchWho(w), "", "the Ban's who")
			end)
		end)
	end)
end)

test("1.2.6 net-off out in the world: the target still fills each box in, and an empty answer still takes him", function()
	H.WithUI(function()
		H.WithNetoff(function(w)
			H.AsSoldier("Test Councillor")
			WithTarget({}, function()
				Click(L.NETOFF_ADD)
				eq(Popup(w, "OLYMPUS_NETOFF_WHO").text, ns.DisplayName("Spammer Guy-Realm"))
				Click(L.NETOFF_ADD_GUILD)
				eq(Popup(w, "OLYMPUS_NETOFF_GUILD").text, "Olympus II")
				M.AskExile()
				eq(Popup(w, "OLYMPUS_EXILE_GUILD").text, "Olympus II")
				-- An empty answer: the target, then why.
				Click(L.NETOFF_ADD)
				Popup(w, "OLYMPUS_NETOFF_WHO").Answer("")
				eq(w.popups[#w.popups].data.name, "Spammer Guy-Realm")
				Popup(w, "OLYMPUS_NETOFF_WHY").Answer("spam")
				assert(M.Hidden("Spammer Guy-Realm"), "the target, taken off")
				eq(WatchWho(w), ns.DisplayName("Spammer Guy-Realm"), "the Ban's who: the target")
			end)
		end)
	end)
end)
