-- 1.2.4: Arena and Bones use the common, in-window ranking explanation page.
local H = ...
local test, eq, World = H.test, H.eq, H.World

local function Find(lines, id)
	for _, line in ipairs(lines or {}) do if line.id == id then return line end end
end
local function Texts(lines)
	local out = {}
	for _, line in ipairs(lines or {}) do if line.text then out[#out + 1] = line.text end end
	return table.concat(out, "\n")
end

test("1.2.4 Games ranking rules: Arena and Bones open inside the tab and Back restores the selected ranking", function()
	local w = World.New()
	local king = w:Role("king")
	for _, case in ipairs({ { game = "arena", key = "arena-rating", title = king.ns.L.RANK_RULE_ARENA_TITLE },
		{ game = "bones", key = "bones-ranking", title = king.ns.L.RANK_RULE_BONES_TITLE } }) do
		king.ns.ArenaHome.rankGame = case.game
		local lines = w:As(king, king.ns.ArenaHome.TabLines)
		local link = Find(lines, "ranking-rules:" .. case.key)
		assert(link and link.onClick, Texts(lines))
		w:As(king, link.onClick)
		eq(king.ns.ArenaHome.rulesKey, case.key)
		lines = w:As(king, king.ns.ArenaHome.TabLines)
		eq(lines[1].id, "ranking-rules-back")
		assert(Texts(lines):find(case.title, 1, true), Texts(lines))
		if case.game == "arena" then
			local prose = Texts(lines):gsub("\n", " ")
			assert(prose:find("halfway back toward 1500", 1, true), prose)
			assert(prose:find("unsettled and has fewer than 10 rated fights", 1, true), prose)
			assert(prose:find("uses K=24, or K=16 from rating 2000", 1, true), prose)
		end
		w:As(king, lines[1].onClick)
		eq(king.ns.ArenaHome.rulesKey, nil)
		eq(king.ns.ArenaHome.rankGame, case.game, "Back restores the exact game ranking")
	end
	for _, e in ipairs(king.errors) do error(e, 2) end
end)

test("1.2.4 ranking rules: Treasury donor rules preserve Back and close immediately when access is lost", function()
	local w = World.New()
	local king = w:Role("king")
	local T = king.ns.Treasury
	-- This world deliberately does not load Bank.lua per client. Mask the harness's inherited Bank
	-- with the empty bank state the real module exposes, so the Treasury page exercises its own UI.
	rawset(king.ns, "Bank", {
		Current = function() return nil end, HasAPI = function() return true end,
		Requests = function() return {} end, PublicRequests = function() return {} end,
		MyRequests = function() return {} end, MayRequest = function() return false end,
		SeesSisters = function() return false end,
	})
	w:As(king, T.Show, "summary")
	local lines = w:As(king, T.Build)
	local link = Find(lines, "ranking-rules:treasury-donors")
	assert(link and link.onClick, Texts(lines))
	w:As(king, link.onClick)
	eq(T.mode, "rules")
	lines = w:As(king, T.Build)
	local prose = Texts(lines):gsub("\n", " ")
	assert(prose:find("The King, his Stewards and the keepers", 1, true), prose)
	w:As(king, assert(Find(lines, "ranking-rules-back")).onClick)
	eq(T.mode, "summary", "Back restores the exact Treasury page")

	lines = w:As(king, T.Build)
	w:As(king, assert(Find(lines, "ranking-rules:treasury-donors")).onClick)
	local maySee = T.MaySee
	T.MaySee = function() return false end
	lines = w:As(king, T.Build)
	eq(T.mode, "summary", "a stale private rules page is closed")
	eq(Find(lines, "ranking-rules-back"), nil)
	eq(Find(lines, "ranking-rules:treasury-donors"), nil, "the link is gated too")
	T.MaySee = maySee
	rawset(king.ns, "Bank", nil)
	for _, e in ipairs(king.errors) do error(e, 2) end
end)

test("1.2.4 ranking rules: private guild-treasury rules preserve Back and revalidate their audience", function()
	local w = World.New()
	local king = w:Role("king")
	local T, inherited = king.ns.Treasury, king.ns.Bank
	local visible = true
	local snapshot = { guild = "Olympus Ash", by = "Aster Keeper-Emberfall", t = w.clock, money = 25000,
		tabs = { { i = 1, name = "Tab 1", items = {} } } }
	local fake = setmetatable({
		SISTER_OLD = 7 * 86400, SLOTS = 98,
		SeesSisters = function() return visible end,
		Current = function() return nil end, Own = function() return nil end,
		Sisters = function() return { snapshot } end,
		Index = function() return { units = 0, stacks = 0 } end,
		Value = function() return { value = 5000, pending = 0, unpriced = 0 } end,
		Correspondent = function() return "Corin Vale-Emberfall", true end,
		PriceAsks = function() end, HasAPI = function() return true end,
		Requests = function() return {} end, PublicRequests = function() return {} end,
		MyRequests = function() return {} end, MayRequest = function() return false end,
	}, { __index = inherited })
	rawset(king.ns, "Bank", fake)
	w:As(king, T.Show, "summary")
	T.sisterTab = 3
	local lines = w:As(king, T.Build)
	local link = Find(lines, "ranking-rules:treasury-guilds")
	assert(link and link.onClick, Texts(lines))
	w:As(king, link.onClick)
	lines = w:As(king, T.Build)
	eq(lines[1].id, "ranking-rules-back")
	w:As(king, lines[1].onClick)
	eq(T.mode, "summary")
	eq(T.sisterTab, 3, "Back restores the exact directory state")

	lines = w:As(king, T.Build)
	w:As(king, assert(Find(lines, "ranking-rules:treasury-guilds")).onClick)
	visible = false
	lines = w:As(king, T.Build)
	eq(T.mode, "summary", "loss of the private audience closes the page")
	eq(Find(lines, "ranking-rules-back"), nil)
	eq(Find(lines, "ranking-rules:treasury-guilds"), nil)
	rawset(king.ns, "Bank", nil)
	for _, e in ipairs(king.errors) do error(e, 2) end
end)

test("1.2.4 ranking rules: Craft fee rules share the page, preserve Back, and fail closed after access loss", function()
	local w = World.New()
	local king = w:Role("king")
	rawset(king.ns, "UI", false)
	w:As(king, function() assert(loadfile(H.ADDON_DIR .. "CraftRequests.lua"))("Olympus", king.ns) end)
	local R, L, C = king.ns.CraftRequests, king.ns.L, king.ns.Compliance
	w:As(king, R.Reset)
	local lines = w:As(king, R.BoardLines)
	local fees
	for _, line in ipairs(lines) do
		for _, item in ipairs(line.nav or {}) do if item.text == L.CRAFT_BOARD_FEES then fees = item end end
	end
	assert(fees and fees.onClick, Texts(lines))
	w:As(king, fees.onClick)
	lines = w:As(king, R.BoardLines)
	local link = Find(lines, "ranking-rules:craft-debtors")
	assert(link and link.onClick, Texts(lines))
	w:As(king, link.onClick)
	lines = w:As(king, R.BoardLines)
	eq(lines[1].id, "ranking-rules-back")
	w:As(king, lines[1].onClick)
	lines = w:As(king, R.BoardLines)
	assert(Find(lines, "ranking-rules:craft-debtors"), "Back restores the fees page")

	w:As(king, assert(Find(lines, "ranking-rules:craft-debtors")).onClick)
	local wallet = C.Wallet
	C.Wallet = function() return false end
	lines = w:As(king, R.BoardLines)
	eq(Find(lines, "ranking-rules-back"), nil, "access loss closes the private rules")
	eq(Find(lines, "ranking-rules:craft-debtors"), nil)
	for _, line in ipairs(lines) do
		for _, item in ipairs(line.nav or {}) do assert(item.text ~= L.CRAFT_BOARD_FEES, "the private entry point is gated") end
	end
	C.Wallet = wallet
	w:As(king, R.Reset)
	for _, e in ipairs(king.errors) do error(e, 2) end
end)
