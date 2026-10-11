-- 1.2.1, a guild officer with mouse and keyboard: an addon failure "usually when try kick, this time
-- when try change Rank... it hasnt happened every time". The game's guild actions (promote, demote,
-- a rank, Remove from Guild) are calls the game refuses from tainted code. They start from the
-- member's card (its rank and its Remove) or from the roster's own right-click menu, and some ask
-- in the game's popups. The offline harness has no taint: these tests check that what Olympus's
-- code would put there is gone. No Olympus line is built into the game's guild roster menus (it was,
-- for an online member only: a failure that comes and goes), and an Olympus question still up as a
-- game popup moves into Olympus's own window as soon as a guild window opens, before any card.
local H = ...
local test, eq, ns = H.test, H.eq, H.ns

local WHICH = "OLYMPUS_TEST_RANK_QUESTION"

-- PlayerMenu.lua in a namespace of its own, a client with Menu.ModifyMenu recording each menu tag.
local function WithMenus(fn)
	local savedMenu = rawget(_G, "Menu")
	local hooks = {}
	local ok, err = pcall(function()
		Menu = { ModifyMenu = function(tag, cb) hooks[tag] = cb end }
		local pns = setmetatable({}, { __index = ns })
		pns.On = function() end
		pns.Gate = { Hooks = function() end, Allowed = function() return true end }
		pns.GamepadUI = function() return false end
		pns.IsMember = function() return true end
		pns.ChatLocked = function() return false end
		pns.me = "Tester-Realm"
		assert(loadfile(H.ADDON_DIR .. "PlayerMenu.lua"))("Olympus", pns)
		local PM = pns.PlayerMenu
		PM.Add("test-line", function(target, menu) menu.Button("Line for " .. target.name, function() end) end, 10)
		fn(PM, hooks)
	end)
	Menu = savedMenu
	if not ok then error(err, 0) end
end

