-- 1.2.4, the author's ask (rankings are not lost): `/oly backup` (Olympus/Backup.lua) left out the
-- player's own signed halves of the Bones games and the duels that count, so after a wiped saved
-- data his client could neither say his games again to the members who missed them nor complete
-- them. The backup carries them now, and a restore takes each back as his own word (never the
-- other player's: that comes back from its player). Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end
local function LoadBackup(w, c)
	w:As(c, function() assert(loadfile(H.ADDON_DIR .. "Backup.lua"))("Olympus", c.ns) end)
	c.ns.UI = c.ns.UI or {}
	return c.ns.Backup
end
-- The saved data wiped (a reinstall, the beta): the client logs in with nothing kept.
local function Wiped(w, c)
	w:Logout(c)
	c.saved = nil
	w:Login(c)
end
local function Restore(w, c, text)
	local B = LoadBackup(w, c)
	local d = assert(w:As(c, B.Read, text))
	assert(d.arena and d.arena.halves, "the halves in the text")
	local said = table.concat(w:As(c, B.Summary, d), "\n")
	assert(said:find(c.ns.L.BACKUP_ARENA_HALVES, 1, true), said)
	w:As(c, B.Apply, d)
end

print("1.2.4: the backup carries the player's own halves")

test("1.2.4 backup: a Bones player's own halves: in /oly backup; restored after a wipe, his game is said again and completed from the other player", function()
	local w = FW.New({ compliance = "shipped" })
	local a, b = w:Player(N.fighterA), w:Player(N.fighterB)
	w:Group({ a, b })
	local function Do(c, fn, ...) return w:As(c, c.ns.FarkleTable[fn], ...) end
	local id = assert(Do(a, "Create", { guest = b.name, target = 2000 }))
	w:Run(0)
	assert(Do(b, "Answer", id, true, nil, {}))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	Do(a, "Roll", id); Do(b, "Roll", id)
	w:Run(20)
	assert(Do(a, "Concede", id))
	w:Run(0)
	eq(#Do(a, "Best", "L"), 2)
	local B = LoadBackup(w, a)
	local d = w:As(a, B.Data)
	local own = d.arena and d.arena.halves and d.arena.halves.bones
	assert(own, "his own halves in the backup")
	local key = id .. ":" .. (a.name .. ":" .. b.name):lower()
	assert(own[key] and own[key].mine, "this game's, his own half")
	eq(own[key].theirs, nil, "never the other player's")
	local text = w:As(a, B.Export)
	Wiped(w, a)
	eq(#Do(a, "Best", "L"), 0, "nothing kept")
	Restore(w, a, text)
	local held = Do(a, "Halves", id)
	eq(#held, 1); assert(held[1].by[a.name:lower()], "his half back")
	-- An hour on, he logs in: his half said again, b asked for his: the game counts again.
	w:Run(3600)
	w:Logout(a); w:Login(a); w:Group({ a, b })
	w:Run(80)
	local rows = Do(a, "Best", "L")
	eq(#rows, 2, "completed from b's half")
	NoErrors(w)
end)

test("1.2.4 backup: a fighter's own duel halves: in /oly backup; restored after a wipe, his duel is matched again when the other's half comes", function()
	local w, cast = W3.New({ live = false, world = { compliance = "shipped" } })
	cast.A.target, cast.B.target = cast.B.name, cast.A.name
	for _, c in ipairs({ cast.A, cast.B }) do c.globals.UnitRace = function() return "Human", "Human", 1 end end
	for _, c in ipairs(w.clients) do
		c.globals.GetPlayerInfoByGUID = function(guid)
			for _, o in ipairs(w.clients) do
				if o.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, o.short, o.realm ~= c.realm and o.realm or "" end
			end
			return nil
		end
	end
	local F = function(c) return W3.M(w, c, "ArenaFights") end
	local oid = assert(F(cast.A).Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	assert(F(cast.B).Answer(oid, true))
	w:Run(0)
	w:Combat(cast.A, true); w:Combat(cast.B, true)
	w:Run(20)
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Fire(cast.A, "DUEL_FINISHED"); w:Fire(cast.B, "DUEL_FINISHED")
	w:Run(0)
	w:Combat(cast.A, false); w:Combat(cast.B, false)
	w:Run(0)
	local A = cast.A
	eq(#W3.M(w, A, "ArenaLedger").Entries(), 1)
	local B = LoadBackup(w, A)
	local d = w:As(A, B.Data)
	local duels = d.arena and d.arena.halves and d.arena.halves.duels
	assert(duels and duels[oid], "his own half of the duel in the backup")
	local text = w:As(A, B.Export)
	Wiped(w, A)
	W3.Rules(w, A)
	eq(#W3.M(w, A, "ArenaLedger").Entries(), 0, "nothing kept")
	Restore(w, A, text)
	eq(w:As(A, A.ns.ArenaLedger.Pending), 1, "his own half waits for the other's")
	w:Run(cast.B.ns.ArenaFights.HALF_REPEAT + 2)
	local list = W3.M(w, A, "ArenaLedger").Entries()
	eq(#list, 1, "matched again"); eq(list[1] and list[1].fid, oid)
	W3.NoErrors(w)
end)
