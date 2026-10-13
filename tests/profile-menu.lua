local ns, test, eq = ...

test("1.2.4 profile menu: own name offers only View profile; others open the main person page", function()
	local P = ns.PlayerMenu
	local old = { member = ns.IsMember, me = ns.me, ui = ns.UI, edit = ns.ProfileEdit, profile = ns.PlayerProfile, pad = ns.GamepadUI }
	local own, other = 0, nil
	local ok, err = pcall(function()
		ns.IsMember, ns.GamepadUI = function() return true end, function() return false end
		ns.me = "Tester-Realm"
		ns.UI = { OpenPlayerProfile = function() end }
		ns.ProfileEdit = { Open = function() own = own + 1; return true end }
		ns.PlayerProfile = { OpenName = function(name) other = name; return true end }
		local root = { buttons = {} }
		function root:CreateDivider() end
		function root:CreateTitle() end
		function root:CreateButton(text, click) self.buttons[#self.buttons + 1] = { text = text, click = click }; return {} end
		eq(P.Target("FRIEND", { name = ns.me }), nil, "legacy callers still exclude self")
		eq(P.Build("FRIEND", root, { name = ns.me, isSelf = true }), 1)
		eq(#root.buttons, 1, "no self challenge or version request")
		eq(root.buttons[1].text, ns.L.ARENA_MENU_PROFILE)
		root.buttons[1].click(); eq(own, 1); eq(other, nil)
		eq(P.OpenProfile("Other-Realm"), true); eq(other, "Other-Realm")
		ns.GamepadUI = function() return true end
		eq(P.Build("FRIEND", root, { name = ns.me, isSelf = true }), 0, "no native menu integration with gamepad")
		eq(#root.buttons, 1)
		ns.IsMember = function() return false end
		eq(P.OpenProfile("Other-Realm"), false)
	end)
	ns.IsMember, ns.me, ns.UI, ns.ProfileEdit, ns.PlayerProfile, ns.GamepadUI = old.member, old.me, old.ui, old.edit, old.profile, old.pad
	if not ok then error(err, 0) end
end)
