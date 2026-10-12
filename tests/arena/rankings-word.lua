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
