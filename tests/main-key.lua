local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]main%-key%.lua$") or "./"

-- 1.2.1: the borrowed key is Shift + the game's guild key (GetBindingKey("TOGGLEGUILDTAB"), J on
-- Forever by default), else Shift-J. Changed on purpose from Y: Forever binds Y to Legacy and G to
-- Target Last Hostile, so the old Y shortcut never came on there. The rule is the same: only a key
-- whose base binding and override slot are both empty, and no saved binding is ever changed.
local function World(fn)
	local names = { "CreateFrame", "GetBindingAction", "GetBindingKey", "GetBindingText", "SetOverrideBindingClick", "ClearOverrideBindings",
		"InCombatLockdown", "issecretvalue", "BINDING_HEADER_OLYMPUS", "BINDING_NAME_OLYMPUS_TOGGLE", "OlympusToggleBinding" }
	local saved = {}; for _, name in ipairs(names) do saved[name] = _G[name] end
	local w = { events = {}, listeners = {}, member = true, calls = {}, bindings = {}, savedBindings = {}, toggles = 0, guildKey = "J", printed = {} }
	local c = setmetatable({ db = {}, On = function(event, f) w.listeners[event] = f end,
		RegisterEvent = function(event, f) w.events[event] = f end, IsMember = function() return w.member end,
		Print = function(text) w.printed[#w.printed + 1] = text end,
		UI = { Toggle = function() w.toggles = w.toggles + 1 end } }, { __index = ns })
	c.Gate = { Allowed = function(id) eq(id, "main-key"); return not w.pad end,
		Hooks = function(id, hooks) eq(id, "main-key"); w.hooks = hooks end,
		Install = function(id) eq(id, "main-key"); if not w.pad then w.hooks.install() end end }
	InCombatLockdown = function() return w.combat == true end
	issecretvalue = function(value) return value == w.secret and w.secret ~= nil end
	GetBindingAction = function(key, overrides)
		if w.readError then error("binding unavailable") end
		if w.secret then return w.secret end
		return overrides and (w.other or (w.bindings[key] and "CLICK OlympusMainKey:LeftButton")) or w.savedBindings[key] or ""
	end
	-- The keys bound to an action (Blizzard's GetBindingKey: the first, then a second).
	GetBindingKey = function(action)
		eq(action, "TOGGLEGUILDTAB")
		if w.keyError then error("binding unavailable") end
		if w.keySecret then return w.secret end
		return w.guildKey, w.guildKey2
	end
	GetBindingText = function(key) return "<" .. tostring(key) .. ">" end
	CreateFrame = function(_, name)
		eq(name, "OlympusMainKey")
		local b = { scripts = {} }; w.button = b
		function b:RegisterForClicks(...) self.clicks = table.concat({ ... }, ",") end
		function b:SetScript(event, f) self.scripts[event] = f end
		return b
	end
	SetOverrideBindingClick = function(owner, priority, key, button, click)
		assert(not w.combat, "no protected binding change in combat")
		w.calls[#w.calls + 1] = "set " .. key; w.bindings[key] = owner
		eq(priority, false); eq(button, "OlympusMainKey"); eq(click, "LeftButton")
		if w.reentrant then w.events.UPDATE_BINDINGS() end
	end
	ClearOverrideBindings = function(owner)
		assert(not w.combat, "no protected binding change in combat")
		w.calls[#w.calls + 1] = "clear"
		for key, value in pairs(w.bindings) do if value == owner then w.bindings[key] = nil end end
	end
	c.L = setmetatable({}, { __index = ns.L })
	local ok, err = pcall(function()
		assert(loadfile(ROOT .. "Olympus/Locales/MainKeyText.lua"))("Olympus", c)
		assert(loadfile(ROOT .. "Olympus/MainKey.lua"))("Olympus", c)
		fn(c.MainKey, w, c)
	end)
	for _, name in ipairs(names) do _G[name] = saved[name] end
	if not ok then error(err, 0) end
end

local function Bound(w)
	local out = {}
	for key in pairs(w.bindings) do out[#out + 1] = key end
	table.sort(out)
	return table.concat(out, ",")
end

test("Main shortcut: a free Shift + guild key toggles the actual UI entry on press only, without saving a binding", function()
	World(function(k, w)
		w.listeners.LOGIN(); eq(k.Held(), true); eq(w.button.clicks, "AnyDown"); eq(k.HeldKey(), "SHIFT-J"); eq(Bound(w), "SHIFT-J")
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 1)
		w.button.scripts.OnClick(w.button, "LeftButton", false); eq(w.toggles, 1)
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 2)
		eq(next(w.savedBindings), nil); eq(#w.calls, 1)
		w.events.UPDATE_BINDINGS(); eq(#w.calls, 1, "unchanged state does not rebind")
	end)
end)

-- The reported problem: on Forever the game binds Y (Legacy) and G (Target Last Hostile), so the old
-- Y shortcut never came on. Shift + the guild key does, and Y and G stay the game's.
test("Main shortcut: with Forever's own Y and G bound, Shift + the guild key is borrowed and neither Y nor G is touched", function()
	World(function(k, w)
		w.savedBindings.Y, w.savedBindings.G, w.savedBindings.J = "TOGGLELEGACY", "TARGETLASTHOSTILE", "TOGGLEGUILDTAB"
		w.listeners.LOGIN()
		eq(k.Held(), true, "the shortcut is on"); eq(Bound(w), "SHIFT-J")
		eq(w.savedBindings.Y, "TOGGLELEGACY"); eq(w.savedBindings.G, "TARGETLASTHOSTILE"); eq(w.savedBindings.J, "TOGGLEGUILDTAB")
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 1)
	end)
end)

test("Main shortcut: the guild key is read at run time; a moved guild key moves the shortcut, and a modified, missing or unreadable one gives Shift-J", function()
	World(function(k, w)
		w.guildKey = "O"; w.listeners.LOGIN(); eq(Bound(w), "SHIFT-O")
		w.guildKey = "K"; w.events.UPDATE_BINDINGS()
		eq(Bound(w), "SHIFT-K", "the old key went back first"); eq(table.concat(w.calls, "|"), "set SHIFT-O|clear|set SHIFT-K")
		w.guildKey, w.guildKey2 = "BUTTON4", "J"; w.events.UPDATE_BINDINGS(); eq(Bound(w), "SHIFT-BUTTON4", "the first key bound")
	end)
	for _, kind in ipairs({ "none", "empty", "ctrl", "shift", "secret", "error", "api" }) do
		World(function(k, w)
			if kind == "none" then w.guildKey = nil elseif kind == "empty" then w.guildKey = ""
			elseif kind == "ctrl" then w.guildKey = "CTRL-G" elseif kind == "shift" then w.guildKey = "SHIFT-J"
			elseif kind == "secret" then w.keySecret, w.secret = true, {} elseif kind == "error" then w.keyError = true
			else GetBindingKey = nil end
			eq(k.Wanted(), "SHIFT-J", kind)
			if kind ~= "secret" then w.listeners.LOGIN(); eq(Bound(w), "SHIFT-J", kind) end
		end)
	end
end)

test("Main shortcut: saved actions and other addons' overrides are never replaced", function()
	for _, kind in ipairs({ "base", "override" }) do
		World(function(k, w)
			if kind == "base" then w.savedBindings["SHIFT-J"] = "TOGGLEACHIEVEMENT" else w.other = "CLICK OtherOwner:LeftButton" end
			w.listeners.LOGIN(); eq(k.Held(), false); eq(#w.calls, 0); eq(w.button, nil)
			if kind == "base" then w.savedBindings["SHIFT-J"] = nil else w.other = nil end
			w.events.UPDATE_BINDINGS(); eq(k.Held(), true)
			w.savedBindings["SHIFT-J"] = "TOGGLEQUESTLOG"; w.events.UPDATE_BINDINGS()
			eq(k.Held(), false); eq(w.savedBindings["SHIFT-J"], "TOGGLEQUESTLOG")
			w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 0)
		end)
	end
end)

test("Main shortcut: disabled or nonmembers retain their choice and cannot trigger a stale callback", function()
	World(function(k, w, c)
		k.SetEnabled(false); w.listeners.LOGIN(); eq(k.Held(), false); eq(c.db.mainKeyOff, true)
		k.SetEnabled(true); eq(k.Held(), true); eq(c.db.mainKeyOff, nil)
		local other = {}; w.bindings.F8 = other
		w.member = false; w.events.PLAYER_GUILD_UPDATE(); eq(k.Held(), false); eq(w.bindings.F8, other)
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 0)
		w.member = true; w.events.PLAYER_GUILD_UPDATE(); eq(k.Held(), true)
	end)
end)

test("Main shortcut: gamepad login is inert and both switches release or restore only its own owner", function()
	World(function(k, w)
		w.pad = true; w.listeners.LOGIN(); eq(#w.calls, 0); eq(w.button, nil)
		w.pad = false; w.hooks.install(); eq(k.Held(), true)
		local callback = w.button.scripts.OnClick
		w.pad = true; w.hooks.park(); eq(k.Held(), false)
		callback(w.button, "LeftButton", true); w.events.UPDATE_BINDINGS(); eq(w.toggles, 0); eq(#w.calls, 2)
		w.pad = false; w.hooks.install(); eq(k.Held(), true); eq(#w.calls, 3)
	end)
end)

test("Main shortcut: combat defers a binding change and a disabled or gamepad stale click remains inert", function()
	World(function(k, w)
		w.combat = true; w.listeners.LOGIN(); eq(#w.calls, 0)
		w.combat = false; w.events.PLAYER_REGEN_ENABLED(); eq(k.Held(), true)
		w.combat = true; k.SetEnabled(false); eq(k.Held(), true); eq(#w.calls, 1)
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 0)
		w.pad = true; w.hooks.park(); w.combat = false; w.events.PLAYER_REGEN_ENABLED()
		eq(k.Held(), false); eq(#w.calls, 2)
		w.pad = false; k.SetEnabled(true); eq(k.Held(), true)
		w.combat = true; w.savedBindings["SHIFT-J"] = "TOGGLEQUESTLOG"; w.events.UPDATE_BINDINGS()
		w.button.scripts.OnClick(w.button, "LeftButton", true); eq(w.toggles, 0)
		w.combat = false; w.events.PLAYER_REGEN_ENABLED(); eq(k.Held(), false)
		-- (A guild key moved in a fight: the change waits for its end too.)
		w.savedBindings["SHIFT-J"] = nil; w.events.UPDATE_BINDINGS(); eq(k.HeldKey(), "SHIFT-J")
		w.combat = true; w.guildKey = "O"; w.events.UPDATE_BINDINGS(); eq(k.HeldKey(), "SHIFT-J")
		w.combat = false; w.events.PLAYER_REGEN_ENABLED(); eq(k.HeldKey(), "SHIFT-O"); eq(Bound(w), "SHIFT-O")
	end)
end)

test("Main shortcut: missing, restricted or failed binding reads fail closed; binding events may be synchronous", function()
	for _, kind in ipairs({ "missing", "error", "secret" }) do
		World(function(k, w)
			if kind == "missing" then GetBindingAction = nil elseif kind == "error" then w.readError = true else w.secret = {} end
			w.listeners.LOGIN(); eq(k.Held(), false); eq(#w.calls, 0)
		end)
	end
	World(function(k, w)
		w.reentrant = true; w.listeners.LOGIN(); eq(k.Held(), true); eq(#w.calls, 1)
	end)
end)

test("Main shortcut: /oly hotkey names the key as the game writes it", function()
	World(function(k, w, c)
		w.listeners.LOGIN()
		k.Slash("")
		eq(w.printed[#w.printed], c.L.MAINKEY_STATUS:format("<SHIFT-J>", c.L.MAINKEY_ON))
		k.Slash("off"); eq(w.printed[#w.printed], c.L.MAINKEY_STATUS:format("<SHIFT-J>", c.L.MAINKEY_OFF)); eq(k.Held(), false)
		for _, key in ipairs({ "MAINKEY_STATUS", "HELP_MAINKEY" }) do
			assert(c.L[key]:find("Shift", 1, true), key .. " names Shift")
			eq(c.L[key]:find(" Y ", 1, true), nil, key .. ": no Y any more")
		end
	end)
end)

-- The game's Key Bindings menu: Bindings.xml in the addon's folder (the game reads it by itself;
-- a TOC line would load it as a UI file), the header and the name the menu shows, and the player's
-- own key opening and closing the window, the borrowed key's switch and the gamepad UI aside.
test("Main shortcut: Toggle Olympus is in the game's Key Bindings (AddOns) and toggles the window on a key press", function()
	local f = assert(io.open(ROOT .. "Olympus/Bindings.xml", "r")); local xml = f:read("*a"); f:close()
	assert(xml:find('<Binding name="OLYMPUS_TOGGLE" header="OLYMPUS" category="ADDONS">', 1, true), "the binding")
	assert(xml:find("OlympusToggleBinding(keystate)", 1, true), "its body")
	eq(select(2, xml:gsub("<Binding ", "")), 1, "one binding; no key bound by the addon")
	local toc = assert(io.open(ROOT .. "Olympus/Olympus.toc", "r")); local list = toc:read("*a"); toc:close()
	eq(list:find("Bindings.xml", 1, true), nil, "the game loads it by itself, never as a TOC file")
	World(function(k, w, c)
		eq(BINDING_HEADER_OLYMPUS, "Olympus"); eq(BINDING_NAME_OLYMPUS_TOGGLE, c.L.MAINKEY_BINDING)
		eq(type(OlympusToggleBinding), "function")
		OlympusToggleBinding("down"); eq(w.toggles, 1)
		OlympusToggleBinding("up"); eq(w.toggles, 1, "the key's release does nothing")
		k.SetEnabled(false); OlympusToggleBinding("down"); eq(w.toggles, 2, "the player's own key, whatever /oly hotkey says")
		w.pad = true; OlympusToggleBinding("down"); eq(w.toggles, 3, "with the gamepad UI too, as the minimap button")
		eq(#w.calls, 0, "no binding changed by it")
	end)
end)
