-- 1.2.3's equality test (tests/perf.lua): a session the 1.2.2 profiler measured, what it saved
-- and the report it opened. Made by running F.Session in tests/perf.lua's world (its clock,
-- GetTime and heap; time() from GetTime, date() in UTC) under Olympus 1.2.2's Perf.lua and
-- PerfText.lua (e04dd4535f94); do not edit: the listeners' lines name this file's line numbers.
-- The heap moves too: 1.2.2 read none of it, so its figures are what 1.2.3 must still give.
local F = { version = "1.2.2", t0 = 1760000000 }

function F.Session(c, w)
	w.slash("perf on")
	w.Draw()
	c.On("PERF_FIXTURE", function() w.now = w.now + 3; w.heap = w.heap + 40 end)
	c.On("PERF_FIXTURE", function() w.now = w.now + 31; w.heap = w.heap + 900 end)
	c.RegisterEvent("PERF_FIXTURE_EVENT", function() w.now = w.now + 2; c.Fire("PERF_FIXTURE") end)
	for i = 1, 5 do
		w.eventFrame.scripts.OnEvent(w.eventFrame, "PERF_FIXTURE_EVENT")
		c.SafeCall("perf fixture timer", function() w.now = w.now + i * 7; w.heap = w.heap + i * 300 end)
		c.SafeCall("arena after wallet auto Somebank-Realm", function() w.now = w.now + 1 end)
		w.t = w.t + 1
		w.Draw()
	end
	for i = 1, 50 do c.SafeCall("perf fixture many " .. i % 4, function() w.now = w.now + i % 9 end) end
	c.SafeCall("perf fixture outer", function()
		c.SafeCall("perf fixture inner", function() w.now = w.now + 45; w.heap = w.heap + 2500 end)
	end)
	w.Draw()
	w.heap = w.heap - 6000 -- (a collection)
	w.Draw()
	w.t = w.t + 60
	w.slash("perf off")
end

