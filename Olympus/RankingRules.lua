local ADDON, ns = ...
local L = ns.L

-- One native, in-window explanation page for every real ranking. A host owns navigation and
-- authorization: this module rechecks the same `allowed` callback both for the highlighted link
-- and for the page, so a stale callback cannot disclose a private rule page after authority changes.
local Rules = {}
ns.RankingRules = Rules

local specs = {}
local BOOK = "Interface\\Icons\\INV_Misc_Book_09"
Rules.WRAP = 58
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Grey(s) return "|cff9d9d9d" .. tostring(s or "") .. "|r" end
local function Value(v, spec)
	if type(v) == "function" then return v(spec) end
	return v
end

function Rules.Register(key, spec)
	if type(key) ~= "string" or key == "" or type(spec) ~= "table" then return false end
	if type(spec.title) ~= "string" and type(spec.title) ~= "function" then return false end
	specs[key] = spec
	return true
end

function Rules.Spec(key) return specs[key] end

function Rules.Allowed(key)
	local spec = specs[key]
	if not spec then return false end
	return type(spec.allowed) ~= "function" or spec.allowed() == true
end

function Rules.Link(key, onOpen)
	local spec = specs[key]
	if not spec or not Rules.Allowed(key) or type(onOpen) ~= "function" then return nil end
	local icon = Value(spec.icon, spec) or BOOK
	return {
		id = "ranking-rules:" .. key,
		text = Gold((icon and ("|T" .. icon .. ":14:14:0:0|t  ") or "") .. "> " .. L.RANK_RULES_LINK),
		onClick = onOpen,
		tooltip = function(tt)
			tt:AddLine(Value(spec.title, spec) or L.RANK_RULES_LINK, 1, 0.82, 0)
			tt:AddLine(L.RANK_RULES_LINK_TIP, 1, 1, 1, true)
		end,
		gapAfter = true,
	}
end

local TOPIC_ICON = {
	score = "Interface\\Icons\\INV_Misc_Coin_01",
	order = "Interface\\Icons\\INV_Misc_Note_01",
	evidence = "Interface\\Icons\\INV_Misc_Spyglass_03",
	visibility = "Interface\\Icons\\INV_Misc_Key_03",
	limits = "Interface\\Icons\\INV_Misc_PocketWatch_01",
}
local TOPIC_LABEL = {
	score = "RANK_RULES_SCORE",
	order = "RANK_RULES_ORDER",
	evidence = "RANK_RULES_EVIDENCE",
	visibility = "RANK_RULES_VISIBILITY",
	limits = "RANK_RULES_LIMITS",
}

-- The main list renderer does not wrap a row. Split prose into the same short native rows used by
-- Treasury instead of relying on a FontString to clip or escape the window. Colour each row after
-- measuring it so the escape codes do not consume the prose width.
local function Paragraph(lines, text, colour, indent)
	local row, first = "", #lines + 1
	for word in tostring(text or ""):gmatch("%S+") do
		if row ~= "" and #row + 1 + #word > Rules.WRAP then
			lines[#lines + 1] = { indent = indent, text = colour and colour(row) or row }
			row = word
		else
			row = row == "" and word or (row .. " " .. word)
		end
	end
	if row ~= "" then lines[#lines + 1] = { indent = indent, text = colour and colour(row) or row } end
	return #lines >= first
end

function Rules.Lines(key, onBack)
	local spec = specs[key]
	if not spec or not Rules.Allowed(key) or type(onBack) ~= "function" then return nil end
	local lines = {
		{ id = "ranking-rules-back", text = Gold(L.RANK_RULES_BACK), onClick = onBack, gapAfter = true },
	}
	local icon = Value(spec.icon, spec) or BOOK
	lines[#lines + 1] = { header = true, text = (icon and ("|T" .. icon .. ":18:18:0:0|t  ") or "") .. tostring(Value(spec.title, spec) or L.RANK_RULES_LINK) }
	Paragraph(lines, Value(spec.note, spec) or L.RANK_RULES_NOTE, Grey)
	lines[#lines].gapAfter = true
	local sections = Value(spec.sections, spec) or {}
	for _, section in ipairs(sections) do
		local body = Value(section.text, spec)
		if body and body ~= "" then
			local topic = section.topic
			local sectionIcon = Value(section.icon, spec) or TOPIC_ICON[topic] or BOOK
			local label = Value(section.title, spec) or L[TOPIC_LABEL[topic] or "RANK_RULES_EVIDENCE"]
			lines[#lines + 1] = { text = Gold("|T" .. sectionIcon .. ":14:14:0:0|t  " .. tostring(label)) }
			if type(body) ~= "table" then body = { body } end
			local first = #lines + 1
			for _, paragraph in ipairs(body) do
				Paragraph(lines, paragraph, nil, 1)
			end
			if #lines >= first then lines[#lines].gapAfter = true end
		end
	end
	return lines
end

-- The Realm is the one host whose page routing is shared by several modules. Keep the previous
-- page key exactly, then use its native page registry and Back line; no popup or second window.
local realmKey, realmReturn
function Rules.OpenRealm(key)
	if not Rules.Allowed(key) or not (ns.Views and ns.Views.ShowPage) then return false end
	realmKey, realmReturn = key, ns.Views.PageShown and ns.Views.PageShown() or nil
	ns.Views.ShowPage("ranking-rules")
	return true
end
local function CloseRealm()
	local previous = realmReturn
	realmKey, realmReturn = nil, nil
	if ns.Views and ns.Views.ShowPage then ns.Views.ShowPage(previous) end
end
function Rules.RealmLines()
	return Rules.Lines(realmKey, CloseRealm) or { { text = Gold(L.RANK_RULES_BACK), onClick = CloseRealm } }
end

local realmPages = rawget(ns, "RealmPages")
if type(realmPages) ~= "table" then realmPages = {}; ns.RealmPages = realmPages end
realmPages[#realmPages + 1] = { key = "ranking-rules", Lines = Rules.RealmLines, tip = "RANK_RULES_NOTE" }

function Rules.ResetForTests()
	realmKey, realmReturn = nil, nil
end
