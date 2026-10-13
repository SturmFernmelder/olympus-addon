local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]letter%-content%.lua$") or "./"
local MARKS = { "dice", "team", "guild", "church", "craft", "crown", "watch", "wanted", "news" }

local function Language(locale)
	local saved = GetLocale
	local cns = setmetatable({ On = function() end, RegisterEvent = function() end }, { __index = ns })
	GetLocale = function() return locale end
	local ok, why = pcall(function()
		assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", cns)
		assert(loadfile(ROOT .. "Olympus/Letters.lua"))("Olympus", cns)
	end)
	GetLocale = saved
	if not ok then error(why, 0) end
	return cns
end

test("1.2.4 letter content: both languages describe verified records and retain privacy, free-game and live-test limits", function()
	local order
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		local title, body = cns.Letters.Text("1.2.4")
		assert(title and #body > 3500, locale .. ": detailed correction letter")
		assert(body:find("1.2.4", 1, true), locale .. ": consolidated version")
		local raw, marks = cns.L.LETTER_1_2_4, {}
		for mark in raw:gmatch("{(%a+)}") do marks[#marks + 1] = mark end
		local sequence = table.concat(marks, ",")
		if order then eq(sequence, order, "same sections and icon order") else order = sequence end
		assert(not body:find("{[%a]+}"), locale .. ": all icons have a supported text fallback")
		for _, phrase in ipairs(locale == "enUS" and { "unknown keys", "not server-certified proof", "no bets", "Offline tests cannot", "not advertised as finished" }
			or { "chaves desconhecidas", "não são prova certificada pelo servidor", "sem apostas", "Testes offline não", "não são anunciadas como rankings prontos" }) do
			assert(raw:find(phrase, 1, true), locale .. ": " .. phrase)
		end
	end
end)

test("1.2.4 Legate wording: current duty and letter replace the old council century rules in both locales", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local c = Language(locale)
		local L = c.L
		assert(L.NOMINEES_MAIN_TITLE:find("Legates", 1, true))
		assert(L.NOMINEES_MAIN_HINT:find("25", 1, true), "manual appointment capacity is visible")
		assert(L.NOMINEES_LEGATE_DUTY:find("39", 1, true) and L.NOMINEES_LEGATE_DUTY:find("40", 1, true))
		local phrases = locale == "enUS" and { "optional", "offline", "events, raids and wars" }
			or { "opcionais", "offline", "eventos, raides e guerras" }
		for _, phrase in ipairs(phrases) do assert(L.NOMINEES_LEGATE_DUTY:find(phrase, 1, true), phrase) end
		local notice = L.NOMINEES_LEGATE_APPOINTED:format("Issuer", "Olympus", L.NOMINEES_LEGATE_DUTY)
		assert(notice:find("Issuer", 1, true) and notice:find("Olympus", 1, true) and notice:find("39", 1, true))
		eq(L.SQUAD_TOTAL:format(40), locale == "enUS" and "40/40 members" or "40/40 membros")
		assert(not L.NOMINEES_NOTE:find("30", 1, true), "offline duration is no longer appointment revocation")
		assert(not L.BORDERS_WHO_BRONZE:lower():find("legate", 1, true), "Legate office does not award the correspondent's border")
		assert(L.LETTER_1_2_4:find("Legates", 1, true))
		assert(L.LETTER_1_2_4:find(locale == "enUS" and "High Council membership alone does not appoint one" or "pertencer ao High Council não nomeia ninguém sozinho", 1, true))
	end
end)

test("Version letter content: both languages explain the guild, 99 soldiers, Church and free games with supported role markers", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		for _, version in ipairs({ "1.2.0", "1.2.1", "1.2.2" }) do
			local key = "LETTER_" .. version:gsub("%.", "_")
			local raw = assert(rawget(cns.L, key))
			local title, body = cns.Letters.Text(version)
			assert(type(title) == "string" and title ~= "", locale .. ": title")
			assert(type(body) == "string" and #body > 3500, locale .. ": detailed body")
			for _, mark in ipairs(MARKS) do
				assert(raw:find("- {" .. mark .. "}", 1, true), locale .. ": readable " .. mark .. " bullets")
				assert(type(rawget(cns.L, "LETTER_MARK_" .. mark:upper())) == "string", locale .. ": fallback " .. mark)
			end
			assert(not body:find("{[%a]+}"), locale .. ": known marker rendered or expressed in words")
			assert(raw:find(version, 1, true), locale .. ": explicit version")
		end
		local old = cns.L.LETTER_1_2_0
		assert(old:find("99", 1, true) and old:find("High Council", 1, true), locale .. ": actual squad leaders and cap")
		assert(old:find("Vox Populi", 1, true) and old:find("30", 1, true), locale .. ": retained polls")
		assert(old:find(locale == "enUS" and "duels only" or "somente para duelos", 1, true), locale .. ": level band does not apply to Bones")
		assert(old:find(locale == "enUS" and "not a finished new departmental workflow" or "não a um novo fluxo departamental pronto", 1, true), locale .. ": limited departments not advertised as finished")
		assert(cns.L.LETTER_1_2_2:find("Players", 1, true) and cns.L.LETTER_1_2_2:find("Everyone", 1, true), locale .. ": actual table audiences")
	end
end)

test("Version letter content: English and Portuguese preserve the same role marker order and payment/privacy limitations", function()
	local en, pt = Language("enUS"), Language("ptBR")
	local function Order(text)
		local out = {}
		for mark in text:gmatch("{(%a+)}") do out[#out + 1] = mark end
		return table.concat(out, ",")
	end
	for _, key in ipairs({ "LETTER_1_2_0", "LETTER_1_2_1", "LETTER_1_2_2" }) do
		eq(Order(en.L[key]), Order(pt.L[key]), key .. ": same sections and bullet icons")
	end
	assert(en.L.LETTER_1_2_2:find("no local send record or confirmed receipt held", 1, true))
	assert(pt.L.LETTER_1_2_2:find("Sem registro local de envio nem recibo confirmado guardado", 1, true))
	assert(en.L.LETTER_1_2_2:find("not anonymity on the network", 1, true))
	assert(pt.L.LETTER_1_2_2:find("não anonimato na rede", 1, true))
	assert(en.L.LETTER_1_2_2:find("excluded from test and release packages", 1, true))
	assert(pt.L.LETTER_1_2_2:find("fora dos pacotes de teste e de release", 1, true))
	-- 1.2.1 takes Ask to update away from ordinary members: the letter says who keeps it.
	assert(en.L.LETTER_1_2_2:find("Ask to update, in a player's right-click menu, is now only for the King, the High Council and the addon's author", 1, true))
	assert(pt.L.LETTER_1_2_2:find("Pedir para atualizar, no menu do botão direito de um jogador, agora é só para o Rei, o High Council e o autor do addon", 1, true))
end)

test("Version letter content: the actual letters limit level bands to duels and place the King's note in the recipient's local Chronicle", function()
	for _, locale in ipairs({ "enUS", "ptBR" }) do
		local cns = Language(locale)
		local _, before = cns.Letters.Text("1.2.0")
		local _, now = cns.Letters.Text("1.2.2")
		assert(before:find(locale == "enUS" and "duels only" or "somente para duelos", 1, true), locale .. ": the original Bones level-filter claim is corrected")
		assert(now:find(locale == "enUS" and "The recipient keeps the note in their local Chronicle with the King's authorship"
			or "Quem recebe guarda a nota em seu Chronicle local, com a autoria do Rei", 1, true), locale .. ": recipient-local record, not a persistent King's ledger")
		assert(now:find(locale == "enUS" and "main window's Realm tab, available to every member"
			or "aba O Reino da janela principal, disponível para todos os membros", 1, true), locale .. ": personal brief belongs to the ordinary member's main window")
		-- (1.2.2: the popup never reached a release, so the letter no longer says it is gone.)
		eq(now:find(locale == "enUS" and "surprise popup" or "popup inesperado", 1, true), nil, locale .. ": no fix claimed for a popup players never had")
	end
end)
