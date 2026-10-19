local ADDON, ns = ...
local L = ns.L

-- Embrace Anonymity: a moderator's cover name. The King, a High Councillor or the addon's author
-- turns it on when they need to (/oly cover), picking a first name and a surname. Two things follow.
--
-- Their name. Every client whose player accepted moderator protection on the privacy page (an
-- explicit Yes, Consent.lua) shows the cover name in place of the real one wherever Olympus can:
-- the game's target and focus frames and nameplates (below, the gate's "cover-names"), the player's
-- tooltip (Inspect.lua) and Olympus's own pages (Cover.Swap: the census, the person card, the
-- chats, the Board, the map's dots), without the Olympus marks a moderator carries (the council's
-- colour, skull and border, the King's, the dev's: Borders.lua, ChatWindow.lua, Channels.lua). A
-- fake name rather than a masked one: a hidden name draws the eye, and the character's looks would
-- give the rest away. The game's guild list, /who and chat keep the real name: only this addon
-- does it, only for those who said Yes, and turning the addon off shows the real name again. The
-- name the game draws above a character in the world is the game's alone (no addon changes one
-- player's): with friendly nameplates on, the nameplate takes its place.
--
-- Their presence. Their client leaves the Olympus network through quiet presence, Olympus's one
-- silence path (Core.lua's ns.SetQuietPresence, owner "cover"; Comm.QUIET_WORDS): no hello, census,
-- position, layer, hop, sighting or version answer. Quiet presence lasts a session and the cover is
-- kept: each login while it is on asks for it again. And every reporter's census gives them as
-- offline (Cover.Offline, Roster.lua), whatever its own player answered: that is the moderator's
-- request, not a display, and the one part that needs the cover's word on the wire (quiet sends
-- nothing, and the guild roster still shows them online). Their moderation work still goes out.
--
-- How it travels: MC~<cover name> on the Olympus channel or the guild, from the moderator's own
-- client, at once and again every ANNOUNCE_EVERY; MC~0 when it ends, repeated for OFF_REPEAT. The
-- sender is the server's name: a receiver takes it only from the King, a councillor of the signed
-- list or the author (Cover.Eligible), as the councillors' icons (Workshop.HandleIcon). Kept a while
-- (KEEP) in the realm's saved data, so a login before the next announcement still shows the cover.
-- Anyone reading the addon messages themselves can tie the two names: this protects what players
-- see on their screens, not the network.

local Cover = {}
ns.Cover = Cover

Cover.CONSENT_KEY = "moderatorCover"
Cover.CONSENT_VERSION = 1
Cover.ANNOUNCE_EVERY = 300 -- the moderator's client says it again this often (the ticker runs every 60 s)
Cover.OFF_REPEAT = 3600    -- and says it ended for this long after
Cover.KEEP = 12 * 3600     -- a cover heard is kept this long after it was last heard
Cover.MAX = 40             -- covers kept at most (the King, the signed council of 30, the author)
Cover.QUIET_OWNER = "cover" -- our name as quiet presence's owner (Core.lua)

Cover.random = math.random -- tests

local version = 0 -- bumped at every change of what any name shows (Borders' and the plates' inputs)
function Cover.Version() return version end

---------------------------------------------------------------------------
-- Who may, and what a cover name may be
---------------------------------------------------------------------------

function Cover.Eligible(name)
	if type(name) ~= "string" or name == "" then return false end
	if ns.IsKingCharacter(name) or ns.IsHighCouncillor(name) then return true end
	local W = ns.Workshop
	return type(W) == "table" and type(W.IsAuthorName) == "function" and W.IsAuthorName(name) == true
end

