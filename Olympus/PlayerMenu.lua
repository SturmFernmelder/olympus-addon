local ADDON, ns = ...
local L = ns.L

-- Olympus's lines in the game's right-click menus for a player (1.1.2): the target frame, party
-- and raid frames, a name in chat, the Who list, the friends list, a community roster and the chat
-- channel roster (1.2.1: not the game's guild roster, below). One place for every feature that adds a line there: Versions.lua (the player's
-- Olympus version, Ask to update, Check version, Tell them about Olympus), Workshop.lua (the
-- author's Ask for a bug report) and (1.1.6) Watch.lua (Report to Olympus: to this guild's
-- officers). Any later addition uses PlayerMenu.Add too, with no feature hooking a menu of its own.
--
-- How, and what it never does:
-- - Blizzard's own way for addons (Blizzard_Menu, 11.0's menus: Forever and the Classic clients
--   that have them): Menu.ModifyMenu("MENU_UNIT_" .. which, fn) for each menu below. The game
--   calls fn after it built its own lines, each call inside securecallfunction, so ours are added
--   after Blizzard's and never taint them (Blizzard's guide, 11_0_0_MenuImplementationGuide.lua).
--   No Blizzard function is replaced or hooked. A client without Menu.ModifyMenu gets no lines
--   (the person card and the Olympus window still show the version): the old dropdown menus
--   (UIDropDownMenu) taint the menu's other lines when an addon adds to them.
-- - Opening a menu sends nothing: the lines read what this client already knows. A click does
--   what its line says (Versions.lua, Workshop.lua): nothing opens the game's chat box
--   (ChatFrame_SendTell and its friends write the chat's globals and taint what the player types
--   next, see ChatWindow.lua), and no game popup opens with the gamepad UI (Olympus's own windows).
-- - Only a player who can be reached: never ourselves, an enemy (ENEMY_PLAYER is not hooked), an
--   offline name (FRIEND_OFFLINE, GUILD_OFFLINE and an offline guild roster row), a Battle.net
--   friend (BN_*: an account, not a character) or a unit that is not a player.
-- - Nothing from a value the game hides from addons (a secret value: the guild roster's member
--   info in a dungeon or raid, C_Club.GetMemberInfo; a unit's name or identity where it is
--   restricted): tested, a secret stops the addon's code with an error, so such a menu gets no
--   Olympus lines. In a dungeon, a raid or a match (ns.ChatLocked) the lines that would send show
--   greyed and say why: target.locked.

local PlayerMenu = {}
ns.PlayerMenu = PlayerMenu

-- The menus hooked ("MENU_UNIT_" .. each). RAID: the raid roster; FRIEND: a name in chat, the Who
-- list and the friends list; COMMUNITIES_WOW_MEMBER: Forever's community rosters; CHAT_ROSTER: a
-- chat channel's member list; RECENT_ALLY: Forever's recent allies.
-- 1.2.1 (a guild officer, with mouse and keyboard: an addon failure "usually when try kick, this time
-- when try change Rank... it hasnt happened every time"): never the game's guild roster menus,
-- COMMUNITIES_GUILD_MEMBER (Forever's Guild & Communities roster) and GUILD (the old Guild window's).
-- Those hold the game's own guild actions (promote, demote, rank, Remove from Guild), whose calls
-- the game refuses from tainted code; a line of ours there is built by Olympus's code into that same
-- menu (for an online member only, never an offline one: a failure that would come and go). With
-- none, nothing of Olympus is in the menu the officer acts from. Olympus's lines for a guildmate stay
-- in every other menu (a name in chat, the target and party frames, the Who list) and on the
-- Olympus window's own rows.
PlayerMenu.WHICH = { "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "COMMUNITIES_WOW_MEMBER", "CHAT_ROSTER", "RECENT_ALLY" }
-- (Never hooked: the game's guild roster menus, above.)
PlayerMenu.NEVER = { COMMUNITIES_GUILD_MEMBER = true, GUILD = true }

local entries = {}   -- { key, order, build }, in order
local hooked = false -- Menu.ModifyMenu called for every menu above

-- A feature's lines: build(target, menu) adds them to `menu` (below) for `target` = { name (the
-- whole "Name-Realm" as the server writes it), which (the menu), unit (when it came from a unit
-- frame), locked (the game holds addon messages now: a line that sends is shown greyed) }.
-- `order`: lower first (Versions.lua 10, the Watch's report 30, the author's lines 50, later additions after them). The same key again
-- replaces its entry (a file loaded twice); no build takes it off.
-- opts.olympus (1.2.5.1): Olympus's own lines (Report to Olympus, the Arena's, the Church's), only
-- for a player this client knows to be in Olympus (PlayerMenu.KnownOlympus); the others (the
-- version, Tell them about Olympus: recruiting) for anyone.
function PlayerMenu.Add(key, build, order, opts)
	if type(key) ~= "string" then return false end
	for i = #entries, 1, -1 do
		if entries[i].key == key then table.remove(entries, i) end
	end
	if type(build) ~= "function" then return false end
	entries[#entries + 1] = { key = key, order = tonumber(order) or 100, build = build,
		olympus = type(opts) == "table" and opts.olympus == true }
	table.sort(entries, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.key < b.key
	end)
	return true
end

-- Forever's names are "First Surname" and a unit menu gets them apart (UnitNameUnmodified); a name
-- without its realm split by the menu (NameUtil.SplitPlayerNameIntoParts, where names are not one
-- across the region) comes back whole here.
local function Joined(name, surname)
	if type(surname) ~= "string" or surname == "" or name:find("-", 1, true) then return name end
	if ns.splitNames and not name:find(" ", 1, true) and not ns.IsRealmName(surname) then return name .. " " .. surname end
	return name .. "-" .. surname
end

-- Values the client hides from addons (secret values): any of them, and nothing is read.
local function Secret(...)
	if type(issecretvalue) ~= "function" then return false end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return true end
	end
	return false
end

-- The player a menu is for, or nil when it is not one we can reach (see above).
function PlayerMenu.Target(which, ctx, allowSelf)
	if type(ctx) ~= "table" then return nil end
	local info = ctx.clubMemberInfo
	-- (Checked before any test of them: a secret can't be compared or tested.)
	if Secret(ctx.name, ctx.surname, ctx.server, ctx.unit, ctx.isSelf, ctx.isOffline, ctx.bnetIDAccount, ctx.isMobile, info) then return nil end
	if type(info) == "table" and Secret(info.presence, info.name, info.isSelf) then return nil end
	if (ctx.isSelf and not allowSelf) or ctx.isOffline or ctx.bnetIDAccount or ctx.isMobile then return nil end
	local offline = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Offline
	if type(info) == "table" and offline ~= nil and info.presence == offline then return nil end
	local unit = type(ctx.unit) == "string" and ctx.unit ~= "" and ctx.unit or nil
	local name
	if unit then
		local isPlayer = not UnitIsPlayer or UnitIsPlayer(unit)
		local isMe = UnitIsUnit and UnitIsUnit(unit, "player")
		local connected = not UnitIsConnected or UnitIsConnected(unit)
		local first, realm
		if UnitFullName then first, realm = UnitFullName(unit) end
		if Secret(isPlayer, isMe, connected, first, realm) then return nil end
		if not isPlayer or (isMe and not allowSelf) or not connected then return nil end
		name = ns.UnitFullName(unit)
	else
		local raw = ctx.name
		if type(raw) ~= "string" or raw == "" then return nil end
		name = ns.FullName(ns.Normal(Joined(raw, ctx.surname or ctx.server)))
	end
	if type(name) ~= "string" or name == "" then return nil end
	local self = ns.me and ns.Fold(name) == ns.Fold(ns.me) or false
	-- The native self flag must agree with the resolved character. A malformed context
	-- must not turn the own-profile exception into actions against another player.
	if ctx.isSelf and not self then return nil end
	if self and not allowSelf then return nil end
	return { name = name, which = which, unit = unit, locked = ns.ChatLocked(), self = self or nil }
end

-- 1.2.5.1 (the owner, right-clicking a portrait: Olympus's lines "even for those who are not in
-- Olympus"): whether this client knows `name` to be in an Olympus guild, from what it already holds
-- (opening a menu sends nothing): the unit's guild as the game gives it, our roster, the guild our
-- last /who showed, his line on the Olympus channels this session, the guild his own Olympus
-- messages spoke for, the signed manifest. Unknown is no.
function PlayerMenu.KnownOlympus(name, unit)
	if type(unit) == "string" and unit ~= "" and type(GetGuildInfo) == "function" then
		local ok, guild = pcall(GetGuildInfo, unit)
		if ok and not Secret(guild) and type(guild) == "string" and guild ~= "" then return ns.IsFederation(guild) == true end
	end
	if type(name) ~= "string" or name == "" then return false end
	local R = ns.Roster
	if R and type(R.RankOf) == "function" and R.RankOf(name) ~= nil then return true end
	local W = ns.Who
	if type(W) == "table" and type(W.SeenGuild) == "function" then
		local guild, ago = W.SeenGuild(name)
		if type(guild) == "string" and type(ago) == "number" and ago < 1800 then return guild ~= "" and ns.IsFederation(guild) == true end
	end
	-- His line heard on the Olympus channels this session, for an Olympus guild (Channels.SpokeFor):
	-- once the signed leadership boundary is enforced, his line claims nothing (Channels.VerifiedLevel).
	local C = ns.Channels
	local spoke = type(C) == "table" and type(C.SpokeFor) == "function" and C.SpokeFor(name) or nil
	if type(spoke) == "string" and ns.IsFederation(spoke) == true then return true end
	local D = ns.Data
	local claimed = type(D) == "table" and type(D.ClaimedGuild) == "function" and D.ClaimedGuild(name) or nil
	if type(claimed) == "string" then return ns.IsFederation(claimed) == true end
	local A = ns.Authority
	return type(A) == "table" and type(A.Role) == "function" and A.Role(name) ~= nil
end

-- Profiles use the main window, not the Games window. Opening your own menu offers only this
-- local action: version requests, reports and challenges still never target yourself.
function PlayerMenu.OpenProfile(name)
	if not ns.IsMember() or type(name) ~= "string" then return false end
	if ns.me and ns.Fold(ns.FullName(name)) == ns.Fold(ns.me) then
		return ns.ProfileEdit and ns.ProfileEdit.Open and ns.ProfileEdit.Open() or false
	end
	return ns.PlayerProfile and ns.PlayerProfile.OpenName and ns.PlayerProfile.OpenName(name) or false
end

-- What a feature's build gets to add lines with. The first line any of them adds puts a divider
-- and the "Olympus" title over them all; no line, nothing of Olympus in the menu.
local function Wrap(root)
	local m = { count = 0 }
	local function Head()
		if m.count == 0 then
			if root.CreateDivider then root:CreateDivider() end
			root:CreateTitle(L.PLAYERMENU_TITLE)
		end
		m.count = m.count + 1
	end
	local function Tip(d, title, text)
		if not (d and d.SetTooltip and (title or text)) then return end
		d:SetTooltip(function(tooltip)
			if title then tooltip:AddLine(title, 1, 0.82, 0) end
			if text then tooltip:AddLine(text, 1, 1, 1, true) end
		end)
	end
	-- A line that is read, not clicked (the player's version).
	function m.Line(text, tipTitle, tipText)
		Head()
		local d = root:CreateTitle(text)
		Tip(d, tipTitle, tipText)
		return d
	end
	-- A line that does something: fn() on a click, protected. enabled == false: shown greyed (its
	-- tooltip says why).
	function m.Button(text, fn, tipTitle, tipText, enabled)
		Head()
		local d = root:CreateButton(text, function() ns.SafeCall("player menu " .. tostring(text), fn) end)
		Tip(d, tipTitle, tipText)
		if enabled == false and d and d.SetEnabled then d:SetEnabled(false) end
		return d
	end
	return m
end

-- One menu opening: every feature's lines for its player, after the game's own.
function PlayerMenu.Build(which, root, ctx)
	-- Forever's gamepad player menu drives protected interact-target state while it is being
	-- assembled. Even Menu.ModifyMenu's supported callbacks are unnecessary there and a client
	-- report tied opening that menu to SetPreferredGamepadInteractTarget being refused. Once a
	-- callback was registered in mouse mode it cannot be removed, so make it a strict no-op after
	-- a switch to gamepad mode as well.
	if ns.GamepadUI() then return 0 end
	if type(root) ~= "table" and type(root) ~= "userdata" then return 0 end
	if not ns.IsMember() then return 0 end
	local target = PlayerMenu.Target(which, ctx, true)
	if not target then return 0 end
	-- (1.2.5.1) The Olympus window's own rows list Olympus players: every line there.
	target.olympus = target.self == true or which == PlayerMenu.ROW or PlayerMenu.KnownOlympus(target.name, target.unit)
	local menu = Wrap(root)
	if target.olympus and ns.UI and type(ns.UI.OpenPlayerProfile) == "function" then
		menu.Button(L.ARENA_MENU_PROFILE, function() PlayerMenu.OpenProfile(target.name) end,
			L.ARENA_MENU_PROFILE, L.ARENA_MENU_PROFILE_TIP, true)
		target.profileAdded = true
	end
	if target.self then return menu.count end
	for _, e in ipairs(entries) do
		if not e.olympus or target.olympus then ns.SafeCall("player menu " .. e.key, e.build, target, menu) end
	end
	return menu.count
end

-- The Olympus window's own rows (the census, the Realm, the crafters, the arena's lists): a
-- right-click on a row that names a player opens a small menu of the same lines (the owner's
-- call, 2026-09-30: Check version and Ask to update from the guild's rows), the client's own
-- context menu (MenuUtil.CreateContextMenu) where it has one. offline: nothing that sends shows.
PlayerMenu.ROW = "OLYMPUS_ROW"
function PlayerMenu.OpenFor(owner, name, offline)
	if not ns.Gate.Allowed("player-menu") then return false end
	if type(name) ~= "string" or name == "" then return false end
	local MU = rawget(_G, "MenuUtil") -- gp:player-menu
	if not (MU and type(MU.CreateContextMenu) == "function") then return false end
	local ok = pcall(MU.CreateContextMenu, owner, function(_, root)
		if root.CreateTitle then root:CreateTitle(ns.DisplayName(name) or name) end
		ns.SafeCall("player row menu", PlayerMenu.Build, PlayerMenu.ROW, root, { name = name, isOffline = offline == true })
	end)
	return ok
end

-- Every menu above, once (at login: Blizzard_Menu loads before any addon).
function PlayerMenu.Hook() -- gp:player-menu
	if hooked then return true end
	-- Do not register an addon callback in Blizzard's protected gamepad player-menu path. If the
	-- player later returns to mouse and keyboard, the input-style event below installs it then.
	if ns.GamepadUI() then
		ns.Log("player menus: disabled with the gamepad UI")
		return false
	end
	if not (Menu and type(Menu.ModifyMenu) == "function") then
		ns.Log("player menus: this client has no Menu.ModifyMenu, no Olympus lines in them")
		return false
	end
	for _, which in ipairs(PlayerMenu.WHICH) do
		local w = which
		if not PlayerMenu.NEVER[w] then
			local ok, err = pcall(Menu.ModifyMenu, "MENU_UNIT_" .. w, function(_, root, ctx)
				if ns.GamepadUI() then return end
				ns.SafeCall("player menu", PlayerMenu.Build, w, root, ctx)
			end)
			if not ok then ns.Log("player menu %s not hooked: %s", w, tostring(err)) end
		end
	end
	hooked = true
	return true
end
function PlayerMenu.Hooked() return hooked end

-- For /oly status.
function PlayerMenu.StatusLine()
	local keys = {}
	for _, e in ipairs(entries) do keys[#keys + 1] = e.key end
	local state = ns.GamepadUI() and "disabled with the gamepad UI"
		or (hooked and ("hooked (" .. #PlayerMenu.WHICH .. " menus)") or "not hooked")
	return ("%s, lines: %s"):format(state, #keys > 0 and table.concat(keys, ", ") or "none")
end

function PlayerMenu.Reset() hooked = false end -- (tests: the entries stay, each file's own)

ns.On("LOGIN", function() PlayerMenu.Hook() end)
-- A player who logged in with the gamepad UI has no Blizzard-menu callbacks from Olympus. Install
-- them only after a later switch to mouse and keyboard (1.1.5: the gamepad gate, Gamepad.lua, on the
-- next frame); switching back is covered by the no-op guard in the already registered callbacks.
ns.Gate.Hooks("player-menu", { install = function() PlayerMenu.Hook() end })