-- (Below: written by the 1.2.2 run.)
F.saved = {
	events = {
		["callback PERF_FIXTURE"] = {
			at = 1760001000,
			max = 31,
			n = 10,
			total = 170,
		},
		["event PERF_FIXTURE_EVENT"] = {
			at = 1760001000,
			max = 36,
			n = 5,
			total = 180,
		},
	},
	frames = 8,
	heavy = 6,
	keys = 11,
	measured = 65,
	on = false,
	since = 1760001000,
	slow = {
		[1] = {
			at = 1760001005,
			label = "perf fixture inner",
			ms = 45,
		},
		[2] = {
			at = 1760001005,
			label = "perf fixture outer",
			ms = 45,
		},
		[3] = {
			at = 1760001000,
			label = "event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
			ms = 36,
		},
		[4] = {
			at = 1760001001,
			label = "event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
			ms = 36,
		},
		[5] = {
			at = 1760001002,
			label = "event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
			ms = 36,
		},
		[6] = {
			at = 1760001003,
			label = "event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
			ms = 36,
		},
		[7] = {
			at = 1760001004,
			label = "event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
			ms = 36,
		},
		[8] = {
			at = 1760001004,
			label = "perf fixture timer",
			ms = 35,
		},
		[9] = {
			at = 1760001000,
			label = "callback PERF_FIXTURE #2 perf-1.2.2.lua:12",
			ms = 31,
		},
		[10] = {
			at = 1760001001,
			label = "callback PERF_FIXTURE #2 perf-1.2.2.lua:12",
			ms = 31,
		},
		[11] = {
			at = 1760001002,
			label = "callback PERF_FIXTURE #2 perf-1.2.2.lua:12",
			ms = 31,
		},
		[12] = {
			at = 1760001003,
			label = "callback PERF_FIXTURE #2 perf-1.2.2.lua:12",
			ms = 31,
		},
		[13] = {
			at = 1760001004,
			label = "callback PERF_FIXTURE #2 perf-1.2.2.lua:12",
			ms = 31,
		},
		[14] = {
			at = 1760001003,
			label = "perf fixture timer",
			ms = 28,
		},
		[15] = {
			at = 1760001002,
			label = "perf fixture timer",
			ms = 21,
		},
		[16] = {
			at = 1760001001,
			label = "perf fixture timer",
			ms = 14,
		},
		[17] = {
			at = 1760001005,
			label = "perf fixture many 0",
			ms = 8,
		},
		[18] = {
			at = 1760001005,
			label = "perf fixture many 1",
			ms = 8,
		},
		[19] = {
			at = 1760001005,
			label = "perf fixture many 2",
			ms = 8,
		},
		[20] = {
			at = 1760001005,
			label = "perf fixture many 3",
			ms = 8,
		},
		[21] = {
			at = 1760001005,
			label = "perf fixture many 0",
			ms = 8,
		},
		[22] = {
			at = 1760001000,
			label = "perf fixture timer",
			ms = 7,
		},
		[23] = {
			at = 1760001005,
			label = "perf fixture many 3",
			ms = 7,
		},
		[24] = {
			at = 1760001005,
			label = "perf fixture many 0",
			ms = 7,
		},
		[25] = {
			at = 1760001005,
			label = "perf fixture many 1",
			ms = 7,
		},
		[26] = {
			at = 1760001005,
			label = "perf fixture many 2",
			ms = 7,
		},
		[27] = {
			at = 1760001005,
			label = "perf fixture many 3",
			ms = 7,
		},
		[28] = {
			at = 1760001005,
			label = "perf fixture many 2",
			ms = 6,
		},
		[29] = {
			at = 1760001005,
			label = "perf fixture many 3",
			ms = 6,
		},
		[30] = {
			at = 1760001005,
			label = "perf fixture many 0",
			ms = 6,
		},
		[31] = {
			at = 1760001005,
			label = "perf fixture many 1",
			ms = 6,
		},
		[32] = {
			at = 1760001005,
			label = "perf fixture many 2",
			ms = 6,
		},
		[33] = {
			at = 1760001005,
			label = "perf fixture many 1",
			ms = 5,
		},
		[34] = {
			at = 1760001005,
			label = "perf fixture many 2",
			ms = 5,
		},
		[35] = {
			at = 1760001005,
			label = "perf fixture many 3",
			ms = 5,
		},
		[36] = {
			at = 1760001005,
			label = "perf fixture many 0",
			ms = 5,
		},
		[37] = {
			at = 1760001005,
			label = "perf fixture many 1",
			ms = 5,
		},
		[38] = {
			at = 1760001005,
			label = "perf fixture many 2",
			ms = 5,
		},
		[39] = {
			at = 1760001005,
			label = "perf fixture many 0",
			ms = 4,
		},
		[40] = {
			at = 1760001005,
			label = "perf fixture many 1",
			ms = 4,
		},
	},
	stats = {
		["arena after wallet auto"] = {
			at = 1760001000,
			max = 1,
			n = 5,
			total = 5,
		},
		["callback PERF_FIXTURE #1 perf-1.2.2.lua:11"] = {
			at = 1760001000,
			max = 3,
			n = 5,
			total = 15,
		},
		["callback PERF_FIXTURE #2 perf-1.2.2.lua:12"] = {
			at = 1760001000,
			max = 31,
			n = 5,
			total = 155,
		},
		["event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13"] = {
			at = 1760001000,
			max = 36,
			n = 5,
			total = 180,
		},
		["perf fixture inner"] = {
			at = 1760001005,
			max = 45,
			n = 1,
			total = 45,
		},
		["perf fixture many 0"] = {
			at = 1760001005,
			max = 8,
			n = 12,
			total = 51,
		},
		["perf fixture many 1"] = {
			at = 1760001005,
			max = 8,
			n = 13,
			total = 46,
		},
		["perf fixture many 2"] = {
			at = 1760001005,
			max = 8,
			n = 13,
			total = 50,
		},
		["perf fixture many 3"] = {
			at = 1760001005,
			max = 8,
			n = 12,
			total = 48,
		},
		["perf fixture outer"] = {
			at = 1760001005,
			max = 45,
			n = 1,
			total = 45,
		},
		["perf fixture timer"] = {
			at = 1760001004,
			max = 35,
			n = 5,
			total = 105,
		},
	},
	worst = {
		[1] = {
			at = 1760001005,
			ms = 240,
			top = "perf fixture outer",
			topMs = 45,
		},
		[2] = {
			at = 1760001005,
			ms = 72,
			top = "event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
			topMs = 36,
		},
		[3] = {
			at = 1760001004,
			ms = 65,
			top = "event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
			topMs = 36,
		},
		[4] = {
			at = 1760001003,
			ms = 58,
			top = "event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
			topMs = 36,
		},
		[5] = {
			at = 1760001002,
			ms = 51,
			top = "event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
			topMs = 36,
		},
		[6] = {
			at = 1760001001,
			ms = 44,
			top = "event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
			topMs = 36,
		},
	},
}

