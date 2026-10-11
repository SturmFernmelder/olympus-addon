-- 1.2.1, the King's letter when an honour is earned (HonorsNet.lua): who gets it, how often, and
-- its window. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local function Short(name) return (name:gsub("%-.*$", "")) end
-- The Treasurer's donors word (ID) as client c takes it: all time's top 3, `names` in order.
local function Donors(w, c, t, names, month)
	local B36 = c.ns.Arena.B36
	local list = {}
	for i, x in ipairs(names) do list[i] = Short(type(x) == "table" and x.name or x) end
	local body = table.concat({ B36(t), B36(c.ns.Honors.MonthOf(w.clock) - 1), month or "-", #list > 0 and table.concat(list, ",") or "-" }, "~")
	eq(w:As(c, c.ns.HonorsNet.TakeDonors, N.treasurer, body), true, "the Treasurer's word taken")
end
local function Shown(c)
	local f = c.ns.HonorsNet.LetterFrame()
	return f ~= nil and f:IsShown() == true
end

print("HonorsNet: the King's letter (1.2.1)")

-- The owner after Asmon's stream (1.2.1): the King got the King's letter about a frame he holds.
test("1.2.1 the King's letter: never to the King himself: his honour switches on, no letter shows, none is kept or opens on a click; where no King is pinned, the guild master of the King's guild the same; everyone else gets his", function()
	local w, cast = W3.New({ more = { { "gm", "Bryn Halloway", { guild = World.KING_GUILD, rank = 0 } } } })
	local king, A, gm = cast.king, cast.A, cast.gm
	-- (gm's realm group has no King pinned by name: there the guild master of his guild is the King.)
	rawset(gm.ns, "KingCharacter", function() return nil end)
	eq(w:As(gm, gm.ns.King.IsKing), true, "gm is the King where no King is pinned")
	eq(w:As(king, king.ns.IsKingCharacter, king.name), true)
	for _, c in ipairs({ king, A, gm }) do Donors(w, c, w.clock, { king, A, gm }) end
	w:Run(3)
	-- The King: the cornucopia on, no letter from himself.
	eq(king.ns.ArenaProfile.Pick().frame, "donor-top-1", "his honour switched on")
	eq(Shown(king), false, "no letter from himself")
	eq(#king.ns.HonorsNet.QueuedLetters(), 0); eq(#king.ns.HonorsNet.Letters(), 0, "none kept to read again")
	eq(w:As(king, king.ns.HonorsNet.ShowLetter, "donor-top-1"), false, "nor on a click")
	w:As(king, king.ns.HonorsNet.QueueLetter, "arena-champion")
	eq(Shown(king), false); eq(#king.ns.HonorsNet.QueuedLetters(), 0, "whatever asks for one")
	eq(w:As(king, king.ns.HonorsNet.WindowShown), false, "the Olympus window opens none")
	-- The guild master of the King's guild where none is pinned: the same.
	eq(gm.ns.ArenaProfile.Pick().frame, "donor-top-3")
	eq(Shown(gm), false); eq(#gm.ns.HonorsNet.Letters(), 0)
	-- Anyone else: his letter.
	eq(Shown(A), true, "the second donor's letter")
	eq(A.ns.HonorsNet.LetterFrame().key, "donor-top-2")
	eq(#A.ns.HonorsNet.Letters(), 1)
	W3.NoErrors(w)
end)
