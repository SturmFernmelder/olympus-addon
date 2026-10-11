-- 1.2.1, a guild officer's report: "fyi get a fail from addon when kick ppl from guild".
-- Forever's own source (Blizzard_Communities/GuildRoster.xml, Blizzard_StaticPopup_Game/Mainline/
-- GameDialogDefs.lua): the guild member's card in the Guild & Communities window asks Remove from
-- Guild in an exclusive game popup (REMOVE_GUILDMEMBER) whose Yes calls C_GuildInfo.RemoveFromGuild
-- (HasRestrictions: refused from tainted code). Showing it, Blizzard_StaticPopup/StaticPopup.lua
-- goes through every game popup on screen (StaticPopup_HideExclusive, StaticPopup_FindVisible,
-- StaticPopup_SetUpPosition); one that Olympus's code opened (ns.ShowDialog's StaticPopup_Show with
-- mouse and keyboard) hands Olympus's taint to that question, and the removal fails ("Interface
-- action failed because of an AddOn"). The offline harness has no taint: these tests check what
-- removes the cause (no Olympus question opens as a game popup while a game guild window is on
-- screen, and one still up as a game popup moves to Olympus's own window as a member's card opens)
-- and that nothing of Olympus touches the removal itself.
local H = ...
local test, eq, ns = H.test, H.eq, H.ns

local WHICH = "OLYMPUS_TEST_GUILD_QUESTION"

-- The game's guild window, as GuildFrame.lua reads it: shown or not, its alpha (ClassicUI Forever
-- keeps it open unseen at 0) and the scripts hooked on it.
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
	function f:Run(kind) for _, fn in ipairs(self.hooks[kind] or {}) do fn(self) end end
	function f:Show() self.shown = true; self:Run("OnShow") end
	function f:Hide() self.shown = false; self:Run("OnHide") end
	return f
end

