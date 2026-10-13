local ADDON, ns = ...

-- A session-only shortcut. The player's saved bindings and other addons' overrides stay
-- theirs: the key is borrowed only while both its base binding and its override slot are empty.
-- 1.2.1: the key is Shift + the game's guild key (Forever binds Y to Legacy and G to Target Last
-- Hostile; its guild key, "Guild & Communities", is J): read at run time from the player's own
-- binding of TOGGLEGUILDTAB, so a guild key moved elsewhere moves this one too. A guild key that
-- already has a modifier, or none bound, gives Shift-J. The player's own key for Olympus is the
-- game's: Key Bindings, AddOns, "Toggle Olympus" (Bindings.xml, Olympus.Toggle below).
local Key = {}
ns.MainKey = Key
local BUTTON, ACTION = "OlympusMainKey", "CLICK OlympusMainKey:LeftButton"
Key.GUILD_ACTION = "TOGGLEGUILDTAB"
Key.FALLBACK = "SHIFT-J"
local button, held, pending, syncing

local function Combat()
	if type(InCombatLockdown) ~= "function" then return true end
	local ok, locked = pcall(InCombatLockdown)
	return not ok or locked ~= false
end

local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) end

function Key.Enabled() return type(ns.db) == "table" and ns.db.mainKeyOff ~= true end

-- The key this session borrows: "SHIFT-" and the first key bound to the game's guild window, when
-- that key has no modifier of its own; else Key.FALLBACK.
function Key.Wanted()
	if type(GetBindingKey) ~= "function" then return Key.FALLBACK end
	local ok, first = pcall(GetBindingKey, Key.GUILD_ACTION)
	if not ok or Secret(first) or type(first) ~= "string" or first == "" then return Key.FALLBACK end
	for _, mod in ipairs({ "ALT", "CTRL", "SHIFT", "META", "LALT", "RALT", "LCTRL", "RCTRL", "LSHIFT", "RSHIFT" }) do
		if first:sub(1, #mod + 1) == mod .. "-" and #first > #mod + 1 then return Key.FALLBACK end
	end
	return "SHIFT-" .. first
end

local function Available(key) -- gp:main-key
	if not ns.Gate.Allowed("main-key") then return false end
	if type(GetBindingAction) ~= "function" then return false end
	key = key or Key.Wanted()
	for _, overrides in ipairs({ false, true }) do
		local ok, action = pcall(GetBindingAction, key, overrides)
		if not ok or Secret(action) or type(action) ~= "string"
			or (action ~= "" and not (overrides and held == key and action == ACTION)) then return false end
	end
	return true
end

local function Release() -- gp:main-key!undo
	if not held then pending = nil; return true end
	if Combat() then pending = true; return false end
	if type(ClearOverrideBindings) ~= "function" then return false end
	local ok = pcall(ClearOverrideBindings, button)
	if ok then held, pending = nil, nil end
	return ok
end

function Key.Press(_, _, down) -- gp:main-key
	if not ns.Gate.Allowed("main-key") then return end
	if down == false or not Key.Enabled() or not ns.IsMember() or not held or not Available(held) then return end
	local W, V = ns.Watch, ns.ViewAs
	local preview = V and V.Previewing and V.Previewing()
	-- The Council's borrowed guild shortcut opens its real, permission-scoped desk. A
	-- preview or unavailable desk retains the ordinary toggle and grants no reading power.
	if not preview and ns.IsHighCouncillor and ns.IsHighCouncillor(ns.me) == true
		and W and not W.missing and W.CouncilDeskShown and W.CouncilDeskShown() == true
		and ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("watch"); return end
	if ns.UI and ns.UI.Toggle then ns.UI.Toggle() end
end

function Key.Refresh() -- gp:main-key
	if not ns.Gate.Allowed("main-key") then return end
	if syncing then return end
	if Combat() then pending = true; return end
	syncing = true
	local key = Key.Wanted()
	-- (The guild key moved: the old borrowed key goes back first.)
	if held and held ~= key then Release() end
	if not Key.Enabled() or not ns.IsMember() or not Available(key) then
		Release()
	elseif not held and type(SetOverrideBindingClick) == "function" then
		if not button then
			button = CreateFrame("Button", BUTTON, UIParent)
			button:RegisterForClicks("AnyDown")
			button:SetScript("OnClick", Key.Press)
		end
		held = pcall(SetOverrideBindingClick, button, false, key, BUTTON, "LeftButton") and key or nil
	end
	syncing, pending = nil, nil
end

function Key.SetEnabled(on)
	if type(ns.db) ~= "table" or type(on) ~= "boolean" then return false end
	ns.db.mainKeyOff = not on or nil
	if ns.Gate.Allowed("main-key") then Key.Refresh() else Release() end
	return true
end

-- The key as the game writes it for the player ("Shift-J"), else as bound ("SHIFT-J").
function Key.Text(key)
	key = key or held or Key.Wanted()
	if type(GetBindingText) == "function" then
		local ok, text = pcall(GetBindingText, key)
		if ok and not Secret(text) and type(text) == "string" and text ~= "" then return text end
	end
	return key
end

function Key.Slash(text)
	text = tostring(text or ""):lower()
	if text == "on" or text == "off" then Key.SetEnabled(text == "on") end
	ns.Print(ns.L.MAINKEY_STATUS:format(Key.Text(), Key.Enabled() and ns.L.MAINKEY_ON or ns.L.MAINKEY_OFF))
end

-- The game's Key Bindings menu (Bindings.xml: AddOns, "Toggle Olympus"): a key the player chose
-- there, saved by the game as any binding. It opens and closes the Olympus window as the minimap
-- button does, with the gamepad UI too (only Olympus's own window: nothing of the game's runs from
-- it), whatever /oly hotkey says (that switch is the borrowed key's alone).
function Key.Toggle(down)
	if down == "up" or down == false then return end
	if ns.UI and ns.UI.Toggle then
		if ns.SafeCall then ns.SafeCall("toggle binding", ns.UI.Toggle) else ns.UI.Toggle() end
	end
end
BINDING_HEADER_OLYMPUS = "Olympus"
BINDING_NAME_OLYMPUS_TOGGLE = ns.L and ns.L.MAINKEY_BINDING or "Toggle Olympus"
function OlympusToggleBinding(keystate) Key.Toggle(keystate) end

function Key.Held() return held ~= nil end
function Key.HeldKey() return held end
ns.Gate.Hooks("main-key", { now = true, install = Key.Refresh, park = Release })
ns.On("LOGIN", function() ns.Gate.Install("main-key") end)
ns.RegisterEvent("UPDATE_BINDINGS", Key.Refresh)
ns.RegisterEvent("PLAYER_GUILD_UPDATE", Key.Refresh)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if pending then
		if ns.Gate.Allowed("main-key") then Key.Refresh() else Release() end
	end
end)
