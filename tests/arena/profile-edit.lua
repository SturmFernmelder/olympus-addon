-- 1.2, the fights part: the profile (ArenaProfile.lua) and its Edit in the core window (ProfileEdit.lua), on the
-- test world: the pickers, the view model, "preview as others see me", the person card's rows.
-- 1.2.4: the Edit is "My profile", the player's own person page in the Olympus window (its sections,
-- the icon picker inline, no window of its own); the window is stood in (W3.PageUI).
-- Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local function PE(w, c) return W3.M(w, c, "ProfileEdit") end
local function Prof(w, c) return W3.M(w, c, "ArenaProfile") end

-- The global belt won by `winner` in a public title fight (the core's title fights).
local function Belt(w, cast, winner, loser, to)
	local A = cast.arbiter.ns.Arena
	local e = table.concat({ "1", "Fzz" .. winner.short:sub(1, 1):lower(), A.B36(w.clock - 600), "A", "1", A.GK(winner.guid), winner.short, "-",
		A.GK(loser.guid), loser.short, "-", "1:0", "A", "K", "3c", A.GK(cast.arbiter.guid), "prtb" }, "~")
	for _, c in ipairs(to) do w:As(c, function() c.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AE~L1~" .. e) end) end
end

print("ProfileEdit: the Edit in the core window")

test("1.2 the fights part: with the live switch off and the companion not loaded, a frame and a title picked in the Edit change the pick and the profile goes out (AP)", function()
	-- (The belt won while the switch was on: an L entry is refused while it is off.)
	local w, cast = W3.New()
	local A = cast.A
	Belt(w, cast, A, cast.B, { A, cast.spectator })
	W3.Live(w, cast.king, { live = 0 })
	w:Run(3)
	eq(A.ns.ArenaRoles.Live(), false); eq(A.companion.loaded, nil)
	local before = #w:Sent{ from = A, type = "AP" }
	eq(PE(w, A).PickFrame("none"), true)
	w:Run(0)
	eq(A.ns.ArenaProfile.Pick().frame, "none")
	eq(#w:Sent{ from = A, type = "AP", dist = "CHANNEL" }, before + 1, "sent in L whatever the live switch")
	eq(PE(w, A).PickFrame("arena-champion"), true)
	eq(PE(w, A).PickTitle("none"), true)
	w:Run(0)
	local pick = A.ns.ArenaProfile.Pick()
	eq(pick.frame, "arena-champion"); eq(pick.title, nil)
	eq(PE(w, A).PickTitle("arena-champion"), true)
	w:Run(0)
	-- What a viewer sees: the same pick, verified.
	local v = w:As(cast.spectator, cast.spectator.ns.HonorsNet.Verified, A.name, A.guid)
	eq(v.frame, "arena-champion"); eq(v.title, "arena-champion")
	eq(A.companion.loaded, nil, "the companion still not loaded")
	-- A frame he does not hold: refused, the pick unchanged.
	local ok, why = PE(w, A).PickFrame("oracle-1")
	eq(ok, false); eq(why, "frame")
	W3.NoErrors(w)
end)

test("1.2 the fights part: the Edit's view model: the rank's frame, none, every frame held; none and every title held; the nickname from the lists; 'preview as others see me' is what a viewer's Verified shows", function()
	local w, cast = W3.New()
	local A = cast.A
	Belt(w, cast, A, cast.B, { A })
	w:Run(3)
	local vm = PE(w, A).ViewModel()
	eq(vm.frames[1].key, "rank"); eq(vm.frames[2].key, "none")
	eq(vm.frames[3].key, "arena-champion"); eq(vm.frames[3].art, "gryphon-gold"); eq(vm.frames[3].shape, "winged")
	eq(vm.frames[3].selected, true, "switched on when earned")
	eq(vm.titles[1].key, "none"); eq(vm.titles[2].label, "Arena Champion")
	eq(vm.preview.frame, "arena-champion"); eq(vm.preview.titleText, "Arena Champion")
	eq(vm.preview.frameTexture, "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold")
	eq(vm.preview.markTexture, "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold-mark")
	eq(#vm.letters, 1, "the King's letter, to read again")
	-- The nickname: a step through each list, words only from them.
	eq(PE(w, A).NickStep("a", 1), true)
	eq(PE(w, A).NickStep("n", 1), true)
	vm = PE(w, A).ViewModel()
	eq(vm.nick.a, 1); eq(vm.nick.n, 2); eq(vm.nick.text, "the Unbroken Hammer", "the first epithet (a list stepped from none takes both firsts), then the next beast")
	eq(Prof(w, A).SetNick(33, 1), false, "past the list")
	eq(Prof(w, A).NickText("0.0"), nil); eq(Prof(w, A).NickText("32.32"), "the Last Murloc"); eq(Prof(w, A).NickText("x.1"), nil)
	-- The emblem: the game's icons only (ns.CouncilIconValue).
	eq(PE(w, A).Emblem("Spell_Holy_SealOfMight"), true)
	eq(PE(w, A).Emblem("bad|name"), false)
	eq(A.ns.ArenaProfile.Mine().emblem, "Spell_Holy_SealOfMight")
	-- The history switch: its Consent line (unanswered is private).
	eq(PE(w, A).ViewModel().pub, false)
	eq(PE(w, A).SetPublic(true), true)
	eq(A.ns.ArenaProfile.Mine().pub, true)
	eq(w:As(A, A.ns.Consent.Answer, "arenaHistory"), true)
	local historyItem
	for _, item in ipairs(w:As(A, A.ns.Consent.Items, "profile")) do if item.key == "arenaHistory" then historyItem = item end end
	assert(historyItem, "the real history choice is reachable in the Profile section")
	eq(w:As(A, historyItem.shown), true, "the real history choice is visible")
	local beforeRevoke = #w:Sent{ from = A, type = "AP" }
	local revoked = w:As(A, A.ns.Consent.Choose, "arenaHistory", false)
	eq(A.ns.ArenaProfile.Mine().pub, false, "the registered setter ran")
	eq(revoked, true, "the privacy page uses the real setter")
	w:Run(0)
	eq(A.ns.ArenaProfile.Mine().pub, false, "No revokes history sharing")
	eq(w:As(A, A.ns.Consent.Answer, "arenaHistory"), false)
	eq(#w:Sent{ from = A, type = "AP" }, beforeRevoke + 1, "revocation publishes the changed profile word")
	W3.NoErrors(w)
end)

print("ProfileEdit: My profile, the player's own page in the Olympus window (1.2.4)")

-- The page as PlayerProfile.Build hands it on his own (the Olympus window stood in: W3.PageUI):
-- its lines, the detail box's title and text, its buttons and the portrait's art.
local function Page(w, c, facts) return w:As(c, c.ns.ProfileEdit.Page, { full = c.name }, facts or {}) end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- The first line whose words (colours aside) are, or begin with, `text`; and its index.
local function Line(lines, text, from)
	for i = from or 1, #lines do
		local t = Plain(lines[i].text)
		if t == text or t == "> " .. text or t:sub(1, #text) == text then return lines[i], i end
	end
	return nil
end
local function Printed(c, text)
	for _, m in ipairs(c.printed) do if tostring(m):find(text, 1, true) then return true end end
	return false
end
-- A window of its own on that client: a frame made with one of these names.
local function Windows(c, names)
	local found = {}
	for _, x in ipairs(c.frames) do
		local name = type(x.frame) == "table" and x.frame.GetName and x.frame:GetName() or nil
		if name and names[name] then found[#found + 1] = name end
	end
	return table.concat(found, ",")
end
local NO_WINDOWS = { OlympusProfileEdit = true, OlympusCouncilIconFrame = true, OlympusArenaPreview = true, OlympusArenaLetters = true }
local function MacroIcons(c, n)
	local calls = { n = 0 }
	c.globals.GetMacroIcons = function(t)
		calls.n = calls.n + 1
		for i = 1, n or 60 do t[#t + 1] = 200000 + i end
		t[#t + 1] = "Spell_Holy_SealOfMight"
	end
	return calls
end

-- The owner's screenshot (1.2.2/1.2.3): the Games window's Profile, More, Edit, Emblem stacked three
-- windows (the Games window, the floating Edit panel at DIALOG strata, the picker it hosted, spilling
-- 54 px right and 122 down, with the council's words on an emblem). Fails on 1.2.3: the panel is
-- made (OlympusProfileEdit) and the Olympus window is never asked for his page.
test("1.2.4 My profile (the three stacked windows): Edit opens the player's own person page in the Olympus window (UI.OpenPlayerProfile on himself), no window of its own: no Edit panel, no picker window, nothing on the escape list; no game popup in the core's arena files", function()
	local w, cast = W3.New()
	local A = cast.A
	Belt(w, cast, A, cast.B, { A })
	w:Run(3)
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	MacroIcons(A)
	local ui = W3.PageUI(w, A)
	local special = #(A.globals.UISpecialFrames or {})
	eq(PE(w, A).Open(), true)
	eq(#ui.opened, 1, "the window's person page, once")
	local p = ui.opened[1]
	eq(w:As(A, A.ns.Fold, A.ns.FullName(p.name, p.realm)), w:As(A, A.ns.Fold, A.name), "on himself")
	eq(ui.OwnProfileShown(), true); eq(PE(w, A).PageShown(), true)
	eq(PE(w, A).Section(), "look")
	eq(PE(w, A).Open("emblem"), true, "the emblem's picker too")
	eq(PE(w, A).Section(), "icons")
	eq(Windows(A, NO_WINDOWS), "", "no window of its own")
	eq(rawget(A.ns.ProfileEdit, "frame"), nil)
	eq(#(A.globals.UISpecialFrames or {}), special, "nothing on the escape list")
	-- The chat icon's list: his honour's mark first. (The emblem's is the game's icons only: an
	-- emblem is a game icon on both ends, the design, so no honour mark is offered there; review.)
	local list = PE(w, A).IconList("icon")
	eq(type(list[1]), "table"); eq(list[1].key, "gryphon-gold"); eq(list[1].texture, "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold-mark")
	for _, icon in ipairs(PE(w, A).IconList("emblem")) do eq(type(icon) ~= "table", true, "no honour mark as an emblem") end
	-- No game popup anywhere in the core's arena files (the source rule).
	for _, f in ipairs({ "ProfileEdit", "HonorsNet", "ArenaProfile", "ArenaFights", "ArenaLedger", "ArenaTourney" }) do
		local src = io.open(H.ADDON_DIR .. f .. ".lua"):read("*a"):gsub("%-%-[^\n]*", "")
		assert(not src:find("StaticPopup", 1, true), f)
		assert(not src:find("UISpecialFrames", 1, true), f)
	end
	-- Not in an Olympus guild: refused, nothing opened.
	local member = A.ns.IsMember
	A.ns.IsMember = function() return false end
	eq(select(2, PE(w, A).Open()), "guild"); eq(#ui.opened, 2, "nothing opened")
	A.ns.IsMember = member
	W3.NoErrors(w)
end)

-- 1.2.3's /oly arena emblem opened the panel without its picker (Open took "icon" alone). Fails on 1.2.3.
test("1.2.4 My profile (/oly arena emblem landed without the picker): Open('emblem') opens the Icons section on the emblem; Open('icon') a councillor's chat icon, Look for anyone else; /oly arena emblem and the arena's action land there", function()
	local w, cast = W3.New({ more = { { "hc", N.councillor } } })
	local A, hc = cast.A, cast.hc
	MacroIcons(A); MacroIcons(hc)
	W3.PageUI(w, A); W3.PageUI(w, hc)
	eq(PE(w, A).Open("emblem"), true)
	local s, kind = PE(w, A).Section()
	eq(s, "icons"); eq(kind, "emblem")
	eq(#PE(w, A).Icons().list, 61, "the game's icons")
	eq(PE(w, A).Open("icon"), true)
	eq(PE(w, A).Section(), "look", "no councillor: Look")
	eq(PE(w, hc).Open("icon"), true)
	s, kind = PE(w, hc).Section()
	eq(s, "icons"); eq(kind, "icon")
	eq(PE(w, hc).Icons().kind, "icon")
	-- The slash and the action.
	PE(w, A).SetSection("look")
	w:As(A, function() A.slashes.OLYMPUS("arena emblem") end)
	s, kind = PE(w, A).Section()
	eq(s, "icons", "/oly arena emblem"); eq(kind, "emblem")
	PE(w, A).SetSection("look")
	eq(w:As(A, A.ns.Arena.Do, "profile.edit", "emblem"), true)
	eq(PE(w, A).Section(), "icons", "Arena.Action('profile.edit')")
	W3.NoErrors(w)
end)

test("1.2.4 My profile, Look: the section strip first (page chrome); a row per frame held, the one others see marked; a click picks it, one AP goes out and another client's Verified follows; the titles the same; the nickname's two strips step through the fixed lists; the lock", function()
	local w, cast = W3.New()
	local A, viewer = cast.A, cast.spectator
	Belt(w, cast, A, cast.B, { A, viewer })
	w:Run(3)
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	W3.PageUI(w, A)
	eq(PE(w, A).Open(), true)
	local lines, title, text, buttons, art = Page(w, A)
	eq(lines[1].pageNav, true, "the section strip, page chrome"); eq(#lines[1].nav, 4); eq(lines[1].nav[1].selected, true)
	eq(lines[1].nav[1].text, A.ns.L.MYPROFILE_NAV_LOOK); eq(lines[1].nav[4].text, A.ns.L.MYPROFILE_NAV_LETTERS:format(1))
	eq(title, A.ns.L.MYPROFILE_SEEN_TITLE)
	eq(text, A.ns.L.MYPROFILE_SEEN_TEXT:format("Arena Champion", A.ns.L.MYPROFILE_NONE_WORD))
	eq(art.frame, "arena-champion", "the portrait's frame: the one others see")
	eq(buttons[1][1], "PLAYER_PROFILE_BACK"); eq(buttons[2][1], "MYPROFILE_GAMES_PROFILE")
	-- The frames: one row each, in the view model's order, the one shown marked.
	local vm = PE(w, A).ViewModel()
	local head, at = Line(lines, A.ns.L.MYPROFILE_FRAME_HEAD)
	eq(head.header, true); eq(head.right, "Arena Champion", "what shows")
	for i, x in ipairs(vm.frames) do
		local row = lines[at + i]
		eq((Plain(row.text):gsub("^> ", "")), x.label)
		eq(Plain(row.text):sub(1, 2) == "> ", x.shows == true, x.key .. ": marked when shown")
		eq(type(row.onClick), "function", x.key)
	end
	-- A click on "No frame": the pick, one AP, the viewer's Verified (a minute after the last word).
	w:Run(A.ns.ArenaProfile.RATE_CHANGED + 1)
	local before = #w:Sent{ from = A, type = "AP" }
	w:As(A, Line(lines, A.ns.L.PROFILE_FRAME_NONE, at).onClick)
	w:Run(0)
	eq(A.ns.ArenaProfile.Pick().frame, "none")
	eq(#w:Sent{ from = A, type = "AP" }, before + 1, "one AP")
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, A.name, A.guid).frame, "none", "the viewer sees it")
	lines = Page(w, A)
	head = Line(lines, A.ns.L.MYPROFILE_FRAME_HEAD)
	eq(head.right, A.ns.L.PROFILE_FRAME_NONE)
	eq(Plain(Line(lines, A.ns.L.PROFILE_FRAME_NONE).text), "> " .. A.ns.L.PROFILE_FRAME_NONE)
	-- The titles: "No title" picked, the same way.
	w:Run(A.ns.ArenaProfile.RATE_CHANGED + 1)
	local _, tat = Line(lines, A.ns.L.MYPROFILE_TITLE_HEAD)
	w:As(A, Line(lines, A.ns.L.PROFILE_TITLE_NONE, tat).onClick)
	w:Run(0)
	eq(A.ns.ArenaProfile.Pick().title, nil)
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, A.name, A.guid).title, nil)
	lines, _, text = Page(w, A)
	eq(text, A.ns.L.MYPROFILE_SEEN_TEXT:format(A.ns.L.PROFILE_TITLE_NONE, A.ns.L.MYPROFILE_NONE_WORD))
	-- The nickname: two strips of the fixed lists (< word >), each arrow one step.
	local _, nat = Line(lines, A.ns.L.MYPROFILE_NICK_HEAD)
	local epithet, beast = lines[nat + 1].nav, lines[nat + 2].nav
	eq(#epithet, 3); eq(epithet[2].text, A.ns.L.MYPROFILE_EPITHET:format(A.ns.L.MYPROFILE_NONE_WORD)); eq(epithet[2].onClick, nil)
	w:As(A, epithet[3].onClick)
	w:As(A, beast[3].onClick)
	lines = Page(w, A)
	eq(lines[nat + 1].nav[2].text, A.ns.L.MYPROFILE_EPITHET:format(A.ns.L.ARENA_EPI_A[1]))
	eq(lines[nat + 2].nav[2].text, A.ns.L.MYPROFILE_BEAST:format(A.ns.L.ARENA_EPI_N[2]))
	eq(Line(lines, A.ns.L.MYPROFILE_NICK_HEAD).right, "the Unbroken Hammer")
	-- A step is the side clicked alone, wrapping within its list; the other word stays, and each AP
	-- carries the nickname. (The branch's first page wrapped a list through none: the nickname gone,
	-- an AP without it, and the other word then replaced by its first or last. Fails there: "back
	-- from the first word" gave no nickname, and a lap of the epithets from "3.7" ended "1.1".)
	local function SentNick()
		w:Run(0)
		local sent = w:Sent{ from = A, type = "AP" }
		local fields = {}
		for f in (sent[#sent].msg .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = f end
		return fields[8]
	end
	local clear = lines[nat + 3]
	eq(Plain(clear.text), A.ns.L.MYPROFILE_NICK_NONE, "No nickname: its own row, under the strips"); eq(type(clear.onClick), "function")
	w:As(A, lines[nat + 1].nav[1].onClick)
	eq(A.ns.ArenaProfile.Mine().nick, "32.2", "back from the first epithet: the last one, the beast kept"); eq(SentNick(), "32.2")
	w:As(A, lines[nat + 1].nav[3].onClick)
	eq(A.ns.ArenaProfile.Mine().nick, "1.2", "past the last epithet: the first"); eq(SentNick(), "1.2")
	-- The review's case: "3.7", a whole lap of the epithets with '>': the beast stays 7, every AP
	-- carries a nickname, and the lap ends where it began.
	local size = A.ns.ArenaProfile.EPITHETS
	eq(Prof(w, A).SetNick(3, 7), true)
	for i = 1, size do
		w:As(A, lines[nat + 1].nav[3].onClick)
		local want = ("%d.7"):format((3 + i - 1) % size + 1)
		eq(A.ns.ArenaProfile.Mine().nick, want, "step " .. i); eq(SentNick(), want, "step " .. i .. ": its AP")
	end
	eq(A.ns.ArenaProfile.Mine().nick, "3.7", "a lap: back where he was")
	-- The beast's '<' from its first word: the last beast, the epithet kept; '>' back.
	eq(Prof(w, A).SetNick(3, 1), true)
	w:As(A, lines[nat + 2].nav[1].onClick)
	eq(A.ns.ArenaProfile.Mine().nick, "3.32", "back from the first beast: the last one, the epithet kept")
	w:As(A, lines[nat + 2].nav[3].onClick)
	eq(A.ns.ArenaProfile.Mine().nick, "3.1")
	-- No nickname: its row takes it away (one AP, without it); marked then, and no click.
	local sent = #w:Sent{ from = A, type = "AP" }
	w:As(A, clear.onClick)
	eq(A.ns.ArenaProfile.Mine().nick, nil, "No nickname"); eq(SentNick(), "0.0", "the AP says none")
	eq(#w:Sent{ from = A, type = "AP" }, sent + 1, "one AP")
	lines = Page(w, A)
	eq(Plain(lines[nat + 3].text), "> " .. A.ns.L.MYPROFILE_NICK_NONE, "marked"); eq(lines[nat + 3].onClick, nil, "none already: no click")
	eq(lines[nat + 1].nav[2].text, A.ns.L.MYPROFILE_EPITHET:format(A.ns.L.MYPROFILE_NONE_WORD))
	eq(Line(lines, A.ns.L.MYPROFILE_NICK_HEAD).right, A.ns.L.MYPROFILE_NONE_WORD)
	-- (From none, one step gives both sides a word: the last ones, stepping back.)
	w:As(A, lines[nat + 2].nav[1].onClick)
	eq(A.ns.ArenaProfile.Mine().nick, "32.32", "back from none: the last words")
	-- The emblem's row opens Icons; the lock's row keeps his pick.
	lines = Page(w, A)
	eq(Line(lines, A.ns.L.MYPROFILE_EMBLEM_HEAD).right, A.ns.L.MYPROFILE_NONE_WORD)
	local lock = Line(lines, A.ns.L.PROFILE_LOCK)
	w:As(A, lock.onClick)
	eq(A.ns.ArenaProfile.Mine().locked, true)
	eq(Plain(Line(Page(w, A), A.ns.L.PROFILE_LOCKED).text), A.ns.L.PROFILE_LOCKED)
	-- His honours.
	lines = Page(w, A)
	local _, hat = Line(lines, A.ns.L.PROFILE_HONOURS)
	eq(Plain(lines[hat + 1].text), "Arena Champion")
	-- No Council icon for anyone but a councillor.
	eq(Line(lines, A.ns.L.MYPROFILE_ICON_HEAD), nil)
	W3.NoErrors(w)
end)

-- 1.2.3 left a held frame this version does not wear out of the list, and 1.2.2 listed it as if
-- pickable (Honors.Choose refused it: a row "selected" while the portrait showed the rank's).
-- Fails on 1.2.3: the view model has no such entry (shipped is nil).
test("1.2.4 My profile, Look: a held frame not released in this version is listed grey, no click, 'comes in a later version'; once its family ships it picks", function()
	local w, cast = W3.New()
	local A = cast.A
	Belt(w, cast, A, cast.B, { A })
	w:Run(3)
	w:As(A, A.ns.HonorsNet.CloseLetter, false)
	local family
	for _, h in ipairs(A.ns.HonorsNet.Holdings(A.name)) do if h.frame == "arena-champion" then family = h.family or h.kind end end
	assert(family, "the belt's family")
	A.ns.Honors.FRAMES_SHIPPED = { ["donor-top"] = true }
	w:As(A, A.ns.Fire, "HONORS_CHANGED", A.name)
	W3.PageUI(w, A)
	eq(PE(w, A).Open(), true)
	local entry
	for _, x in ipairs(PE(w, A).ViewModel().frames) do if x.key == "arena-champion" then entry = x end end
	assert(entry, "listed")
	eq(entry.shipped, false); eq(entry.selected, false); eq(entry.shows, false)
	local lines = Page(w, A)
	local _, at = Line(lines, A.ns.L.MYPROFILE_FRAME_HEAD)
	local row = Line(lines, "Arena Champion", at)
	eq(row.onClick, nil, "no click")
	eq(Plain(row.right), A.ns.L.MYPROFILE_FRAME_LATER)
	eq(row.text, "|cff9d9d9d" .. "Arena Champion" .. "|r", "grey")
	-- Released (1.2.3's path for its frames): the row picks it.
	A.ns.Honors.FRAMES_SHIPPED[family] = true
	lines = Page(w, A)
	_, at = Line(lines, A.ns.L.MYPROFILE_FRAME_HEAD)
	row = Line(lines, "Arena Champion", at)
	eq(type(row.onClick), "function")
	w:As(A, row.onClick)
	eq(A.ns.ArenaProfile.Pick().frame, "arena-champion")
	eq(w:As(A, A.ns.HonorsNet.Verified, A.name).frame, "arena-champion", "and it shows")
	W3.NoErrors(w)
end)

test("1.2.4 My profile, Icons: the picker inline, the list built once per open (7 x 4 slots a page, at the icon in use), a slot's click only previews, Use this icon saves the emblem (one AP) and goes back to Look; a mark is no emblem; a councillor's mark picks its honour and drops his own icon; the filter finds a mark by its words", function()
	local w, cast = W3.New({ more = { { "hc", N.councillor } } })
	local A, hc = cast.A, cast.hc
	local calls = MacroIcons(A)
	MacroIcons(hc)
	W3.PageUI(w, A); W3.PageUI(w, hc)
	eq(PE(w, A).Emblem(200040), true, "an emblem in use, on the second page")
	eq(PE(w, A).Open("emblem"), true)
	eq(calls.n, 1, "the list built once")
	local c = PE(w, A).Icons()
	eq(c.page, 2, "it opens at the page of the icon in use")
	local lines, _, _, buttons = Page(w, A)
	Page(w, A)
	eq(calls.n, 1, "a redraw builds nothing")
	eq(lines[2].nav, nil, "no councillor: the emblem alone (no strip)")
	eq(lines[2].text, A.ns.L.MYPROFILE_EMBLEM_SAMPLE:format("|T200040:16|t"), "the sample: his emblem"); eq(lines[2].right, "#200040")
	local grid
	for _, l in ipairs(lines) do if l.items then grid = l end end
	assert(grid, "the slots")
	eq(grid.columns, 7); eq(#grid.items, 28)
	eq(grid.items[1].value, 200029); eq(grid.items[12].found, true, "the one in use lit")
	eq(grid.items[1].label, "#200029", "a slot's words: its name or number")
	local pager = lines[#lines].nav
	eq(pager[2].text, A.ns.L.COUNCIL_ICON_PAGE:format(2, 3))
	eq(buttons[2][1], "COUNCIL_ICON_DEFAULT"); eq(buttons[3][1], "MYPROFILE_USE"); eq(buttons[3].enabled, false, "nothing changed yet")
	-- A click on a slot: the preview only.
	local before = #w:Sent{ from = A, type = "AP" }
	w:As(A, grid.onItem, grid.items[3])
	eq(c.choice, 200031); eq(#w:Sent{ from = A, type = "AP" }, before, "nothing sent")
	eq(select(4, Page(w, A))[3].enabled, true)
	w:As(A, pager[1].onClick)
	eq(c.page, 1)
	-- Use this icon: saved, said, Look again.
	eq(PE(w, A).UseIcon(), true)
	w:Run(0)
	eq(A.ns.ArenaProfile.Mine().emblem, 200031)
	eq(#w:Sent{ from = A, type = "AP" }, before + 1, "one AP")
	eq(PE(w, A).Section(), "look"); eq(PE(w, A).Icons(), nil, "its list let go")
	-- A mark is never an emblem (AP carries a game icon alone).
	PE(w, A).SetSection("icons", "emblem")
	eq(calls.n, 2, "built again for the new open")
	PE(w, A).Icons().choice = { key = "gryphon-gold", texture = "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold-mark" }
	local ok, why = PE(w, A).UseIcon()
	eq(ok, false); eq(why, "mark"); eq(Printed(A, A.ns.L.PROFILE_ICON_REFUSED), true)
	eq(A.ns.ArenaProfile.Mine().emblem, 200031, "unchanged")
	-- No icon: no emblem.
	PE(w, A).NoIcon()
	eq(PE(w, A).UseIcon(), true)
	eq(A.ns.ArenaProfile.Mine().emblem, nil)
	-- A councillor: his honour's mark first; the filter by its words; Use picks the honour and takes
	-- his own icon away so the mark shows (the design; ported from the hosted picker's test).
	local e = table.concat({ "1", "Fzzq", hc.ns.Arena.B36(w.clock - 600), "A", "1", hc.ns.Arena.GK(hc.guid), hc.short, "-", hc.ns.Arena.GK(cast.B.guid), cast.B.short,
		"-", "1:0", "A", "K", "3c", hc.ns.Arena.GK(cast.arbiter.guid), "prtb" }, "~")
	w:As(hc, function() hc.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AE~L1~" .. e) end)
	w:Run(3)
	w:As(hc, hc.ns.HonorsNet.CloseLetter, false)
	eq(w:As(hc, hc.ns.Workshop.SetCouncilIcon, 200001), true)
	w:As(hc, hc.ns.ArenaProfile.SetPick, "rank", nil)
	eq(PE(w, hc).Open("icon"), true)
	local hcIcons = PE(w, hc).Icons()
	eq(type(hcIcons.list[1]), "table"); eq(hcIcons.list[1].key, "gryphon-gold")
	eq(hcIcons.choice, 200001, "his own icon in use")
	lines = Page(w, hc)
	eq(#lines[2].nav, 2, "Emblem | Council icon"); eq(lines[2].nav[2].selected, true)
	assert(Plain(lines[3].text):find(hc.ns.L.MYPROFILE_CHAT_SAMPLE:format(""), 1, true), "the chat's sample")
	PE(w, hc).FilterIcons("champion")
	eq(#hcIcons.shown, 1); eq(hcIcons.shown[1].key, "gryphon-gold", "a mark found by its words")
	eq(PE(w, hc).ChooseIcon(hcIcons.shown[1]), true)
	eq(PE(w, hc).UseIcon(), true)
	eq(hc.ns.ArenaProfile.Pick().frame, "arena-champion", "the honour picked")
	eq(hc.ns.CouncilIcon(hc.name), "", "his own icon taken away: the mark shows")
	-- A game icon: his own icon again.
	PE(w, hc).SetSection("icons", "icon")
	eq(PE(w, hc).ChooseIcon(200002), true)
	eq(PE(w, hc).UseIcon(), true)
	eq(hc.ns.db.councilIcons[hc.name], 200002)
	W3.NoErrors(w)
end)

test("1.2.4 My profile, Who sees what: what goes out, his page's facts as others open them, and his Profile choices of the privacy page, one click each (the history's republishes his word); read-only lines take no click; the privacy page by an explicit click", function()
	local w, cast = W3.New()
	local A = cast.A
	W3.PageUI(w, A)
	eq(PE(w, A).Open("privacy"), true)
	eq(PE(w, A).Section(), "privacy")
	local fact = { text = "Level 60 Warrior", right = "census, fresh" }
	local lines, _, _, buttons = Page(w, A, { fact })
	eq(#buttons, 1, "Back alone")
	-- (The whole sentence: its first words are also the Games-off one's.)
	local _, fat = Line(lines, A.ns.L.MYPROFILE_FACTS_HEAD)
	local said = {}
	for i = 2, fat - 1 do said[#said + 1] = Plain(lines[i].text) end
	eq(table.concat(said, " "), A.ns.L.MYPROFILE_LOOK_PUBLIC, "what goes out")
	eq(lines[fat + 1], fact, "his page's facts, as PlayerProfile makes them")
	local _, cat = Line(lines, A.ns.L.MYPROFILE_CHOICES_HEAD)
	local items = w:As(A, A.ns.Consent.Items, "profile")
	assert(#items > 0)
	local history, readonly
	for i, item in ipairs(items) do
		local row = lines[cat + i]
		local d = w:As(A, A.ns.Consent.Describe, item.key)
		eq(row.text, d.label, item.key); eq(row.right, d.state, item.key)
		if d.readonly then
			eq(row.onClick, nil, item.key .. ": read-only")
			readonly = true
		elseif item.key == "arenaHistory" then
			history = row
		end
	end
	assert(history, "the history's choice"); assert(readonly, "a read-only line")
	-- (The design's words, as the row shows them: the branch's first edit of this label was a copy
	-- in ArenaFightsText.lua that ArenaHomeText.lua, loading after it, overrode. pt-BR: the test below.)
	eq(history.text, "Show my list of fights on my profile", "the fight list's choice, rendered")
	eq(w:As(A, A.ns.Consent.Describe, "arenaHistory").label, "Show my list of fights on my profile")
	eq(w:As(A, A.ns.Consent.Answer, "arenaHistory"), nil)
	local before = #w:Sent{ from = A, type = "AP" }
	w:As(A, history.onClick)
	w:Run(0)
	eq(w:As(A, A.ns.Consent.Answer, "arenaHistory"), true); eq(A.ns.ArenaProfile.Mine().pub, true)
	eq(#w:Sent{ from = A, type = "AP" }, before + 1, "his word says it")
	local shown
	local show = A.ns.Consent.Show
	A.ns.Consent.Show = function(section) shown = section end
	w:As(A, Line(lines, A.ns.L.MYPROFILE_PRIVACY_PAGE).onClick)
	eq(shown, "profile")
	A.ns.Consent.Show = show
	W3.NoErrors(w)
end)

-- The design reworded the fight list's choice ("my profile", the whole addon's), but the edit went
-- to a copy of the key in ArenaFightsText.lua: ArenaHomeText.lua, after it in Olympus.toc, set the
-- key again, and Consent reads the last one. The words loaded as the game loads them (Locales.lua,
-- then every Locales file in the TOC's order), in both languages; and each of its two keys has one
-- definition, so a later edit is never dead. Fails on the branch's first page: "Your arena fight
-- history" / "Seu histórico de lutas na arena", and the keys in two files.
test("1.2.4 My profile, Who sees what: the fight list's choice reads the design's words, as the TOC loads them, in English and pt-BR; its keys have one definition", function()
	local files = {}
	for line in io.lines(H.ADDON_DIR .. "Olympus.toc") do
		local file = line:match("^Locales\\(.-)%.lua%s*$")
		if file then files[#files + 1] = file end
	end
	assert(#files > 5, "the TOC's locale files")
	local function Loaded(locale)
		local lns = {}
		local saved = GetLocale
		GetLocale = function() return locale end
		local ok, err = pcall(function()
			assert(loadfile(H.ADDON_DIR .. "Locales.lua"))("Olympus", lns)
			for _, file in ipairs(files) do assert(loadfile(H.ADDON_DIR .. "Locales/" .. file .. ".lua"))("Olympus", lns) end
		end)
		GetLocale = saved
		assert(ok, err)
		return lns.L
	end
	eq(rawget(Loaded("enUS"), "ARENA_CONSENT_HISTORY"), "Show my list of fights on my profile")
	eq(rawget(Loaded("ptBR"), "ARENA_CONSENT_HISTORY"), "Mostrar a minha lista de lutas no meu perfil")
	for _, key in ipairs({ "ARENA_CONSENT_HISTORY", "ARENA_CONSENT_HISTORY_TEXT" }) do
		local where = {}
		for _, file in ipairs(files) do
			local f = assert(io.open(H.ADDON_DIR .. "Locales/" .. file .. ".lua", "rb"))
			local src = f:read("*a")
			f:close()
			local _, n = ("\n" .. src):gsub("\n\t?L%." .. key .. " =", "")
			if n > 0 then where[#where + 1] = file .. " x" .. n end
		end
		eq(table.concat(where, ", "), "ArenaHomeText x2", key .. ": English and pt-BR, in one file")
	end
end)

test("1.2.4 My profile, Letters: the King's, newest first, unread in gold, a click opens one in the King's letter window; none: says so", function()
	local w, cast = W3.New()
	local A = cast.A
	W3.PageUI(w, A)
	eq(PE(w, A).Open("letters"), true)
	local lines = Page(w, A)
	eq(Plain(lines[2].text), A.ns.L.MYPROFILE_LETTERS_NONE)
	local m = A.ns.ArenaProfile.Mine(true)
	m.letters = { { key = "donor-top-1", t = w.clock - 7200, read = true }, { key = "arena-champion", t = w.clock - 60 } }
	lines = Page(w, A)
	eq(lines[1].nav[4].text, A.ns.L.MYPROFILE_NAV_LETTERS:format(2))
	eq(lines[2].text, "|cffffd200Arena Champion|r", "newest first, unread in gold")
	eq(Plain(lines[3].text), A.ns.HonorsNet.TitleText("donor-top-1")); eq(lines[3].text:find("|cffffd200", 1, true), nil, "read")
	w:As(A, lines[2].onClick)
	local letter = A.ns.HonorsNet.LetterFrame()
	eq(letter ~= nil and letter:IsShown(), true, "the King's letter window"); eq(letter.key, "arena-champion")
	W3.NoErrors(w)
end)

-- /oly profile with no name (or his own) is a click on My profile, as the person card's and the
-- Realm's ways in: on Look, where an older open of the page was left on another section.
test("1.2.4 /oly profile with no name (or his own) is My profile, on Look; another's name, his page", function()
	local w, cast = W3.New()
	local A = cast.A
	local ui = W3.PageUI(w, A)
	PE(w, A).SetSection("letters")
	w:As(A, function() A.slashes.OLYMPUS("profile") end)
	eq(ui.OwnProfileShown(), true); eq(PE(w, A).Section(), "look")
	PE(w, A).SetSection("letters")
	w:As(A, function() A.slashes.OLYMPUS("profile " .. A.short) end)
	eq(ui.OwnProfileShown(), true, "his own name: the same"); eq(PE(w, A).Section(), "look")
	w:As(A, function() A.slashes.OLYMPUS("profile Selka Drummond") end)
	eq(ui.OwnProfileShown(), false); eq(ui.person.name, "Selka Drummond", "another's: his page")
	W3.NoErrors(w)
end)

-- A failure case: with the Games off on this character (or an older companion refused) the profile's
-- word (AP) does not travel, so the page offers none of its pickers.
test("1.2.4 My profile with the Games off: no picker in Look but one grey line saying why; no Games profile button; Icons says the same to anyone but a councillor", function()
	local w, cast = W3.New()
	local A = cast.A
	MacroIcons(A)
	W3.PageUI(w, A)
	A.ns.db.arenaOff = true
	eq(A.ns.Arena.Off(), true)
	eq(PE(w, A).Open(), true)
	local lines, _, _, buttons = Page(w, A)
	eq(Line(lines, A.ns.L.MYPROFILE_FRAME_HEAD), nil, "no frame picker"); eq(Line(lines, A.ns.L.MYPROFILE_TITLE_HEAD), nil)
	eq(Line(lines, A.ns.L.MYPROFILE_NICK_HEAD), nil); eq(Line(lines, A.ns.L.PROFILE_LOCK), nil)
	local words = {}
	for i = 2, #lines do if not lines[i].header and not lines[i].onClick then words[#words + 1] = Plain(lines[i].text) end end
	assert(table.concat(words, " "):find(A.ns.L.MYPROFILE_GAMES_OFF, 1, true), "the grey line: " .. table.concat(words, " | "))
	eq(#buttons, 1, "Back alone")
	eq(PE(w, A).Open("emblem"), true)
	eq(PE(w, A).Icons(), nil, "no emblem's list")
	lines = Page(w, A)
	for _, l in ipairs(lines) do eq(l.items, nil, "no slots") end
	-- Who sees what says the same: nothing of his look goes out (Arena.Send refuses AP: a nickname
	-- set sends none), never "every member's addon shows them". (Fails on the branch's first page:
	-- that line was MYPROFILE_LOOK_PUBLIC whatever the Games.)
	local function Said()
		PE(w, A).SetSection("privacy")
		local said = {}
		for i, l in ipairs(Page(w, A)) do if i > 1 and not l.header then said[#said + 1] = Plain(l.text) end end
		return table.concat(said, " ")
	end
	local said = Said()
	assert(said:find(A.ns.L.MYPROFILE_LOOK_KEPT, 1, true), "nothing goes out: " .. said)
	eq(said:find(A.ns.L.MYPROFILE_LOOK_PUBLIC, 1, true), nil, "Games off: not 'every member's addon shows them'")
	local before = #w:Sent{ from = A, type = "AP" }
	eq(Prof(w, A).SetNick(3, 7), true)
	w:Run(0)
	eq(#w:Sent{ from = A, type = "AP" }, before, "no AP while the Games are off")
	A.ns.db.arenaOff = nil
	A.ns.Arena.companionRefused = "version"
	PE(w, A).SetSection("look")
	lines = Page(w, A)
	eq(Line(lines, A.ns.L.MYPROFILE_FRAME_HEAD), nil, "an older companion refused: the same")
	-- (An older companion refused hides the pickers, not the word: AP still goes out, so Who sees
	-- what still says it does.)
	said = Said()
	assert(said:find(A.ns.L.MYPROFILE_LOOK_PUBLIC, 1, true), "an older companion refused: " .. said)
	before = #w:Sent{ from = A, type = "AP" }
	eq(Prof(w, A).SetNick(4, 7), true)
	w:Run(0)
	eq(#w:Sent{ from = A, type = "AP" }, before + 1, "an older companion refused: AP still goes out")
	A.ns.Arena.companionRefused = nil
	W3.NoErrors(w)
end)

test("1.2.4 My profile from the Realm: its link (a Realm page's, before the Board, beside My week) for a member alone; its click opens his own page", function()
	local w, cast = W3.New()
	local A = cast.A
	local ui = W3.PageUI(w, A)
	local entry
	for _, p in ipairs(rawget(A.ns, "RealmPages") or {}) do if p.key == "myprofile" then entry = p end end
	assert(entry, "a Realm page's entry"); eq(entry.beforeBoard, true, "with My week, before the Board")
	eq(#w:As(A, entry.Lines), 0, "no page of the Realm's: the link opens his person page")
	local link = w:As(A, entry.Link)
	assert(link and link.onClick, "the link")
	assert(Plain(link.text):find(A.ns.L.MYPROFILE_LINK, 1, true), link.text)
	w:As(A, link.onClick)
	eq(ui.OwnProfileShown(), true); eq(PE(w, A).Section(), "look")
	local member = A.ns.IsMember
	A.ns.IsMember = function() return false end
	eq(w:As(A, entry.Link), nil, "outside an Olympus guild: none")
	A.ns.IsMember = member
	W3.NoErrors(w)
end)

-- The owner's words: not the arena's profile, the profile of everything. Fails on 1.2.3 (the letter's
-- notice said "your arena profile"; the panel's title was "My arena profile").
test("1.2.4 My profile's words: the page's name, the letter waiting's notice, the Games window's words for it, in English and pt-BR, never say the arena's profile", function()
	local function Core(locale)
		local L = setmetatable({}, { __index = function(_, k) return k end })
		local saved = GetLocale
		GetLocale = function() return locale end
		local ok, err = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales/ArenaFightsText.lua"))("Olympus", { L = L }) end)
		GetLocale = saved
		assert(ok, err)
		return L
	end
	local function Companion(locale)
		local L = setmetatable({}, { __index = function(_, k) return k end })
		local saved = GetLocale
		GetLocale = function() return locale end
		local ok, err = pcall(function() assert(loadfile(H.ARENA_DIR .. "Locales/UIText.lua"))("Olympus_Arena", { host = { L = L } }) end)
		GetLocale = saved
		assert(ok, err)
		return L
	end
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local C, A = Core(locale), Companion(locale)
		local words = { MYPROFILE_TITLE = rawget(C, "MYPROFILE_TITLE"), MYPROFILE_LINK = rawget(C, "MYPROFILE_LINK"),
			MYPROFILE_SEEN_TITLE = rawget(C, "MYPROFILE_SEEN_TITLE"), HONOR_LETTER_WAITING = rawget(C, "HONOR_LETTER_WAITING"),
			ARENA_PROFILE_EDIT = rawget(A, "ARENA_PROFILE_EDIT"), ARENA_PROFILE_MINE_TEXT = rawget(A, "ARENA_PROFILE_MINE_TEXT") }
		for key, text in pairs(words) do
			assert(type(text) == "string", locale .. " " .. key)
			assert(not text:lower():find("arena", 1, true), locale .. " " .. key .. ": " .. text)
		end
		eq(rawget(C, "PROFILE_EDIT_TITLE"), nil, locale .. ": the panel's title gone")
	end
	-- (It is said under the gamepad UI alone, where no slash command is registered: it names the page.)
	assert(Core("enUS").HONOR_LETTER_WAITING:find(Core("enUS").MYPROFILE_TITLE, 1, true))
	assert(Core("ptBR").HONOR_LETTER_WAITING:find(Core("ptBR").MYPROFILE_TITLE, 1, true))
end)

print("ArenaProfile: the person card, the profile's word")

local function ProfileStore()
	local w = World.New()
	local viewer = w:Client("Lida Fenn")
	eq(W3.Companion(w, viewer), true)
	return w, viewer, viewer.ns.ArenaProfile, viewer.ns.Arena.Heavy("L")
end
local function ProfileCount(profiles)
	local n = 0
	for _ in pairs(profiles) do n = n + 1 end
	return n
end
local function ProfileBody(w, viewer, gk)
	return table.concat({ gk or "-", "WA", "1", "2", "60", "0.0", "-", "0", "-", "-", viewer.ns.Arena.B36(w.clock) }, "~")
end

test("1.2.0 profile store cap: new senders retain the current and own profiles, evict the oldest others and leave lightweight picks available", function()
	local w, viewer, P, heavy = ProfileStore()
	eq(P.PROFILES_MAX, 3000)
	P.PROFILES_MAX = 4 -- exercise eviction with a small independent client's store
	eq(w:As(viewer, P.Take, viewer.name, ProfileBody(w, viewer)), true)
	local ownKey = viewer.name:lower()
	for i = 1, 6 do
		w.clock = w.clock + 1
		eq(w:As(viewer, P.Take, "New Fighter " .. i .. "-Emberfall", ProfileBody(w, viewer)), true)
	end
	eq(ProfileCount(heavy.profiles), P.PROFILES_MAX)
	eq(heavy.profiles[ownKey].name, viewer.name, "the player's own old profile survives the flood")
	eq(heavy.profiles["new fighter 3-emberfall"], nil, "oldest others leave first")
	for i = 4, 6 do eq(heavy.profiles["new fighter " .. i .. "-emberfall"].name, "New Fighter " .. i .. "-Emberfall") end
	eq(w:As(viewer, P.Of, "New Fighter 1-Emberfall").name, "New Fighter 1-Emberfall", "an evicted heavy row still has its lightweight pick")
	W3.NoErrors(w)
end)

test("1.2.0 profile store cap: an oversized saved table is trimmed on first read, keeping own and recent rows with deterministic ties", function()
	local w, viewer, P, heavy = ProfileStore()
	P.PROFILES_MAX = 3
	local ownKey = viewer.name:lower()
	heavy.profiles = {
		[ownKey] = { name = viewer.name, heard = w.clock - 1000 },
		["old fighter-emberfall"] = { name = "Old Fighter-Emberfall", heard = w.clock - 100 },
		["alpha fighter-emberfall"] = { name = "Alpha Fighter-Emberfall", heard = w.clock - 10 },
		["beta fighter-emberfall"] = { name = "Beta Fighter-Emberfall", heard = w.clock - 10 },
		["recent fighter-emberfall"] = { name = "Recent Fighter-Emberfall", heard = w.clock },
	}
	eq(w:As(viewer, P.Of, "Recent Fighter-Emberfall").name, "Recent Fighter-Emberfall")
	eq(ProfileCount(heavy.profiles), P.PROFILES_MAX)
	eq(heavy.profiles[ownKey].name, viewer.name)
	eq(heavy.profiles["old fighter-emberfall"], nil)
	eq(heavy.profiles["alpha fighter-emberfall"], nil, "equal ages evict by stable key")
	eq(heavy.profiles["beta fighter-emberfall"].name, "Beta Fighter-Emberfall")
	W3.NoErrors(w)
end)

test("1.2.0 profile store cap: repeated verified renames update one GUID row, bound former names, and retain the current row during a same-second flood", function()
	local w, viewer, P, heavy = ProfileStore()
	P.PROFILES_MAX = 3
	local guid, short = "Player-4395-00AA11BB", nil
	local gk = viewer.ns.Arena.GK(guid)
	viewer.globals.UnitTokenFromGUID = function() return nil end
	viewer.globals.GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR", "Human", "Human", 2, short, "Emberfall" end
	for i = 1, 8 do
		short = "Renamed Fighter " .. i
		eq(w:As(viewer, P.Take, short .. "-Emberfall", ProfileBody(w, viewer, gk)), true)
	end
	eq(ProfileCount(heavy.profiles), 1, "a rename replaces the GUID row")
	local p = w:As(viewer, P.Of, gk)
	eq(p.name, "Renamed Fighter 8-Emberfall"); eq(#p.formerly, P.FORMERLY)
	eq(table.concat(p.formerly, ","), "Renamed Fighter 7-Emberfall,Renamed Fighter 6-Emberfall,Renamed Fighter 5-Emberfall")
	for i = 4, 1, -1 do eq(w:As(viewer, P.Take, "Alpha Fighter " .. i .. "-Emberfall", ProfileBody(w, viewer)), true) end
	eq(ProfileCount(heavy.profiles), P.PROFILES_MAX)
	eq(heavy.profiles["alpha fighter 1-emberfall"].name, "Alpha Fighter 1-Emberfall", "the accepted row survives even when its key sorts first at equal age")
	W3.NoErrors(w)
end)

test("1.2 the fights part: the person card's rows (UI.personRows): 'Rank · Title' when a verified title shows; the arena's line when the ledger knows him; nothing for an unheld title", function()
	local w, cast = W3.New()
	local viewer = cast.spectator
	Belt(w, cast, cast.A, cast.B, { viewer, cast.A })
	eq(Prof(w, cast.A).SetPick("arena-champion", "arena-champion"), true)
	w:Run(0)
	local rows = { "|cffffd200Knight|r" }
	w:As(viewer, viewer.ns.ArenaProfile.PersonRows, { name = cast.A.short, realm = cast.A.realm, rank = "Knight" }, rows)
	eq(rows[1], "|cffffd200Knight · Arena Champion|r")
	-- Without a rank row: its own row.
	rows = {}
	w:As(viewer, viewer.ns.ArenaProfile.PersonRows, { name = cast.A.short, realm = cast.A.realm }, rows)
	eq(rows[1], "|cffffd200Arena Champion|r")
	-- A forged title on someone who holds none: nothing.
	rows = { "|cffffd200Knight|r" }
	w:As(viewer, function()
		viewer.ns.Arena.Inject("CHANNEL", cast.B.name, "AP~L1~" .. table.concat({ "-", "WA", "1", "2", "60", "0.0", "-", "0", "-", "arena-champion",
			viewer.ns.Arena.B36(w.clock) }, "~"))
	end)
	w:As(viewer, viewer.ns.ArenaProfile.PersonRows, { name = cast.B.short, realm = cast.B.realm, rank = "Knight" }, rows)
	eq(rows[1], "|cffffd200Knight|r")
	eq(rows[2], viewer.ns.L.ARENA_PERSON_PROFILE, "a profile heard: the arena's line")
	viewer.ns.db.arenaOff = true
	rows = { "|cffffd200Knight|r" }
	w:As(viewer, viewer.ns.ArenaProfile.PersonRows, { name = cast.A.short, realm = cast.A.realm, rank = "Knight" }, rows)
	eq(#rows, 1, "Arena-only rows are absent while the core Arena is disabled")
	viewer.ns.db.arenaOff = nil
	viewer.ns.Arena.companionRefused = "version"
	rows = { "|cffffd200Knight|r" }
	w:As(viewer, viewer.ns.ArenaProfile.PersonRows, { name = cast.A.short, realm = cast.A.realm, rank = "Knight" }, rows)
	eq(#rows, 1, "Arena-only rows are absent after an older companion was refused")
	viewer.ns.Arena.companionRefused = nil
	W3.NoErrors(w)
end)

test("1.2 the fights part: AP carries only public-safe fields (no zone, no gold); a sender whose gk the game gives to another character is refused; one per 5 minutes per sender (a change after a minute passes)", function()
	local w, cast = W3.New()
	local A = cast.A
	eq(Prof(w, A).SetNick(3, 7), true)
	w:Run(0)
	local sent = w:Sent{ from = A, type = "AP" }
	local body = sent[#sent].msg
	local fields = {}
	for f in (body .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = f end
	eq(#fields, 13, "AP~L1~ and 11 fields")
	assert(not body:lower():find("zone", 1, true))
	eq(fields[8], "3.7")
	-- A viewer whose game says that GUID is another's: refused (past the 5 minutes since the one heard).
	local viewer = cast.spectator
	w:Run(301)
	viewer.globals.GetPlayerInfoByGUID = function() return "Mage", "MAGE", "Human", "Human", 2, "Other Person", "" end
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", A.name, body) end)
	eq(viewer.ns.ArenaProfile.Stats().refused.gk, 1)
	viewer.globals.GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR", "Human", "Human", 2, "Torvin Hale", "" end
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", A.name, body) end)
	local p = w:As(viewer, viewer.ns.ArenaProfile.Of, A.name)
	eq(p.verified, true); eq(p.nick, "3.7")
	-- Again at once, the same: dropped (the rate).
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", A.name, body) end)
	eq(viewer.ns.ArenaProfile.Stats().refused.rate, 1)
	W3.NoErrors(w)
end)

test("1.2 the fights part: profile cards keep partial identity dense and carry only observed guild metadata, normalized sex and a verified worn honour, with provenance", function()
	local w, cast = W3.New()
	local viewer, A = cast.spectator, cast.A
	viewer.ns.Roster.guild = viewer.guild
	viewer.ns.Roster.members = { { full = A.name, rank = "Knight" } }
	viewer.ns.Roster.byName = { [A.name] = 3 }
	local body = table.concat({ "-", "-", "2", "3", "-", "0.0", "-", "0", "-", "-", viewer.ns.Arena.B36(w.clock) }, "~")
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", A.name, "AP~L1~" .. body) end)
	local card = Prof(w, viewer).Card(A.name)
	eq(card.class, nil); eq(card.level, nil)
	eq(card.race.v, 2); eq(card.race.src, "own")
	eq(card.gender.v, 3); eq(card.gender.src, "own")
	eq(card.sex.v, 3); eq(card.sex.src, "own")
	eq(card.guild.v, viewer.guild); eq(card.guild.src, "seen")
	eq(card.guildRank.v, "Knight"); eq(card.guildRank.src, "seen")
	eq(card.honour, nil, "an unknown or rank frame is not invented as an honour")
	local unknownBody = table.concat({ "-", "WA", "-", "1", "60", "0.0", "-", "0", "-", "-", viewer.ns.Arena.B36(w.clock) }, "~")
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", cast.B.name, "AP~L1~" .. unknownBody) end)
	local unknown = Prof(w, viewer).Card(cast.B.name)
	eq(unknown.gender, nil); eq(unknown.sex, nil, "the client's unknown UnitSex value is not promoted to a gender")
	eq(unknown.guildRank, nil, "a numeric or absent rank is not invented as a rank name")
	-- The companion's real model used to pass holes to table.concat when only race was known.
	eq(W3.Companion(w, viewer), true)
	local model = w:As(viewer, viewer.companion.own.ArenaUI.ProfileModel, A.name)
	eq(model.class, nil); eq(model.race, 2); eq(model.level, nil); eq(model.gender, 3)
	eq(#model.lines > 0, true)
	-- Own server facts and a frame this viewer has verified are separately tagged.
	A.globals.UnitSex = function() return 3 end
	Belt(w, cast, A, cast.B, { A })
	eq(Prof(w, A).SetPick("arena-champion", nil), true)
	w:Run(0)
	local own = Prof(w, A).Card(A.name)
	eq(own.gender.v, 3); eq(own.gender.src, "own")
	eq(own.guild.v, A.guild); eq(own.guildRank.v, A.rankName)
	eq(own.guild.src, "seen"); eq(own.guildRank.src, "seen")
	eq(own.honour.v, "arena-champion"); eq(own.honour.src, "verified")
	W3.NoErrors(w)
end)

-- The owner's UFC card (2026-10-04): the ledger's rating, its peak, the duels fled and the streak reach
-- the real person card, and from it the Tale of the tape.
test("1.2 the tale of the tape from the ledger: the rating and its peak, a fled duel and the streak on the real person card", function()
	local w, cast = W3.New()
	local viewer, A, B = cast.spectator, cast.A, cast.B
	local Ar = cast.arbiter.ns.Arena
	-- Two rated fights: A knocks B out, then flees the rematch (A's rating falls from its peak).
	local function Fight(fid, ago, winner, method)
		local e = table.concat({ "1", fid, Ar.B36(w.clock - ago), "A", "1", Ar.GK(A.guid), A.short, "-", Ar.GK(B.guid), B.short, "-", "1:0",
			winner, method, "3c", Ar.GK(cast.arbiter.guid), "pr" }, "~")
		w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AE~L1~" .. e) end)
	end
	eq(W3.Companion(w, viewer), true) -- (the ledger's entries live in the companion's tables)
	Fight("Fzzk1", 900, "A", "K")
	Fight("Fzzr2", 600, "B", "R")
	-- (his profile word heard, its GUID his as the game says: the card finds his ledger key through it)
	viewer.globals.GetPlayerInfoByGUID = function(guid) if guid == A.guid then return "Warrior", "WARRIOR", "Human", "Human", 2, A.short, "" end end
	local body = table.concat({ Ar.GK(A.guid), "WA", "1", "2", "60", "0.0", "-", "0", "-", "-", viewer.ns.Arena.B36(w.clock) }, "~")
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", A.name, "AP~L1~" .. body) end)
	local card = Prof(w, viewer).Card(A.name)
	assert(card.record and card.rating and card.peak, "the record, the rating and the peak")
	eq(card.peak.src, "ledger")
	assert(card.peak.v > card.rating.v, "his peak (after the win) above his rating now: " .. card.peak.v .. " / " .. card.rating.v)
	eq(card.record.v.fled, 1); eq(card.record.v.streak, -1)
	local UI = viewer.companion.own.ArenaUI
	local f = w:As(viewer, UI.Card.Fighter, A.name)
	eq(f.rating, card.rating.v); eq(f.peak, card.peak.v); eq(f.fled, 1); eq(f.streak, -1)
	local found = {}
	for _, r in ipairs(w:As(viewer, UI.Card.Rows, f, "g", "window")) do found[r.label] = r.value end
	assert(found.rating and found.rating:find(tostring(card.peak.v), 1, true), "the rating row names the peak: " .. tostring(found.rating))
	eq(found.fled, "1")
	assert(found.streak and found.streak:find("L1", 1, true), tostring(found.streak))
	W3.NoErrors(w)
end)