local function Root()
	local r = { items = {} }
	function r:CreateDivider() self.items[#self.items + 1] = "divider" end
	function r:CreateTitle(text) self.items[#self.items + 1] = "title:" .. text; return {} end
	function r:CreateButton(text) self.items[#self.items + 1] = "button:" .. text; return {} end
	return r
end

test("guild rank (1.2.1): no Olympus line in the game's guild roster menus, where its promote, demote, rank and removal are; the other player menus keep theirs", function()
	WithMenus(function(PM, hooks)
		eq(PM.Hook(), true)
		eq(hooks.MENU_UNIT_COMMUNITIES_GUILD_MEMBER, nil, "Forever's Guild & Communities roster: not hooked")
		eq(hooks.MENU_UNIT_GUILD, nil, "the old Guild window's roster: not hooked")
		for _, which in ipairs({ "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "COMMUNITIES_WOW_MEMBER", "CHAT_ROSTER", "RECENT_ALLY" }) do
			assert(hooks["MENU_UNIT_" .. which], which .. " keeps Olympus's lines")
		end
		-- A guildmate's name in chat: the lines are there, for the same player.
		local r = Root()
		hooks.MENU_UNIT_FRIEND(nil, r, { name = "Ada" })
		assert(table.concat(r.items, "|"):find("button:Line for Ada-Realm", 1, true), table.concat(r.items, "|"))
		-- A later addition to the list cannot bring them back.
		PM.WHICH[#PM.WHICH + 1] = "COMMUNITIES_GUILD_MEMBER"
		PM.WHICH[#PM.WHICH + 1] = "GUILD"
		PM.Reset(); hooks.MENU_UNIT_COMMUNITIES_GUILD_MEMBER, hooks.MENU_UNIT_GUILD = nil, nil
		eq(PM.Hook(), true)
		eq(hooks.MENU_UNIT_COMMUNITIES_GUILD_MEMBER, nil); eq(hooks.MENU_UNIT_GUILD, nil)
	end)
end)

-- The game's guild window and its member's card, as GuildFrame.lua reads them.
local function GuildWindow(name)
	local f = { name = name, shown = false, alpha = 1, hooks = {} }
	function f:GetName() return self.name end
	function f:GetParent() return nil end
	function f:GetWidth() return 814 end
	function f:GetHeight() return 426 end
	function f:GetFrameLevel() return 5 end
	function f:GetAlpha() return self.alpha end
	function f:IsShown() return self.shown end
	function f:IsVisible() return self.shown end
	function f:HookScript(kind, fn) self.hooks[kind] = self.hooks[kind] or {}; table.insert(self.hooks[kind], fn) end
	function f:Show() self.shown = true; for _, fn in ipairs(self.hooks.OnShow or {}) do fn(self) end end
	function f:Hide() self.shown = false; for _, fn in ipairs(self.hooks.OnHide or {}) do fn(self) end end
	return f
end

-- GuildFrame.lua in a namespace of its own (its gamepad gate too), logged in with mouse and
-- keyboard; the harness's ns.ShowDialog reads it as ns.GuildFrameHook. The game's popups are
-- WithGamepadUI's (shown and hidden, recorded), StaticPopup_Visible answering from them.
local function WithGuildWindow(fn)
	H.WithUI(function()
		H.WithGamepadUI(false, function(game)
			local saved = { communities = rawget(_G, "CommunitiesFrame"), guild = rawget(_G, "GuildFrame"), social = rawget(_G, "FriendsFrame"),
				panel = rawget(_G, "ClassicUIForeverGuildPanel"), visible = rawget(_G, "StaticPopup_Visible"), dialog = StaticPopupDialogs[WHICH] }
			local up = {}
			local show, hide = StaticPopup_Show, StaticPopup_Hide
			StaticPopup_Show = function(which, ...) up[which] = { EditBox = { GetText = function() return "" end } }; return show(which, ...) end
			StaticPopup_Hide = function(which, ...) up[which] = nil; return hide(which, ...) end
			StaticPopup_Visible = function(which) if up[which] then return "StaticPopup1", up[which] end return nil end
			GuildFrame, FriendsFrame, ClassicUIForeverGuildPanel = nil, nil, nil
			CommunitiesFrame = GuildWindow("CommunitiesFrame")
			CommunitiesFrame.GuildMemberDetailFrame = GuildWindow(nil)
			local answers = {}
			StaticPopupDialogs[WHICH] = { text = "Question %s", button1 = "Yes", button2 = "No", timeout = 0, whileDead = true, hideOnEscape = true,
				OnAccept = function(_, data) answers[#answers + 1] = data end }
			local login = {}
			local gns = setmetatable({}, { __index = ns })
			gns.RegisterEvent = function() end
			gns.After = function() end
			assert(loadfile(H.ADDON_DIR .. "GamepadRegistry.lua"))("Olympus", gns)
			assert(loadfile(H.ADDON_DIR .. "Gamepad.lua"))("Olympus", gns)
			gns.On = function(name, f) if name == "LOGIN" then login[#login + 1] = f end end
			gns.UI = { CloseIfDocked = function() end, FollowHost = function() end, Undock = function() end }
			gns.MakeRoundButton = function()
				return setmetatable({ Show = function() end, Hide = function() end }, { __index = function() return function() end end })
			end
			assert(loadfile(H.ADDON_DIR .. "GuildFrame.lua"))("Olympus", gns)
			local ok, err = pcall(function()
				for _, f in ipairs(login) do f() end
				local caught
				H.WithStub("CaptureError", function(where, e) caught = caught or (tostring(where) .. ": " .. tostring(e)) end, function()
					H.WithStub("GuildFrameHook", gns.GuildFrameHook, function()
						fn({ game = game, answers = answers, popups = up, window = CommunitiesFrame, card = CommunitiesFrame.GuildMemberDetailFrame })
					end)
				end)
				assert(not caught, "an error the addon caught: " .. tostring(caught))
			end)
			ns.Dialog.Reset()
			StaticPopup_Show, StaticPopup_Hide, StaticPopup_Visible = show, hide, saved.visible
			CommunitiesFrame, GuildFrame, FriendsFrame, ClassicUIForeverGuildPanel = saved.communities, saved.guild, saved.social, saved.panel
			StaticPopupDialogs[WHICH] = saved.dialog
			if not ok then error(err, 0) end
		end)
	end)
end

local function Shown(which)
	local f = ns.Dialog.Find(which)
	return f ~= nil and f:IsShown() and f or nil
end

-- Olympus's questions among the game's popups now (what the game goes through when it shows its own).
local function OursUp(w)
	local n = 0
	for which in pairs(w.popups) do if which:find("^OLYMPUS_") then n = n + 1 end end
	return n
end

test("guild rank (1.2.1): an Olympus question up as a game popup moves into Olympus's own window as the guild window opens, before any member's card", function()
	WithGuildWindow(function(w)
		local data = { name = "Ada-Realm" }
		ns.ShowDialog(WHICH, "kept", nil, data)
		eq(OursUp(w), 1, "no guild window: the game's popup, as always")
		w.window:Show()
		eq(OursUp(w), 0, "the guild window open (its roster's right-click menu, no card): none of ours among the game's popups")
		eq(#w.answers, 0, "not answered by the move")
		local f = assert(Shown(WHICH), "asked again in Olympus's own window")
		assert(f.text:GetText():find("Question kept", 1, true), f.text:GetText())
		-- A question asked now stays in Olympus's window; the card opening moves nothing more.
		ns.ShowDialog(WHICH, "again", nil, "second")
		eq(OursUp(w), 0)
		w.card:Show()
		eq(OursUp(w), 0); eq(ns.MoveDialogsOffGame(), 0, "nothing more to move")
		f = assert(Shown(WHICH))
		f.buttons[1]:Click()
		eq(w.answers[1], "second", "its Yes answers as the game's would")
		-- ClassicUI Forever's unseen Communities window (alpha 0) is no window the player uses.
		w.window:Hide()
		w.window.alpha = 0
		ns.ShowDialog(WHICH, "unseen", nil, "third")
		w.window:Show()
		eq(OursUp(w), 1, "an unseen guild window moves nothing")
		ns.HideDialog(WHICH)
	end)
end)
