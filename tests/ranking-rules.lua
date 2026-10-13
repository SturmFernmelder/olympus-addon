-- 1.2.4: every actual ranking explains its live rules inside the main Olympus window.
local ns, test, eq = ...
local Rules, L = ns.RankingRules, ns.L

local function Find(lines, id)
	for _, line in ipairs(lines or {}) do if line.id == id then return line end end
end
local function Texts(lines)
	local out = {}
	for _, line in ipairs(lines or {}) do if line.text then out[#out + 1] = line.text end end
	return table.concat(out, "\n")
end

test("1.2.4 ranking rules: the reusable link and native page recheck access, keep Back, and resolve live values only when drawn", function()
	local allowed, value, opened, backed = false, 7, 0, 0
	assert(Rules.Register("test-dynamic", {
		title = "Dynamic ranking",
		icon = "Interface\\Icons\\INV_Misc_Book_09",
		allowed = function() return allowed end,
		sections = function()
			return { { topic = "score", text = "Live value " .. value }, { topic = "order", text = "Higher first" } }
		end,
	}))
	eq(Rules.Link("test-dynamic", function() opened = opened + 1 end), nil, "private ranking has no discoverable link")
	eq(Rules.Lines("test-dynamic", function() backed = backed + 1 end), nil, "stale callback cannot open private rules")
	allowed = true
	local link = Rules.Link("test-dynamic", function() opened = opened + 1 end)
	eq(link.id, "ranking-rules:test-dynamic")
	assert(link.text:find(L.RANK_RULES_LINK, 1, true), link.text)
	link.onClick(); eq(opened, 1)
	local lines = Rules.Lines("test-dynamic", function() backed = backed + 1 end)
	eq(lines[1].id, "ranking-rules-back")
	assert(Texts(lines):find("Live value 7", 1, true), Texts(lines))
	value = 11
	lines = Rules.Lines("test-dynamic", function() backed = backed + 1 end)
	assert(Texts(lines):find("Live value 11", 1, true), Texts(lines))
	lines[1].onClick(); eq(backed, 1)
	allowed = false
	eq(Rules.Lines("test-dynamic", function() end), nil, "authority is checked again on the page")
end)

test("1.2.4 ranking rules: long prose is split into native renderer rows instead of clipping", function()
	local paragraph = "This deliberately long explanation has enough ordinary words to cross the native list width more than once while preserving every word in its original order for the reader."
	assert(Rules.Register("test-wrapping", {
		title = "Wrapped ranking",
		sections = function() return { { topic = "score", text = paragraph } } end,
	}))
	local lines = Rules.Lines("test-wrapping", function() end)
	local rows = {}
	for _, line in ipairs(lines) do
		if line.indent == 1 then
			rows[#rows + 1] = line.text
			assert(#line.text <= Rules.WRAP, "renderer row exceeds the shared prose width: " .. line.text)
		end
	end
	assert(#rows >= 3, "the renderer received one clipping row instead of several native rows")
	eq(table.concat(rows, " "), paragraph, "wrapping preserves the explanation")
end)

test("1.2.4 ranking rules: real integrations register only actual rankings and Realm Back restores the exact prior page", function()
	for _, key in ipairs({ "treasury-donors", "treasury-guilds", "realm-level", "craft-debtors" }) do
		assert(Rules.Spec(key), "missing ranking rules: " .. key)
	end
	for _, key in ipairs({ "lottery", "justice", "census", "honours" }) do
		eq(Rules.Spec(key), nil, "not a fabricated ranking: " .. key)
	end
	local allowed = true
	Rules.Register("test-realm", { title = "Realm rules", allowed = function() return allowed end,
		sections = function() return { { topic = "evidence", text = "Local evidence" } } end })
	local pages = ns.RealmPages
	pages[#pages + 1] = { key = "test-source", Lines = function() return {} end }
	ns.Views.ShowPage("test-source")
	eq(ns.Views.PageShown(), "test-source")
	assert(Rules.OpenRealm("test-realm"))
	eq(ns.Views.PageShown(), "ranking-rules")
	local lines = Rules.RealmLines()
	local back = Find(lines, "ranking-rules-back")
	assert(back and back.onClick, "native Back")
	back.onClick()
	eq(ns.Views.PageShown(), "test-source", "the exact prior Realm page")
	table.remove(pages)
	Rules.ResetForTests()
end)
