-- The configured crown consent remains independent of actual current map publishability.
local H = ...
local test, eq = H.test, H.eq
local function Setup()
	local w = H.World.New({ compliance = "shipped" })
	local king = w:Role("king")
	king.mapID, king.x, king.y = 1453, 0.42, 0.51
	king.globals.C_Map = {
		GetBestMapForUnit = function() return king.mapID end,
		GetPlayerMapPosition = function()
			if king.noPosition then return nil end
			return { GetXY = function() return king.x, king.y end }
		end,
	}
	king.db.throneLocation = true
	return w, king
end
local function PositionSends(w)
	local n = 0
	for _, packet in ipairs(w.sent) do if packet.msg:match("^T1~P~") then n = n + 1 end end
	return n
end
local function Has(lines, text)
	for _, line in ipairs(lines) do if line.text and line.text:find(text, 1, true) then return true end end
	return false
end

test("King effective map status: real Throne banner never claims live inside an instance or without coordinates", function()
	for _, blocked in ipairs({ "instance", "missing", "zero", "invalid" }) do
		local w, king = Setup()
		if blocked == "instance" then king.instance = true
		elseif blocked == "missing" then king.noPosition = true
		elseif blocked == "zero" then king.x, king.y = 0, 0
		else king.y = nil end
		w:As(king, function()
			local K = king.ns.King
			local lines = K.Build()
			eq(Has(lines, king.ns.L.THRONE_LOCATION_LIVE), false, blocked .. " must not advertise an effective position")
			eq(Has(lines, king.ns.L.THRONE_LOCATION_PAUSED), true)
			eq(K.SharingLocation(), true, "saved opt-in stays on")
			local live, why = K.EffectiveLocation()
			eq(live, false); eq(why, blocked == "instance" and "instance" or "position")
		end)
		w:Run(6); eq(PositionSends(w), 0, "the actual native timer uses the same gate")
	end
end)

test("King effective map status: valid position resumes automatically, toggle still turns consent off while unavailable", function()
	local w, king = Setup()
	assert(king.Roles.SetSettings({ live = 1 })); w:Run(0)
	king.instance = true
	eq(w:As(king, king.ns.King.EffectiveLocation), false)
	w:Run(6); eq(PositionSends(w), 0); eq(king.Roles.Live(), true, "independent game lives remain enabled")
	king.instance = nil
	eq(w:As(king, king.ns.King.EffectiveLocation), true)
	w:Run(6); eq(PositionSends(w) > 0, true)
	eq(Has(w:As(king, king.ns.King.Build), king.ns.L.THRONE_LOCATION_LIVE), true)
	king.noPosition = true
	w:As(king, king.ns.King.ToggleLocation)
	eq(king.db.throneLocation, false, "toggle operates on configured consent, not temporarily unavailable status")
	eq(king.Roles.Live(), true)
	w:As(king, king.ns.King.ToggleLocation)
	eq(king.db.throneLocation, true); eq(w:As(king, king.ns.King.EffectiveLocation), false)
	eq(king.Roles.Live(), true, "none of these map decisions toggle game lives")
end)

test("King effective map status: unavailable map, invalid coordinates and lost real King permission fail closed without mutating opt-in", function()
	local w, king = Setup()
	for _, coords in ipairs({ { -0.1, 0.3 }, { 0.2, 1.1 }, { 0 / 0, 0.3 }, { 0.4, math.huge } }) do
		king.x, king.y = coords[1], coords[2]
		eq(w:As(king, king.ns.King.EffectiveLocation), false)
	end
	king.mapID = nil; eq(w:As(king, king.ns.King.EffectiveLocation), false)
	king.mapID, king.x, king.y = 1453, 0.5, 0.5
	king.rank = 1
	local live, why = w:As(king, king.ns.King.EffectiveLocation)
	eq(live, false); eq(why, "role"); eq(king.db.throneLocation, true)
	w:Run(6); eq(PositionSends(w), 0, "a configured preference grants no lost King permission")
end)
