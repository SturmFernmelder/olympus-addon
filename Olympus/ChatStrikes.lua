local ADDON, ns = ...
local L = ns.L

-- Chat warnings (the author, 2026-10-19: "Vamos fazer a cada 24 horas e vamos fazer três mesmo. É,
-- primeiro avisa e bota um bloqueio de 5 minutos, alguma coisa assim, e apaga e esconde a mensagem
-- que a pessoa mandou. Segundo, esconde, bloqueio de 30, avisa o negócio. É isso. Terceiro, avisa a
-- equipe de moderação, bloqueia o uso do chat da pessoa até a equipe de moderação decidir e assim
-- por diante ... A equipe de moderação precisa ver o que ele digitou ... quais foram as palavras
-- que ele usou").
-- A word of the built-in list in the words a player typed is refused on his own client, before
-- anything leaves (WatchChat.RefuseSevere: the three chats, a pin, every room, the fight rooms):
--   1st in a rolling 24 hours (the server's clock): not sent, his box and reply cleared, a pop-up
--       saying why (no age can be checked, Blizzard's Terms of Service, screenshots, Asmongold's
--       team moderates), his Olympus chats paused 5 minutes;
--   2nd: the same, "you're doing it again", 30 minutes;
--   3rd and every later one in the window: held out of the chats until an Olympus moderator decides
--       (lets him chat, or gives a timeout of his own), and the team is sent what he typed.
-- A decision never restarts the count ("e assim por diante"). A hold nobody decides lapses in 30
-- days, as every hold. A line typed while paused or held is refused before its words are read:
-- warnings never stack. Chats only: the block is never a moderator's timeout (WatchChat's
-- timeouts), so no power, game, map, Crafting or wallet bar comes with it and no other client
-- silences him. The King and the author have the line refused and counted, nothing more (nobody
-- could decide their hold); The Watch's own room is not checked (staff quote what was said).
-- What is kept: the struck lines alone, on this client, 30 days (ns.rdb.chatStrikes: the
-- account's characters of this realm group and faction share it). Ordinary chat is never kept or
-- relayed. The team: the author while online, the King, the signed High Council and the Olympus
-- moderators named (ChatRooms' "watch" audience, WatchChat.RoomRecipients). From the third
-- warning his client (the character that typed it) sends each of them, by logged whisper:
--   MS~1~H~<id>~<n>~<c24>~<c30>~<k>~<guild>               the head (id: the hold's time)
--   MS~1~L~<id>~<i>~<at>~<n>~<where>~<words>~<text>        k lines: up to 3 of the window, 2 earlier
--   MS~1~K~<id>                                            team -> him: kept
--   MS~1~P~<id>                                            him -> one of the team: decided?
--   MS~1~D~<Name-Realm>~<id>~<R|T>~<at>                    decided: R let him chat, T a timeout
-- A case is kept under the name the server stamped on its sender (a modified client can only
-- incriminate itself); a decision counts from someone who may act on him in Olympus scope
-- (WatchChat.Authority "O"), or from an Olympus moderator's own timeout on him (WatchChat's Apply).
-- Never on the channel or over GUILD. Clients without this file ignore MS.
-- Limits: an older client's player gets no warning, nor does a line typed in the game's own guild
-- box; matching is whole words (ChatStrikes.Hits says which spellings), so a new spelling, a word
-- split in pieces of two letters or more, or letters added inside it are missed and the
-- moderators' own tools still cover them.

local S = {}
ns.ChatStrikes = S

S.PROTOCOL = 1
S.WINDOW = 86400              -- "a cada 24 horas": a rolling day, by the server's clock
S.PAUSES = { 300, 1800 }      -- the 1st and 2nd warnings (WatchChat.DURATIONS' 5 and 30 minutes)
S.HOLD_AT = 3                 -- from this warning on: held until the team decides
S.KEEP = 30 * 86400           -- struck lines and the team's cases (WatchChat.KEEP)
S.HOLD_MAX = 30 * 86400       -- a hold nobody decided lapses (WatchChat.HOLD_MAX)
S.MINE_MAX = 20
S.CASES_MAX = 100
S.TEXT_MAX = 140              -- a struck line's window around its first word (The Watch's report line)
S.LEAD = 40                   -- ...starting about this far before it
S.WORDS_MAX = 60
S.WHERE_MAX = 16
S.HITS_MAX = 3
S.IN_WINDOW, S.EARLIER = 3, 2 -- lines a report carries: of the window, and from the 30 days before it
S.LINES_MAX = 5
S.PER_TICK = 2                -- team members sent a report a minute
S.RETRY = 900                 -- an unacknowledged one is sent again this long after...
S.TRIES = 3                   -- ...this many times at most for one hold
S.PING = 600                  -- "decided?" to one of the team this often while held
S.QUEUE_SPARE = 20            -- Comm's queue keeps this much room for everything else
S.HEADS_HOUR = 6              -- reports taken from one sender an hour...
S.HEADS_ALL = 30              -- ...and from all senders in ten minutes
S.PINGS_HOUR = 6
S.PENDING_MAX, S.PENDING_FOR = 20, 120 -- reports whose lines are still coming
S.NOTICE_GAP = 600            -- the team's notice of one name at most this often
S.DATE_AHEAD = 60
S.TEXTS_KEPT = 128            -- texts whose words were read (as Filter.WordsOf keeps them)
S.FORMS_KEPT = 512            -- forms whose digest was made
S.MESSAGE_MAX = 255
S.SALT = "olympus-strike-1:"

-- The words: digests, not words. Each key is the first 8 bytes, in hex, of SHA-256 over SALT and
-- the word's canonical form (ChatStrikes.Canon), and each value that form's length in bytes. This
-- keeps the words out of GitHub and the CurseForge package (as ProfileEffects.lua's caption); it
-- is not secret: anyone can hash a word list and compare. scripts/strike-digest.lua makes the
-- table from a plain list kept outside this repository. Empty: nothing is checked, nothing changes.
S.LIST = {
}
S.LENGTHS = {}

-- The lengths of the forms worth hashing, from the list's values (after a change to S.LIST).
function S.Index()
	local lengths = {}
	for _, n in pairs(S.LIST) do if type(n) == "number" then lengths[n] = true end end
	S.LENGTHS = lengths
	return lengths
end
S.Index()

local function Grey(s) return "|cff9d9d9d" .. tostring(s or "") .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Red(s) return "|cffff6060" .. tostring(s or "") .. "|r" end
local function Green(s) return "|cff40ff40" .. tostring(s or "") .. "|r" end
local function Live(t) return type(t) == "table" and not t.missing and t or nil end
local function Clock() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or ns.Now() end
local function Now() return ns.Now() end
local function Key(s) return ns.Fold(tostring(s or "")) end
local function Same(a, b) return type(a) == "string" and type(b) == "string" and a ~= "" and Key(a) == Key(b) end
local function WC() return Live(ns.WatchChat) end
local function Hour(t) return date and date("%H:%M", t) or tostring(t) end
local function Stamp(t) return date and date("%Y-%m-%d %H:%M", t) or tostring(t) end

local function Int(s, low, high)
	local n = tonumber(s)
	if not n or n ~= math.floor(n) or n < low or n > high or not tostring(s):match("^%d+$") then return nil end
	return n
end

---------------------------------------------------------------------------
-- Matching
---------------------------------------------------------------------------

-- Deleted, not made spaces (a space would split the word): zero-width and direction marks
-- (U+200B-U+200F), the word joiner and invisible operators (U+2060-U+2064), U+FEFF and the soft
-- hyphen (U+00AD).
local INVISIBLE = { "\226\128[\139-\143]", "\226\129[\160-\164]", "\239\187\191", "\194\173" }
local SYMBOL = { ["@"] = "a", ["$"] = "s", ["!"] = "i" }
local LEET = { ["0"] = "o", ["3"] = "e", ["4"] = "a", ["5"] = "s", ["7"] = "t" }
-- Latin-1's letters, capital or small (UTF-8 C3 80-BF), without their accents; × and ÷ stay.
local PLAIN = {}
do
	local function Set(from, to, plain) for b = from, to do PLAIN["\195" .. string.char(b)] = plain end end
	for _, base in ipairs({ 0x80, 0xA0 }) do
		Set(base, base + 5, "a"); Set(base + 6, base + 6, "ae"); Set(base + 7, base + 7, "c"); Set(base + 8, base + 11, "e")
		Set(base + 12, base + 15, "i"); Set(base + 16, base + 16, "d"); Set(base + 17, base + 17, "n"); Set(base + 18, base + 22, "o")
		Set(base + 24, base + 24, "o"); Set(base + 25, base + 28, "u"); Set(base + 29, base + 29, "y"); Set(base + 30, base + 30, "th")
	end
	PLAIN["\195\159"], PLAIN["\195\191"] = "ss", "y"
end
-- Cyrillic and Greek letters drawn as Latin ones (а е о р с у х і ј ѕ, ο α ν ι κ ρ τ, and their
-- capitals that look the same): read so only in a word that also holds a Latin letter.
local LOOK = {
	["\208\176"] = "a", ["\208\181"] = "e", ["\208\190"] = "o", ["\209\128"] = "p", ["\209\129"] = "c", ["\209\131"] = "y",
	["\209\133"] = "x", ["\209\150"] = "i", ["\209\152"] = "j", ["\209\149"] = "s",
	["\208\144"] = "a", ["\208\149"] = "e", ["\208\158"] = "o", ["\208\160"] = "p", ["\208\161"] = "c", ["\208\163"] = "y",
	["\208\165"] = "x", ["\208\134"] = "i", ["\208\136"] = "j", ["\208\133"] = "s",
	["\206\191"] = "o", ["\206\177"] = "a", ["\206\189"] = "v", ["\206\185"] = "i", ["\206\186"] = "k", ["\207\129"] = "p",
	["\207\132"] = "t",
	["\206\159"] = "o", ["\206\145"] = "a", ["\206\157"] = "n", ["\206\153"] = "i", ["\206\154"] = "k", ["\206\161"] = "p",
	["\206\164"] = "t",
}

local function Lower(s) return (s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)) end
local function Chars(s) return select(2, s:gsub("[^\128-\191]", "")) end

-- A text as its words are read: invisible characters out; @ $ ! as letters only between two
-- letters or digits (an @Name mention stays a mention); a link's [text] kept and the case folded
-- as a search reads it (ns.Searchable); the general and Latin-1 punctuation blocks made spaces.
local function Prepare(s)
	s = tostring(s or "")
	for _, p in ipairs(INVISIBLE) do s = s:gsub(p, "") end
	s = s:gsub("(%w)([@%$!])%f[%w]", function(a, sym) return a .. SYMBOL[sym] end)
	local Codec = ns.Codec
	if Codec and Codec.SanitizeChat then s = Codec.SanitizeChat(s) end
	s = ns.Searchable and ns.Searchable(s) or Lower(s)
	return (s:gsub("\226\128[\128-\191]", " "):gsub("\194[\128-\191]", " "))
end

-- One word as the list reads it: no accents; with a Latin letter in it, the look-alikes as Latin
-- letters and 0 3 4 5 7 as o e a s t (a 1 is both i and l: Forms).
local function Base(token)
	token = token:gsub("\195[\128-\191]", PLAIN)
	if token:find("%a") then
		token = token:gsub("[\206-\209][\128-\191]", LOOK)
		token = token:gsub("[03457]", LEET)
	end
	return token
end

-- Runs of 3 or more of one letter made `to` long (an exact double is never touched: a doubled
-- letter is part of a word, and its single-letter neighbour another word).
local function Squeeze(s, to)
	if not s:find("(%a)%1%1") then return s end
	local out, i, n = {}, 1, #s
	while i <= n do
		local c, j = s:sub(i, i), i
		while j < n and s:sub(j + 1, j + 1) == c do j = j + 1 end
		out[#out + 1] = (j - i >= 2 and c:find("%a")) and c:rep(to) or s:sub(i, j)
		i = j + 1
	end
	return table.concat(out)
end

-- The forms one word is looked up as: as it is, its runs squeezed to two, and to one; with a 1 in
-- a word of letters, each with the 1 as i and as l.
local function Forms(token, add)
	local base = Base(token)
	local variants = { base }
	if base:find("1", 1, true) and base:find("%a") then variants = { (base:gsub("1", "i")), (base:gsub("1", "l")) } end
	for _, v in ipairs(variants) do
		add(v); add(Squeeze(v, 2)); add(Squeeze(v, 1))
	end
end

-- Every word of a text with its forms, and every run of 3 or more one-character words joined
-- ("s l u r", "s.l.u.r", "s-l-u-r", "s*l*u*r"): { { word = as typed, forms = { ... } } }.
local function Build(raw)
	local s = Prepare(raw)
	local out = {}
	local function Candidate(word, src)
		local forms, seen = {}, {}
		Forms(src, function(f) if f ~= "" and not seen[f] then seen[f] = true; forms[#forms + 1] = f end end)
		out[#out + 1] = { word = word, forms = forms }
	end
	local run = {}
	local function Flush()
		if #run >= 3 then Candidate(table.concat(run, " "), table.concat(run)) end
		run = {}
	end
	for w in s:gmatch("[%w\128-\255]+") do
		Candidate(w, w)
		if Chars(w) == 1 then run[#run + 1] = w else Flush() end
	end
	Flush()
	return out
end

-- Kept in two halves (Filter.WordsOf's way): a text's words, a form's digest.
local textsNow, textsBefore, textsCount = {}, {}, 0
local formsNow, formsBefore, formsCount = {}, {}, 0
local function Candidates(raw)
	local c = textsNow[raw]
	if c then return c end
	c = textsBefore[raw] or Build(raw)
	if textsCount >= S.TEXTS_KEPT then textsBefore, textsNow, textsCount = textsNow, {}, 0 end
	textsNow[raw], textsCount = c, textsCount + 1
	return c
end

local function Hex8(bytes)
	local out = {}
	for i = 1, 8 do out[i] = ("%02x"):format(bytes:byte(i) or 0) end
	return table.concat(out)
end

-- A form's digest: the list's key for it (16 lowercase hex characters).
function S.Digest(form)
	local Sg = ns.Sign
	if type(form) ~= "string" or type(Sg) ~= "table" or type(Sg.SHA256) ~= "function" then return nil end
	return Hex8(Sg.SHA256(S.SALT .. form))
end
local function DigestOf(form)
	local d = formsNow[form]
	if d then return d end
	d = formsBefore[form] or S.Digest(form)
	if not d then return nil end
	if formsCount >= S.FORMS_KEPT then formsBefore, formsNow, formsCount = formsNow, {}, 0 end
	formsNow[form], formsCount = d, formsCount + 1
	return d
end

-- A word of a plain list as the list keeps it (scripts/strike-digest.lua): one word, its accents,
-- look-alikes and digits read as Base reads them, runs of 3 or more squeezed to two; nil and why
-- for anything else (two words, a 1 or another digit left).
function S.Canon(word)
	if type(word) ~= "string" then return nil, "word" end
	local token
	for w in Prepare(word):gmatch("[%w\128-\255]+") do
		if token then return nil, "words" end
		token = w
	end
	if not token then return nil, "empty" end
	local form = Squeeze(Base(token), 2)
	if form:find("%d") then return nil, "digit" end
	return form
end

-- The list's words in a text, as typed (up to HITS_MAX), or nil. Whole words only: no part of a
-- word, stem or near spelling. Only forms of a length the list holds are hashed.
function S.Hits(raw)
	if next(S.LIST) == nil or type(raw) ~= "string" or raw == "" then return nil end
	local hits, seen
	for _, c in ipairs(Candidates(raw)) do
		if not (seen and seen[c.word]) then
			for _, form in ipairs(c.forms) do
				if S.LENGTHS[#form] then
					local d = DigestOf(form)
					if d and S.LIST[d] == #form then
						hits, seen = hits or {}, seen or {}
						hits[#hits + 1], seen[c.word] = c.word, true
						if #hits >= S.HITS_MAX then return hits end
						break
					end
				end
			end
		end
	end
	return hits
end

---------------------------------------------------------------------------
-- What this client keeps (ns.rdb.chatStrikes)
--   mine:  this account's struck lines here, newest last: { at, n, char, where, words, text,
--          untilAt (a pause's end; 0 a hold), decided = { op, by, at } }
--   out:   the report of the hold now on: { id, to = { [name key] = { name, tries, last, acked } }, pinged }
--   cases: a team member's reports: ["<sender key>#<id>"] = { name, guild, id, n, c24, c30, heard,
--          lines = { { at, n, where, words, text } }, decided }
---------------------------------------------------------------------------

local function Store()
	local rdb = ns.rdb
	if type(rdb) ~= "table" then return nil end
	local s = rdb.chatStrikes
	if type(s) ~= "table" or s.v ~= 1 then
		s = { v = 1 }
		rdb.chatStrikes = s
	end
	if type(s.mine) ~= "table" then s.mine = {} end
	if type(s.cases) ~= "table" then s.cases = {} end
	if s.out ~= nil and type(s.out) ~= "table" then s.out = nil end
	return s
end
S.Store = Store

local function Entry(e) return type(e) == "table" and Int(e.at, 1, 2147483647) ~= nil and Int(e.n, 1, 9999) ~= nil end

local function Prune(s)
	local now = Clock()
	for i = #s.mine, 1, -1 do
		local e = s.mine[i]
		if not Entry(e) or now - e.at > S.KEEP then table.remove(s.mine, i) end
	end
	while #s.mine > S.MINE_MAX do table.remove(s.mine, 1) end
	local n, oldest, at = 0, nil, nil
	for key, c in pairs(s.cases) do
		if type(c) ~= "table" or not Int(c.id, 1, 2147483647) or now - c.id > S.KEEP then s.cases[key] = nil
		else n = n + 1 end
	end
	while n > S.CASES_MAX do
		oldest, at = nil, nil
		for key, c in pairs(s.cases) do
			-- (a decided case goes before any open one)
			local rank = (c.decided and 0 or S.KEEP * 2) + c.id
			if not at or rank < at then oldest, at = key, rank end
		end
		s.cases[oldest] = nil
		n = n - 1
	end
end
S.Prune = Prune

-- Struck lines of this account in (from - span, from].
local function Within(s, from, span)
	local n = 0
	for _, e in ipairs(s.mine) do
		if Entry(e) and e.at > from - span and e.at <= from then n = n + 1 end
	end
	return n
end

-- The block on this account's chats now, from its newest struck line: { kind = "pause", entry, ends }
-- while a 1st or 2nd warning's pause lasts, { kind = "hold", entry } while a later one waits for
-- the team (until HOLD_MAX), else nil.
function S.Block(now)
	local s = Store()
	local e = s and s.mine[#s.mine]
	if not Entry(e) then return nil end
	now = now or Clock()
	if e.n < S.HOLD_AT then
		local ends = tonumber(e.untilAt) or 0
		if ends > now then return { kind = "pause", entry = e, ends = ends } end
		return nil
	end
	if type(e.decided) ~= "table" and now < e.at + S.HOLD_MAX then return { kind = "hold", entry = e } end
	return nil
end

---------------------------------------------------------------------------
-- The player: a struck line, and the block it leaves
---------------------------------------------------------------------------

local lastPopup = -math.huge

local function Tell(text)
	local W = WC()
	if W and W.TellDecision then return W.TellDecision(text) end
	ns.ShowDialog("OLYMPUS_WATCHCHAT_DECISION", text)
	return true
end

local function Span(seconds)
	local W = WC()
	return W and W.Span and W.Span(seconds) or tostring(seconds)
end

function S.BlockText(b)
	if type(b) ~= "table" then return "" end
	if b.kind == "hold" then return L.WATCHCHAT_STRIKE_HELD end
	return L.WATCHCHAT_STRIKE_PAUSED:format(Hour(b.ends))
end

-- A line refused while paused or held: a pop-up at most every POPUP_GAP (force: always), else a
-- red line. The block, or nil.
function S.TellBlock(b, force)
	b = b or S.Block()
	if not b then return nil end
	local text = S.BlockText(b)
	local W = WC()
	if not force and Now() - lastPopup < (W and W.POPUP_GAP or 60) then
		ns.Print(Red(text))
		return b
	end
	lastPopup = Now()
	Tell(text)
	return b
end

-- The Chat tab's strip and input hint while blocked.
function S.StripText()
	local b = S.Block()
	if not b then return nil end
	if b.kind == "hold" then return L.WATCHCHAT_STRIP_STRIKE_HOLD end
	return L.WATCHCHAT_STRIP_STRIKE:format(Hour(b.ends))
end

-- Nobody could decide the hold of the King or the author (WatchChat.Authority: nobody above them).
local function Exempt()
	local W = WC()
	return ns.me ~= nil and W ~= nil and type(W.ProtectLevel) == "function" and type(W.LEVEL) == "table"
		and W.ProtectLevel(ns.me) >= W.LEVEL.king
end

local function Clean(s, max)
	local W = Live(ns.Watch)
	if W and W.CleanLine then return W.CleanLine(s, max) end
	s = tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
	s = s:gsub("[~|%^%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, max)
end

-- Where a line was typed, as a report names it: A C L (the channels), P (a pin), F (a fight
-- room), R:<room>.
local function Code(where) return ns.Cut((tostring(where or "?"):gsub("[^%w:_%-]", "")), S.WHERE_MAX) end
local function WhereCode(where)
	where = tostring(where or "?")
	if where ~= "A" and where ~= "C" and where ~= "L" and where ~= "P" and where ~= "F" then where = "R:" .. where end
	return Code(where)
end

-- The struck line as kept and reported: The Watch's report form, at most TEXT_MAX bytes from about
-- LEAD before the first word, never inside a character, "..." where it was cut.
local function Window(body, first)
	local line = Clean(body, S.MESSAGE_MAX)
	if #line <= S.TEXT_MAX then return line end
	local at = type(first) == "string" and ns.Fold(line):find(first, 1, true) or 1
	local from = math.max(1, at - S.LEAD)
	local b = line:byte(from)
	while from > 1 and b and b >= 128 and b < 192 do from = from - 1; b = line:byte(from) end
	local head = from > 1 and "..." or ""
	local rest = line:sub(from)
	if #head + #rest <= S.TEXT_MAX then return head .. rest end
	return head .. ns.Cut(rest, S.TEXT_MAX - #head - 3):gsub("%s+$", "") .. "..."
end

local function WordsText(hits)
	return ns.Cut(Clean(table.concat(hits, ", "), S.WORDS_MAX), S.WORDS_MAX)
end

local function PopupText(e)
	if e.n == 1 then return L.WATCHCHAT_STRIKE_1:format(Span(e.untilAt - e.at)) end
	if e.n == 2 then return L.WATCHCHAT_STRIKE_2:format(Span(e.untilAt - e.at)) end
	if e.n == S.HOLD_AT then return L.WATCHCHAT_STRIKE_3 end
	return L.WATCHCHAT_STRIKE_MORE:format(e.n)
end

-- A line with a word of the list: counted (WatchChat's blocked lines: never the words), told,
-- kept, and the warning's block on.
local function Strike(body, hits, where)
	local W = WC()
	if ns.me and W and W.CountBlocked then W.CountBlocked(ns.me, "severe") end
	ns.Print(Red(L.WATCHCHAT_SEVERE_REFUSED))
	local s = Store()
	if Exempt() or not s or not ns.me then return "severe" end
	Prune(s)
	local now = math.floor(Clock())
	local last = s.mine[#s.mine]
	-- (A hold's time is its report's id: never one an earlier line of this account has.)
	if Entry(last) and last.at >= now then now = last.at + 1 end
	local n = 1 + Within(s, now, S.WINDOW)
	local e = { at = now, n = n, char = ns.me, where = WhereCode(where), words = WordsText(hits), text = Window(body, hits[1]),
		untilAt = n < S.HOLD_AT and now + (S.PAUSES[n] or S.PAUSES[#S.PAUSES]) or 0 }
	s.mine[#s.mine + 1] = e
	while #s.mine > S.MINE_MAX do table.remove(s.mine, 1) end
	Tell(PopupText(e))
	ns.Fire("WATCHCHAT_CHANGED", "W", ns.me)
	if n >= S.HOLD_AT then
		s.out = { id = e.at, to = {}, pinged = Now() }
		S.Tick()
	end
	return "severe"
end

-- WatchChat.RefuseSevere: "severe" (refused, told, a warning given), or nil and the line to send:
-- the raw line, or without its quote of another's line when only the quote holds such a word (the
-- one who replies is never warned for it). The raw line: Codec.SanitizeChat drops the separator
-- ChatWindow.EncodeReply puts between a quote and the words typed.
function S.Refuse(raw, where)
	if next(S.LIST) == nil or type(raw) ~= "string" then return nil, raw end
	if where == "watch" then return nil, raw end
	local quote, body = nil, raw
	local CW = Live(ns.ChatWindow)
	if CW and type(CW.DecodeReply) == "function" then
		local reply, rest = CW.DecodeReply(raw)
		if reply and type(rest) == "string" then quote, body = raw:sub(1, #raw - #rest), rest end
	end
	local hits = S.Hits(body)
	if hits then return Strike(body, hits, where) end
	if quote and S.Hits(quote) then return nil, body end
	return nil, raw
end

---------------------------------------------------------------------------
-- The report: from the third warning, to the team (MS)
---------------------------------------------------------------------------

local function Team()
	local R = Live(ns.ChatRooms)
	local list = R and R.Recipients and R.Recipients("watch")
	return type(list) == "table" and list or {}
end

local function Whisper(to, msg, permit, id)
	local C = ns.Comm
	if type(msg) ~= "string" or #msg > S.MESSAGE_MAX or type(C) ~= "table" or type(C.Whisper) ~= "function" then return false end
	return C.Whisper(to, msg, nil, false, true, nil, { owner = S, key = "ms:" .. tostring(id), permit = permit }) ~= false
end

-- At the game send: still this hold, still a whisper to someone of the team.
local function ReportPermit(id, recipient)
	return function(owner, _, dist, target)
		if owner ~= S or dist ~= "WHISPER" or not Same(target, recipient) then return false, "guard" end
		local b = S.Block()
		if not b or b.kind ~= "hold" or b.entry.at ~= id then return false, "revoked" end
		local W = WC()
		if not (W and W.InRoom and W.InRoom(recipient)) then return false, "revoked" end
		return true
	end
end
local function ReplyPermit(recipient)
	return function(owner, _, dist, target)
		if owner ~= S or dist ~= "WHISPER" or not Same(target, recipient) then return false, "guard" end
		return true
	end
end

-- The lines a hold's report carries, oldest first: up to IN_WINDOW of its window (the hold's own
-- among them) and EARLIER from the 30 days before.
local function ReportLines(s, e)
	local inside, before = {}, {}
	for i = #s.mine, 1, -1 do
		local x = s.mine[i]
		if Entry(x) and x.at <= e.at then
			if x.at > e.at - S.WINDOW then
				if #inside < S.IN_WINDOW then inside[#inside + 1] = x end
			elseif x.at > e.at - S.KEEP and #before < S.EARLIER then
				before[#before + 1] = x
			end
		end
	end
	local out = {}
	for i = #before, 1, -1 do out[#out + 1] = before[i] end
	for i = #inside, 1, -1 do out[#out + 1] = inside[i] end
	return out
end

local function GuildWord(g) return ns.Cut((tostring(g or ""):gsub("[~|%^%c]", "")), 72) end

local function ReportMessages(s, e)
	local lines = ReportLines(s, e)
	local guild = GuildWord(GetGuildInfo and GetGuildInfo("player"))
	if #lines == 0 or guild == "" then return nil end
	local out = { ("MS~1~H~%d~%d~%d~%d~%d~%s"):format(e.at, e.n, Within(s, e.at, S.WINDOW), Within(s, e.at, S.KEEP), #lines, guild) }
	for i, x in ipairs(lines) do
		local head = ("MS~1~L~%d~%d~%d~%d~%s~%s~"):format(e.at, i, x.at, x.n, Code(x.where), ns.Cut(Clean(x.words, S.WORDS_MAX), S.WORDS_MAX))
		out[#out + 1] = head .. ns.Cut(Clean(x.text, S.TEXT_MAX), math.min(S.TEXT_MAX, S.MESSAGE_MAX - #head))
	end
	-- (Each fits by its fields' bounds; one that would not is never cut short in flight.)
	for _, m in ipairs(out) do if #m > S.MESSAGE_MAX then return nil end end
	return out
end
S.ReportMessages = ReportMessages -- (tests)

-- Every minute (and at once from a third warning): while a hold waits for the team, this
-- character (the one that typed it) sends its report to PER_TICK of the team online who have not
-- said they keep it, each RETRY apart and TRIES times at most (saved: a /reload starts nothing
-- over), and asks one of them every PING whether it was decided. Not in a lockdown (the game
-- holds addon messages there: the report waits for it to end), nor out of Olympus.
function S.Tick()
	local s = Store()
	if not s then return end
	local b = S.Block()
	local e = b and b.kind == "hold" and b.entry or nil
	if not e then s.out = nil return end
	if type(s.out) ~= "table" or s.out.id ~= e.at then s.out = { id = e.at, to = {}, pinged = Now() } end
	if not ns.me or not Same(e.char, ns.me) or not ns.IsMember() or (ns.ChatLocked and ns.ChatLocked()) then return end
	local out, now = s.out, Now()
	if type(out.to) ~= "table" then out.to = {} end
	local msgs = ReportMessages(s, e)
	if not msgs then return end
	local C = ns.Comm
	local team, sent = Team(), 0
	for _, name in ipairs(team) do
		if sent >= S.PER_TICK then break end
		local key = Key(name)
		local r = type(out.to[key]) == "table" and out.to[key] or { tries = 0 }
		out.to[key] = r
		local tries = tonumber(r.tries) or 0
		if not r.acked and tries < S.TRIES and (not tonumber(r.last) or now - r.last >= S.RETRY) then
			if C and C.QueueRoom and C.QueueRoom() < #msgs + S.QUEUE_SPARE then break end
			r.name, r.tries, r.last = name, tries + 1, now
			for _, m in ipairs(msgs) do Whisper(name, m, ReportPermit(e.at, name), e.at) end
			sent = sent + 1
		end
	end
	if now - (tonumber(out.pinged) or -math.huge) >= S.PING and #team > 0 then
		local to = team[1]
		for _, name in ipairs(team) do
			local r = out.to[Key(name)]
			if type(r) == "table" and r.acked then to = name break end
		end
		out.pinged = now
		Whisper(to, ("MS~1~P~%d"):format(e.at), ReportPermit(e.at, to), e.at)
	end
end

---------------------------------------------------------------------------
-- The team's side, and every MS taken
---------------------------------------------------------------------------

local stats = { taken = 0, refused = 0 }
local heads, headsAll, pings, pending, told = {}, {}, {}, {}, {}

local function Refused(why, sender)
	stats.refused = stats.refused + 1
	-- (Who and why only: never a word or a line, which /oly bug would carry.)
	if sender then ns.Log("chat warning message from %s refused: %s", tostring(sender), tostring(why)) end
	return false, why
end

-- `max` times in `span` seconds from one list of times: false once spent.
local function Budget(list, max, span)
	local now = Now()
	for i = #list, 1, -1 do if now - list[i] >= span then table.remove(list, i) end end
	if #list >= max then return false end
	list[#list + 1] = now
	return true
end
local function Each(t, key)
	local list = t[key] or {}
	t[key] = list
	return list
end

local function Split(s, max)
	local out, from = {}, 1
	while true do
		local at = s:find("~", from, true)
		if not at then out[#out + 1] = s:sub(from) return out end
		out[#out + 1] = s:sub(from, at - 1)
		from = at + 1
		if #out >= max then return nil end
	end
end

local function ShownBy(name)
	local W = Live(ns.Watch)
	if W and W.ShownBy then return W.ShownBy(name) end
	return ns.DisplayName(name) or tostring(name or "?")
end
local function Masked() return ns.CouncilMasked ~= nil and ns.CouncilMasked() == true end

local function Linked(name)
	local A = Live(ns.Alts)
	local list = A and A.Linked and A.Linked(name)
	return type(list) == "table" and list or {}
end
-- The same player: the name, or a name his player linked (both ways, as WatchChat's actions read it).
local function SamePerson(a, b)
	if Same(a, b) then return true end
	for _, other in ipairs(Linked(a)) do if Same(other, b) then return true end end
	for _, other in ipairs(Linked(b)) do if Same(other, a) then return true end end
	return false
end

local function Reply(to, msg) return Whisper(to, msg, ReplyPermit(to), "r") end

local function Changed()
	ns.Fire("WATCH_CHANGED")
end

local function TakeHead(sender, f)
	local W = WC()
	if #f ~= 9 then return Refused("shape", sender) end
	if not (W and W.InRoom and W.InRoom(ns.me)) then return Refused("audience", sender) end
	local guild, now = f[9], Clock()
	if not ns.IsFederation(guild) then return Refused("guild", sender) end
	local id = Int(f[4], 1, 2147483647)
	if not id or id < now - S.KEEP or id > now + S.DATE_AHEAD then return Refused("time", sender) end
	local n, c24, c30, k = Int(f[5], S.HOLD_AT, 9999), Int(f[6], 1, 9999), Int(f[7], 1, 99999), Int(f[8], 1, S.LINES_MAX)
	if not n or not c24 or not c30 or not k then return Refused("count", sender) end
	local who = Key(sender)
	if not Budget(Each(heads, who), S.HEADS_HOUR, 3600) or not Budget(headsAll, S.HEADS_ALL, 600) then return Refused("rate", sender) end
	local s = Store()
	if not s then return false, "store" end
	if s.cases[who .. "#" .. id] then
		Reply(sender, ("MS~1~K~%d"):format(id))
		return true, "repeat"
	end
	for _, c in pairs(s.cases) do
		if Same(c.name, sender) and c.id > id then return Refused("old", sender) end
	end
	local live, t = 0, Now()
	for key, p in pairs(pending) do
		if t - p.t > S.PENDING_FOR then pending[key] = nil elseif key ~= who then live = live + 1 end
	end
	if live >= S.PENDING_MAX then return Refused("busy", sender) end
	pending[who] = { id = id, n = n, c24 = c24, c30 = c30, k = k, guild = guild, lines = {}, got = 0, t = t }
	return true
end

local function CleanField(s, max)
	return type(s) == "string" and s ~= "" and #s <= max and Clean(s, max) == s
end

local function TakeLine(sender, f)
	if #f ~= 10 then return Refused("shape", sender) end
	local who = Key(sender)
	local p = pending[who]
	local id = Int(f[4], 1, 2147483647)
	if not p or p.id ~= id or Now() - p.t > S.PENDING_FOR then return Refused("head", sender) end
	local i, at, n = Int(f[5], 1, p.k), Int(f[6], 1, 2147483647), Int(f[7], 1, 9999)
	if not i or p.lines[i] or not at or at > p.id + S.DATE_AHEAD or at < p.id - S.KEEP or not n then return Refused("line", sender) end
	local where, words, text = f[8], f[9], f[10]
	if not (type(where) == "string" and where:match("^[%w:_%-]+$") and #where <= S.WHERE_MAX)
		or not CleanField(words, S.WORDS_MAX) or not CleanField(text, S.TEXT_MAX) then return Refused("field", sender) end
	p.lines[i] = { at = at, n = n, where = where, words = words, text = text }
	p.got = p.got + 1
	if p.got < p.k then return true end
	pending[who] = nil
	local s = Store()
	if not s then return false, "store" end
	local c = { name = sender, guild = p.guild, id = p.id, n = p.n, c24 = p.c24, c30 = p.c30, heard = Now(), lines = p.lines }
	-- (An Olympus moderator's timeout on him given since the hold, heard before the report.)
	local W = WC()
	local e = W and W.TimeoutOf and W.TimeoutOf(sender)
	if type(e) == "table" and e.scope == "O" and (tonumber(e.at) or 0) >= p.id then c.decided = { op = "T", by = e.by, at = e.at } end
	s.cases[who .. "#" .. p.id] = c
	Prune(s)
	stats.taken = stats.taken + 1
	if Now() - (told[who] or -math.huge) >= S.NOTICE_GAP then
		told[who] = Now()
		ns.Print(Gold(L.WATCHCHAT_STRIKE_IN:format(ShownBy(sender), p.n)))
		if ns.PlayAlert then ns.PlayAlert("soft", "watch") end
	end
	Reply(sender, ("MS~1~K~%d"):format(p.id))
	Changed()
	return true
end

local function TakeAck(sender, f)
	if #f ~= 4 then return Refused("shape", sender) end
	local s, id = Store(), Int(f[4], 1, 2147483647)
	local out = s and s.out
	local r = type(out) == "table" and out.id == id and type(out.to) == "table" and out.to[Key(sender)] or nil
	if type(r) ~= "table" or not r.last then return Refused("audience", sender) end
	r.acked = true
	return true
end

local function DecisionWire(c)
	return ("MS~1~D~%s~%d~%s~%d"):format(c.name, c.id, c.decided.op, tonumber(c.decided.at) or 0)
end

local function TakePing(sender, f)
	if #f ~= 4 then return Refused("shape", sender) end
	local s, id = Store(), Int(f[4], 1, 2147483647)
	local c = s and id and s.cases[Key(sender) .. "#" .. id]
	if type(c) ~= "table" then return Refused("case", sender) end
	if not Budget(Each(pings, Key(sender)), S.PINGS_HOUR, 3600) then return Refused("rate", sender) end
	if type(c.decided) == "table" and (c.decided.op == "R" or c.decided.op == "T") then Reply(sender, DecisionWire(c)) end
	return true
end

-- A decision on this account's hold (its own client) or on a case this client keeps (the team's).
local function TakeDecision(sender, f)
	if #f ~= 7 then return Refused("shape", sender) end
	local W = WC()
	local name = W and W.CharName and W.CharName(f[4])
	local id, op, at = Int(f[5], 1, 2147483647), f[6], Int(f[7], 1, 2147483647)
	if not name or not id or (op ~= "R" and op ~= "T") or not at or at < id or at > Clock() + S.DATE_AHEAD then return Refused("shape", sender) end
	local ok, why = W.Authority(sender, name, "O")
	if not ok then return Refused(why or "rank", sender) end
	local s = Store()
	if not s then return false, "store" end
	local taken, result = false, "case"
	local b = S.Block()
	for _, e in ipairs(s.mine) do
		if Entry(e) and e.at == id and Same(e.char, name) and e.n >= S.HOLD_AT then
			if type(e.decided) == "table" then result = "repeat"
			elseif not (b and b.kind == "hold" and b.entry == e) then result = "old"
			else
				e.decided = { op = op, by = sender, at = at }
				taken = true
				if op == "R" then ns.Print(Green(L.WATCHCHAT_STRIKE_RELEASED)) end
				ns.Fire("WATCHCHAT_CHANGED", "W", ns.me)
			end
		end
	end
	local c = s.cases[Key(name) .. "#" .. id]
	if type(c) == "table" then
		if type(c.decided) == "table" then
			if not taken then result = "repeat" end
		else
			c.decided = { op = op, by = sender, at = at }
			taken = true
			Changed()
		end
	end
	if taken then return true end
	if result == "repeat" then return true, "repeat" end
	return Refused(result, sender)
end

function S.Handle(dist, sender, text)
	if type(text) ~= "string" or #text > S.MESSAGE_MAX then return Refused("size") end
	if dist ~= "WHISPER" then return Refused("lane", sender) end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then
		return Refused("unlogged", sender)
	end
	local W = WC()
	sender = W and W.CharName and W.CharName(sender)
	if not sender then return Refused("sender") end
	if Same(sender, ns.me) then return Refused("self", sender) end
	local f = Split(text, 10)
	if not f or f[1] ~= "MS" or f[2] ~= "1" then return Refused("shape", sender) end
	local op = f[3]
	if op == "H" then return TakeHead(sender, f) end
	if op == "L" then return TakeLine(sender, f) end
	if op == "K" then return TakeAck(sender, f) end
	if op == "P" then return TakePing(sender, f) end
	if op == "D" then return TakeDecision(sender, f) end
	return Refused("op", sender)
end

if ns.Comm and ns.Comm.Handle then ns.Comm.Handle("MS", function(dist, sender, text) S.Handle(dist, sender, text) end) end

-- WatchChat's Apply: an Olympus moderator's timeout on him (or a name his player linked), given
-- since the hold, decides it: the hold gives way to the timeout, on his client and in the team's
-- cases. A guild's timeout and a lift decide nothing.
function S.Decided(op, target, at, by)
	local s = Store()
	if not s or type(target) ~= "string" then return end
	at = tonumber(at) or 0
	local mine = false
	local b = S.Block()
	if b and b.kind == "hold" and SamePerson(target, b.entry.char) and at >= b.entry.at then
		b.entry.decided = { op = op, by = by, at = at }
		mine = true
	end
	local cases = false
	for _, c in pairs(s.cases) do
		if type(c) == "table" and type(c.decided) ~= "table" and SamePerson(target, c.name) and at >= (tonumber(c.id) or math.huge) then
			c.decided = { op = op, by = by, at = at }
			cases = true
		end
	end
	if mine then ns.Fire("WATCHCHAT_CHANGED", "W", ns.me) end
	if cases then Changed() end
end

-- "Let them chat": this client's decision on a case, if it may act on him in Olympus scope; told to
-- him and to the team online.
function S.Release(key)
	local s = Store()
	local c = s and s.cases[key]
	local W = WC()
	if type(c) ~= "table" or not W then return false, "case" end
	local ok, why = W.Authority(ns.me, c.name, "O")
	if not ok then
		ns.Print(L.WATCHCHAT_FAILED:format(W.WhyText and W.WhyText(why) or tostring(why)))
		return false, why
	end
	if type(c.decided) == "table" then return false, "decided" end
	c.decided = { op = "R", by = ns.me, at = math.max(math.floor(Clock()), c.id) }
	local msg = DecisionWire(c)
	Reply(c.name, msg)
	for _, name in ipairs(Team()) do if not Same(name, c.name) then Reply(name, msg) end end
	ns.Print(Green(L.WATCHCHAT_STRIKE_DONE:format(ShownBy(c.name))))
	Changed()
	return true
end

---------------------------------------------------------------------------
-- What the team sees: The Watch's Chat moderation page, the dialog, the copy, the commands
---------------------------------------------------------------------------

local function WhereText(where)
	where = tostring(where or "")
	local C = Live(ns.Channels)
	local tier = C and C.TIERS and C.TIERS[where]
	if tier then return L[tier.label] or where end
	if where == "P" then return L.WATCHCHAT_STRIKE_WHERE_P end
	if where == "F" then return L.WATCHCHAT_STRIKE_WHERE_F end
	return L.WATCHCHAT_STRIKE_WHERE_R:format((where:gsub("^R:", "")))
end

local function CaseWords(c)
	local out, seen = {}, {}
	for i = 1, S.LINES_MAX do
		local l = c.lines and c.lines[i]
		for w in tostring(type(l) == "table" and l.words or ""):gmatch("[^,]+") do
			w = w:gsub("^%s+", ""):gsub("%s+$", "")
			if w ~= "" and not seen[w] then seen[w] = true; out[#out + 1] = w end
		end
	end
	return table.concat(out, ", ")
end

local function StateText(c)
	local d = c.decided
	if type(d) ~= "table" then return Gold(L.WATCHCHAT_STRIKE_OPEN) end
	if d.op == "R" then return Green(L.WATCHCHAT_STRIKE_LET_BY:format(ShownBy(d.by))) end
	return Grey(L.WATCHCHAT_STRIKE_TIMED_BY:format(ShownBy(d.by)))
end

-- The copy pop-up's text of these cases ("pop-ups, not chat": the author copies it): each line
-- with when, where and its words. On the King's stream the words and lines are hidden.
function S.CopyText(keys)
	local s = Store()
	local out = {}
	for _, key in ipairs(keys or {}) do
		local c = s and s.cases[key]
		if type(c) == "table" then
			if #out > 0 then out[#out + 1] = "" end
			out[#out + 1] = L.WATCHCHAT_STRIKE_COPY_HEAD:format(ShownBy(c.name), tostring(c.guild or "?"), c.n, c.c24 or c.n, c.c30 or c.n)
			for i = 1, S.LINES_MAX do
				local l = c.lines and c.lines[i]
				if type(l) == "table" then
					out[#out + 1] = L.WATCHCHAT_STRIKE_COPY_LINE:format(Stamp(l.at), WhereText(l.where),
						Masked() and L.NETOFF_REASON_HIDDEN or l.words)
					out[#out + 1] = "    " .. (Masked() and L.NETOFF_REASON_HIDDEN or l.text)
				end
			end
		end
	end
	out[#out + 1] = ""
	out[#out + 1] = L.WATCHCHAT_STRIKE_COPY_NOTE
	return table.concat(out, "\n")
end

function S.ShowCopy(keys)
	local UI = Live(ns.UI)
	if not (UI and UI.ShowCopy) then return false end
	UI.ShowCopy(L.WATCHCHAT_STRIKES_TITLE, S.CopyText(keys), nil, { key = "watch-strike" })
	return true
end

function S.AskText(c)
	return L.WATCHCHAT_STRIKE_ASK:format(ShownBy(c.name), c.n, Masked() and L.NETOFF_REASON_HIDDEN or CaseWords(c))
end

function S.Ask(key)
	local s = Store()
	local c = s and s.cases[key]
	if type(c) ~= "table" then return false end
	return ns.ShowDialog("OLYMPUS_WATCHCHAT_STRIKE", S.AskText(c), nil, { key = key, name = c.name })
end

local function Sorted(s)
	local list = {}
	for key, c in pairs(s.cases) do if type(c) == "table" then list[#list + 1] = { key = key, c = c } end end
	table.sort(list, function(a, b)
		local ao, bo = type(a.c.decided) ~= "table", type(b.c.decided) ~= "table"
		if ao ~= bo then return ao end
		return (tonumber(a.c.id) or 0) > (tonumber(b.c.id) or 0)
	end)
	return list
end

-- WatchChat.PageLines, for the team (WatchChat.InRoom): the cases, open first. Nothing while none.
function S.Rows(lines)
	local s = Store()
	if not s then return end
	local list, open = Sorted(s), 0
	if #list == 0 then return end
	for _, x in ipairs(list) do if type(x.c.decided) ~= "table" then open = open + 1 end end
	lines[#lines + 1] = { header = true, text = L.WATCHCHAT_STRIKES_TITLE, right = Grey(tostring(open)),
		tooltip = function(tt) tt:AddLine(L.WATCHCHAT_STRIKES_TITLE, 1, 0.82, 0); tt:AddLine(L.WATCHCHAT_STRIKES_TIP, 1, 1, 1, true) end }
	for i = 1, math.min(15, #list) do
		local key, c = list[i].key, list[i].c
		local who = ShownBy(c.name)
		lines[#lines + 1] = { indent = 1, text = Red(who) .. "  " .. Grey(L.WATCHCHAT_STRIKE_ROW:format(c.n)) .. "  " .. StateText(c),
			right = Grey(ns.Ago(c.heard)),
			onClick = function() S.Ask(key) end,
			tooltip = function(tt)
				tt:AddLine(who, 1, 0.82, 0)
				tt:AddLine(L.WATCHCHAT_STRIKE_WORDS:format(Masked() and L.NETOFF_REASON_HIDDEN or CaseWords(c)), 1, 1, 1, true)
				tt:AddLine(L.WATCHCHAT_STRIKE_CLICK, 0.6, 0.6, 0.6, true)
			end }
	end
	lines[#lines].gapAfter = true
end

-- /oly watch strikes: the open cases in the copy pop-up. /oly watch release <Name-Realm>: lets the
-- newest open case of that name chat.
function S.Slash(verb, rest)
	local W = WC()
	if not (W and W.InRoom and ns.me and W.InRoom(ns.me)) then return ns.Print(L.WATCH_NO_ACCESS) end
	local s = Store()
	if not s then return false end
	if verb == "strikes" then
		local keys = {}
		for _, x in ipairs(Sorted(s)) do if type(x.c.decided) ~= "table" then keys[#keys + 1] = x.key end end
		if #keys == 0 then ns.Print(L.WATCHCHAT_STRIKES_NONE) return false end
		return S.ShowCopy(keys)
	elseif verb == "release" then
		local name = W.CharName(rest)
		if not name then return ns.Print(L.WATCH_BAD_NAME) end
		for _, x in ipairs(Sorted(s)) do
			if type(x.c.decided) ~= "table" and Same(x.c.name, name) then return S.Release(x.key) end
		end
		ns.Print(L.WATCHCHAT_STRIKE_NOT_FOUND:format(ns.DisplayName(name) or name))
		return false
	end
	ns.Print(L.WATCHCHAT_STRIKES_USAGE)
	return false
end

-- The team's dialog on a case (WatchChat's OLYMPUS_WATCHCHAT_ACT's way): let him chat, a timeout
-- (WatchChat's own dialogs: an Olympus moderator's timeout decides the case), or every line.
if StaticPopupDialogs then
	StaticPopupDialogs["OLYMPUS_WATCHCHAT_STRIKE"] = {
		text = "%s",
		button1 = L.WATCHCHAT_STRIKE_LET, button2 = L.WATCHCHAT_TIMEOUT_BTN, button3 = L.WATCHCHAT_STRIKE_SHOW,
		OnAccept = function(self, data)
			data = data or (self and self.data)
			ns.SafeCall("chat warnings", S.Release, data and data.key)
		end,
		OnCancel = function(self, data, reason)
			data = data or (self and self.data)
			local W = WC()
			if reason == "clicked" and data and W and W.AskName then ns.SafeCall("chat warnings", W.AskName, data.name, "timeout") end
		end,
		OnAlt = function(self, data)
			data = data or (self and self.data)
			if data then ns.SafeCall("chat warnings", S.ShowCopy, { data.key }) end
		end,
		noCancelOnEscape = true,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
end

function S.Stats() return stats end

function S.ResetForTests()
	textsNow, textsBefore, textsCount = {}, {}, 0
	formsNow, formsBefore, formsCount = {}, {}, 0
	wipe(heads); wipe(headsAll); wipe(pings); wipe(pending); wipe(told)
	lastPopup = -math.huge
	for k in pairs(stats) do stats[k] = 0 end
end

ns.On("LOGIN", function()
	local s = Store()
	if s then Prune(s) end
	if ns.Every then ns.Every(60, "chat warnings", function() S.Tick() end) end
end)
