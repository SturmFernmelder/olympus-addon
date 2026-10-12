local ns, test, eq, WithWindow, ForeverWorld = ...

local function Tab(frame, kind)
	for _, button in ipairs(frame.subtabs.nav) do
		if button:IsShown() and button.item.entry.kind == kind then return button end
	end
	error("missing destination " .. kind)
end

-- (1.2.3: the two tests of the Race and Class lists, opened under their clicked tabs in both
-- windows, went with the race and class rooms. ForeverWorld, the HD window, was theirs alone.)
test("Chat picker anchor: Arena and role menus retain their right edge placement", function()
	WithWindow(function(w)
		local f = w.CW.Open("A")
		local arena = Tab(f, "arena")
		arena:Click()
		eq(f.subMenu:GetRight(), f:GetRight() - 12)
		eq(f.subMenu:GetTop(), arena:GetBottom() - 2)
		f.subCatcher:Click()
		local V, preview, role = ns.ViewAs, ns.ViewAs.Previewing, ns.ViewAs.Role
		local ok, why = pcall(function()
			V.Previewing = function() return true end
			V.Role = function() return "king" end
			w.fire("DATA_CHANGED"); w.CW.Render()
			local owner = Tab(f, "role")
			owner:Click()
			eq(f.subMenu:GetRight(), f:GetRight() - 12)
			eq(f.subMenu:GetTop(), owner:GetBottom() - 2)
			f.subCatcher:Click()
		end)
		V.Previewing, V.Role = preview, role
		if not ok then error(why, 0) end
	end)
end)