F.report = {
	[1] = "Olympus profiler - Olympus 1.2.2, game 1.15.8.99999 (11508)",
	[2] = "Input: mouse and keyboard.",
	[3] = "Measuring: off, 1 min 05 s measured (since 2025-10-09 09:10).",
	[4] = "Frames with 30 ms or more of Olympus's work: 6 of 8 drawn.",
	[5] = "",
	[6] = "Worst frames (Olympus's time in one frame, and its biggest call in it):",
	[7] = "  240.0 ms at 09:10:05, mostly perf fixture outer (45.0 ms)",
	[8] = "  72.0 ms at 09:10:05, mostly event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13 (36.0 ms)",
	[9] = "  65.0 ms at 09:10:04, mostly event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13 (36.0 ms)",
	[10] = "  58.0 ms at 09:10:03, mostly event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13 (36.0 ms)",
	[11] = "  51.0 ms at 09:10:02, mostly event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13 (36.0 ms)",
	[12] = "  44.0 ms at 09:10:01, mostly event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13 (36.0 ms)",
	[13] = "",
	[14] = "The 40 slowest calls:",
	[15] = "  45.0 ms at 09:10:05  perf fixture inner",
	[16] = "  45.0 ms at 09:10:05  perf fixture outer",
	[17] = "  36.0 ms at 09:10:00  event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
	[18] = "  36.0 ms at 09:10:01  event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
	[19] = "  36.0 ms at 09:10:02  event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
	[20] = "  36.0 ms at 09:10:03  event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
	[21] = "  36.0 ms at 09:10:04  event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13",
	[22] = "  35.0 ms at 09:10:04  perf fixture timer",
	[23] = "  31.0 ms at 09:10:00  callback PERF_FIXTURE #2 perf-1.2.2.lua:12",
	[24] = "  31.0 ms at 09:10:01  callback PERF_FIXTURE #2 perf-1.2.2.lua:12",
	[25] = "  31.0 ms at 09:10:02  callback PERF_FIXTURE #2 perf-1.2.2.lua:12",
	[26] = "  31.0 ms at 09:10:03  callback PERF_FIXTURE #2 perf-1.2.2.lua:12",
	[27] = "  31.0 ms at 09:10:04  callback PERF_FIXTURE #2 perf-1.2.2.lua:12",
	[28] = "  28.0 ms at 09:10:03  perf fixture timer",
	[29] = "  21.0 ms at 09:10:02  perf fixture timer",
	[30] = "  14.0 ms at 09:10:01  perf fixture timer",
	[31] = "  8.0 ms at 09:10:05  perf fixture many 0",
	[32] = "  8.0 ms at 09:10:05  perf fixture many 1",
	[33] = "  8.0 ms at 09:10:05  perf fixture many 2",
	[34] = "  8.0 ms at 09:10:05  perf fixture many 3",
	[35] = "  8.0 ms at 09:10:05  perf fixture many 0",
	[36] = "  7.0 ms at 09:10:00  perf fixture timer",
	[37] = "  7.0 ms at 09:10:05  perf fixture many 3",
	[38] = "  7.0 ms at 09:10:05  perf fixture many 0",
	[39] = "  7.0 ms at 09:10:05  perf fixture many 1",
	[40] = "  7.0 ms at 09:10:05  perf fixture many 2",
	[41] = "  7.0 ms at 09:10:05  perf fixture many 3",
	[42] = "  6.0 ms at 09:10:05  perf fixture many 2",
	[43] = "  6.0 ms at 09:10:05  perf fixture many 3",
	[44] = "  6.0 ms at 09:10:05  perf fixture many 0",
	[45] = "  6.0 ms at 09:10:05  perf fixture many 1",
	[46] = "  6.0 ms at 09:10:05  perf fixture many 2",
	[47] = "  5.0 ms at 09:10:05  perf fixture many 1",
	[48] = "  5.0 ms at 09:10:05  perf fixture many 2",
	[49] = "  5.0 ms at 09:10:05  perf fixture many 3",
	[50] = "  5.0 ms at 09:10:05  perf fixture many 0",
	[51] = "  5.0 ms at 09:10:05  perf fixture many 1",
	[52] = "  5.0 ms at 09:10:05  perf fixture many 2",
	[53] = "  4.0 ms at 09:10:05  perf fixture many 0",
	[54] = "  4.0 ms at 09:10:05  perf fixture many 1",
	[55] = "",
	[56] = "Most time in all:",
	[57] = "  event PERF_FIXTURE_EVENT #1 perf-1.2.2.lua:13  calls 5, total 180 ms, average 36.00 ms, slowest 36.0 ms",
	[58] = "  callback PERF_FIXTURE #2 perf-1.2.2.lua:12  calls 5, total 155 ms, average 31.00 ms, slowest 31.0 ms",
	[59] = "  perf fixture timer  calls 5, total 105 ms, average 21.00 ms, slowest 35.0 ms",
	[60] = "  perf fixture many 0  calls 12, total 51 ms, average 4.25 ms, slowest 8.0 ms",
	[61] = "  perf fixture many 2  calls 13, total 50 ms, average 3.85 ms, slowest 8.0 ms",
	[62] = "  perf fixture many 3  calls 12, total 48 ms, average 4.00 ms, slowest 8.0 ms",
	[63] = "  perf fixture many 1  calls 13, total 46 ms, average 3.54 ms, slowest 8.0 ms",
	[64] = "  perf fixture inner  calls 1, total 45 ms, average 45.00 ms, slowest 45.0 ms",
	[65] = "  perf fixture outer  calls 1, total 45 ms, average 45.00 ms, slowest 45.0 ms",
	[66] = "  callback PERF_FIXTURE #1 perf-1.2.2.lua:11  calls 5, total 15 ms, average 3.00 ms, slowest 3.0 ms",
	[67] = "  arena after wallet auto  calls 5, total 5 ms, average 1.00 ms, slowest 1.0 ms",
	[68] = "",
	[69] = "Each event's listeners together:",
	[70] = "  event PERF_FIXTURE_EVENT  calls 5, total 180 ms, average 36.00 ms, slowest 36.0 ms",
	[71] = "  callback PERF_FIXTURE  calls 10, total 170 ms, average 17.00 ms, slowest 31.0 ms",
	[72] = "",
	[73] = "/oly perf on starts measuring, /oly perf off stops, /oly perf reset clears; /oly perf alone opens this report.",
	[74] = "Only Olympus's protected calls are measured: events, listeners, timers, commands and clicks. A call's time includes the calls made inside it. After a /reload it starts again once the loading is over. A listener is #n in the order it was registered, the same for everyone on one version: with its name where Olympus has one, and scripts/perf-listeners.lua in Olympus's source gives each #n its file and line.",
}

return F