-- A word of a cover name: a capital then small letters (ASCII, or Latin-1's accented ones in UTF-8),
-- 2 to 12 letters. Returns the word with its first letter capital, or nil.
local function Word(w)
	if type(w) ~= "string" or w == "" then return nil end
	local letters = 0
	local i = 1
	while i <= #w do
		local b = w:byte(i)
		if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then
			i = i + 1
		elseif b == 0xC3 and i < #w and w:byte(i + 1) >= 0x80 and w:byte(i + 1) <= 0xBF and w:byte(i + 1) ~= 0x97 and w:byte(i + 1) ~= 0xB7 then
			i = i + 2
		else
			return nil
		end
		letters = letters + 1
	end
	if letters < 2 or letters > 12 then return nil end
	local first = w:sub(1, 1)
	if first:match("%l") then w = first:upper() .. w:sub(2) end
	return w
end

-- A cover name as typed or as it came: one or two words (Forever's names are a first name and a
-- surname), each Word's; spaces trimmed. Nothing else: no pipe, tilde or escape ever reaches a frame.
function Cover.Clean(s)
	if type(s) ~= "string" then return nil end
	s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	if s == "" or #s > 40 then return nil end
	local a, b = s:match("^(%S+) (%S+)$")
	if not a then a = s:match("^(%S+)$") end
	a = Word(a)
	if not a then return nil end
	if b then
		b = Word(b)
		if not b then return nil end
		return a .. " " .. b
	end
	return a
end

local function Store()
	local rdb = ns.rdb
	if not rdb then return nil end
	if type(rdb.covers) ~= "table" then rdb.covers = {} end
	return rdb.covers
end

local function Lower(s) return ns.Fold and ns.Fold(s) or s:lower() end

-- Is this cover name someone's real name we know, or another holder's cover? (`holder`: the one
-- whose cover it would be.) The King, the signed council, the author, our own name, our guild's
-- roster, and the covers kept.
function Cover.Taken(alias, holder)
	local key = Lower(alias)
	local function Same(name) return type(name) == "string" and Lower(ns.ShortName(name)) == key end
	if Same(ns.me) or Same(ns.AUTHOR) then return true end
	for _, pin in pairs(ns.KING_CHARACTER or {}) do if Same(pin) then return true end end
	local c = ns.rdb and ns.rdb.council
	if type(c) == "table" and type(c.names) == "table" and c.names[key] then return true end
	local R = ns.Roster
	if R and type(R.RankOf) == "function" and R.RankOf(ns.FullName(alias)) ~= nil then return true end
	local store = Store()
	holder = holder and ns.FullName(holder)
	for who, e in pairs(store or {}) do
		if who ~= holder and type(e) == "table" and type(e.alias) == "string" and Lower(e.alias) == key then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- The covers heard
---------------------------------------------------------------------------

local byShort -- [folded short name] = full name, rebuilt when the store changes
local function Changed()
	version = version + 1
	byShort = nil
	ns.Fire("COVER_CHANGED")
end

function Cover.Prune(now)
	local store = Store()
	if not store then return end
	now = now or ns.Now()
	local n, gone = 0, false
	for who, e in pairs(store) do
		if type(e) ~= "table" or type(e.alias) ~= "string" or not Cover.Clean(e.alias) or now - (tonumber(e.t) or 0) > Cover.KEEP
			or not Cover.Eligible(who) then
			store[who], gone = nil, true
		else
			n = n + 1
		end
	end
	while n > Cover.MAX do
		local oldest, at = nil, math.huge
		for who, e in pairs(store) do
			if (tonumber(e.t) or 0) < at then oldest, at = who, tonumber(e.t) or 0 end
		end
		if not oldest then break end
		store[oldest], n, gone = nil, n - 1, true
	end
	if gone then Changed() end
end

function Cover.Handle(dist, sender, text)
	if (dist ~= "CHANNEL" and dist ~= "GUILD") or type(text) ~= "string" or not Cover.Eligible(sender) then return end
	local who = ns.FullName(sender)
	if who == ns.FullName(ns.me) then return end
	local v = text:match("^MC~(.+)$")
	if not v then return end
	local store = Store()
	if not store then return end
	if v == "0" then
		if store[who] then
			store[who] = nil
			Changed()
		end
		return
	end
	local alias = Cover.Clean(v)
	if not alias or Cover.Taken(alias, who) then return end
	local had = store[who]
	store[who] = { alias = alias, t = ns.Now() }
	if not (type(had) == "table" and had.alias == alias) then Changed() end
	Cover.Prune()
end
ns.Comm.Handle("MC", function(...) Cover.Handle(...) end)

-- The cover a name has now (a fresh entry, its holder still one who may), whoever looks; nil when none.
local function Held(name)
	if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then return nil end
	local store = ns.rdb and ns.rdb.covers
	if type(store) ~= "table" or next(store) == nil then return nil end
	local full = ns.FullName(ns.Normal(name))
	local e = store[full]
	if not e then
		-- Forever's names are one per realm group: the same short name on another realm of ours.
		if not byShort then
			byShort = {}
			for who in pairs(store) do byShort[Lower(ns.ShortName(who))] = who end
		end
		local other = byShort[Lower(ns.ShortName(full))]
		local realm, otherRealm = ns.RealmOf(full), other and ns.RealmOf(other)
		if other and realm and otherRealm and ns.GroupOf(realm) == ns.GroupOf(otherRealm) then full, e = other, store[other] end
	end
	if type(e) ~= "table" or ns.Now() - (tonumber(e.t) or 0) > Cover.KEEP or not Cover.Eligible(full) then return nil end
	return e.alias, full
end

-- Has this client's player accepted moderator protection?
function Cover.Consented()
	local C = ns.Consent
	return type(C) == "table" and type(C.Answer) == "function" and C.Answer(Cover.CONSENT_KEY) == true
end

-- The cover name to show for this name on this client, or nil: a cover held, its player's Yes, and
-- never our own name (the moderator sees themselves as they are).
function Cover.AliasOf(name)
	if not Cover.Consented() then return nil end
	local alias, full = Held(name)
	if not alias or full == ns.FullName(ns.me) then return nil end
	return alias
end

-- A name as a page shows it: its cover where it has one, else the name as given.
function Cover.Swap(name)
	return Cover.AliasOf(name) or name
end
-- ns.DisplayName's twin for the pages (ns.DisplayName itself also names people in the census and
-- other messages, so it stays the real name).
function Cover.Shown(name)
	return Cover.AliasOf(name) or ns.DisplayName(name)
