-- 1.2.4, the author's ask (rankings and what shows them are never lost, and pass from client to
-- client): the King's (or a named councillor's) word that shows a game's ranking to everyone (AU,
-- ArenaRoles.lua) is the realm group's, and any client holding it tells it. Before, each word was
-- kept under its giver's realm and only its giver repeated it, so a member who never was online with
-- him, or one on another realm of the group, never saw the Games tab's rankings at all.
-- On the test world (tests/arena/lib/world.lua); every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local N = World.NAMES

local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end
local function Public(w, c, game) return w:As(c, c.ns.ArenaHome.RankingsPublic, game) end
local function Word(w, c, game) return w:As(c, c.ns.ArenaRoles.PublishWord, game) end
local function AUs(w, from)
	local out = {}
	for _, s in ipairs(w:Sent({ from = from, type = "AU" })) do out[#out + 1] = s end
	return out
end
-- An AU on the channel, as a modified client would send it.
local function Say(w, c, body, dist)
	w:As(c, function() c.ns.Arena.Send("AU", "L", body, { dist = dist or "CHANNEL" }) end)
	w:Run(0)
end
-- The member opens the Games tab (the Olympus window's), then long enough for the answers.
local function Opens(w, c)
	w:As(c, c.ns.ArenaHome.TabLines)
	local R = c.ns.ArenaRoles
	w:Run((R.ANSWER_MIN or 2) + (R.ANSWER_SPREAD or 10) + 2)
end

print("1.2.4: the rankings' publish word, kept and told by any holder")

test("1.2.4 rankings word: the King shows Bones' ranking and logs out; a member who logs in later opens the Games tab and asks, a member who holds the word tells it (its giver named), and the tab shows the ranking", function()
	local w = World.New()
	local king = w:Role("king")
	local lida = w:Client("Lida Fenn")
	assert(w:As(king, king.ns.ArenaRoles.Publish, "bones", true))
	w:Run(0)
	eq(Public(w, lida, "bones"), true, "heard from the King")
	w:Logout(king)
	w:Run(king.ns.ArenaRoles.REPEAT * 2)
	local late = w:Client("Parric Stowe")
	w:Run(3600)
	eq(Public(w, late, "bones"), false, "nothing heard yet")
	eq(#AUs(w, late) + #AUs(w, lida), 0, "nobody sends anything unasked")
	Opens(w, late)
	eq(Public(w, late, "bones"), true, "told by a member who holds it")
	local word = Word(w, late, "bones")
	eq(word.from, N.king, "the King's word, as he gave it"); eq(word.on, true)
	local said = AUs(w, lida)
	assert(#said >= 1, "Lida told it")
	assert(said[#said].msg:find("^AU~L1~b~1~%d+~" .. N.king:gsub("%-", "%%-") .. "$"), said[#said].msg)
	-- (the ask names the games it lacks, once a session; a 1.2.3 client ignores both forms)
	local asks = AUs(w, late)
	eq(#asks, 1); eq(asks[1].msg, "AU~L1~q~abl", "it lacked them all")
	Opens(w, late)
	eq(#AUs(w, late), 1, "once a session")
	-- the word stays through the late member's relog, the King still away
	w:Logout(late); w:Logout(lida)
	w:Login(late)
	eq(Public(w, late, "bones"), true, "kept in his saved data")
	NoErrors(w)
end)

test("1.2.4 rankings word: it is the realm group's: a word kept under the giver's realm (as 1.2.4 before kept it) counts on the group's other realm, and a guildmate tells it over the guild to a realm the King's channel never reaches", function()
	local w = World.New()
	local king = w:Role("king")
	local far = w:Client("Wenna Crale", { realm = World.REALMS[2] })
	-- (a word as the build before kept it: under the King's realm, in the saved data of a client of
	-- the other realm, an account that also plays there)
	w:Logout(far)
	local rdb = far.saved.db.realms[World.GROUP]
	rdb.arena = rdb.arena or {}
	rdb.arena.realms = rdb.arena.realms or {}
	rdb.arena.realms[World.REALMS[1]] = { v = 1, roles = { rankPub = { arena = { on = true, at = w.clock - 60, from = N.king, t = w.clock - 60 } },
		rankLog = { { game = "arena", on = true, at = w.clock - 60, from = N.king } } } }
	w:Login(far)
	eq(Public(w, far, "arena"), true, "the group's word")
	eq(#w:As(far, far.ns.ArenaRoles.PublishLog), 1, "its log too")
	-- The King shows Bones on his realm's channel: the other realm's channel never hears it.
	local lida = w:Client("Lida Fenn")
	assert(w:As(king, king.ns.ArenaRoles.Publish, "bones", true))
	w:Run(0)
	eq(Public(w, lida, "bones"), true)
	eq(Public(w, far, "bones"), false, "another realm's channel")
	-- Wenna opens the Games tab; their guild spans the group's realms: she asks it too, and Lida's
	-- client answers there.
	far.ns.Comm.SpansRealms = function() return true end
	Opens(w, far)
	eq(Public(w, far, "bones"), true, "heard over the guild")
	local said = AUs(w, lida)
	eq(said[#said].dist, "GUILD")
	eq(Word(w, far, "bones").from, N.king)
	NoErrors(w)
end)

test("1.2.4 rankings word: a copy (unsigned) only fills: never over a word heard from its giver; the giver's own word replaces any copy of his; a copy naming one who may not publish counts nowhere", function()
	local w = World.New()
	local king = w:Role("king")
	local lida = w:Client("Lida Fenn")
	local x = w:Client("Idris Fold")
	assert(w:As(king, king.ns.ArenaRoles.Publish, "bones", true))
	w:Run(0)
	local at = Word(w, lida, "bones").at
	-- x says the King hid it, a second later: Lida heard the King himself, and keeps his word.
	Say(w, x, ("b~0~%d~%s"):format(at + 1, N.king))
	eq(Public(w, lida, "bones"), true, "a copy never replaces the giver's own word")
	-- A member who heard nothing takes x's copy (it only fills)...
	w:Logout(king)
	local late = w:Client("Parric Stowe")
	Say(w, x, ("b~0~%d~%s"):format(at + 2, N.king))
	eq(Public(w, late, "bones"), false, "the made-up copy, while nothing else is heard")
	eq(Word(w, late, "bones").copy, true)
	-- ...until the King's own word: his, whatever its time.
	w:Login(king)
	w:Run(king.ns.ArenaRoles.LOGIN_REPEAT + 1)
	eq(Public(w, late, "bones"), true, "the King's own word replaces a copy of it")
	eq(Word(w, late, "bones").copy, nil)
	-- A copy naming a councillor the King never named for Bones: nowhere.
	local other = w:Client("Tessa Morrow")
	Say(w, x, ("b~1~%d~%s"):format(at + 5, N.councillor2))
	eq(Word(w, other, "bones"), nil, "not a publisher")
	eq(Public(w, other, "bones"), false)
	-- A copy older than the copy held: ignored.
	local fresh = w:Client("Odo Brask")
	Say(w, x, ("b~1~%d~%s"):format(at + 10, N.king))
	Say(w, x, ("b~0~%d~%s"):format(at + 9, N.king))
	eq(Public(w, fresh, "bones"), true, "the newer copy stands")
	NoErrors(w)
end)

-- (The review) A copy is unsigned: one naming another publisher (a councillor the King named for that
-- game), dated after the King's word, held on a member's client that heard neither giver. The King's
-- own word, older than the made-up copy, must still replace it: any giver's own word replaces any copy.
-- Before, it was refused as older, at every repeat of his, so the made-up copy stood for good there.
test("1.2.4 rankings word: a made-up copy naming another publisher, newer than the King's word, gives way to the King's own word at his next repeat", function()
	local w = World.New()
	local king, hc = w:Role("king"), w:Role("councillor")
	local late = w:Client("Parric Stowe")
	-- (the member hears the King name the councillor, then is away when the King shows Bones)
	assert(w:As(king, king.ns.ArenaRoles.SetPublishers, { { name = hc.name, games = { bones = true } } }))
	w:Run(0)
	w:Logout(late)
	assert(w:As(king, king.ns.ArenaRoles.Publish, "bones", true))
	w:Run(0)
	local at = Word(w, king, "bones").at
	w:Logout(king); w:Logout(hc)
	w:Run(3 * 3600)
	local x = w:Client("Idris Fold")
	w:Login(late)
	w:Run(0)
	eq(w:As(late, late.ns.ArenaRoles.MayPublish, hc.name, "bones"), true, "the councillor publishes Bones")
	eq(Word(w, late, "bones"), nil, "no word heard")
	-- x makes up the councillor's word hiding Bones, an hour after the King's
	Say(w, x, ("b~0~%d~%s"):format(at + 3600, hc.name))
	eq(Public(w, late, "bones"), false, "the made-up copy, while nothing else is heard")
	-- the King logs in: his client says his own word again (its time the same, older than the copy)
	w:Login(king)
	w:Run(king.ns.ArenaRoles.LOGIN_REPEAT + 1)
	eq(Public(w, late, "bones"), true, "the King's own word replaces the copy")
	eq(Word(w, late, "bones").from, N.king); eq(Word(w, late, "bones").copy, nil)
	-- and a copy, newer still, never replaces it again
	Say(w, x, ("b~0~%d~%s"):format(at + 7200, hc.name))
	eq(Public(w, late, "bones"), true, "a copy never replaces a giver's own word")
	NoErrors(w)
end)

-- (The review) "About three holders whatever the army's size": the channel joins every Olympus guild,
-- so a holder's odds to answer an ask heard there are three in the army's addon users (the census's,
-- King.AddonsOnline, as the signed authority's answers draw), not three in his own guild's (Comm's
-- peers): with thirty guilds about ninety holders were drawn for each ask. Over the guild, his
-- guild's.
test("1.2.4 rankings word: a holder answers an ask on the channel at the army's odds, over the guild at his guild's", function()
	local w = World.New()
	local king = w:Role("king")
	local lida = w:Client("Lida Fenn")
	assert(w:As(king, king.ns.ArenaRoles.Publish, "bones", true))
	w:Run(0)
	w:Logout(king)
	local late = w:Client("Parric Stowe")
	-- (Lida's draw: one half; the army's addon users online: 300, her guild's few)
	lida.ns.ArenaRoles.random = function() return 0.5 end
	lida.ns.King.AddonsOnline = function() return 300 end
	local before = #AUs(w, lida)
	Say(w, late, "q~b")
	w:Run(lida.ns.ArenaRoles.ANSWER_MIN + lida.ns.ArenaRoles.ANSWER_SPREAD + 2)
	eq(#AUs(w, lida), before, "three in 300 on the channel: not drawn")
	eq(Public(w, late, "bones"), false)
	w:Run(lida.ns.ArenaRoles.ANSWER_GAP + 1)
	Say(w, late, "q~b", "GUILD")
	w:Run(lida.ns.ArenaRoles.ANSWER_MIN + lida.ns.ArenaRoles.ANSWER_SPREAD + 2)
	local said = AUs(w, lida)
	eq(#said, before + 1, "over the guild: her guild's few, drawn"); eq(said[#said].dist, "GUILD")
	eq(Public(w, late, "bones"), true)
	NoErrors(w)
end)

test("1.2.4 rankings word: a refused catch-up ask may retry in the same session", function()
	local w = World.New()
	local late = w:Client("Parric Stowe")
	local send = late.ns.Arena.Send
	late.ns.Arena.Send = function() return false, "off" end
	eq(w:As(late, late.ns.ArenaRoles.AskPublish), nil, "the refused ask was not accepted")
	late.ns.Arena.Send = send
	assert(w:As(late, late.ns.ArenaRoles.AskPublish), "the same session retries after transport returns")
	w:Run(0)
	eq(#AUs(w, late), 1)
	NoErrors(w)
end)
