local ns, test, eq, extra = ...
local FILE = extra.ADDON_DIR .. "PersonalVerification.lua"

local function With(fn)
	local old = rawget(_G, "OlympusVerifyBridge242")
	local state = { refreshes = 0, calls = 0 }
	local n = { L = { TAB_SELF_VERIFY = "My verification" }, UI = {} }
	n.UI.AddTab = function(tab) state.tab = tab return true end
	n.UI.Refresh = function() state.refreshes = state.refreshes + 1 end
	OlympusVerifyBridge242 = nil
	assert(loadfile(FILE))("Olympus", n)
	local ok, err = pcall(fn, n.PersonalVerification, state)
	OlympusVerifyBridge242 = old
	if not ok then error(err, 0) end
end

local function Envelope()
	return { version = 243, deliveryOnly = true, membershipProof = false, roleAuthority = false,
		total = 0, truncated = false, requests = {} }
end

local function Text(V)
	local lines, title, detail = V.Build()
	local out = { title, detail }
	for _, line in ipairs(lines) do
		out[#out + 1] = line.text
		if line.tooltip then line.tooltip({ AddLine = function(_, text) out[#out + 1] = text end }) end
	end
	return table.concat(out, "\n"), lines
end

test("personal verification: absent at file load, discovered at page open after PLAYER_LOGIN, dot calls only", function()
	With(function(V, s)
		assert(Text(V):find("bridge unavailable", 1, true))
		V.Edit("CODE234")
		eq(V.Submit(), false)
		OlympusVerifyBridge242 = {
			QueueSelf = function(code, extraArg) eq(code, "CODE234"); eq(extraArg, nil); s.calls = s.calls + 1 return true end,
			Status = function(self) eq(self, nil); return Envelope() end,
		}
		for _ = 1, 5 do Text(V) end
		eq(s.calls, 0, "opening/status refresh never submits")
		eq(V.Submit(), true); eq(s.calls, 1)
		assert(Text(V):find("Local request exists", 1, true))
		assert(Text(V):find("not confirmed", 1, true))
	end)
end)

test("personal verification: actual tab, input and buttons queue only a deliberate click through refresh and reopen", function()
	extra.WithUI(function()
		local UI, uns = extra.LoadUI()
		local savedBridge = rawget(_G, "OlympusVerifyBridge242")
		local savedLabel, savedSubmit = rawget(ns.L, "TAB_SELF_VERIFY"), rawget(ns.L, "SELF_VERIFY_SUBMIT")
		local calls, statusReads, submitted = 0, 0, {}
		local ok, err = pcall(function()
			GetGuildInfo = function() return "Olympus II" end
			OlympusVerifyBridge242 = nil
			assert(loadfile(extra.ADDON_DIR .. "Locales/PersonalVerificationText.lua"))("Olympus", uns)
			assert(loadfile(FILE))("Olympus", uns)
			UI.Toggle() -- the real tab registration must happen before this creates the window
			eq(UI.SelectTab("selfverification"), true, "the actual added tab opens")
			local main = assert(OlympusFrame, "the actual Olympus window")
			eq(main.tab, "selfverification")
			eq(main.buttons[1]:GetText(), ns.L.SELF_VERIFY_SUBMIT)
			main.buttons[1]:Click()
			eq(calls, 0, "the actual Submit button is inert without Verify")
			OlympusVerifyBridge242 = {
				Status = function(self)
					eq(self, nil, "the real page reads Status with a dot call")
					statusReads = statusReads + 1
					return Envelope()
				end,
				QueueSelf = function(code, self)
					eq(self, nil, "the real button submits with a dot call")
					calls = calls + 1
					submitted[#submitted + 1] = code
					main.buttons[1]:Click() -- a callback cannot reenter the real button
					return true
				end,
			}
			UI.Refresh()
			local eb = assert(main.views.selfverification.input, "the real Views input box")
			eq(eb.template, "InputBoxTemplate")
			eb:SetText("CODE234"); eb:Fire("OnTextChanged", true)
			eb:Fire("OnEnterPressed")
			eq(calls, 0, "the real input's Enter handler only releases focus")
			main.buttons[2]:Click()
			eq(calls, 0, "the real Refresh button only reads status")
			eq(eb:GetText(), "CODE234", "refresh preserves the current deliberate input")
			main.buttons[1]:Click()
			eq(calls, 1); eq(submitted[1], "CODE234")
			eq(eb:GetText(), "", "the real input clears after submission")
			eb:Fire("OnTextChanged", false) -- the native SetText callback after the clearing redraw
			main.buttons[1]:Click(); eb:Fire("OnEnterPressed"); main.buttons[2]:Click()
			eq(calls, 1, "clear callbacks, a second click, Enter and refresh never duplicate the request")
			eq(UI.SelectTab("census"), true); eq(UI.SelectTab("selfverification"), true)
			eq(eb:GetText(), ""); eq(calls, 1, "reopening the page reads status without queueing")
			eb:SetText("CODE567"); eb:Fire("OnTextChanged", true)
			UI.Toggle(); UI.Toggle()
			eq(calls, 1, "closing and reopening the window never submits an unsent draft")
			eq(UI.SelectTab("census"), true); eq(UI.SelectTab("selfverification"), true)
			eq(eb:GetText(), "", "leaving the actual tab clears an unsent draft")
			main.buttons[1]:Click(); eq(calls, 1, "the cleared draft cannot be submitted")
			assert(statusReads > 1, "refresh and reopening reached the actual page builder")
		end)
		OlympusVerifyBridge242 = savedBridge
		ns.L.TAB_SELF_VERIFY, ns.L.SELF_VERIFY_SUBMIT = savedLabel, savedSubmit
		ns.Views.Unregister("selfverification")
		if not ok then error(err, 0) end
	end)
end)

test("personal verification: one deliberate submit, reentrant/double clicks and unknown callbacks never retry", function()
	With(function(V, s)
		local status = Envelope()
		OlympusVerifyBridge242 = { Status = function() return status end, QueueSelf = function()
			s.calls = s.calls + 1; eq(V.Submit(), false, "reentrant submit blocked")
			V.Edit("REENTER"); eq(V.Submit(), false)
			return true
		end }
		V.Edit("CODE234"); eq(V.Submit(), true)
		for _ = 1, 5 do eq(V.Submit(), false); Text(V) end
		eq(s.calls, 1)
		local lines = V.Build()
		for _, line in ipairs(lines) do if line.input then eq(line.input.text, "", "secret cleared before callback") end end
		V.Edit("CODE567"); OlympusVerifyBridge242.QueueSelf = function() s.calls = s.calls + 1 error("PRIVATE ERROR CODE567") end
		eq(V.Submit(), false); eq(V.Submit(), false); eq(s.calls, 2)
		local text = Text(V)
		assert(text:find("Submission unconfirmed", 1, true)); assert(not text:find("PRIVATE", 1, true))
		OlympusVerifyBridge242.QueueSelf = function() return false end
		V.Edit("CODE890"); eq(V.Submit(), false)
		assert(Text(V):find("No request confirmed", 1, true))
	end)
end)

test("personal verification: five delivery states, bounded redacted descriptors, no role or payment claims", function()
	With(function(V)
		local s = Envelope()
		for i, state in ipairs({ "pending", "delivered", "rejected", "unsupported_callback", "unknown" }) do
			s.requests[i] = { id = string.rep(tostring(i), 32), type = i == 5 and "donation" or "verify",
				requestedAt = 1900000000.5, deliveryState = state, code = "PRIVATE CODE", guid = "Player-PRIVATE", name = "PRIVATE NAME", body = "PRIVATE BODY" }
		end
		s.total = 5
		OlympusVerifyBridge242 = { QueueSelf = function() error("must not queue") end, Status = function() return s end }
		local text = Text(V)
		for _, word in ipairs({ "Pending delivery", "Delivery acknowledged", "Request rejected", "Delivery route unavailable", "Delivery unconfirmed",
			"Discord /verify-status", "/olv status", "not a transport ID", "Donation declaration" }) do assert(text:find(word, 1, true), word) end
		assert(not text:find("PRIVATE", 1, true))
		for i = 6, 25 do s.requests[i] = { id = string.rep("a", 32), type = "role", requestedAt = 1, deliveryState = "pending" } end
		s.total, s.truncated = 25, true
		local _, lines = Text(V)
		local n = 0
		for _, line in ipairs(lines) do if line.text:find("View ID:", 1, true) then n = n + 1 end end
		eq(n, 20); assert(Text(V):find("at most 20", 1, true))
	end)
end)

test("personal verification: incompatible envelope and hostile descriptor fields cannot imply success or leak", function()
	With(function(V)
		local s = Envelope()
		OlympusVerifyBridge242 = { QueueSelf = function() return true end, Status = function() return s end }
		for key, bad in pairs({ version = 1, deliveryOnly = false, membershipProof = true, roleAuthority = true, total = 0/0, truncated = "false", requests = false }) do
			local old = s[key]; s[key] = bad
			assert(Text(V):find("incompatible", 1, true), key)
			s[key] = old
		end
		s.requests = { { id = "PRIVATE ID", type = "verify", requestedAt = 1, deliveryState = "delivered" },
			{ id = string.rep("a", 32), type = "PRIVATE KIND", requestedAt = 1, deliveryState = "delivered" },
			{ id = string.rep("b", 32), type = "role", requestedAt = 1, deliveryState = "PRIVATE STATE" } }
		s.total = 3
		local text = Text(V)
		assert(not text:find("PRIVATE", 1, true)); assert(not text:find("Delivery acknowledged", 1, true))
		assert(text:find("Delivery unconfirmed", 1, true))
	end)
end)
