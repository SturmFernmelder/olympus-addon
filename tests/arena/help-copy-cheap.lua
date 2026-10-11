-- 1.2.1, the help's copy window (Olympus/UI.lua's UI.ShowHelp and UI.ShowCopy): on a slow laptop
-- the in-game timer measured 2.7 s for one opening of the help (the Olympus window's "i"); offline
-- it costs under a millisecond, so the time is the client's own work on the window and its text.
-- The cheaper path: the help's text is made once a session, the box keeps a text it shows already
-- (the help opened again sets no text, so the client lays nothing out again), and the box's
-- read-only guard sets its text back only when it is not the box's own: on a client that called
-- the box's own SetText typed, the old guard set it again and again. On the harness's stand-in
-- frames (H.WithUI), UI.lua loaded fresh as the harness's LoadUI does.
local H = ...
local test, eq = H.test, H.eq

local function check(cond, msg, ...) if not cond then error((msg or "check failed"):format(...), 2) end end
-- UI.lua in a namespace of its own, over the harness's.
local function LoadUI()
	local uns = setmetatable({}, { __index = H.ns })
	uns.On = function() end
	assert(loadfile(H.ADDON_DIR .. "UI.lua"))("Olympus", uns)
	return uns.UI, uns
end
-- Counts the box's SetText calls; with `typed`, the box reports its own SetText as the player's
-- typing (its OnTextChanged with userInput true), as such a client would, up to a depth.
local function Count(box, typed)
	local calls, depth, deepest = 0, 0, 0
	local set = box.SetText
	rawset(box, "SetText", function(self, text)
		calls = calls + 1
		set(self, text)
		if typed and depth < 40 then
			depth = depth + 1
			deepest = math.max(deepest, depth)
			local fn = self:GetScript("OnTextChanged")
			if fn then fn(self, true) end
			depth = depth - 1
		end
	end)
	return function() return calls, deepest end
end

print("1.2.1: the help's copy window, the cheaper path")

test("1.2.1 help copy window: its text is made once; opened again it sets no text; another copy and the help again set it once each", function()
	H.WithUI(function()
		local UI = LoadUI()
		local L = H.ns.L
		UI.ShowHelp()
		local box = assert(_G.OlympusCopyFrame, "the help's copy window")
		eq(box.TitleText:GetText(), L.HELP_TITLE)
		local help = box.text
		check(help:find(L.HELP_LINKS, 1, true), "the help in the box")
		eq(box.eb:GetText(), help)
		local calls = Count(box.eb)
		-- Closed and opened again: the box keeps its text, nothing set.
		box:Hide()
		UI.ShowHelp()
		eq(box:IsShown(), true, "shown again")
		eq((calls()), 0, "no text set again")
		eq(box.eb:GetText(), help); eq(box.text, help)
		eq(box.action:GetText(), L.REPORT_BUG); eq(box.second:IsShown(), true, "its buttons as ever")
		-- Another copy in the same box, then the help: each sets its own text once.
		UI.ShowCopy("A copy", "another text")
		eq((calls()), 1); eq(box.eb:GetText(), "another text"); eq(box.second:IsShown(), false)
		UI.ShowHelp()
		eq((calls()), 2); eq(box.eb:GetText(), help); eq(box.second:IsShown(), true)
		-- The help's text, made once a session.
		check(rawequal(UI.HelpText(), UI.HelpText()), "made once")
		eq(UI.HelpText(), help)
	end)
end)

test("1.2.1 help copy window: the read-only guard sets the text back once, also on a client that reports the box's own SetText as typed; typing still goes", function()
	H.WithUI(function()
		local UI = LoadUI()
		UI.ShowCopy("A copy", "first")
		local box = assert(_G.OlympusCopyFrame)
		local calls = Count(box.eb, true)
		UI.ShowCopy("A copy", "second text")
		local n, deepest = calls()
		eq(n, 1, "one SetText for a new text")
		check(deepest <= 1, "never set again from its own change (%d deep)", deepest)
		eq(box.eb:GetText(), "second text")
		-- The player types into it: the text goes back, once, and is selected for Ctrl+C.
		box.eb:SetText("second textX")
		local typedAt = calls()
		eq(box.eb:GetText(), "second text", "what was typed went")
		eq(typedAt, 3, "the typed text and the one setting back")
	end)
end)
