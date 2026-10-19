local _, own = ...; local ns = own.host; if not ns then return end

-- Olympus Arena (the load-on-demand companion): Spectate.lua. 1.2.6, the Blood Arena's duel view
-- (the owner's duel-view request, 2026-10-19: "Watch duel", for whoever watches a duel of ours, the
-- stream's two inspect panels as ONE window split down the middle). Its data is the core's
-- (Olympus/ArenaSpectate.lua, S below): who is watched, each fighter's unit, the gear and talents
-- from this client's own inspection, the result line. This file only draws it.
-- Frames are named OlympusArena... (so /oly photo keeps them); no OnUpdate, no game popup, no
-- UISpecialFrames but through ns.EscapeCloses, no edit box.
--
-- OlympusArenaWatch (960 x 500 at scale 1, 0.6 to 1.6, kept; HIGH strata; movable, its place
-- kept): the Olympus window's bronze metal without the portrait ring (Kit.Frame, ns.Window), the
-- parchment inside, the title in its bar. Top to bottom:
--   the strip: Gear | Talents (both halves), the fight's line (best of, round, score, its state;
--   the result as this client read it, a round's "Last round" while a best of 3 goes on; "Not an
--   Olympus duel"), the pins Auto | Full | Bar, -/+ and
--   Copy (the text in Kit.Copy's pop-up, never in chat);
--   the halves, A (red) left and B (blue) right, mirrored round the VS seal and a bronze line:
--     the header (the portrait, the name in his class's colour darkened for the ink, "Class · Race
--     · Level N", an Olympus guild's name, the side's banner at the seal);
--     the health bar (432 x 18, "cur / max" or "NN%") and the power bar (8 high, "NN%");
--     Gear: a dark framed stage (264 x 300: his 3D model in his gear while in sight, the last one
--     kept out of sight; the 19 slots round it with the game's own item tooltip) and on the
--     parchment, on the outer side, "Stats from gear" and "Resistances" in dark ink;
--     Talents: each tree's icon grid (tiers by columns, "3/5", an untaken talent dimmed), its name
--     and points, a talent's tooltip its name, Passive or Active, what it does and "Rank r / max";
--     the points per tree alone where the client gives no grid, and the line saying so;
--     his cast bar on either tab (the half's own: on the stage above the weapons, or under the trees);
--     the status line ("Waiting for inspection – move within inspect range"...) and Inspect again.
-- OlympusArenaWatchBar (560 x 56, its own place, on UIParent, HIGH): the compact bar on a bronze-
-- edged wood strip, both fighters (class icon, name, health with "NN%", power, a thin cast bar)
-- and the seal (the score and round when this client knows them, else VS). Auto shows it while
-- either fighter is in combat (UnitAffectingCombat, plain only; unknown keeps the view) and the
-- full view again between rounds and at the result; a pin wins.
--
-- Timers: one C_Timer ticker (0.2 s) while either is shown, the sight pass and the slow redraw
-- every 5th tick; a 0.1 s ticker only while a cast shows; one private event frame, its events
-- registered on show and each one unregistered on hide. Nothing runs, nothing listens before the
-- first show or after the hide. Every live value (health, power, casts: secret on Forever) goes
-- from the game into the widgets through the core's S.Push and S.Cast only: this file never reads
-- one, nor a widget holding one.
local ArenaUI = own.ArenaUI

local L = ns.L
local Kit = ArenaUI.Kit

local Spectate = {}
ArenaUI.Spectate = Spectate

Spectate.W, Spectate.H = 960, 500
Spectate.BAR_W, Spectate.BAR_H = 560, 56
Spectate.TICK = 0.2          -- the live values
Spectate.CAST_TICK = 0.1     -- a cast's fill, only while one shows
Spectate.SIGHT_EVERY = 5     -- ticks between two sight passes and slow redraws (1 s)
Spectate.HOLD = 1.5          -- Auto: out of combat this long before the full view comes back
Spectate.RESULT_HOLD = 10    -- Auto: the full view this long after the result (the combat flag lingers)
Spectate.MODEL_RETRY = 5     -- his model not drawable yet (too far for it): asked again this often
Spectate.SCALE_MIN, Spectate.SCALE_MAX, Spectate.SCALE_STEP = 0.6, 1.6, 0.1
Spectate.PINS = { "auto", "full", "compact" }
Spectate.TABS = { "gear", "talents" }
Spectate.EVENTS = { "CHAT_MSG_SYSTEM", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "NAME_PLATE_UNIT_ADDED",
	"NAME_PLATE_UNIT_REMOVED", "UNIT_INVENTORY_CHANGED", "UNIT_MODEL_CHANGED" }

-- The window's layout (px at scale 1): its margin inside the metal, the gutter between the halves
-- (the seal), each half's width; heights from the window's top, then from a half's top.
local M, GUTTER = 16, 64
local HALF = (Spectate.W - 2 * M - GUTTER) / 2       -- 432
local STRIP_Y, HALF_Y = 30, 64
local HP_TOP, HP_H, PW_TOP, PW_H = 58, 18, 80, 8
local BODY_TOP, BODY_H, STATUS_TOP = 96, 300, 402
local STAGE_W, SLOT, SLOT_GAP = 264, 30, 4
local STATS_W = HALF - STAGE_W - 8                    -- 160
local PORTRAIT = 44
local POINTS_NOTE_Y = 92                              -- Talents, points only: the line under the trees' pictures
-- The bar's: each side's box, the seal between.
local BAR_SIDE, BAR_SEAL = 214, 44

local SIDES = { "A", "B" }
local SIDE_COLOR = { A = { 0.75, 0.15, 0.1 }, B = { 0.15, 0.35, 0.75 } } -- the overlay's
local STAGE_BG = { 0.045, 0.032, 0.02, 0.96 }
local DARK = { 0.06, 0.04, 0.02, 0.88 }
local RUBRIC = { 0.42, 0.12, 0.03 }   -- the headings' red-brown ink
local SOFT = { 0.36, 0.27, 0.16 }     -- the dimmer ink (a guild, a note)
local RED_INK = { 0.50, 0.06, 0.03 }
local CAST, CHANNEL = { 1, 0.7, 0 }, { 0.3, 0.82, 0.2 }
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ICON_FRAME = "Interface\\Common\\WhiteIconFrame"
local EMPTY_SLOT = "Interface\\Buttons\\UI-EmptySlot"
local POWER = { MANA = { 0, 0.44, 0.87 }, RAGE = { 0.85, 0.1, 0.1 }, ENERGY = { 1, 0.86, 0.1 }, FOCUS = { 1, 0.5, 0.25 } }
-- The slots' names for the game's empty-slot pictures (GetInventorySlotInfo).
local SLOT_NAMES = { "HeadSlot", "NeckSlot", "ShoulderSlot", "ShirtSlot", "ChestSlot", "WaistSlot", "LegsSlot", "FeetSlot",
	"WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "BackSlot", "MainHandSlot",
	"SecondaryHandSlot", "RangedSlot", "TabardSlot" }

local win, bar, events, ticker, castTicker
local view = { mode = nil, pin = "auto", tab = "gear", ticks = 0, swapping = false, hiding = false, calmAt = nil, model = nil }

local function Core() local S = ns.ArenaSpectate return type(S) == "table" and S or nil end
local function Settings()
	local s = Kit.Settings()
	if type(s.watch) ~= "table" then s.watch = {} end
	return s.watch
end
local function Clamp(s)
	s = tonumber(s) or 1
	return math.max(Spectate.SCALE_MIN, math.min(Spectate.SCALE_MAX, s))
end
local function Other(side) return side == "A" and "B" or "A" end

---------------------------------------------------------------------------
-- Small pieces
---------------------------------------------------------------------------

local function Ink(fs, c) if fs and fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end end
local function Text(parent, kind, justify, color)
	local fs = Kit.Text(parent, kind, justify)
	Ink(fs, color or Kit.INK)
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	return fs
end
-- A font of the game's (white, shadowed: on a dark ground or a bar).
local function Light(parent, font, justify, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY", font or "GameFontHighlightSmall")
	if justify then fs:SetJustifyH(justify) end
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	return fs
end
local function Fill(parent, color, layer, sub)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
	t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	return t
end

-- A name in his class's colour: as it is on a dark ground; darkened for the parchment's ink (a
-- priest's white, a rogue's yellow would not read there).
local function ClassRGB(file)
	local c = type(file) == "string" and type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[file] or nil
	if type(c) ~= "table" or not tonumber(c.r) then return nil end
	return { c.r, c.g, c.b }
end
local function ClassInk(file)
	local c = ClassRGB(file)
	if not c then return Kit.INK end
	return { c[1] * 0.45, c[2] * 0.45, c[3] * 0.45 }
end
local function ClassIcon(tex, file)
	local Card = ArenaUI.Card
	local coords = file and Card and Card.ClassCoords and Card.ClassCoords(file) or nil
	if coords then
		tex:SetTexture(Card.CIRCLES)
		if tex.SetTexCoord then tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
	else
		tex:SetTexture(Kit.Emblem())
		if tex.SetTexCoord then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
	end
end
local function PowerRGB(token, kind)
	local P = type(PowerBarColor) == "table" and PowerBarColor or nil
	local c = P and ((token and P[token]) or (kind and P[kind])) or nil
	if type(c) == "table" and tonumber(c.r) then return { c.r, c.g, c.b } end
	return POWER[token or ""] or POWER.MANA
end

local function StatusBar(parent, w, h, color, reverse)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetSize(w, h)
	b:SetStatusBarTexture(BAR_TEXTURE)
	b:SetStatusBarColor(color[1], color[2], color[3])
	if reverse and b.SetReverseFill then b:SetReverseFill(true) end
	b:SetMinMaxValues(0, 1)
	b:SetValue(0)
	b.bg = Fill(b, DARK, "BACKGROUND")
	b.bg:SetAllPoints()
	Kit.Edge(b, Kit.BRONZE, 1, 1)
	return b
end

-- A round seal: a dark disc in a bronze ring, its words on it.
local function Seal(parent, size)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(size, size)
	s.ring = s:CreateTexture(nil, "BORDER")
	s.ring:SetTexture(MASK)
	s.ring:SetVertexColor(Kit.BRONZE[1], Kit.BRONZE[2], Kit.BRONZE[3])
	s.ring:SetAllPoints()
	s.disc = s:CreateTexture(nil, "ARTWORK")
	s.disc:SetTexture(MASK)
	s.disc:SetVertexColor(0.09, 0.06, 0.03)
	s.disc:SetPoint("TOPLEFT", 3, -3)
	s.disc:SetPoint("BOTTOMRIGHT", -3, 3)
	s.text = s:CreateFontString(nil, "OVERLAY", Kit.Font("title"))
	s.text:SetPoint("CENTER", 0, 0)
	s.text:SetTextColor(Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3])
	s.small = Light(s, "GameFontHighlightSmall", "CENTER")
	s.small:SetPoint("BOTTOM", 0, 6)
	return s
end

local function SavePoint(frame, key)
	if ns.Arena.Sim() or not frame.GetPoint then return end
	local point, _, rel, x, y = frame:GetPoint(1)
	if type(point) == "string" then Settings()[key] = { point, type(rel) == "string" and rel or point, tonumber(x) or 0, tonumber(y) or 0 } end
end
local function Place(frame, key, default)
	local p = Settings()[key]
	frame:ClearAllPoints()
	if type(p) == "table" and type(p[1]) == "string" then
		frame:SetPoint(p[1], UIParent, type(p[2]) == "string" and p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
	else
		frame:SetPoint(default[1], UIParent, default[2], default[3], default[4])
	end
end

---------------------------------------------------------------------------
-- A half of the window: one fighter
---------------------------------------------------------------------------

local function SlotButton(parent, side, slot)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(SLOT, SLOT)
	b.slot, b.side = slot, side
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.frame = b:CreateTexture(nil, "OVERLAY")
	b.frame:SetTexture(ICON_FRAME)
	b.frame:SetAllPoints()
	b.frame:SetVertexColor(Kit.BRONZE[1], Kit.BRONZE[2], Kit.BRONZE[3])
	if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
	b:SetScript("OnEnter", function(self) if self.item then Kit.ItemTip(self, self.item) end end)
	b:SetScript("OnLeave", function(self) Kit.HideTip(self) end)
	return b
end

local function CastBar(parent, w, h, iconSize)
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(w, h)
	c.bar = StatusBar(c, w, h, CAST)
	c.bar:SetAllPoints()
	if iconSize then
		c.icon = c:CreateTexture(nil, "ARTWORK")
		c.icon:SetSize(iconSize, iconSize)
		c.icon:SetPoint("RIGHT", c, "LEFT", -3, 0)
		if c.icon.SetTexCoord then c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
		c.name = Light(c.bar, "GameFontHighlightSmall", "LEFT")
		c.name:SetPoint("LEFT", 4, 0)
		c.name:SetWidth(w - 40)
		c.time = Light(c.bar, "GameFontHighlightSmall", "RIGHT")
		c.time:SetPoint("RIGHT", -4, 0)
	end
	c.widgets = { bar = c.bar }
	if iconSize then c.widgets.name, c.widgets.icon, c.widgets.time = c.name, c.icon, c.time end
	c:Hide()
	return c
end

-- A half's cast bar where its tab shows it: the stage above the weapons (Gear), under the trees
-- (Talents: their grid ends above it, the points-only line sits higher).
local CAST_LIFT = 8 + SLOT + 8
local function PlaceCast(h, tab)
	if h.castTab == tab then return end
	h.castTab = tab
	h.cast:ClearAllPoints()
	if tab == "talents" then h.cast:SetPoint("BOTTOM", h.talents, "BOTTOM", 8, 3)
	else h.cast:SetPoint("BOTTOM", h.stage, "BOTTOM", 8, CAST_LIFT) end
end

local function TalentCell(parent)
	local b = CreateFrame("Button", nil, parent)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.frame = b:CreateTexture(nil, "OVERLAY")
	b.frame:SetTexture(ICON_FRAME)
	b.frame:SetAllPoints()
	b.rankBg = b:CreateTexture(nil, "OVERLAY", nil, 2)
	b.rankBg:SetColorTexture(0, 0, 0, 0.78)
	b.rankBg:SetSize(22, 11)
	b.rankBg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
	b.rank = Light(b, "NumberFontNormalSmall", "RIGHT")
	b.rank:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
	if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
	b:SetScript("OnEnter", function(self)
		local S = Core()
		local lines = self.talent and S and S.TalentLines(self.talent)
		if not lines then return end
		Kit.Tip(self, { { lines.title, 1, 1, 1, false }, lines.kind and { lines.kind, 1, 1, 1, false } or "",
			lines.desc and { lines.desc, 1, 0.82, 0, true } or "", { lines.rank, 1, 1, 1, false } })
	end)
	b:SetScript("OnLeave", function(self) Kit.HideTip(self) end)
	return b
end

local function Half(parent, side)
	local mirror = side == "B"
	local outer, inner = mirror and "RIGHT" or "LEFT", mirror and "LEFT" or "RIGHT"
	local sign = mirror and -1 or 1
	local h = CreateFrame("Frame", nil, parent)
	h.side = side
	h:SetSize(HALF, Spectate.H - HALF_Y - 6)
	h:SetPoint("TOPLEFT", parent, "TOPLEFT", mirror and (M + HALF + GUTTER) or M, -HALF_Y)
	-- The header: the portrait at the outer edge, the words beside it, the banner at the seal.
	local reach = Kit.PortraitReach(PORTRAIT)
	h.rig = Kit.NewPortrait(h, PORTRAIT)
	h.portrait = h.rig.slot
	h.portrait:SetPoint("TOP" .. outer, h, "TOP" .. outer, sign * (mirror and reach.right or reach.left), -4)
	h.banner = CreateFrame("Frame", nil, h)
	h.banner:SetSize(18, 50)
	h.banner:SetPoint("TOP" .. inner, h, "TOP" .. inner, 0, 2)
	local c = SIDE_COLOR[side]
	h.banner.cloth = Fill(h.banner, { c[1], c[2], c[3], 1 }, "ARTWORK")
	h.banner.cloth:SetPoint("TOPLEFT", 0, -3)
	h.banner.cloth:SetPoint("BOTTOMRIGHT", 0, 8)
	h.banner.tail = Fill(h.banner, { c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1 }, "ARTWORK")
	h.banner.tail:SetPoint("TOPLEFT", h.banner.cloth, "BOTTOMLEFT", 3, 0)
	h.banner.tail:SetPoint("BOTTOMRIGHT", h.banner, "BOTTOMRIGHT", -3, 0)
	h.banner.pole = Fill(h.banner, Kit.BRONZE, "OVERLAY")
	h.banner.pole:SetPoint("TOPLEFT", -2, 0)
	h.banner.pole:SetPoint("TOPRIGHT", 2, 0)
	h.banner.pole:SetHeight(3)
	Kit.Edge(h.banner, { 0.25, 0.13, 0.04, 0.9 }, 1, 0, "OVERLAY", h.banner.cloth)
	local wordsW = HALF - PORTRAIT - reach.left - reach.right - 8 - 18 - 10
	h.name = Text(h, "title", outer)
	h.name:SetPoint("TOP" .. outer, h.portrait, "TOP" .. inner, sign * (8 + (mirror and reach.left or reach.right)), -1)
	h.name:SetWidth(wordsW)
	h.who = Text(h, "small", outer)
	h.who:SetPoint("TOP" .. outer, h.name, "BOTTOM" .. outer, 0, -3)
	h.who:SetWidth(wordsW)
	h.guild = Text(h, "small", outer, SOFT)
	h.guild:SetPoint("TOP" .. outer, h.who, "BOTTOM" .. outer, 0, -2)
	h.guild:SetWidth(wordsW)
	-- The bars: health "cur / max" (or "NN%"), power with its percentage at the inner end.
	h.hp = StatusBar(h, HALF, HP_H, c, mirror)
	h.hp:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -HP_TOP)
	h.hpText = Light(h.hp, "GameFontHighlight", "CENTER")
	h.hpText:SetPoint("CENTER", 0, 0)
	h.power = StatusBar(h, HALF - 46, PW_H, POWER.MANA, mirror)
	h.power:SetPoint("TOP" .. outer, h, "TOP" .. outer, 0, -PW_TOP)
	h.powerText = Text(h, "small", inner)
	h.powerText:SetPoint(inner, h, "TOP" .. inner, 0, -(PW_TOP + PW_H / 2))
	h.powerText:SetWidth(40)
	h.live = { health = h.hp, healthText = h.hpText, power = h.power, powerText = h.powerText }
	-- Gear: the stage at the seal's side, the stats at the outer side.
	h.gear = CreateFrame("Frame", nil, h)
	h.gear:SetSize(HALF, BODY_H)
	h.gear:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -BODY_TOP)
	local st = CreateFrame("Frame", nil, h.gear)
	h.stage = st
	st:SetSize(STAGE_W, BODY_H)
	st:SetPoint("TOP" .. inner, h.gear, "TOP" .. inner, 0, 0)
	st.bg = Fill(st, STAGE_BG, "BACKGROUND")
	st.bg:SetAllPoints()
	Kit.Edge(st, Kit.BRONZE, 2, 2)
	Kit.Edge(st, { 0.22, 0.14, 0.05, 1 }, 1, 0, "ARTWORK")
	-- (A warm light behind him and his shadow under his feet.)
	st.glow = st:CreateTexture(nil, "BACKGROUND", nil, 2)
	st.glow:SetTexture(MASK)
	st.glow:SetVertexColor(0.55, 0.36, 0.14, 0.32)
	if st.glow.SetBlendMode then st.glow:SetBlendMode("ADD") end
	st.glow:SetSize(210, 250)
	st.glow:SetPoint("CENTER", st, "CENTER", 0, 4)
	st.floor = st:CreateTexture(nil, "BORDER")
	st.floor:SetTexture(MASK)
	st.floor:SetVertexColor(0, 0, 0, 0.6)
	st.floor:SetSize(150, 22)
	st.floor:SetPoint("BOTTOM", st, "BOTTOM", 0, 34)
	st.class = st:CreateTexture(nil, "ARTWORK")
	st.class:SetSize(72, 72)
	st.class:SetPoint("CENTER", st, "CENTER", 0, 8)
	st.class:SetAlpha(0.55)
	-- His 3D model in his gear (a PlayerModel on his unit, as the game's own inspect window draws
	-- it); a client that makes none keeps the class picture.
	local okModel, model = pcall(CreateFrame, "PlayerModel", nil, st)
	if okModel and model then
		st.model = model
		model:SetPoint("TOPLEFT", st, "TOPLEFT", SLOT + 14, -8)
		model:SetPoint("BOTTOMRIGHT", st, "BOTTOMRIGHT", -(SLOT + 14), 40)
		if model.SetFrameLevel and st.GetFrameLevel then model:SetFrameLevel((st:GetFrameLevel() or 1) + 1) end
		model:Hide()
	end
	st.look = { drawn = false }
	st.sight = Light(st, "GameFontDisableSmall", "CENTER")
	st.sight:SetPoint("TOP", st, "TOP", 0, -8)
	st.sight:SetText(L.ARENA_WATCH_OUT)
	st.slots = {}
	local S = Core()
	local function Column(list, x)
		for i, slot in ipairs(list or {}) do
			local b = SlotButton(st, side, slot)
			b:SetPoint("TOPLEFT", st, "TOPLEFT", x, -(8 + (i - 1) * (SLOT + SLOT_GAP)))
			st.slots[slot] = b
		end
	end
	Column(S and S.GEAR_LEFT, 8)
	Column(S and S.GEAR_RIGHT, STAGE_W - 8 - SLOT)
	local bottom = S and S.GEAR_BOTTOM or {}
	local x0 = (STAGE_W - (#bottom * SLOT + (#bottom - 1) * SLOT_GAP)) / 2
	for i, slot in ipairs(bottom) do
		local b = SlotButton(st, side, slot)
		b:SetPoint("BOTTOMLEFT", st, "BOTTOMLEFT", x0 + (i - 1) * (SLOT + SLOT_GAP), 8)
		st.slots[slot] = b
	end
	for _, b in pairs(st.slots) do if b.SetFrameLevel and st.GetFrameLevel then b:SetFrameLevel((st:GetFrameLevel() or 1) + 3) end end
	-- (His cast bar: the half's own, so it shows on both tabs; on the stage above the weapons, or
	-- under the trees. Above the stage's model and slots.)
	h.cast = CastBar(h, 150, 12, 12)
	if h.cast.SetFrameLevel and st.GetFrameLevel then h.cast:SetFrameLevel((st:GetFrameLevel() or 1) + 4) end
	-- The stats, in dark ink on the parchment.
	local sx = CreateFrame("Frame", nil, h.gear)
	h.stats = sx
	sx:SetSize(STATS_W, BODY_H)
	sx:SetPoint("TOP" .. outer, h.gear, "TOP" .. outer, 0, 0)
	local function Rows(title, rows, top)
		local head = Text(sx, "small", "LEFT", RUBRIC)
		head:SetPoint("TOPLEFT", sx, "TOPLEFT", 0, -top)
		head:SetWidth(STATS_W)
		head:SetText(title)
		local out = {}
		for i, row in ipairs(rows or {}) do
			local y = top + 16 + (i - 1) * 13
			local label = Text(sx, "small", "LEFT")
			label:SetPoint("TOPLEFT", sx, "TOPLEFT", 4, -y)
			label:SetWidth(STATS_W - 44)
			label:SetText(L[row.label] or row.key)
			local value = Text(sx, "small", "RIGHT")
			value:SetPoint("TOPRIGHT", sx, "TOPRIGHT", 0, -y)
			value:SetWidth(40)
			out[row.key] = value
		end
		return out, top + 16 + #(rows or {}) * 13
	end
	local after
	sx.values, after = Rows(L.ARENA_WATCH_STATS, S and S.STATS, 0)
	sx.resist, after = Rows(L.ARENA_WATCH_RESISTS, S and S.RESISTS, after + 8)
	sx.note = Text(sx, "small", "LEFT", SOFT)
	sx.note:SetPoint("TOPLEFT", sx, "TOPLEFT", 0, -(after + 6))
	sx.note:SetWidth(STATS_W)
	if sx.note.SetWordWrap then sx.note:SetWordWrap(true) end
	-- Talents: the trees' grids, made as a tree needs them.
	h.talents = CreateFrame("Frame", nil, h)
	h.talents:SetSize(HALF, BODY_H)
	h.talents:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -BODY_TOP)
	h.talents.trees = {}
	h.talents.note = Text(h.talents, "small", "CENTER", SOFT)
	h.talents.note:SetPoint("BOTTOM", h.talents, "BOTTOM", 0, 2)
	h.talents.note:SetWidth(HALF)
	h.talents:Hide()
	PlaceCast(h, "gear")
	-- The status line and Inspect again, at the outer bottom.
	h.refresh = Kit.Button(h, 60, 24, L.ARENA_WATCH_REFRESH, function()
		local Sc = Core()
		if Sc then Sc.Reinspect(side) end
		Spectate.Refresh()
	end, L.ARENA_WATCH_REFRESH_TIP)
	Kit.Fit(h.refresh, 60)
	h.refresh:SetPoint("TOP" .. outer, h, "TOP" .. outer, 0, -STATUS_TOP)
	h.status = Text(h, "small", outer)
	h.status:SetPoint(outer, h.refresh, inner, sign * 8, 0)
	h.status:SetWidth(HALF - (tonumber(h.refresh:GetWidth()) or 60) - 10)
	if h.status.SetWordWrap then h.status:SetWordWrap(true) end
	h.sig = {}
	return h
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function BuildWindow()
	if win then return win end
	win = Kit.Frame("OlympusArenaWatch", Spectate.W, Spectate.H, { title = L.ARENA_WATCH_TITLE, strata = "HIGH", stack = true,
		free = true, footer = false })
	Place(win, "point", { "TOP", "TOP", 0, -80 })
	Kit.FitWindow(win, Spectate.W, Spectate.H, Clamp(Settings().scale))
	win:SetScript("OnDragStop", function(self)
		if self.StopMovingOrSizing then self:StopMovingOrSizing() end
		SavePoint(self, "point")
	end)
	-- Its X and Escape end the session; a swap to the bar (Auto) or the UI hidden with its parent do not.
	win:HookScript("OnHide", function(self)
		if view.swapping or (self.IsShown and self:IsShown()) then return end
		Spectate.Hide()
	end)
	-- The strip: Gear | Talents, the fight's line, the pins, -/+ and Copy.
	win.tabs = Kit.Choices(win, { { "gear", L.ARENA_WATCH_GEAR }, { "talents", L.ARENA_WATCH_TALENTS } }, 84, function(key) Spectate.SetTab(key) end)
	win.tabs:SetPoint("TOPLEFT", win, "TOPLEFT", M, -STRIP_Y)
	win.tabs.buttons[1].tip, win.tabs.buttons[2].tip = L.ARENA_WATCH_GEAR_TIP, L.ARENA_WATCH_TALENTS_TIP
	for _, b in ipairs(win.tabs.buttons) do Kit.SetButton(b, nil, true) end
	win.smaller = Kit.Button(win, 28, 24, L.ARENA_WATCH_SMALLER, function() Spectate.SetScale(Settings().scale and Settings().scale - Spectate.SCALE_STEP or 1 - Spectate.SCALE_STEP) end, L.ARENA_WATCH_SMALLER_TIP)
	win.smaller:SetPoint("LEFT", win.tabs.buttons[2], "RIGHT", 10, 0)
	win.larger = Kit.Button(win, 28, 24, L.ARENA_WATCH_LARGER, function() Spectate.SetScale((Settings().scale or 1) + Spectate.SCALE_STEP) end, L.ARENA_WATCH_LARGER_TIP)
	win.larger:SetPoint("LEFT", win.smaller, "RIGHT", 2, 0)
	win.copy = Kit.Button(win, 64, 24, L.ARENA_BTN_COPY, function()
		local S = Core()
		if S then Kit.Copy(L.ARENA_WATCH_TITLE, S.Text()) end
	end, L.ARENA_WATCH_COPY_TIP)
	win.copy:SetPoint("TOPRIGHT", win, "TOPRIGHT", -M, -STRIP_Y)
	local pins = {}
	for _, key in ipairs(Spectate.PINS) do pins[#pins + 1] = { key, L["ARENA_WATCH_PIN_" .. key:upper()] } end
	win.pins = Kit.Choices(win, pins, 76, function(key) Spectate.Pin(key) end)
	win.pins:SetPoint("RIGHT", win.copy, "LEFT", -(10 + 2 * 78), 0)
	for i, key in ipairs(Spectate.PINS) do
		win.pins.buttons[i].tip = L["ARENA_WATCH_PIN_" .. key:upper() .. "_TIP"]
		Kit.SetButton(win.pins.buttons[i], nil, true)
	end
	win.fight = Text(win, nil, "CENTER")
	win.fight:SetPoint("TOP", win, "TOP", 0, -(STRIP_Y + 4))
	win.fight:SetWidth(300)
	-- The halves, the seal between them and the bronze line down the middle.
	win.halves = { A = Half(win, "A"), B = Half(win, "B") }
	win.seal = Seal(win, 48)
	win.seal:SetPoint("CENTER", win, "TOP", 0, -(HALF_Y + 26))
	win.seal.text:SetText(L.ARENA_WATCH_VS)
	for _, part in ipairs({ { -(STRIP_Y + 30), -(HALF_Y + 2) }, { -(HALF_Y + 52), -(Spectate.H - 14) } }) do
		local line = Fill(win, { Kit.BRONZE[1], Kit.BRONZE[2], Kit.BRONZE[3], 0.55 }, "BORDER")
		line:SetWidth(2)
		line:SetPoint("TOP", win, "TOP", 0, part[1])
		line:SetPoint("BOTTOM", win, "TOP", 0, part[2])
	end
	win.watermark = Text(win, "small", "CENTER", RED_INK)
	win.watermark:SetPoint("BOTTOM", win, "BOTTOM", 0, 10)
	return win
end

---------------------------------------------------------------------------
-- The compact bar
---------------------------------------------------------------------------

local function BarSide(b, side)
	local mirror = side == "B"
	local outer, inner = mirror and "RIGHT" or "LEFT", mirror and "LEFT" or "RIGHT"
	local sign = mirror and -1 or 1
	local s = CreateFrame("Frame", nil, b)
	s:SetSize(BAR_SIDE, Spectate.BAR_H)
	s:SetPoint(inner, b, "CENTER", -sign * (BAR_SEAL / 2 + 8), 0)
	s.icon = s:CreateTexture(nil, "ARTWORK")
	s.icon:SetSize(34, 34)
	s.icon:SetPoint(outer, s, outer, 0, 0)
	s.ring = s:CreateTexture(nil, "BORDER")
	s.ring:SetTexture(MASK)
	s.ring:SetVertexColor(Kit.BRONZE[1], Kit.BRONZE[2], Kit.BRONZE[3])
	s.ring:SetPoint("TOPLEFT", s.icon, "TOPLEFT", -2, 2)
	s.ring:SetPoint("BOTTOMRIGHT", s.icon, "BOTTOMRIGHT", 2, -2)
	local w = BAR_SIDE - 34 - 6
	s.name = Light(s, "GameFontNormal", outer)
	s.name:SetPoint("TOP" .. outer, s, "TOP" .. outer, sign * 40, -6)
	s.name:SetWidth(w)
	local c = SIDE_COLOR[side]
	s.hp = StatusBar(s, w, 14, c, mirror)
	s.hp:SetPoint("TOP" .. outer, s, "TOP" .. outer, sign * 40, -21)
	s.hpText = Light(s.hp, "GameFontHighlightSmall", "CENTER")
	s.hpText:SetPoint("CENTER", 0, 0)
	s.power = StatusBar(s, w - 34, 6, POWER.MANA, mirror)
	s.power:SetPoint("TOP" .. outer, s.hp, "BOTTOM" .. outer, 0, -3)
	s.powerText = Light(s, "GameFontHighlightSmall", inner)
	s.powerText:SetPoint(inner, s.hp, "BOTTOM" .. inner, 0, -6)
	s.powerText:SetWidth(32)
	s.cast = CastBar(s, w, 4)
	s.cast:SetPoint("TOP" .. outer, s.power, "BOTTOM" .. outer, 0, -3)
	s.live = { health = s.hp, healthPct = s.hpText, power = s.power, powerText = s.powerText }
	return s
end

local function BuildBar()
	if bar then return bar end
	bar = CreateFrame("Frame", "OlympusArenaWatchBar", UIParent)
	bar:SetSize(Spectate.BAR_W, Spectate.BAR_H)
	bar:SetFrameStrata("HIGH")
	bar:SetClampedToScreen(true)
	bar:EnableMouse(true)
	bar:SetMovable(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
	bar:SetScript("OnDragStop", function(self)
		if self.StopMovingOrSizing then self:StopMovingOrSizing() end
		SavePoint(self, "barPoint")
	end)
	Place(bar, "barPoint", { "BOTTOM", "BOTTOM", 0, 190 })
	bar:SetScale(Clamp(Settings().scale))
	-- Bones' wood (its table's strip, as the games' bottom bar), darker, in a bronze edge.
	local G = own.Games
	local wood = type(G) == "table" and type(G.WOOD) == "table" and G.WOOD or nil
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	if wood and Kit.Exists(wood.file) then
		bar.bg:SetTexture(wood.file)
		if bar.bg.SetTexCoord then bar.bg:SetTexCoord(unpack(wood.coords)) end
		bar.bg:SetVertexColor(0.45, 0.40, 0.36)
	else
		bar.bg:SetColorTexture(0.10, 0.06, 0.03, 0.94)
	end
	bar.wash = Fill(bar, { 0, 0, 0, 0.35 }, "BACKGROUND", 1)
	bar.wash:SetAllPoints()
	Kit.Edge(bar, Kit.BRONZE, 2, 0, "BORDER")
	Kit.Edge(bar, { 0.18, 0.10, 0.03, 1 }, 1, -2, "BORDER")
	bar.sides = { A = BarSide(bar, "A"), B = BarSide(bar, "B") }
	bar.seal = Seal(bar, BAR_SEAL)
	bar.seal:SetPoint("CENTER", bar, "CENTER", 0, 0)
	bar.expand = Kit.Button(bar, 24, 24, L.ARENA_WATCH_EXPAND, function() Spectate.Pin("full") end, L.ARENA_WATCH_EXPAND_TIP)
	bar.expand:SetPoint("LEFT", bar, "LEFT", 6, 0)
	bar.close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
	bar.close:SetSize(26, 26)
	bar.close:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	bar.close:SetScript("OnClick", function() Spectate.Hide() end)
	bar:Hide()
	return bar
end

---------------------------------------------------------------------------
-- Drawing (the slow pass: once a second, at a change; never a live value)
---------------------------------------------------------------------------

local function Watermark(m)
	local A = ns.Arena
	local AF = ns.ArenaFights
	local f = m.fight and type(AF) == "table" and type(AF.Fight) == "function" and AF.Fight(m.fight.fid) or nil
	if (type(f) == "table" and f.mode == "T") or (type(A.TestBuild) == "function" and A.TestBuild()) then return L.ARENA_WATERMARK_TEST end
	return nil
end

-- The fight's line: the result as this client read it, else the fight it knows (best of, round,
-- score, its state), else "Not an Olympus duel"; "In combat" while either fighter is.
function Spectate.FightLine(m, fighting)
	if type(m) ~= "table" then return "" end
	local S = Core()
	-- (A best of 3 after a round: the fight's line and that round's, never "wins" before it is won.)
	local round = m.result and S and S.RoundResult(m)
	if m.result then
		local w, l = m.sides[m.result.w], m.sides[Other(m.result.w)]
		if not round then
			if m.result.m == "R" then return L.ARENA_WATCH_WON_FLED:format(Kit.Name(w.name), Kit.Name(l.name)) end
			return L.ARENA_WATCH_WON_KO:format(Kit.Name(w.name))
		end
	end
	local parts = {}
	if m.fight then
		parts[1] = L.ARENA_WATCH_FIGHT_LINE:format(m.fight.bo or 1, math.max(1, m.fight.round or 0), m.fight.a or 0, m.fight.b or 0)
		local word = not round and ns.ArenaHome.StateWord({ state = m.fight.state })
		if word and word ~= "" then parts[#parts + 1] = word end
	elseif not m.olympus then
		parts[1] = L.ARENA_WATCH_NOT_OLYMPUS
	end
	if round then
		local w, l = m.sides[m.result.w], m.sides[Other(m.result.w)]
		parts[#parts + 1] = m.result.m == "R" and L.ARENA_WATCH_ROUND_FLED:format(Kit.Name(w.name), Kit.Name(l.name))
			or L.ARENA_WATCH_ROUND_KO:format(Kit.Name(w.name))
	end
	if fighting == true then parts[#parts + 1] = L.ARENA_WATCH_IN_COMBAT end
	return table.concat(parts, " · ")
end

local function DrawHeader(h, s)
	local key = table.concat({ tostring(s.name), tostring(s.class), tostring(s.className), tostring(s.raceName), tostring(s.level),
		tostring(s.guild), tostring(s.token) }, "|")
	if h.sig.head == key then return end
	h.sig.head = key
	Kit.DrawPortrait(h.rig, s.name, { class = s.class })
	h.name:SetText(Kit.Name(s.name))
	Ink(h.name, ClassInk(s.class))
	if s.className or s.raceName or s.level then
		h.who:SetText(L.ARENA_WATCH_WHO:format(s.className or "?", s.raceName or "?", s.level or 0))
	else
		h.who:SetText("")
	end
	h.guild:SetText(s.guild and ("<" .. s.guild .. ">") or "")
	local p = PowerRGB(s.powerToken, s.powerType)
	h.power:SetStatusBarColor(p[1], p[2], p[3])
end

-- His model: drawn once his unit is in sight (the game's own SetUnit, its true: it could draw
-- him), kept when he leaves sight, drawn again when his look changes (UNIT_MODEL_CHANGED).
local FACING = { A = 0.45, B = -0.45 } -- (each turned a little towards the other, across the seal)
local function DrawModel(h, s)
	local st = h.stage
	local model = st.model
	local now = GetTime()
	local look = st.look
	if model and s.inSight and s.token and not look.drawn and now - (look.triedAt or -math.huge) >= Spectate.MODEL_RETRY then
		look.triedAt = now
		local ok, drawn = pcall(model.SetUnit, model, s.token)
		if ok and drawn ~= false then
			look.drawn = true
			if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end
			if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, 1.05) end
			if model.SetFacing then pcall(model.SetFacing, model, FACING[h.side]) end
		end
	end
	if model then
		model:SetShown(look.drawn == true)
		if look.drawn and model.SetModelAlpha then pcall(model.SetModelAlpha, model, s.inSight and 1 or 0.5) end
	end
	st.class:SetShown(not look.drawn)
	if not look.drawn then ClassIcon(st.class, s.class) end
	st.sight:SetShown(not s.inSight)
end

local function ItemID(item) return type(item) == "string" and tonumber(item:match("^item:(%d+)")) or nil end
local function ItemIcon(id)
	local I = C_Item
	if type(I) == "table" and type(I.GetItemIconByID) == "function" then
		local ok, icon = pcall(I.GetItemIconByID, id)
		if ok and icon then return icon end
	end
	if type(GetItemIcon) == "function" then
		local ok, icon = pcall(GetItemIcon, id)
		if ok and icon then return icon end
	end
	return nil
end
local function QualityRGB(id)
	local I = C_Item
	if type(I) ~= "table" or type(I.GetItemQualityByID) ~= "function" then return nil end
	local ok, q = pcall(I.GetItemQualityByID, id)
	if not ok or type(q) ~= "number" or q < 2 then return nil end
	local c = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[q] or nil
	if type(c) == "table" and tonumber(c.r) then return { c.r, c.g, c.b } end
	return nil
end
local function EmptySlot(slot)
	local name = SLOT_NAMES[slot]
	if name and type(GetInventorySlotInfo) == "function" then
		local ok, _, texture = pcall(GetInventorySlotInfo, name)
		if ok and texture then return texture end
	end
	return EMPTY_SLOT
end

local function DrawGear(h, s)
	local st = h.stage
	for slot, b in pairs(st.slots) do
		local item = type(s.gear) == "table" and s.gear[slot] or nil
		local id = ItemID(item)
		b.item = id and item or nil
		local icon = id and ItemIcon(id) or nil
		b.icon:SetTexture(icon or EmptySlot(slot))
		b.icon:SetDesaturated(icon == nil)
		b.icon:SetAlpha(icon and 1 or 0.6)
		local q = id and QualityRGB(id) or nil
		local c = q or Kit.BRONZE
		b.frame:SetVertexColor(c[1], c[2], c[3])
	end
	local sx = h.stats
	local stats, resist = type(s.stats) == "table" and s.stats or {}, type(s.resist) == "table" and s.resist or {}
	local known = s.stats ~= nil
	for key, fs in pairs(sx.values) do fs:SetText(known and tostring(stats[key] or 0) or L.ARENA_WATCH_DASH) end
	for key, fs in pairs(sx.resist) do fs:SetText(known and tostring(resist[key] or 0) or L.ARENA_WATCH_DASH) end
	sx.note:SetText(s.statsPending and L.ARENA_WATCH_LOADING or L.ARENA_WATCH_STATS_NOTE)
end

local function TreeFrame(h, i)
	local t = h.talents.trees[i]
	if t then return t end
	t = CreateFrame("Frame", nil, h.talents)
	t.name = Text(t, "small", "CENTER", RUBRIC)
	t.name:SetPoint("TOP", t, "TOP", 0, 0)
	t.points = Text(t, "small", "CENTER")
	t.points:SetPoint("TOP", t.name, "BOTTOM", 0, -1)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetSize(40, 40)
	t.icon:SetPoint("TOP", t.points, "BOTTOM", 0, -10)
	t.cells = {}
	h.talents.trees[i] = t
	return t
end

local function DrawTalents(h, s, status)
	local box = h.talents
	local tal = type(s.talents) == "table" and s.talents or nil
	local trees = tal and tal.trees or {}
	local n = math.min(#trees, 5)
	local gap = 6
	local tw = n > 0 and math.floor((HALF - gap * (n - 1)) / n) or HALF
	for i = 1, math.max(n, #box.trees) do
		local tree, t = trees[i], (i <= n) and TreeFrame(h, i) or box.trees[i]
		if t then
			t:SetShown(tree ~= nil)
			if tree then
				t:ClearAllPoints()
				t:SetPoint("TOPLEFT", box, "TOPLEFT", (i - 1) * (tw + gap), 0)
				t:SetSize(tw, BODY_H - 18)
				t.name:SetWidth(tw)
				t.name:SetText(tree.name or "?")
				t.points:SetText(tree.points and L.ARENA_WATCH_POINTS:format(tree.points) or L.ARENA_WATCH_DASH)
				local list = tal.grid and tree.talents or {}
				-- The grid: tiers by columns, as large as the tree's room allows (34 px at most).
				local tiers, cols = math.max(1, tree.tiers or 1), math.max(1, tree.columns or 1)
				local cell = math.max(14, math.min(34, math.floor(tw / cols), math.floor((BODY_H - 18 - 32) / tiers)))
				local x0 = math.floor((tw - cols * cell) / 2)
				for j = 1, math.max(#list, #t.cells) do
					local talent, b = list[j], t.cells[j]
					if talent and not b then
						b = TalentCell(t)
						t.cells[j] = b
					end
					if b then
						b:SetShown(talent ~= nil)
						if talent then
							b.talent = talent
							b:SetSize(cell - 4, cell - 4)
							b:ClearAllPoints()
							b:SetPoint("TOPLEFT", t, "TOPLEFT", x0 + ((talent.column or 1) - 1) * cell + 2, -(32 + ((talent.tier or 1) - 1) * cell))
							b.icon:SetTexture(talent.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
							local rank, max = talent.rank or 0, talent.max or 1
							b.icon:SetDesaturated(rank == 0)
							b.icon:SetAlpha(rank == 0 and 0.45 or 1)
							b.rank:SetText(("%d/%d"):format(rank, max))
							local c = rank == 0 and { 0.6, 0.6, 0.6 } or (rank >= max and Kit.GOLD or { 0.25, 1, 0.25 })
							b.rank:SetTextColor(c[1], c[2], c[3])
							local f = rank == 0 and { 0.35, 0.3, 0.25 } or c
							b.frame:SetVertexColor(f[1], f[2], f[3])
						else
							b.talent = nil
						end
					end
				end
				-- No grid on this client: the tree's own picture under its points.
				t.icon:SetShown(not tal.grid)
				if not tal.grid then t.icon:SetTexture(tree.icon or "Interface\\Icons\\INV_Misc_QuestionMark") end
			end
		end
	end
	if not tal then
		box.note:ClearAllPoints()
		box.note:SetPoint("CENTER", box, "CENTER", 0, 0)
		box.note:SetText((s.inspected or s.own) and L.ARENA_WATCH_NO_TALENTS or (status or ""))
	else
		-- (Points only: the line under the trees' pictures, clear of the cast bar at the bottom.)
		box.note:ClearAllPoints()
		if tal.grid then box.note:SetPoint("BOTTOM", box, "BOTTOM", 0, 2)
		else box.note:SetPoint("TOP", box, "TOP", 0, -POINTS_NOTE_Y) end
		box.note:SetText(not tal.grid and L.ARENA_WATCH_POINTS_ONLY or "")
	end
end

local function DrawHalf(h, s)
	local S = Core()
	DrawHeader(h, s)
	DrawModel(h, s)
	local status = S and S.StatusLine(s) or nil
	h.status:SetText(status or "")
	h.refresh:SetShown(not s.own)
	h.gear:SetShown(view.tab == "gear")
	h.talents:SetShown(view.tab == "talents")
	PlaceCast(h, view.tab)
	local key = table.concat({ view.tab, tostring(s.inspected), tostring(s.statsPending), tostring(s.gearN),
		tostring(s.talents and s.talents.total), tostring(s.talents and s.talents.source), tostring(s.stats ~= nil), view.tab == "talents" and tostring(status) or "" }, "|")
	if h.sig.body == key then return end
	h.sig.body = key
	if view.tab == "talents" then DrawTalents(h, s, status) else DrawGear(h, s) end
end

local function DrawWindow(m)
	local S = Core()
	win.fight:SetText(Spectate.FightLine(m, S and S.Fighting()))
	Ink(win.fight, m.result and RED_INK or Kit.INK)
	win.watermark:SetText(Watermark(m) or "")
	if win.tabs.selected ~= view.tab then win.tabs:Select(view.tab) end
	if win.pins.selected ~= view.pin then win.pins:Select(view.pin) end
	for _, key in ipairs(SIDES) do DrawHalf(win.halves[key], m.sides[key]) end
end

local function DrawBar(m)
	for _, key in ipairs(SIDES) do
		local s, b = m.sides[key], bar.sides[key]
		b.name:SetText(Kit.Name(s.name))
		local c = ClassRGB(s.class)
		if c then b.name:SetTextColor(c[1], c[2], c[3]) else b.name:SetTextColor(Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3]) end
		ClassIcon(b.icon, s.class)
		local p = PowerRGB(s.powerToken, s.powerType)
		b.power:SetStatusBarColor(p[1], p[2], p[3])
	end
	local seal = bar.seal
	seal.text:ClearAllPoints()
	seal.small:ClearAllPoints()
	if m.fight then
		seal.text:SetPoint("CENTER", seal, "CENTER", 0, 5)
		seal.text:SetText(("%d : %d"):format(m.fight.a or 0, m.fight.b or 0))
		seal.small:SetPoint("CENTER", seal, "CENTER", 0, -10)
		seal.small:SetText(L.ARENA_WATCH_BAR_ROUND:format(math.max(1, m.fight.round or 0)))
	else
		seal.text:SetPoint("CENTER", seal, "CENTER", 0, 0)
		seal.text:SetText(L.ARENA_WATCH_VS)
		seal.small:SetText("")
	end
end

-- The slow pass: the model read once, the shown frame drawn from it.
local function Slow()
	local S = Core()
	local m = S and S.Model()
	if not m then return nil end
	view.model = m
	if view.mode == "compact" then DrawBar(m) elseif win then DrawWindow(m) end
	return m
end

---------------------------------------------------------------------------
-- The live values (every tick) and the cast
---------------------------------------------------------------------------

local function Widgets(side)
	if view.mode == "compact" then return bar and bar.sides[side] end
	return win and win.halves[side]
end
local function Live()
	local S = Core()
	if not S then return end
	for _, key in ipairs(SIDES) do
		local w = Widgets(key)
		if w then S.Push(key, w.live) end
	end
end

local function ShowCast(c, kind)
	c:SetShown(kind ~= nil)
	if kind == c.castKind then return end
	c.castKind = kind
	-- (A channel: the fill dark, the ground bright, so the bright part shrinks as it runs out.)
	if kind == "channel" then
		c.bar:SetStatusBarColor(DARK[1], DARK[2], DARK[3])
		c.bar.bg:SetColorTexture(CHANNEL[1], CHANNEL[2], CHANNEL[3], 0.95)
	else
		c.bar:SetStatusBarColor(CAST[1], CAST[2], CAST[3])
		c.bar.bg:SetColorTexture(DARK[1], DARK[2], DARK[3], DARK[4])
	end
end
local CastTick
CastTick = function()
	local S = Core()
	if not S then return end
	local any = false
	for _, key in ipairs(SIDES) do
		local w = Widgets(key)
		local c = w and w.cast
		if c then
			local kind = S.Cast(key, c.widgets)
			ShowCast(c, kind)
			if kind then any = true end
		end
	end
	-- (The other frame's cast bars: hidden, so a swap never shows a stale one.)
	for _, key in ipairs(SIDES) do
		local o = view.mode == "compact" and win and win.halves[key] or (bar and bar.sides[key])
		if o and o.cast and o ~= Widgets(key) then ShowCast(o.cast, nil) end
	end
	if any and not castTicker and C_Timer and C_Timer.NewTicker then
		castTicker = C_Timer.NewTicker(Spectate.CAST_TICK, function() ns.SafeCall("arena watch cast", CastTick) end)
	elseif not any and castTicker then
		castTicker:Cancel()
		castTicker = nil
	end
end

---------------------------------------------------------------------------
-- Full or bar (Auto, or the pin)
---------------------------------------------------------------------------

local function WantMode()
	if view.pin == "full" or view.pin == "compact" then return view.pin end
	local S = Core()
	local fighting = S and S.Fighting()
	-- (The result: the full view, whatever the combat flag still says for a few seconds.)
	if view.resultAt and GetTime() - view.resultAt < Spectate.RESULT_HOLD then return "full" end
	if fighting == true then
		view.calmAt, view.resultAt = nil, nil
		return "compact"
	end
	if fighting == false then
		if view.mode == "compact" and not view.resultAt then
			local now = GetTime()
			view.calmAt = view.calmAt or now
			if now - view.calmAt < Spectate.HOLD then return "compact" end
		end
		return "full"
	end
	return view.mode or "full"
end

local function ApplyMode(mode)
	if mode == view.mode then return false end
	view.mode = mode
	view.swapping = true
	if mode == "compact" then
		if win and win:IsShown() then win:Hide() end
		bar:Show()
	else
		if bar and bar:IsShown() then bar:Hide() end
		win:Show()
	end
	view.swapping = false
	if win then for _, key in ipairs(SIDES) do win.halves[key].sig = {} end end
	return true
end

---------------------------------------------------------------------------
-- The session's frames, events and timers
---------------------------------------------------------------------------

local function OnEvent(event, ...)
	local S = Core()
	if not S or not S.Active() then return end
	if event == "CHAT_MSG_SYSTEM" then
		local side = S.OnSystem((...))
		if side then
			view.resultAt = GetTime()
			if view.pin == "auto" then ApplyMode("full") end
			Slow()
		end
	elseif event == "UNIT_INVENTORY_CHANGED" then
		local unit = ...
		S.OnInventory(unit)
		Spectate.ModelChanged(unit)
	elseif event == "UNIT_MODEL_CHANGED" then
		Spectate.ModelChanged((...))
	elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
		-- (A crowd's nameplates come and go all the time: only his own one looked at.)
		local unit = ...
		if Spectate.HisPlate(unit, event == "NAME_PLATE_UNIT_ADDED") then
			S.Track(event == "NAME_PLATE_UNIT_ADDED")
			Live()
			Slow()
		end
	else
		-- (The target, the focus: who is in sight now, at once.)
		S.Track(true)
		Live()
		Slow()
	end
end

-- A nameplate that is one fighter's: added, his GUID's (one out of sight); removed, the token he
-- had. A GUID the game keeps secret is no match.
function Spectate.HisPlate(unit, added)
	local S = Core()
	if not S or type(unit) ~= "string" or (type(issecretvalue) == "function" and issecretvalue(unit)) then return false end
	local m = view.model
	for _, key in ipairs(SIDES) do
		local token = S.Token(key)
		if not added and token == unit then return true end
		local guid = m and m.sides[key] and m.sides[key].guid
		if added and not token and type(guid) == "string" and type(UnitGUID) == "function" then
			local ok, g = pcall(UnitGUID, unit)
			if ok and not (type(issecretvalue) == "function" and issecretvalue(g)) and g == guid then return true end
		end
	end
	return false
end

-- His look changed (or his gear): the model drawn again, on his unit now.
function Spectate.ModelChanged(unit)
	if not win or type(unit) ~= "string" or (type(issecretvalue) == "function" and issecretvalue(unit)) then return false end
	local S = Core()
	for _, key in ipairs(SIDES) do
		local st = win.halves[key].stage
		if S and S.Token(key) == unit and st.model then
			st.look = { drawn = false }
			return true
		end
	end
	return false
end

local function Listen(on)
	if not events then
		if not on then return end
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", function(_, event, ...) ns.SafeCall("arena watch " .. tostring(event), OnEvent, event, ...) end)
	end
	for _, e in ipairs(Spectate.EVENTS) do
		if on then pcall(events.RegisterEvent, events, e) else events:UnregisterEvent(e) end
	end
end

local function Tick()
	local S = Core()
	if not S or not S.Active() then return Spectate.Hide() end
	view.ticks = view.ticks + 1
	local slow = view.ticks % Spectate.SIGHT_EVERY == 0
	if slow then S.Track(false) end
	if ApplyMode(WantMode()) then slow = true end
	Live()
	if not castTicker then CastTick() end
	if slow then Slow() end
end

local function StopTickers()
	if ticker then ticker:Cancel() ticker = nil end
	if castTicker then castTicker:Cancel() castTicker = nil end
end

-- The window and the bar forgotten, back to their first look for a new pair.
local function Reset()
	view.ticks, view.calmAt, view.resultAt, view.model = 0, nil, nil, nil
	for _, key in ipairs(SIDES) do
		local h = win.halves[key]
		h.sig = {}
		local st = h.stage
		st.look = { drawn = false } -- (drawn: his model is on it; triedAt: when it was last asked)
		if st.model then
			if st.model.ClearModel then pcall(st.model.ClearModel, st.model) end
			st.model:Hide()
		end
		ShowCast(h.cast, nil)
		ShowCast(bar.sides[key].cast, nil)
	end
end

---------------------------------------------------------------------------
-- The API (ArenaUI.Open("duel.watch", subject), the core's S.Close; the tests)
---------------------------------------------------------------------------

-- Opens the view on a subject (ArenaSpectate's): the session started, both frames made, the one
-- Auto or the pin wants shown. Returns the window, or nil when the subject is no pair.
function Spectate.Show(subject)
	local S = Core()
	if not S or not S.Start(subject) then return nil end
	BuildWindow()
	BuildBar()
	StopTickers()
	Reset()
	local set = Settings()
	view.pin = (set.pin == "full" or set.pin == "compact") and set.pin or "auto"
	view.tab = set.tab == "talents" and "talents" or "gear"
	view.mode = nil
	Listen(true)
	S.Track(true)
	ApplyMode(WantMode())
	Live()
	CastTick()
	Slow()
	if not ticker and C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(Spectate.TICK, function() ns.SafeCall("arena watch", Tick) end)
	end
	return win
end

-- Closes it: both frames hidden, the tickers cancelled, the events unregistered, the session over.
function Spectate.Hide()
	if view.hiding then return false end
	view.hiding = true
	Listen(false)
	StopTickers()
	view.swapping = true
	if win and win:IsShown() then win:Hide() end
	if bar and bar:IsShown() then bar:Hide() end
	view.swapping = false
	view.mode, view.model = nil, nil
	local S = Core()
	if S then S.Stop() end
	view.hiding = false
	return true
end

-- Redrawn now (a button's click, the tests).
function Spectate.Refresh()
	if not view.mode then return nil end
	if win then for _, key in ipairs(SIDES) do win.halves[key].sig.body = nil end end
	Live()
	return Slow()
end

-- Auto, Full or Bar (kept).
function Spectate.Pin(pin)
	if pin ~= "auto" and pin ~= "full" and pin ~= "compact" then return false end
	view.pin = pin
	if not ns.Arena.Sim() then Settings().pin = pin end
	if view.mode then
		ApplyMode(WantMode())
		Live()
		CastTick()
		Slow()
	end
	return true
end

-- Gear or Talents, both halves (kept).
function Spectate.SetTab(tab)
	if tab ~= "gear" and tab ~= "talents" then return false end
	view.tab = tab
	if not ns.Arena.Sim() then Settings().tab = tab end
	if win then
		win.tabs:Select(tab)
		if view.mode then Slow() end
	end
	return true
end

-- The scale (0.6 to 1.6) of the window and the bar, kept.
function Spectate.SetScale(s)
	s = Clamp(s)
	s = math.floor(s * 100 + 0.5) / 100
	Settings().scale = s
	if win then Kit.FitWindow(win, Spectate.W, Spectate.H, s) end
	if bar then bar:SetScale(s) end
	return s
end

function Spectate.Frame() return win end
function Spectate.Bar() return bar end
function Spectate.Mode() return view.mode end
function Spectate.Events() return events end
function Spectate.Ticking() return ticker ~= nil, castTicker ~= nil end