end

-- Shown offline in the census we send (Roster.lua): a cover held, whatever our player answered.
function Cover.Offline(name)
	local alias, full = Held(name)
	return alias ~= nil and full ~= ns.FullName(ns.me)
end

---------------------------------------------------------------------------
-- Our own cover
---------------------------------------------------------------------------

local function Mine()
	local db = ns.db
	if not db or not ns.me then return nil end
	local t = type(db.cover) == "table" and db.cover[ns.me]
	return type(t) == "table" and t or nil
end

-- Our cover name while it is on (and we still may), or nil.
function Cover.Active()
	local m = Mine()
	if not m or type(m.alias) ~= "string" then return nil end
	if not Cover.Eligible(ns.me) then return nil end
	return m.alias
end

-- Quiet presence on or off for the cover (Core.lua). On: true, or false and why ("authority": not
-- a current signed issuer or the author; "guild"); "owner" (another owner made us quiet already)
-- counts as quiet. Off ends only a quiet the cover turned on.
local function Quiet(on)
	if type(ns.SetQuietPresence) ~= "function" then return false, "missing" end
	local ok, why = ns.SetQuietPresence(on, Cover.QUIET_OWNER)
	if on and not ok and why == "owner" and ns.QuietPresence() then return true end
	return ok, why
end

local lastSaid = -math.huge
function Cover.Say(force)
	local m = Mine()
	if not m or not ns.IsMember() then return false end
	local now = ns.Now()
	local alias = Cover.Active()
	if not alias and not (m.off and now - m.off <= Cover.OFF_REPEAT) then return false end
	if not force and now - lastSaid < Cover.ANNOUNCE_EVERY then return false end
	lastSaid = now
	local msg = "MC~" .. (alias or "0")
	ns.Comm.Send("CHANNEL", msg, "cover", true)
	if IsInGuild() then ns.Comm.Send("GUILD", msg, "cover guild", true) end
	return true
end

function Cover.Enable(typed)
	if not Cover.Eligible(ns.me) then
		ns.Print(L.COVER_ONLY)
		return false
	end
	local alias = Cover.Clean(typed)
	if not alias then
		ns.Print(L.COVER_BAD)
		return false
	end
	if Cover.Taken(alias, ns.me) then
		ns.Print(L.COVER_TAKEN)
		return false
	end
	-- Off the network first: no cover without it.
	local quiet = Quiet(true)
	if not quiet then
		ns.Print(L.COVER_ONLY)
		return false
	end
	if type(ns.db.cover) ~= "table" then ns.db.cover = {} end
	ns.db.cover[ns.me] = { alias = alias, at = ns.Now() }
	Cover.Say(true)
	Changed()
	ns.Print(L.COVER_ON:format(alias))
	return true
end

