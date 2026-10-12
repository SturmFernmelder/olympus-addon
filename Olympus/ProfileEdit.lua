local ADDON, ns = ...

-- 1.2, the Blood Arena: ProfileEdit.lua. A stub the arena's core created for the fights part (fights and honours) to fill: keep these first
-- lines, the addon's table and the namespace; the rest is the package's.

-- "My profile" (1.2.4, the owner's: the profile of everything, not the arena's): the player's own person page in
-- the Olympus window, in the window's own format (UI.OpenPlayerProfile on himself; PlayerProfile.Build
-- hands his page to ProfileEdit.Page): the window's in-page strip of sections, Look | Icons | Who
-- sees what | Letters, their rows in the list, the detail box the live preview of what others see
-- (his portrait in the frame others verify, his title and nickname) and the bottom buttons. The icon
-- picker is a section of the page: no window of its own (1.2.3's floating Edit panel, beside the
-- Olympus window or over the Games window, and the picker it hosted, spilling past its edges with
-- the council's words on an emblem, were three windows stacked; they are gone). Every way in lands
-- here: his own person page, the Realm's "My profile" and "My council icon", the Games tab's row,
-- the Games window's Profile ("Edit my profile"), /oly profile, /oly emblem, /oly council icon.
-- API (the design): Open(what, opts), Section(), SetSection(key, kind), Page(details, facts),
-- PageShown(), Back(), DressPortrait(rig, art), ViewModel(), Preview(), and the pickers below.
local ProfileEdit = {}
ns.ProfileEdit = ProfileEdit

-- Frames, titles and honours are one system for the whole addon (donors, the best guild, the
-- Apostles, Bones, the Slayers, the council icon), so the page is the core's: the Games window is
-- hidden while the live switch is off and missing when the companion is disabled. Rows, nav cells
-- and the list's item slots only (Views.lua: no edit box but the list's own filter, which never
-- takes the keyboard by itself; no game popup; nothing on the escape list), so it works the same
-- with the gamepad UI. The Games window's Profile tab (the screens) reads the same view model
-- (ProfileEdit.ViewModel) and opens this page to edit it.
--   ViewModel() -> { frames = { { key, label, art, shape, metal, shipped, selected, shows } } (the
--     rank's, none, every frame held, and a signed Apostle's own look, own = true: Borders.OwnLook,
--     on his screen alone, never his pick, so never sent; 1.2.4: a frame held that this version
--     does not wear yet, Honors.FrameShipped, is listed with shipped = false and never selected:
--     the page greys it, "comes in a later version", as Honors.Choose refuses it; shows: the frame
--     another client shows of him now, Preview().frame), titles = { { key, label, selected } } (none,
--     and every title held), nick = { a, n, text, lists = { A, N } }, emblem, pub, locked,
--     letters = { { key, title, t, read } },
--     preview = Preview(), councillor, honours = the honours held (Honors.Holdings's) }
--   Preview() -> what another client shows of this player now: { frame, title, titleText, mark,
--     frameTexture, shape, markTexture, nick, emblem }
--   PickFrame(key), PickTitle(key), Nick(a, n), NickStep(which, delta), Emblem(icon), SetPublic(on),
--   Lock(on), IconList(kind), HonourOfMark(art), PickIcon(icon)

local L = ns.L
local PE = ProfileEdit
local Arena = ns.Arena

PE.ICON_COLS, PE.ICON_ROWS = 7, 4 -- the Icons grid: 7 slots of 39 px (273) inside the list's 296 at the default width
PE.WRAP = 48 -- a long sentence, cut into rows of about this many letters (a list row is one line)
PE.SECTIONS = { "look", "icons", "privacy", "letters" }

local function P() return ns.ArenaProfile end
local function H() return ns.HonorsNet end
-- (1.2.3) A held honour's frame this version wears (Honors.FrameShipped), the only ones the
-- pickers take: Honors.Choose refuses the rest.
local function Worn(h)
	local Hs = ns.Honors
	return type(h) == "table" and h.frame ~= nil and type(Hs) == "table" and type(Hs.FrameShipped) == "function" and Hs.FrameShipped(h) == true
end
-- (1.2.1: the borders' own looks, Borders.OWN_LOOKS; none where Borders.lua is a stand-in.)
local function B()
	local b = ns.Borders
	return type(b) == "table" and not b.missing and type(b.OwnLookAllowed) == "function" and type(b.SetOwnLook) == "function" and b or nil
end
local function Gold(s) return "|cffffd200" .. tostring(s) .. "|r" end
local function Grey(s) return "|cff9d9d9d" .. tostring(s) .. "|r" end
-- The Games on this character, the gate of the person card's Arena rows (ArenaProfile.PersonRows):
-- the profile's word (AP) goes out on the Games' channel, so none of its pickers shows while they
-- are off. A councillor's chat icon is the council's (Workshop.lua), whatever the Games.
local function GamesOn() return not Arena.Off() and Arena.companionRefused ~= "version" end
local function Councillor() return ns.IsHighCouncillor(ns.me) == true end

---------------------------------------------------------------------------
-- The view model
---------------------------------------------------------------------------

function PE.Preview()
	local HN = H()
	local v = HN.Verified(ns.me)
	local m = P().Mine()
	local tex, shape
	if v.frame ~= "rank" and v.frame ~= "none" then tex, shape = HN.FrameTexture(v.frame) end
	return { frame = v.frame, title = v.title, titleText = v.title and HN.TitleText(v.title) or nil, mark = v.mark,
		frameTexture = tex, shape = shape, markTexture = v.mark ~= "rank" and HN.MarkTexture(v.mark) or nil,
		nick = P().NickText(m.nick), emblem = m.emblem }
end

function PE.ViewModel()
	local HN, PR = H(), P()
	local held = HN.Holdings(ns.me, PR.MyGk())
	local pick = PR.Pick()
	local m = PR.Mine()
	local vm = { frames = {}, titles = {}, honours = held, emblem = m.emblem, pub = m.pub == true, locked = m.locked == true,
		letters = {}, councillor = Councillor() }
	vm.frames[1] = { key = "rank", label = L.PROFILE_FRAME_RANK, shipped = true, selected = (pick.frame or "rank") == "rank" }
	vm.frames[2] = { key = "none", label = L.PROFILE_FRAME_NONE, shipped = true, selected = pick.frame == "none" }
	vm.titles[1] = { key = "none", label = L.PROFILE_TITLE_NONE, selected = pick.title == nil }
	for _, h in ipairs(held) do
		-- (1.2.4: every frame held, one this version does not wear yet listed unpickable; a title
		-- is offered whatever its frame.)
		if h.frame then
			local shipped = Worn(h)
			vm.frames[#vm.frames + 1] = { key = h.frame, label = HN.TitleText(h.key) or h.key, art = h.art, shape = h.shape, metal = h.metal,
				milestone = h.milestone, shipped = shipped, selected = shipped and pick.frame == h.frame }
		end
		if h.title then vm.titles[#vm.titles + 1] = { key = h.title, label = HN.TitleText(h.key) or h.key, selected = pick.title == h.title } end
	end
	-- 1.2.1: a signed Apostle's own look (the red cross), on his own screen alone: while he wears it,
	-- the frame picked (what everyone else sees) is not the one selected here.
	local borders = B()
	if borders then
		local look = borders.OwnLook()
		for key in pairs(borders.OWN_LOOKS or {}) do
			if borders.OwnLookAllowed(key) then
				local art, shape, metal = ns.Honors.ArtOf(key)
				vm.frames[#vm.frames + 1] = { key = key, label = L.PROFILE_FRAME_RED_CROSS, short = L.MYPROFILE_RED_CROSS, art = art, shape = shape,
					metal = metal, own = true, shipped = true, selected = look == key }
			end
		end
		if look then
			for _, x in ipairs(vm.frames) do if not x.own then x.selected = false end end
		end
	end
	local a, n = tostring(m.nick or "0.0"):match("^(%d+)%.(%d+)$")
	vm.nick = { a = tonumber(a) or 0, n = tonumber(n) or 0, text = PR.NickText(m.nick), lists = { A = L.ARENA_EPI_A, N = L.ARENA_EPI_N } }
	for _, x in ipairs(HN.Letters()) do
		vm.letters[#vm.letters + 1] = { key = x.key, title = HN.TitleText(x.key), t = x.t, read = x.read == true }
	end
	vm.preview = PE.Preview()
	-- (1.2.4) The frame others see now: a pick of a frame not worn yet shows the rank's (Honors.Shown).
	for _, x in ipairs(vm.frames) do x.shows = not x.own and x.key == vm.preview.frame end
	return vm
end

---------------------------------------------------------------------------
-- The pickers (each one click; the profile says itself on every change: AP)
---------------------------------------------------------------------------

function PE.PickFrame(key)
	-- 1.2.1: an own look (Borders.OWN_LOOKS) is this screen's alone: the pick, sent to everyone,
	-- stays as it is. Any other frame ends it.
	local borders = B()
	if borders and borders.OWN_LOOKS and borders.OWN_LOOKS[key] then
		local ok, why = borders.SetOwnLook(key)
		PE.Refresh()
		return ok, why
	end
	local pick = P().Pick()
	local ok, why = P().SetPick(key or "rank", pick.title)
	if ok and borders and borders.OwnLook and borders.OwnLook() then borders.SetOwnLook(nil) end
	PE.Refresh()
	return ok, why
end
function PE.PickTitle(key)
	local pick = P().Pick()
	local ok, why = P().SetPick(pick.frame or "rank", key ~= "none" and key or nil)
	PE.Refresh()
	return ok, why
end
function PE.Nick(a, n)
	local ok, why = P().SetNick(a, n)
	PE.Refresh()
	return ok, why
end
-- A step through a list (-1 or +1, wrapping through none). A nickname is two words: a side stepped
-- to none takes it away; from none, one step gives both sides a word (the first, or the last
-- stepping back). 1.2.4: the page's "<" too, so a step back from the first word is never a dead click.
function PE.NickStep(which, delta)
	local m = P().Mine()
	local a, n = tostring(m.nick or "0.0"):match("^(%d+)%.(%d+)$")
	a, n = tonumber(a) or 0, tonumber(n) or 0
	local size = ns.ArenaProfile.EPITHETS
	if which == "a" then a = (a + delta) % (size + 1) else n = (n + delta) % (size + 1) end
	if (which == "a" and a == 0) or (which ~= "a" and n == 0) then return PE.Nick(0, 0) end
	if a == 0 then a = delta < 0 and size or 1 end
	if n == 0 then n = delta < 0 and size or 1 end
	return PE.Nick(a, n)
end
function PE.Emblem(icon)
	local ok, why = P().SetEmblem(icon)
	PE.Refresh()
	return ok, why
end
function PE.SetPublic(on)
	local C = ns.Consent
	if type(C) == "table" and not C.missing and type(C.Choose) == "function" and C.Choose("arenaHistory", on) then
		PE.Refresh()
		return true
	end
	local ok = P().SetPublic(on)
	PE.Refresh()
	return ok
end
function PE.Lock(on)
	P().SetLocked(on)
	PE.Refresh()
	return true
end

-- The icons the page's Icons section lists. kind "icon", the chat icon (the design: councillors
-- keep their picked icon, otherwise the chosen honour's mark): the player's honour marks first,
-- then, for a councillor, the game's whole list. "emblem" (the default), the fighter's emblem
-- (the design: a game icon, ns.CouncilIconValue on both ends): the game's icons only.
function PE.IconList(kind)
	local HN = H()
	local out = {}
	if kind == "icon" then
		-- (1.2.3: a mark picks its honour's frame, PickIcon: the marks of frames worn in this version
		-- alone, as the frame picker.)
		for _, h in ipairs(HN.Holdings(ns.me, P().MyGk())) do
			if h.art and Worn(h) then
				out[#out + 1] = { key = h.art, texture = HN.MarkTexture(h.art), label = HN.TitleText(h.key) or h.key }
			end
		end
		if not Councillor() then return out end
	end
	local W = ns.Workshop
	local icons = type(W) == "table" and type(W.GameIcons) == "function" and W.GameIcons() or {}
	for _, icon in ipairs(icons) do out[#out + 1] = icon end
	return out
end
-- A councillor's own icon as he picked it (Workshop.SetCouncilIcon keeps it), or nil.
local function MyCouncilIcon()
	local mine = ns.db and ns.db.councilIcons
	local v = type(mine) == "table" and mine[ns.me] or nil
	return v and ns.CouncilIconValue(v) or nil
end
-- The honour a mark (its art) belongs to among those held whose frame this version wears, or nil.
function PE.HonourOfMark(art)
	if type(art) ~= "string" then return nil end
	for _, h in ipairs(H().Holdings(ns.me, P().MyGk())) do
		if h.art == art and Worn(h) then return h end
	end
	return nil
end
-- An icon picked for the chat icon: an honour's mark picks that honour (its frame: the mark
-- shown is the shown honour's; the title stays) and takes a councillor's own icon away so the
-- mark shows; a game icon is a councillor's own icon. True when taken.
function PE.PickIcon(icon)
	local W = ns.Workshop
	local h = type(icon) == "string" and PE.HonourOfMark(icon)
	if h then
		local pick = P().Pick()
		P().SetPick(h.frame or pick.frame, pick.title)
		if Councillor() and MyCouncilIcon() and type(W) == "table" and W.SetCouncilIcon then W.SetCouncilIcon(nil) end
		return true
	end
	if Councillor() and ns.CouncilIconValue(icon) and type(W) == "table" and W.SetCouncilIcon then return W.SetCouncilIcon(icon) end
	ns.Print(L.PROFILE_ICON_REFUSED)
	return false
end

---------------------------------------------------------------------------
-- The page: his own person page in the Olympus window (the design, "My profile")
---------------------------------------------------------------------------

local section, iconKind = "look", "emblem"
local icons       -- the Icons section's list while it is open: { kind, list, shown, page, filter, choice, current, names }
local gamesReturn -- { shown }: opened from the Games window (Back brings it back; shown: the Olympus window was open)
local drawn       -- the page was drawn this session: its portrait and its icon slots are made (never first in combat)

-- His own page is the one the Olympus window shows now.
function PE.PageShown()
	local UI = ns.UI
	if type(UI) ~= "table" or type(UI.OwnProfileShown) ~= "function" or type(UI.IsShown) ~= "function" then return false end
	return UI.IsShown() and UI.OwnProfileShown() == true or false
end
-- Drawn again at once while it shows (a click on it), else nothing.
function PE.Refresh()
	if PE.PageShown() and type(ns.UI.Refresh) == "function" then ns.UI.Refresh() end
end
-- (Through the window's redraw timer: a listener's, or a box's typing.)
local function RefreshSoon()
	if not PE.PageShown() then return end
	local UI = ns.UI
	if type(UI.RefreshSoon) == "function" then UI.RefreshSoon() elseif type(UI.Refresh) == "function" then UI.Refresh() end
end

local function Per() return PE.ICON_COLS * PE.ICON_ROWS end
-- An entry of the list: a game icon (a file number, an icon's name), or an honour's mark
-- ({ key, texture, label }, Workshop.IconEntry). Its key in the list, its picture, its words, and
-- what a choice of it hands on (a mark's key).
local function IconKey(icon)
	if type(icon) == "table" then return "mark:" .. tostring(icon.key):lower() end
	return icon ~= nil and tostring(icon):lower() or nil
end
local function IconArt(icon)
	if type(icon) == "table" then return icon.texture end
	return ns.CouncilIconTexture(icon)
end
local function IconLabel(icon)
	if type(icon) == "table" then return icon.label or icon.key end
	return type(icon) == "number" and ("#" .. icon) or tostring(icon)
end
local function IconValue(icon) if type(icon) == "table" then return icon.key end return icon end
-- The icon in use: the emblem; a councillor's own chat icon, else the mark of the honour shown.
local function CurrentIcon(kind)
	if kind == "icon" then return MyCouncilIcon() or H().Verified(ns.me).art end
	return P().Mine().emblem
end

-- The section's list, built when it opens (IconList, each entry as Workshop.IconEntry takes it,
-- repeats left out, as the picker's window did) and let go when it closes, the way that window let
-- go of it on hide. It opens at the page of the icon in use.
local function OpenIcons(kind)
	local W = ns.Workshop
	local entry = type(W) == "table" and type(W.IconEntry) == "function" and W.IconEntry or ns.CouncilIconValue
	local list, seen, names = {}, {}, false
	for _, v in ipairs(PE.IconList(kind)) do
		local icon = entry(v)
		local key = IconKey(icon)
		if key and not seen[key] then
			seen[key] = true
			list[#list + 1] = icon
			if type(icon) ~= "number" then names = true end
		end
	end
	local current = CurrentIcon(kind)
	local choice = ns.CouncilIconValue(current)
	for _, icon in ipairs(list) do if type(icon) == "table" and icon.key == current then choice = icon end end
	local page, key = 1, IconKey(choice)
	for i, icon in ipairs(list) do
		if key and IconKey(icon) == key then
			page = math.floor((i - 1) / Per()) + 1
			break
		end
	end
	icons = { kind = kind, list = list, shown = list, page = page, filter = "", choice = choice, current = choice, names = names }
	return icons
end
function PE.Icons() return icons end -- (tests: the list held)

-- The section shown ("look", "icons", "privacy", "letters") and the Icons section's kind ("emblem",
-- "icon").
local SECTION = { look = true, icons = true, privacy = true, letters = true }
function PE.Section() return section, iconKind end
local function SetSection(key, kind)
	if not SECTION[key] then return false end
	if key == "icons" then
		kind = kind or iconKind
		-- (A councillor's chat icon for a councillor alone; with the Games off, his only one.)
		if kind == "icon" and not Councillor() then kind = "emblem" end
		if kind == "emblem" and not GamesOn() and Councillor() then kind = "icon" end
		if (kind == "icon" or GamesOn()) and not (icons and icons.kind == kind) then OpenIcons(kind) end
		if kind == "emblem" and not GamesOn() then icons = nil end
		iconKind = kind
	else
		icons = nil
	end
	section = key
	return true
end
function PE.SetSection(key, kind)
	if not SetSection(key, kind) then return false end
	PE.Refresh()
	return true
end

-- A click on a slot (or No icon: nil): the preview only, nothing sent until Use this icon.
function PE.ChooseIcon(icon)
	if not icons then return false end
	if icon == nil then
		icons.choice = nil
	else
		local key, found = IconKey(icon), nil
		for _, x in ipairs(icons.list) do
			if IconKey(x) == key or (type(x) == "table" and x.key == icon) then found = x break end
		end
		if not found then return false end
		icons.choice = found
	end
	PE.Refresh()
	return true
end
function PE.NoIcon() return PE.ChooseIcon(nil) end
function PE.IconPage(delta)
	if not icons then return false end
	local pages = math.max(1, math.ceil(#icons.shown / Per()))
	icons.page = math.max(1, math.min(pages, icons.page + (tonumber(delta) or 0)))
	PE.Refresh()
	return true
end
-- The filter: the names (and file numbers) that hold the text, any case; a mark by its words or its
-- key. Typed into the list's own box, it redraws through the window's timer (never inside the box's
-- own handler), and its own text set again is no change.
function PE.FilterIcons(text)
	if not icons then return false end
	text = tostring(text or "")
	if text == icons.filter then return true end
	icons.filter = text
	local want = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if want == "" then
		icons.shown = icons.list
	else
		local shown = {}
		for _, icon in ipairs(icons.list) do
			local words = type(icon) == "table" and ((icon.label or "") .. " " .. icon.key) or tostring(icon)
			if words:lower():find(want, 1, true) then shown[#shown + 1] = icon end
		end
		icons.shown = shown
	end
	icons.page = 1
	RefreshSoon()
	return true
end
-- Use this icon: the emblem (a game icon alone: AP carries no mark), or a councillor's chat icon (a
-- mark picks its honour and drops his own icon, a game icon is his own icon, none the mark alone).
-- The page goes back to Look.
function PE.UseIcon()
	if not icons then return false end
	local choice, ok, why = icons.choice, false, nil
	if icons.kind == "icon" then
		if choice == nil then
			local W = ns.Workshop
			ok = type(W) == "table" and type(W.SetCouncilIcon) == "function" and W.SetCouncilIcon(nil) == true
		else
			ok = PE.PickIcon(IconValue(choice)) == true
		end
	elseif type(choice) == "table" then
		ns.Print(L.PROFILE_ICON_REFUSED)
		return false, "mark"
	else
		ok, why = P().SetEmblem(choice)
	end
	if not ok then return false, why end
	PE.SetSection("look")
	return true
end

-- A long sentence as rows of the list (a row is one line): grey, cut between words.
local function Words(lines, text, indent)
	local row = ""
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + 1 + #word > PE.WRAP then
			lines[#lines + 1] = { text = Grey(row), indent = indent }
			row = word
		else
			row = row == "" and word or (row .. " " .. word)
		end
	end
	if row ~= "" then lines[#lines + 1] = { text = Grey(row), indent = indent } end
end
local function Tip(title, text)
	return function(tt)
		tt:AddLine(title, 1, 0.82, 0)
		if text then tt:AddLine(text, 1, 1, 1, true) end
	end
end
local function Texture(art, size) return "|T" .. tostring(art) .. ":" .. (size or 16) .. "|t" end

-- The section strip: page chrome under the header (Views.SplitPageNav), the Realm's component.
local function Nav(vm)
	local words = { look = L.MYPROFILE_NAV_LOOK, icons = L.MYPROFILE_NAV_ICONS, privacy = L.MYPROFILE_NAV_PRIVACY,
		letters = L.MYPROFILE_NAV_LETTERS:format(#vm.letters) }
	local items = {}
	for _, key in ipairs(PE.SECTIONS) do
		local k = key
		items[#items + 1] = { text = words[k], selected = section == k, onClick = function() PE.SetSection(k) end }
	end
	return { pageNav = true, nav = items, id = "myprofile-navigation" }
end

-- A councillor's chat icon in Look: what shows after the silver dragon, and the way to Icons.
local function CouncilIconLines(lines)
	local mine = MyCouncilIcon()
	lines[#lines + 1] = { text = L.MYPROFILE_ICON_HEAD, header = true,
		right = mine and Texture(ns.CouncilIconTexture(mine)) or L.COUNCIL_ICON_MARK_ONLY }
	lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.MYPROFILE_CHOOSE_ICON), onClick = function() PE.SetSection("icons", "icon") end }
end

-- Look: the frame (one row each, one click each), the title, the nickname (two strips of the
-- fixed lists), the emblem (a row into Icons), a councillor's chat icon, the lock, the honours held.
local function LookLines(lines, vm)
	if not GamesOn() then
		Words(lines, L.MYPROFILE_GAMES_OFF)
		if vm.councillor then CouncilIconLines(lines) end
	else
		local shows
		for _, x in ipairs(vm.frames) do if x.shows then shows = x.label end end
		lines[#lines + 1] = { text = L.MYPROFILE_FRAME_HEAD, header = true, right = shows or "" }
		for _, x in ipairs(vm.frames) do
			local key = x.key
			if x.shipped == false then
				-- (1.2.4: held, not worn in this version: Honors.Choose would refuse it.)
				lines[#lines + 1] = { indent = 1, text = Grey(x.label), right = Grey(L.MYPROFILE_FRAME_LATER) }
			else
				local mark = x.shows or (x.own and x.selected)
				lines[#lines + 1] = { indent = 1, text = mark and Gold("> " .. x.label) or x.label, onClick = function() PE.PickFrame(key) end }
			end
		end
		local titled
		for _, x in ipairs(vm.titles) do if x.selected then titled = x.label end end
		lines[#lines + 1] = { text = L.MYPROFILE_TITLE_HEAD, header = true, right = titled or "" }
		for _, x in ipairs(vm.titles) do
			local key = x.key
			lines[#lines + 1] = { indent = 1, text = x.selected and Gold("> " .. x.label) or x.label, onClick = function() PE.PickTitle(key) end }
		end
		local nick = vm.nick
		lines[#lines + 1] = { text = L.MYPROFILE_NICK_HEAD, header = true, right = nick.text or L.MYPROFILE_NONE_WORD }
		for _, which in ipairs({ "a", "n" }) do
			local w = which
			local list = w == "a" and nick.lists.A or nick.lists.N
			local at = w == "a" and nick.a or nick.n
			local word = type(list) == "table" and at > 0 and list[at] or L.MYPROFILE_NONE_WORD
			lines[#lines + 1] = { nav = {
				{ text = "<", onClick = function() PE.NickStep(w, -1) end },
				{ text = (w == "a" and L.MYPROFILE_EPITHET or L.MYPROFILE_BEAST):format(word) },
				{ text = ">", onClick = function() PE.NickStep(w, 1) end },
			} }
		end
		lines[#lines + 1] = { text = L.MYPROFILE_EMBLEM_HEAD, header = true,
			right = vm.emblem and Texture(ns.CouncilIconTexture(vm.emblem)) or L.MYPROFILE_NONE_WORD }
		lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.MYPROFILE_CHOOSE_EMBLEM), onClick = function() PE.SetSection("icons", "emblem") end }
		if vm.councillor then CouncilIconLines(lines) end
		local locked = vm.locked
		lines[#lines + 1] = { indent = 1, text = locked and Gold(L.PROFILE_LOCKED) or L.PROFILE_LOCK, gapAfter = true,
			onClick = function() PE.Lock(not locked) end, tooltip = Tip(L.PROFILE_LOCK, L.MYPROFILE_LOCK_TIP) }
	end
	lines[#lines + 1] = { text = L.PROFILE_HONOURS, header = true }
	for _, h in ipairs(vm.honours) do lines[#lines + 1] = { indent = 1, text = H().TitleText(h.key) or h.key } end
	if #vm.honours == 0 then Words(lines, L.PROFILE_NO_HONOURS, 1) end
end

-- Icons: the picker inline (a councillor's strip between his emblem and his chat icon), the
-- sample, the filter, one row of 7 x 4 slots, the pager.
local function IconsLines(lines, vm)
	if vm.councillor and GamesOn() then
		lines[#lines + 1] = { nav = {
			{ text = L.MYPROFILE_EMBLEM_HEAD, selected = iconKind == "emblem", onClick = function() PE.SetSection("icons", "emblem") end },
			{ text = L.MYPROFILE_ICON_HEAD, selected = iconKind == "icon", onClick = function() PE.SetSection("icons", "icon") end },
		} }
	end
	local c = icons
	if not c then
		Words(lines, L.MYPROFILE_GAMES_OFF)
		return
	end
	local art = c.choice ~= nil and IconArt(c.choice) or nil
	local label = c.choice ~= nil and IconLabel(c.choice) or nil
	if c.kind == "icon" then
		-- (Our name as the game's chat shows it: the High Council's silver dragon, the icon after it;
		-- Borders.lua's stand-in, a client updated without a restart: the council's skull.)
		local Bd = ns.Borders
		local mark = type(Bd) == "table" and not Bd.missing and type(Bd.ChatMarkText) == "function" and Bd.ChatMarkText("silver") or ns.HIGH_COUNCIL_MARK
		local sample = "[" .. mark .. (art and ("|T" .. art .. ":0|t") or "") .. (ns.DisplayName(ns.me) or "?") .. "]"
		lines[#lines + 1] = { text = L.MYPROFILE_CHAT_SAMPLE:format(sample), right = label or L.COUNCIL_ICON_MARK_ONLY,
			tooltip = Tip(L.MYPROFILE_ICON_HEAD, L.MYPROFILE_ICON_HINT) }
	else
		lines[#lines + 1] = { text = L.MYPROFILE_EMBLEM_SAMPLE:format(art and Texture(art) or L.MYPROFILE_NONE_WORD), right = label or "",
			tooltip = Tip(L.MYPROFILE_EMBLEM_HEAD, L.MYPROFILE_EMBLEM_HINT) }
	end
	if c.names then
		lines[#lines + 1] = { text = L.COUNCIL_ICON_FILTER, input = { text = c.filter, onChange = function(text) PE.FilterIcons(text) end } }
	end
	local per = Per()
	local pages = math.max(1, math.ceil(#c.shown / per))
	c.page = math.max(1, math.min(c.page, pages))
	if #c.shown == 0 then
		lines[#lines + 1] = { indent = 1, text = Grey(L.COUNCIL_ICON_NONE) }
		return
	end
	local items, chosen = {}, IconKey(c.choice)
	for i = (c.page - 1) * per + 1, math.min(#c.shown, c.page * per) do
		local icon = c.shown[i]
		items[#items + 1] = { icon = IconArt(icon), label = IconLabel(icon), found = chosen ~= nil and IconKey(icon) == chosen, value = icon }
	end
	lines[#lines + 1] = { items = items, columns = PE.ICON_COLS, onItem = function(it) PE.ChooseIcon(it.value) end }
	lines[#lines + 1] = { nav = {
		{ text = "<", onClick = c.page > 1 and function() PE.IconPage(-1) end or nil },
		{ text = L.COUNCIL_ICON_PAGE:format(c.page, pages) },
		{ text = ">", onClick = c.page < pages and function() PE.IconPage(1) end or nil },
	} }
end

-- Who sees what: what goes out, his page as others open it (the person page's facts, each with
-- its source and freshness), and his choices of the privacy page's Profile section (Consent.lua),
-- each one click; the page itself for its long texts.
local function PrivacyLines(lines, facts)
	Words(lines, L.MYPROFILE_LOOK_PUBLIC)
	lines[#lines + 1] = { text = L.MYPROFILE_FACTS_HEAD, header = true }
	for _, line in ipairs(facts or {}) do lines[#lines + 1] = line end
	local C = ns.Consent
	if type(C) ~= "table" or C.missing or type(C.Items) ~= "function" then return end
	lines[#lines + 1] = { text = L.MYPROFILE_CHOICES_HEAD, header = true }
	for _, item in ipairs(C.Items("profile")) do
		local d = type(C.Describe) == "function" and C.Describe(item.key) or nil
		if d then
			local key, on = d.key, d.on == true
			lines[#lines + 1] = { indent = 1, text = d.label, right = d.state, tooltip = Tip(d.label, d.text ~= "" and d.text or nil),
				onClick = not d.readonly and function()
					C.Choose(key, not on)
					PE.Refresh()
				end or nil }
		end
	end
	if type(C.Show) == "function" then
		lines[#lines + 1] = { indent = 1, text = Gold("> " .. L.MYPROFILE_PRIVACY_PAGE), onClick = function() C.Show("profile") end }
	end
end

-- Letters: the King's, newest first, unread in gold; a click opens one in the King's letter window.
local function LetterLines(lines, vm)
	if #vm.letters == 0 then
		Words(lines, L.MYPROFILE_LETTERS_NONE)
		return
	end
	for i = #vm.letters, 1, -1 do
		local x = vm.letters[i]
		local key = x.key
		local title = x.title or key
		lines[#lines + 1] = { indent = 1, text = x.read and title or Gold(title),
			right = x.t and type(date) == "function" and Grey(date("%Y-%m-%d", x.t)) or "",
			onClick = function() H().ShowLetter(key) end }
	end
end

local function Buttons()
	local list = { { "PLAYER_PROFILE_BACK", function() PE.Back() end } }
	local AH = ns.ArenaHome
	if section == "look" and GamesOn() and type(AH) == "table" and type(AH.Open) == "function" then
		list[2] = { "MYPROFILE_GAMES_PROFILE", function() AH.Open("profile") end }
	elseif section == "icons" and icons then
		list[2] = { "COUNCIL_ICON_DEFAULT", function() PE.NoIcon() end }
		list[3] = { "MYPROFILE_USE", function() PE.UseIcon() end, enabled = IconKey(icons.choice) ~= IconKey(icons.current) }
	end
	return list
end

-- The detail box: as others see him (his title and nickname), and an own look he wears on his
-- screen alone named.
local function Seen(vm)
	local pv = vm.preview
	local text = L.MYPROFILE_SEEN_TEXT:format(pv.titleText or L.PROFILE_TITLE_NONE, pv.nick or L.MYPROFILE_NONE_WORD)
	for _, x in ipairs(vm.frames) do
		if x.own and x.selected then text = text .. "\n" .. L.MYPROFILE_OWN_LOOK:format(x.short or x.label) end
	end
	return text
end

-- His page (PlayerProfile.Build, on his own): lines (the section strip first), the detail box's
-- title and text, the bottom buttons, and the portrait's art: { frame (the one others verify),
-- emblem }. `facts`: the person page's rows of him (PlayerProfile's, with their sources).
function PE.Page(details, facts)
	drawn = true
	local vm = PE.ViewModel()
	if section == "icons" and not icons then SetSection("icons", iconKind) end
	local lines = { Nav(vm) }
	if section == "icons" then IconsLines(lines, vm)
	elseif section == "privacy" then PrivacyLines(lines, facts)
	elseif section == "letters" then LetterLines(lines, vm)
	else LookLines(lines, vm) end
	return lines, L.MYPROFILE_SEEN_TITLE, Seen(vm), Buttons(), { frame = vm.preview.frame, emblem = vm.preview.emblem }
end

-- The page's portrait (UI.lua makes it on the detail box, HonorsNet.NewPortrait) as another client
-- shows him: his emblem where he has one, else his live portrait (the Arena's reviewed rule: a
-- viewer who has him as no unit sees his emblem, and never his border preview or his own look), in
-- the frame others verify (art.frame: an honour's art, "rank" his rank's border, "none" none), as
-- HonorsNet.DressPortrait dresses his live one. What shows: "honour", "rank" or nil.
function PE.DressPortrait(rig, art)
	art = type(art) == "table" and art or {}
	local tex = type(rig) == "table" and rig.portrait or nil
	if not tex then return nil end
	local icon = art.emblem ~= nil and ns.CouncilIconTexture(art.emblem) or nil
	if not icon then
		if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
		return H().DressPortrait(rig, art.frame)
	end
	tex:SetTexture(icon)
	if tex.SetTexCoord then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end -- (the icon's own edge left out)
	local Bd = ns.Borders
	if rig.plain or type(Bd) ~= "table" or Bd.missing then return nil end
	local key = art.frame
	if type(key) == "string" and key ~= "rank" and key ~= "none" then
		if Bd.ShowHonour(rig, key) then return "honour" end
		Bd.ShowTier(rig, nil)
		return nil
	end
	local tier = key == "rank" and Bd.TierOf("player") or nil
	Bd.ShowTier(rig, tier)
	return tier and "rank" or nil
end

-- Opened in the Olympus window. what: nil or "look", "emblem" (Icons, on the emblem), "icon"
-- (Icons, on a councillor's chat icon; Look for anyone else), "privacy", "letters". opts.from =
-- "games": opened from the Games window's Profile (Back brings it back). False and why outside an
-- Olympus guild ("guild"), in combat before the page was first drawn ("combat"), or without the
-- window ("window").
local OPEN = { look = { "look" }, emblem = { "icons", "emblem" }, icon = { "icons", "icon" }, privacy = { "privacy" }, letters = { "letters" } }
function PE.Open(what, opts)
	if not ns.IsMember() then return false, "guild" end
	if InCombatLockdown and InCombatLockdown() and not drawn then return false, "combat" end
	local UI = ns.UI
	if type(UI) ~= "table" or type(UI.OpenPlayerProfile) ~= "function" then return false, "window" end
	local to = OPEN[what] or OPEN.look
	if what == "icon" and not Councillor() then to = OPEN.look end
	local wasShown = type(UI.IsShown) == "function" and UI.IsShown() == true
	local PP = ns.PlayerProfile
	local me = type(PP) == "table" and type(PP.Find) == "function" and PP.Find(ns.me) or nil
	if UI.OpenPlayerProfile(type(me) == "table" and me or { name = ns.me }) ~= true then return false, "window" end
	-- (After the window opened: its opening let go of an older page's section and Games return.)
	PE.SetSection(to[1], to[2])
	gamesReturn = type(opts) == "table" and opts.from == "games" and { shown = wasShown } or nil
	-- A King's letter waiting (the gamepad UI shows none by itself): this click opens it.
	local HN = H()
	if HN and HN.QueuedLetters and HN.QueuedLetters()[1] then HN.ShowLetter(nil, true) end
	return true
end

-- Back, the page's first button: the page before it (UI.BackFromPlayerProfile); opened from the
-- Games window, the Games window again on Profile, the Olympus window closed when it was before.
function PE.Back()
	local back = gamesReturn
	gamesReturn = nil
	local UI = ns.UI
	local ok = type(UI) == "table" and type(UI.BackFromPlayerProfile) == "function" and UI.BackFromPlayerProfile() == true
	if back then
		if not back.shown and type(UI.IsShown) == "function" and UI.IsShown() and type(UI.Toggle) == "function" then UI.Toggle() end
		local AH = ns.ArenaHome
		if type(AH) == "table" and type(AH.Open) == "function" then ns.SafeCall("games profile", AH.Open, "profile") end
	end
	return ok
end

-- What changes the page while it shows: a pick heard back, a choice made on the privacy page,
-- an own look (the author's border preview fires with it). Left (UI.lua: Back, a tab, the window
-- closed), it lets go of its list, of the Games return, and opens on Look next time.
for _, event in ipairs({ "HONORS_CHANGED", "CONSENT_CHANGED", "BORDERS_PREVIEW" }) do
	ns.On(event, function() RefreshSoon() end)
end
ns.On("PLAYER_PROFILE_LEFT", function(key)
	if key ~= nil and key ~= ns.Fold(tostring(ns.me)) then return end
	icons, gamesReturn, section = nil, nil, "look"
end)

-- The Realm's "My profile" (beside "My week", before the Board): this page. (rawget: a client of
-- the test world, over the harness's namespace, keeps its own list.)
function PE.Link()
	if not ns.IsMember() then return nil end
	return { text = "|TInterface\\Icons\\INV_Misc_Head_Human_01:14:14|t " .. Gold(L.MYPROFILE_LINK), onClick = function() PE.Open() end }
end
do
	local pages = rawget(ns, "RealmPages") or {}
	rawset(ns, "RealmPages", pages)
	table.insert(pages, { key = "myprofile", beforeBoard = true, Link = function() return PE.Link() end, Lines = function() return {} end })
end

Arena.Action("profile.edit", nil, function(what) return PE.Open(what) end)
