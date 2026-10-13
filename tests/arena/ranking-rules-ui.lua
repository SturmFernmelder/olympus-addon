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
		w:As(king, lines[1].onClick)
		eq(king.ns.ArenaHome.rulesKey, nil)
		eq(king.ns.ArenaHome.rankGame, case.game, "Back restores the exact game ranking")
	end
	for _, e in ipairs(king.errors) do error(e, 2) end
end)