function Cover.Disable()
	local m = Mine()
	if not m or not m.alias then
		ns.Print(L.COVER_STATUS_OFF)
		return false
	end
	ns.db.cover[ns.me] = { off = ns.Now() }
	Cover.Say(true)
	-- Back on the network (our hello follows quiet presence's end, Comm.lua).
	Quiet(false)
	Changed()
	ns.Print(L.COVER_OFF)
	return true
end

-- A suggestion for the box: a first name and a surname in Forever's way, none anyone has here.
local FIRST = { "Al", "Bran", "Cor", "Dal", "Ed", "Fen", "Gar", "Hal", "Ir", "Jor", "Kel", "Lor", "Mar", "Nor", "Os", "Per",
	"Ren", "Sel", "Tor", "Val", "Wil", "Yor" }
local FIRST_END = { "an", "en", "ric", "wyn", "ius", "ard", "on", "eth", "ias", "or", "ell", "ane" }
local SUR_START = { "Ash", "Black", "Bright", "Cold", "Dawn", "Ember", "Frost", "Gold", "Iron", "Oak", "Raven", "Silver",
	"Stone", "Storm", "Thorn", "Wolf" }
local SUR_END = { "brook", "field", "hart", "hollow", "mere", "ridge", "shield", "vale", "wood", "crest", "ford", "wick" }
function Cover.Suggest()
	local R = Cover.random
	for _ = 1, 20 do
		local s = FIRST[R(#FIRST)] .. FIRST_END[R(#FIRST_END)] .. " " .. SUR_START[R(#SUR_START)] .. SUR_END[R(#SUR_END)]
		local clean = Cover.Clean(s)
		if clean and not Cover.Taken(clean, ns.me) then return clean end
	end
	return nil
end

function Cover.Slash(rest)
	rest = type(rest) == "string" and rest:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if not Cover.Eligible(ns.me) then return ns.Print(L.COVER_ONLY) end
	local word = rest:lower()
	if word == "off" or word == "desligar" then return Cover.Disable() end
	if word == "status" then
		local m, alias = Mine(), Cover.Active()
		return ns.Print(alias and L.COVER_STATUS_ON:format(alias, date("%m-%d %H:%M", m.at or 0)) or L.COVER_STATUS_OFF)
	end
	if rest ~= "" then return Cover.Enable(rest) end
	local alias = Cover.Active()
	ns.ShowDialog("OLYMPUS_COVER", alias and L.COVER_PROMPT_ON:format(alias) or L.COVER_PROMPT)
end

StaticPopupDialogs["OLYMPUS_COVER"] = {
	text = "%s",
	button1 = L.COVER_ON_BTN,
	button2 = CANCEL or "Cancel",
	button3 = L.COVER_OFF_BTN,
	hasEditBox = true,
	editBoxWidth = 220,
	maxLetters = 27,
	OnShow = function(self)
		local alias = Cover.Active()
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText(alias or Cover.Suggest() or ""); eb:SetFocus() end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("cover", Cover.Enable, eb and eb:GetText())
	end,
	OnAlt = function() ns.SafeCall("cover", Cover.Disable) end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("cover", Cover.Enable, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- The privacy page's line
---------------------------------------------------------------------------

if ns.Consent and ns.Consent.Register then
	ns.Consent.Register({
		key = Cover.CONSENT_KEY,
		label = "COVER_CONSENT_LABEL",
		text = "COVER_CONSENT_TEXT",
		explicit = true,
		adopt = false,
		version = Cover.CONSENT_VERSION,
		get = function() local v = ns.db.coverConsent if v == nil then return nil end return v == true end,
		set = function(on)
			ns.db.coverConsent = on == true
			Changed()
		end,
	})
end

---------------------------------------------------------------------------
-- The game's name texts (the gate's "cover-names"): the target and focus frames' names, and the
-- names of the compact unit frames the game updates with CompactUnitFrame_UpdateName (nameplates,
-- raid frames). Each text we write is remembered with what the game had there; when the cover
-- ends, or at a switch to the gamepad UI, a text still ours gets the game's back. A text the game
-- wrote since is the game's: left alone. Names the client hides (secret values) are left as they are.
---------------------------------------------------------------------------

local written = setmetatable({}, { __mode = "k" }) -- [font string] = { alias, real }

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function Restore(fs) -- gp:cover-names!undo
	local w = written[fs]
	written[fs] = nil
	if not w then return end
	local ok, text = pcall(fs.GetText, fs)
	if ok and not Secret(text) and text == w.alias then fs:SetText(w.real) end
end

local function Write(fs, unit) -- gp:cover-names
	if not ns.Gate.Allowed("cover-names") then return end
	if type(fs) ~= "table" or type(fs.GetText) ~= "function" or type(fs.SetText) ~= "function" then return end
	local alias
	if type(unit) == "string" and unit ~= "" then
		local isPlayer = UnitIsPlayer(unit)
		if not Secret(isPlayer) and isPlayer then alias = Cover.AliasOf(ns.UnitFullName(unit)) end
	end
	local ok, text = pcall(fs.GetText, fs)
	if not ok or Secret(text) or type(text) ~= "string" then return end
	if not alias then
		if written[fs] then Restore(fs) end
		return
	end
	if text == alias then return end
	written[fs] = { alias = alias, real = text }
	fs:SetText(alias)
end

local function Forbidden(frame)
	return type(frame.IsForbidden) == "function" and frame:IsForbidden()
end

-- After the game's CompactUnitFrame_UpdateName: many times a second, so nothing but a lookup when
-- no cover is held and none of ours is written.
function Cover.NameUpdated(frame) -- gp:cover-names
	if not ns.Gate.Allowed("cover-names") then return end
	if type(frame) ~= "table" then return end
	local fs = frame.name
	if type(fs) ~= "table" then return end
	if not written[fs] then
		local store = ns.rdb and ns.rdb.covers
		if type(store) ~= "table" or next(store) == nil then return end
	end
	if Forbidden(frame) then return end
	Write(fs, frame.unit)
end

-- The target or focus frame's name text: the game's UnitFrame keeps it as .name.
local UNIT_FRAMES = { target = "TargetFrame", focus = "FocusFrame" }
local function NameText(frame)
	if type(frame) ~= "table" then return nil end
	if type(frame.name) == "table" then return frame.name end
	local content = frame.TargetFrameContent
	local main = type(content) == "table" and content.TargetFrameContentMain
	return type(main) == "table" and type(main.Name) == "table" and main.Name or nil
end
function Cover.FrameUpdated(unit) -- gp:cover-names
	if not ns.Gate.Allowed("cover-names") then return end
	local frame = _G[UNIT_FRAMES[unit] or ""] -- gp:cover-names
	if type(frame) ~= "table" or Forbidden(frame) then return end
	Write(NameText(frame), unit)
end
function Cover.FramesSoon()
	ns.After(0, "cover frames", function()
		Cover.FrameUpdated("target")
		Cover.FrameUpdated("focus")
	end)
end

-- The plates' and compact frames' names: after the game's CompactUnitFrame_UpdateName, on the
-- nameplates' own hook (Nameplates.OnNameUpdate: one hook on it a session). The target and focus
-- frames: on the game's events that rewrite their name (below), on the next frame.
local function NameListener(frame)
	if not ns.Gate.Allowed("cover-names") then return end
	Cover.NameUpdated(frame)
end
local function Install() -- gp:cover-names!hook
	local N = ns.Nameplates
	if type(N) == "table" and type(N.OnNameUpdate) == "function" then N.OnNameUpdate(NameListener) end
end

local function RestoreAll() -- gp:cover-names!undo
	local list = {}
	for fs in pairs(written) do list[#list + 1] = fs end
	for _, fs in ipairs(list) do Restore(fs) end
end

ns.Gate.Hooks("cover-names", {
	install = function() Install(); Cover.FramesSoon() end,
	park = RestoreAll,
})

-- A change of covers or of our answer: every text of ours given back, the frames worked out again
-- (the plates follow at the game's next update of their names).
ns.On("COVER_CHANGED", function()
	RestoreAll()
	if ns.Gate.Allowed("cover-names") then Cover.FramesSoon() end
	-- The Olympus window's pages drawn again (the chat window listens itself, ChatWindow.lua).
	if ns.UI and type(ns.UI.Refresh) == "function" then ns.UI.Refresh() end
end)

-- Quiet presence lasts a session: our cover asks for it again at each login (quiet before anything
-- of ours goes out: LOGIN's other listeners say hello later).
function Cover.Resume()
	if not Cover.Active() then return false end
	local ok, why = Quiet(true)
	if not ok then ns.Log("cover: quiet presence refused (%s)", tostring(why)) end
	return ok
end

ns.On("LOGIN", function()
	Cover.Resume()
	Cover.Prune()
	ns.Gate.Install("cover-names")
	Cover.Say(true)
	ns.Every(60, "cover", function()
		Cover.Say()
		Cover.Prune()
	end)
end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() if ns.Gate.Allowed("cover-names") then Cover.FramesSoon() end end)
pcall(ns.RegisterEvent, "PLAYER_FOCUS_CHANGED", function() if ns.Gate.Allowed("cover-names") then Cover.FramesSoon() end end)
ns.RegisterEvent("UNIT_NAME_UPDATE", function(unit)
	if (unit == "target" or unit == "focus") and ns.Gate.Allowed("cover-names") then Cover.FramesSoon() end
end)