-- GuildFrame.lua in a namespace of its own (its gamepad gate too), logged in with mouse and
-- keyboard, the harness's ns.ShowDialog reading it as ns.GuildFrameHook; the game's popups those
-- of WithGamepadUI (shown and hidden, recorded), StaticPopup_Visible answering from them.
local function WithGuildWindow(fn)
	H.WithUI(function()
		H.WithGamepadUI(false, function(game)
			local saved = { communities = rawget(_G, "CommunitiesFrame"), guild = rawget(_G, "GuildFrame"), social = rawget(_G, "FriendsFrame"),
				panel = rawget(_G, "ClassicUIForeverGuildPanel"), visible = rawget(_G, "StaticPopup_Visible"), dialog = StaticPopupDialogs[WHICH] }
			local up = {}
			local show, hide = StaticPopup_Show, StaticPopup_Hide
			StaticPopup_Show = function(which, ...) up[which] = true return show(which, ...) end
			StaticPopup_Hide = function(which, ...) up[which] = nil return hide(which, ...) end
			StaticPopup_Visible = function(which) return up[which] and ("StaticPopup1") or nil end
			GuildFrame, FriendsFrame, ClassicUIForeverGuildPanel = nil, nil, nil
			CommunitiesFrame = GuildWindow("CommunitiesFrame")
			-- (The member's card, its Remove button the game's: Blizzard_Communities/CommunitiesFrame.xml.)
			CommunitiesFrame.GuildMemberDetailFrame = GuildWindow(nil)
			local answers = {}
			StaticPopupDialogs[WHICH] = { text = "Question %s", button1 = "Yes", button2 = "No", timeout = 0, whileDead = true,
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
						fn({ game = game, answers = answers, window = CommunitiesFrame, card = CommunitiesFrame.GuildMemberDetailFrame })
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

test("guild removal (1.2.1): with the game's guild window on screen an Olympus question is Olympus's own window, never a game popup; closed, the game's popup as before", function()
	WithGuildWindow(function(w)
		ns.ShowDialog(WHICH, "before", nil, "first")
		eq(#w.game.shown, 1, "no guild window: the game's popup, as always"); eq(w.game.shown[1].which, WHICH)
		ns.HideDialog(WHICH)
		w.window:Show()
		ns.ShowDialog(WHICH, "while open", nil, "second")
		eq(#w.game.shown, 1, "never the game's popup while the guild window is up")
		local f = assert(Shown(WHICH), "Olympus's own window")
		assert(f.text:GetText():find("Question while open", 1, true), f.text:GetText())
		f.buttons[1]:Click()
		eq(w.answers[#w.answers], "second", "its Yes answers as the game's would")
		-- ClassicUI Forever's unseen Communities window (alpha 0) is no window the player uses.
		w.window.alpha = 0
		ns.ShowDialog(WHICH, "unseen", nil, "third")
		eq(#w.game.shown, 2, "the game's popup again"); eq(Shown(WHICH), nil)
		ns.HideDialog(WHICH)
		w.window.alpha = 1
		w.window:Hide()
		ns.ShowDialog(WHICH, "after", nil, "fourth")
		eq(#w.game.shown, 3, "closed: the game's popup again")
	end)
end)

test("guild removal (1.2.1): a question of Olympus's up as a game popup when a member's card opens (its Remove) moves to Olympus's own window, with what it asked", function()
	WithGuildWindow(function(w)
		local data = { name = "Ada-Realm" }
		ns.ShowDialog(WHICH, "kept", nil, data)
		eq(#w.game.shown, 1); eq(StaticPopup_Visible(WHICH) ~= nil, true, "up as the game's popup")
		w.window:Show()
		eq(StaticPopup_Visible(WHICH) ~= nil, true, "the guild window alone leaves it where it is")
		w.card:Show()
		eq(StaticPopup_Visible(WHICH), nil, "the card open: no longer among the game's popups")
		local hidden = false
		for _, which in ipairs(w.game.hidden) do if which == WHICH then hidden = true end end
		eq(hidden, true, "closed there unanswered")
		eq(#w.answers, 0, "and not answered")
		local f = assert(Shown(WHICH), "asked again in Olympus's own window")
		assert(f.text:GetText():find("Question kept", 1, true), f.text:GetText())
		f.buttons[1]:Click()
		eq(w.answers[1], data, "the same question: the same data")
		eq(ns.MoveDialogsOffGame(), 0, "nothing more to move")
	end)
end)

-- Nothing else of Olympus is in the game's removal: no code (comments aside) names its question or
-- the removal call, writes to the member's card, hooks the game's popups or menus, or writes a popup
-- of the game's own (every StaticPopupDialogs entry Olympus writes is an OLYMPUS_ one). Olympus's
-- lines in the right-click menus (PlayerMenu.lua) go through Menu.ModifyMenu, whose lines Forever's
-- Blizzard_Menu builds inside securecallfunction, and its guild member menu has no removal.
test("guild removal (1.2.1): no Olympus code touches the game's Remove from Guild, its popups' functions or its menus' own lines", function()
	local scanned = 0
	for _, dir in ipairs({ H.ADDON_DIR, H.ROOT .. "Olympus_Arena/" }) do
		local p = io.popen('ls "' .. dir .. '" 2>/dev/null')
		for file in p:lines() do
			if file:match("%.lua$") then
				scanned = scanned + 1
				local n = 0
				for line in io.lines(dir .. file) do
					n = n + 1
					local code = line:gsub("%-%-.*$", "")
					local where = file .. ":" .. n
					for _, name in ipairs({ "REMOVE_GUILDMEMBER", "RemoveFromGuild", "UnitPopup_", "StaticPopup_OnClick" }) do
						assert(not code:find(name, 1, true), where .. " names " .. name)
					end
					-- (The member's card: GuildFrame.lua alone looks it up, to hook its OnShow after the
					-- game's, never writing to it.)
					if code:find("GuildMemberDetail", 1, true) then
						eq(file, "GuildFrame.lua", where .. " names the member's card")
						assert(not code:find("GuildMemberDetailFrame%.[%w_]+%s*=[^=]") and not code:find("SetScript", 1, true), where .. " writes to the member's card")
					end
					assert(not code:find("hooksecurefunc%(%s*[\"']StaticPopup"), where .. " hooks a game popup function")
					assert(not code:find("hooksecurefunc%(%s*[\"']UnitPopup") and not code:find("hooksecurefunc%(%s*UnitPopup"), where .. " hooks the unit menus")
					assert(not code:find("hooksecurefunc%(%s*CommunitiesFrame"), where .. " hooks the Communities window's functions")
					for key in code:gmatch("StaticPopupDialogs%[%s*[\"']([%w_]+)[\"']%s*%]%s*=[^=]") do
						assert(key:find("^OLYMPUS_"), where .. " writes the game's popup " .. key)
					end
				end
			end
		end
		p:close()
	end
	assert(scanned > 60, "the files scanned: " .. scanned)
end)
