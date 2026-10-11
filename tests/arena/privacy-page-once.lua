-- 1.2.1 (a player's report: "The popups are becoming annoying. How many times do I need to update my
-- settings?"): the privacy page (Consent.lua) opens by itself once for each question, never at every
-- login for a line left unanswered. A line the page showed counts as asked in the saved data, so a
-- new session (the world's Logout and Login: the files load again, OlympusDB kept) does not open it
-- again; the Most Wanted sightings line (explicit: Accept all never answers it) included. /oly
-- privacy still shows every line. Every name is invented.
local H = ...
local test, eq, World = H.test, H.eq, H.World

local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end

-- The real Most Wanted sightings line (Wanted.lua registers it on the page as it loads), loaded
-- into the client after the world's modules, as the TOC has it after Consent.lua.
local function LoadWanted(w, c)
	w:As(c, function() assert(loadfile(H.ADDON_DIR .. "Wanted.lua"))("Olympus", c.ns) end)
end
local function Relog(w, c)
	w:Logout(c)
	w:Login(c)
	LoadWanted(w, c)
end
local function Keys(list)
	local out = {}
	for _, item in ipairs(list) do out[#out + 1] = item.key end
	table.sort(out)
	return table.concat(out, ",")
end

test("1.2.1 privacy page: closed with lines unanswered, it never opens by itself again at the next logins; /oly privacy still shows them, off", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Client("Lida Fenn")
	LoadWanted(w, a)
	local C = a.Consent
	assert(C.Pending()[1], "lines wait for an answer on a fresh install")
	eq(C.Waiting(), true)
	w:Run(C.LOGIN_WAIT + 1)
	local page = C.Frame()
	assert(page and page:IsShown(), "the first login: the page asks")
	page:Hide() -- (the X: nothing answered)
	local waiting = Keys(C.Pending())
	assert(waiting:find("wantedsightings", 1, true), "the sightings line among them: " .. waiting)
	eq(C.Ask("window"), false, "this session: not again")
	for session = 2, 4 do
		Relog(w, a)
		C = a.Consent
		eq(Keys(C.Pending()), waiting, "session " .. session .. ": the same lines still unanswered")
		eq(C.Waiting(), false, "session " .. session .. ": nothing new to ask (the version letter need not wait)")
		w:Run(C.LOGIN_WAIT + 125)
		eq(C.Frame(), nil, "session " .. session .. ": the page does not open by itself")
		eq(C.Ask("window"), false, "nor when the window opens")
		eq(C.Ask("location"), false, "nor for the 1.0 location question")
	end
	-- Unanswered stays off; the player opens the page when he wants.
	eq(C.Answer("inspection"), nil)
	page = C.Show()
	eq(page:IsShown(), true, "/oly privacy: the page, every line on it")
	page:Hide()
	NoErrors(w)
end)

test("1.2.1 privacy page: Accept all counts as asked for the Most Wanted sightings line: it stays off and unanswered, and the page never opens by itself for it again", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Client("Parric Stowe")
	LoadWanted(w, a)
	local C = a.Consent
	-- (The zone and layer's lines: their modules are not in the test world; his answers of 1.1.)
	a.db.shareLocation, a.db.layerHelp = false, false
	eq(C.Ask("login"), true, "the page asks")
	eq(C.AuthorizePending(), true, "Accept all")
	eq(C.Frame():IsShown(), false, "closed")
	eq(a.db.wantedSightings, nil, "the sightings line: never answered by the bulk Yes")
	eq(Keys(C.Pending()), "wantedsightings", "it alone still waits")
	for session = 2, 3 do
		Relog(w, a)
		C = a.Consent
		eq(Keys(C.Pending()), "wantedsightings")
		eq(C.Waiting(), false, "session " .. session)
		w:Run(C.LOGIN_WAIT + 125)
		eq(C.Frame(), nil, "session " .. session .. ": the page does not open by itself for it")
		eq(a.db.wantedSightings, nil, "still off")
	end
	-- Its own Yes, any time from the page.
	C.Show()
	eq(C.Choose("wantedsightings", true), true)
	eq(a.db.wantedSightings, true)
	NoErrors(w)
end)

test("1.2.1 privacy page: a question the page never showed still opens it once (a member who answered every line before), then never again", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Client("Wenna Crale")
	LoadWanted(w, a)
	local C = a.Consent
	-- Every line answered, as a member before the sightings line came (1.2.0).
	for _, item in ipairs(C.Pending()) do
		if item.key ~= "wantedsightings" then C.Choose(item.key, false) end
	end
	a.db.shareLocation, a.db.layerHelp = false, false
	eq(Keys(C.Pending()), "wantedsightings", "only the new line waits")
	eq(C.Ask("login"), true, "a new question: the page, once")
	C.Frame():Hide()
	Relog(w, a)
	C = a.Consent
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "asked once: not at the next login")
	-- A changed question (its version) is a new one: asked once more.
	local version = 1
	assert(C.Register({ key = "test-versioned", label = "A test line", text = "A versioned question.",
		get = function() return nil end, set = function() end, version = function() return version end }))
	eq(C.Ask("login"), true, "the new line: asked")
	C.Frame():Hide()
	eq(C.Ask("login"), false)
	version = 2
	eq(C.Ask("login"), false, "this session it was on the page")
	Relog(w, a)
	C = a.Consent
	assert(C.Register({ key = "test-versioned", label = "A test line", text = "A versioned question.",
		get = function() return nil end, set = function() end, version = function() return version end }))
	eq(C.Ask("login"), true, "its new version: asked once")
	C.Frame():Hide()
	Relog(w, a)
	C = a.Consent
	assert(C.Register({ key = "test-versioned", label = "A test line", text = "A versioned question.",
		get = function() return nil end, set = function() end, version = function() return version end }))
	eq(C.Ask("login"), false, "then never again")
	-- An answer kept per character (a keeper's book): asked once for each character of the account.
	assert(C.Register({ key = "test-own", label = "A test line", text = "A character's own question.",
		get = function() return nil end, set = function() end, perCharacter = true }))
	eq(C.Ask("login"), true, "this character: asked")
	C.Frame():Hide()
	Relog(w, a)
	C = a.Consent
	local function Own()
		return C.Register({ key = "test-own", label = "A test line", text = "A character's own question.",
			get = function() return nil end, set = function() end, perCharacter = true })
	end
	assert(Own())
	eq(C.Ask("login"), false, "this character, the next login: not again")
	local me = a.ns.me
	a.ns.me = "Wenna Alt-Emberfall" -- (another character on the same saved data)
	eq(C.Ask("login"), true, "another character: his own question, once")
	C.Frame():Hide()
	a.ns.me = me
	NoErrors(w)
end)

-- (Review: the arena bank's yes is kept per character, but the page's record of asking it was the
-- account's: one bank character asked, the account's others never were by themselves.)
test("1.2.1 privacy page: the arena bank's line is asked once on each bank character of the account", function()
	local w = World.New()
	local king = w:Role("king")
	local bank = w:Role("bank")
	LoadWanted(w, bank)
	local other = "Coffrey Strongbox-Emberfall" -- (another bank character on the same saved data)
	w:As(king, function()
		assert(king.ns.ArenaRoles.SetSettings({ live = 1 }))
		assert(king.ns.ArenaRoles.SetBanks({ World.NAMES.bank, other }))
	end)
	w:Run(0)
	-- (A third character of the account answered before: Wallet.lua's book of the bank's yeses.)
	bank.db.arenaBankYes = { ["coffrey hoard-emberfall"] = true }
	local C = bank.Consent
	local function Waits()
		for _, item in ipairs(C.Pending()) do if item.key == "arenabank" then return true end end
		return false
	end
	eq(Waits(), true, "the bank's line waits for this character's answer")
	eq(C.Ask("login"), true, "this bank character: the page asks")
	C.Frame():Hide()
	Relog(w, bank)
	C = bank.Consent
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "the next login: not again")
	bank.ns.me = other
	eq(Waits(), true, "the other bank character's own answer waits")
	eq(C.Ask("login"), true, "the other bank character: asked once")
	eq(C.Choose("arenabank", false), true)
	C.Frame():Hide()
	eq(bank.db.arenaBankYes[World.NAMES.bank:lower()], nil, "the first one's: still unanswered, off")
	eq(C.Ask("login"), false)
	NoErrors(w)
end)

-- (Review: a new tabard contract drops both answers, but with the page's record kept for good the
-- lines were never asked again by themselves: off, unseen.)
test("1.2.1 privacy page: a new tabard contract asks its two lines once more", function()
	local w = World.New({ compliance = "shipped" })
	local a = w:Client("Lida Fenn")
	local function LoadTabards(contract)
		w:As(a, function()
			assert(loadfile(H.ADDON_DIR .. "TabardsV2.lua"))("Olympus", a.ns)
			if contract then a.ns.TabardsV2.CONTRACT = contract end
		end)
	end
	LoadTabards()
	local C = a.Consent
	a.db.shareLocation, a.db.layerHelp = false, false
	eq(C.Ask("login"), true, "the first login: the page")
	for _, item in ipairs(C.Pending()) do C.Choose(item.key, true) end
	C.Frame():Hide()
	eq(a.ns.TabardsV2.Consent("self"), true); eq(a.ns.TabardsV2.Consent("nearby"), true)
	eq(Keys(C.Pending()), "", "every line answered")
	-- A later build with a new contract: its lines lose their answer.
	local contract = a.ns.TabardsV2.CONTRACT + 1
	w:Logout(a); w:Login(a); LoadTabards(contract)
	C = a.Consent
	eq(Keys(C.Pending()), "tabardnearbyv2,tabardselfv2", "the new contract's lines wait")
	eq(C.Waiting(), true)
	eq(C.Ask("login"), true, "asked once more")
	C.Frame():Hide()
	w:Logout(a); w:Login(a); LoadTabards(contract)
	C = a.Consent
	w:Run(C.LOGIN_WAIT + 125)
	eq(C.Frame(), nil, "then not again for that contract")
	NoErrors(w)
end)
