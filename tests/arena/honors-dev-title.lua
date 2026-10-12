-- 1.2.3, the author's own title, "The Royal Dev" (Honors.Holdings, HonorsNet.Holdings): a title alone,
-- held by the author's character and worked out the same on every client. Every name is invented;
-- the author is whichever character Workshop.IsAuthorName names here.
local H = ...
local test, eq = H.test, H.eq
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local function Short(name) return (name:gsub("%-.*$", "")) end
local function Kept(w, c)
	w:Logout(c)
	w:Login(c)
	W3.Rules(w, c)
	return c
end
local function DevHeld(c, name)
	for _, h in ipairs(c.ns.HonorsNet.Holdings(name)) do
		if h.title == "the-dev" then return h end
	end
	return nil
end

print("HonorsNet: the author's title (1.2.3)")

test("1.2.3 the author's title: his character holds The Royal Dev, a title alone (no frame, no mark, no King's letter), switched on for him; every other client shows it on him, and nobody else holds or can pick it", function()
	local w, cast = W3.New()
	local author, viewer = cast.A, cast.spectator
	-- (after the login: a login builds the client's namespace again)
	Kept(w, author); Kept(w, viewer)
	-- (The core's borders say who the dev is, Borders.IsDevName: the arena's files never name the
	-- author. This world's borders may be the core's stand-in: it is told here, on both clients.)
	for _, c in ipairs({ author, viewer }) do
		local function IsDev(name) return type(name) == "string" and Short(name) == Short(author.name) end
		rawset(c.ns.Workshop, "IsAuthorName", IsDev)
		if type(c.ns.Borders) ~= "table" then rawset(c.ns, "Borders", {}) end
		rawset(c.ns.Borders, "IsDevName", IsDev)
	end
	w:As(author, author.ns.HonorsNet.Refresh or function() end)
	w:Run(3)
	-- His client: the title, alone.
	local h = DevHeld(author, author.name)
	assert(h, "the author holds the-dev")
	eq(h.frame, nil, "no frame"); eq(h.mark, nil, "no mark"); eq(h.art, nil, "no art")
	eq(author.ns.HonorsNet.TitleText("the-dev"), "The Royal Dev")
	eq(author.ns.ArenaProfile.Pick().title, "the-dev", "switched on the first time")
	eq(author.ns.ArenaProfile.Pick().frame ~= "the-dev", true, "never a frame")
	eq(#author.ns.HonorsNet.QueuedLetters(), 0, "no King's letter queued")
	eq(#author.ns.HonorsNet.Letters(), 0, "none kept to read again")
	-- The frame picker offers it among his titles, never among his frames.
	local vm = w:As(author, author.ns.ProfileEdit.ViewModel)
	local inTitles, inFrames = false, false
	for _, x in ipairs(vm.titles) do if x.key == "the-dev" then inTitles = true; eq(x.label, "The Royal Dev") end end
	for _, x in ipairs(vm.frames) do if x.key == "the-dev" then inFrames = true end end
	eq(inTitles, true, "among his titles"); eq(inFrames, false, "not among his frames")
	-- Another client: it shows on him, worked out there.
	w:Run(3)
	eq(DevHeld(viewer, author.name) ~= nil, true, "held by the author on the other client too")
	eq(w:As(viewer, viewer.ns.HonorsNet.Verified, author.name).title, "the-dev", "shown on him")
	-- Nobody else holds it, nor can pick it.
	eq(DevHeld(viewer, viewer.name), nil, "the viewer holds none")
	local held = viewer.ns.HonorsNet.Holdings(viewer.name)
	local pick, why = viewer.ns.Honors.Choose(viewer.ns.ArenaProfile.Pick(), held, "rank", "the-dev")
	eq(pick, nil); eq(why, "title")
	W3.NoErrors(w)
end)
