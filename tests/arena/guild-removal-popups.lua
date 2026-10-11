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
local NOTE = "OLYMPUS_TEST_GUILD_NOTE"

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
-- of WithGamepadUI (shown and hidden, recorded), StaticPopup_Visible answering from them as
-- Forever's does (the popup's name, then the popup: Blizzard_StaticPopup/StaticPopup.lua), each
-- popup with its EditBox, which the game's StaticPopup_OnHide empties.
local function WithGuildWindow(fn)
	H.WithUI(function()
		H.WithGamepadUI(false, function(game)
			local saved = { communities = rawget(_G, "CommunitiesFrame"), guild = rawget(_G, "GuildFrame"), social = rawget(_G, "FriendsFrame"),
				panel = rawget(_G, "ClassicUIForeverGuildPanel"), visible = rawget(_G, "StaticPopup_Visible"), dialog = StaticPopupDialogs[WHICH],
				note = StaticPopupDialogs[NOTE] }
			local up = {}
			local show, hide = StaticPopup_Show, StaticPopup_Hide
			StaticPopup_Show = function(which, ...)
				up[which] = { EditBox = { text = "", GetText = function(self) return self.text end } }
				return show(which, ...)
			end
			StaticPopup_Hide = function(which, ...)
				if up[which] then up[which].EditBox.text = "" end
				up[which] = nil
				return hide(which, ...)
			end
			StaticPopup_Visible = function(which) if up[which] then return "StaticPopup1", up[which] end return nil end
			GuildFrame, FriendsFrame, ClassicUIForeverGuildPanel = nil, nil, nil
			CommunitiesFrame = GuildWindow("CommunitiesFrame")
			-- (The member's card, its Remove button the game's: Blizzard_Communities/CommunitiesFrame.xml.)
			CommunitiesFrame.GuildMemberDetailFrame = GuildWindow(nil)
			local answers, cancels, notes = {}, {}, {}
			StaticPopupDialogs[WHICH] = { text = "Question %s", button1 = "Yes", button2 = "No", timeout = 0, whileDead = true, hideOnEscape = true,
				OnAccept = function(_, data) answers[#answers + 1] = data end,
				OnCancel = function(_, data, reason) cancels[#cancels + 1] = tostring(data) .. " " .. tostring(reason) end }
			-- (As Olympus's report note and whisper questions: an edit box their OnShow empties.)
			StaticPopupDialogs[NOTE] = { text = "Note on %s", button1 = "Send", button2 = "Cancel", hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
				OnShow = function(self) self.editBox:SetText("") end,
				OnAccept = function(self, data) notes[#notes + 1] = tostring(data) .. ": " .. tostring(self.editBox:GetText()) end }
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
						fn({ game = game, answers = answers, cancels = cancels, notes = notes, popups = up, window = CommunitiesFrame,
							card = CommunitiesFrame.GuildMemberDetailFrame })
					end)
				end)
				assert(not caught, "an error the addon caught: " .. tostring(caught))
			end)
			ns.Dialog.Reset()
			StaticPopup_Show, StaticPopup_Hide, StaticPopup_Visible = show, hide, saved.visible
			CommunitiesFrame, GuildFrame, FriendsFrame, ClassicUIForeverGuildPanel = saved.communities, saved.guild, saved.social, saved.panel
			StaticPopupDialogs[WHICH], StaticPopupDialogs[NOTE] = saved.dialog, saved.note
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

-- (A reviewer: the move happens whenever a member's card opens, to look at a member too; a note the
-- player was writing in the game's popup must not be wiped by that click.)
test("guild removal (1.2.1): what the player has in the box of an Olympus game popup moves with it into Olympus's own window", function()
	WithGuildWindow(function(w)
		ns.ShowDialog(NOTE, "Ada", nil, "case 7")
		local box = assert(w.popups[NOTE], "the game's popup").EditBox
		box.text = "spam in the Olympus channel, twice"
		w.window:Show()
		w.card:Show()
		eq(StaticPopup_Visible(NOTE), nil, "no longer the game's popup")
		local f = assert(Shown(NOTE), "in Olympus's own window")
		eq(f.editBox:GetText(), "spam in the Olympus channel, twice", "the note as the player left it, after the question's own OnShow")
		f.buttons[1]:Click()
		eq(w.notes[1], "case 7: spam in the Olympus channel, twice", "sent with that note")
		-- An empty box stays empty; a question without a box gets nothing in one.
		w.window:Hide()
		ns.ShowDialog(NOTE, "Bo", nil, "case 8")
		ns.ShowDialog(WHICH, "plain", nil, "plain")
		w.window:Show()
		w.card:Hide(); w.card:Show()
		eq(assert(Shown(NOTE)).editBox:GetText(), "")
		eq(assert(Shown(WHICH)).editBox:IsShown(), false)
	end)
end)

-- (A reviewer: with mouse and keyboard Escape closed these questions as the game's popups; asked in
-- Olympus's window while the guild window is open, Escape closed the guild window and left the
-- question alone on screen.) The game's Escape past its own popups and menus is CloseAllWindows,
-- whose CloseSpecialWindows hides every frame named on UISpecialFrames
-- (Blizzard_UIParentPanelManager); its PLAYER_DEAD and PLAYER_ENTERING_WORLD handlers and the
-- interface shown again sweep the same list, and the game's popups live through those.
test("guild removal (1.2.1): with the guild window open Escape closes an Olympus question as it closed the game's popup, and the game's other sweeps of its windows leave it up", function()
	WithGuildWindow(function(w)
		local timers, clock, savedTime = {}, 100, GetTime
		GetTime = function() return clock end
		local ok, err = pcall(H.WithStub, "After", function(_, _, fn) timers[#timers + 1] = fn end, function()
			local function NextFrame() local due = timers; timers = {}; for _, fn in ipairs(due) do fn() end end
			local function Listed()
				for _, name in ipairs(UISpecialFrames) do if name == "OlympusQuestionEscape" then return _G[name] end end
				return nil
			end
			local function Sweep()
				for _, name in pairs(UISpecialFrames) do
					local frame = _G[name]
					if frame and frame:IsShown() then frame:Hide() end
				end
			end
			-- The game's popup (no guild window): nothing of ours on the list.
			ns.ShowDialog(WHICH, "popup", nil, "popup")
			eq(Listed(), nil, "the game's popup: the game's Escape")
			ns.HideDialog(WHICH)
			w.window:Show()
			ns.ShowDialog(WHICH, "asked", nil, "first")
			local f = assert(Shown(WHICH))
			local catcher = assert(Listed(), "on the escape list while it is up")
			eq(catcher:IsShown(), true)
			Sweep()
			eq(f:IsShown(), true, "not inside the game's walk of its list")
			NextFrame()
			eq(Shown(WHICH), nil, "Escape closed it")
			eq(w.cancels[#w.cancels], "first clicked", "cancelled as the game's Escape cancels its popup")
			eq(#w.answers, 0)
			eq(catcher:IsShown(), false, "nothing up: off")
			-- noCancelOnEscape: closed, not cancelled.
			StaticPopupDialogs[WHICH].noCancelOnEscape = true
			ns.ShowDialog(WHICH, "asked", nil, "second")
			Sweep(); NextFrame()
			eq(Shown(WHICH), nil); eq(#w.cancels, 1, "not cancelled")
			StaticPopupDialogs[WHICH].noCancelOnEscape = nil
			-- A death or a loading screen in that same frame: still up, and Escape still closes it.
			ns.ShowDialog(WHICH, "asked", nil, "third")
			clock = 101
			ns.Dialog.Swept()
			Sweep(); NextFrame()
			assert(Shown(WHICH), "the game's death or loading sweep: still up")
			eq(catcher:IsShown(), true, "back for the next Escape"); eq(#w.cancels, 1)
			-- The interface hidden (Alt+Z) and shown again: the game's sweep then, still up.
			clock = 102
			catcher:Fire("OnHide")
			clock = 103
			catcher:Fire("OnShow")
			Sweep(); NextFrame()
			assert(Shown(WHICH), "the interface shown again: still up")
			clock = 104
			Sweep(); NextFrame()
			eq(Shown(WHICH), nil, "the next Escape: closed"); eq(w.cancels[#w.cancels], "third clicked")
			-- Answered by its button: nothing more on the list's frame, nothing cancelled after.
			ns.ShowDialog(WHICH, "asked", nil, "fourth")
			assert(Shown(WHICH)).buttons[1]:Click()
			eq(catcher:IsShown(), false)
			Sweep(); NextFrame()
			eq(w.answers[#w.answers], "fourth"); eq(#w.cancels, 2)
			-- One moved off the game's popups as a member's card opens closes on Escape too.
			w.window:Hide()
			ns.ShowDialog(WHICH, "moved", nil, "fifth")
			w.window:Show(); w.card:Show()
			assert(Shown(WHICH), "moved")
			eq(catcher:IsShown(), true)
			clock = 105
			Sweep(); NextFrame()
			eq(Shown(WHICH), nil); eq(w.cancels[#w.cancels], "fifth clicked")
		end)
		GetTime = savedTime
		if not ok then error(err, 0) end
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
