local ADDON, ns = ...
local L = ns.L

-- Optional consumer of Verify's existing queue. No saved state, transport or role authority.
-- The bridge is installed at PLAYER_LOGIN: look it up each time the page or action runs.
local V = {}
ns.PersonalVerification = V
local draft, attempted, busy, notice = "", false, false, nil
local KINDS = { verify = "Verification", role = "Role request", guild = "Guild request", donation = "Donation declaration" }
local STATES = {
	pending = { "Pending delivery", "Wait for delivery; inspect /olv status. Do not submit the same request again." },
	delivered = { "Delivery acknowledged", "Delivery only. Check Discord /verify-status for current verification and access." },
	rejected = { "Request rejected", "Check Discord /verify-status and ask staff to review the original request before submitting again." },
	unsupported_callback = { "Delivery route unavailable", "Keep the original request. Ask staff to check the supported delivery route; do not resubmit." },
	unknown = { "Delivery unconfirmed", "Keep the original request. Check /olv status or ask staff; do not resubmit an unconfirmed request." },
}

local function Bridge()
	local bridge = rawget(_G, "OlympusVerifyBridge242")
	if type(bridge) == "table" and type(bridge.QueueSelf) == "function" and type(bridge.Status) == "function" then return bridge end
end

local function Refresh()
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function V.Edit(text)
	if busy then return end
	text = type(text) == "string" and text:sub(1, 64) or ""
	if text ~= draft then draft, attempted = text, false end
end

function V.CanSubmit()
	return not busy and not attempted and draft:match("%S") ~= nil and Bridge() ~= nil
end

-- Called only by the deliberate Submit button. Clear the secret before crossing the bridge;
-- reentrant clicks, Enter/click pairs and page refreshes cannot submit it a second time.
function V.Submit()
	if not V.CanSubmit() then return false end
	local bridge, code = Bridge(), draft
	busy, attempted, draft = true, true, ""
	local ok, accepted = pcall(bridge.QueueSelf, code) -- dot-call contract; boolean, not a request ID
	busy = false
	if ok and accepted == true then
		notice = "Local request exists. Delivery and Discord access are not confirmed."
	elseif ok and accepted == false then
		notice = "No request confirmed. Check /olv status before deciding whether to try again."
	else
		notice = "Submission unconfirmed. Check /olv status or ask staff; do not resubmit."
	end
	Refresh()
	return ok and accepted == true
end

local function Whole(n)
	return type(n) == "number" and n == n and n >= 0 and n <= 253402300799 and n == math.floor(n)
end

local function Timestamp(n)
	return type(n) == "number" and n == n and n > 0 and n <= 253402300799
end

local function Status(bridge)
	local ok, status = pcall(bridge.Status) -- dot call; never queues or retries
	if not ok or type(status) ~= "table" or status.version ~= 243 or status.deliveryOnly ~= true
		or status.membershipProof ~= false or status.roleAuthority ~= false or not Whole(status.total)
		or type(status.truncated) ~= "boolean" or type(status.requests) ~= "table" then return nil end
	return status
end

function V.Build()
	local lines = {
		{ text = "Discord verification", header = true },
		{ text = "Current access: Discord /verify-status" },
		{ text = "Local delivery details: /olv status" },
	}
	local bridge = Bridge()
	if not bridge then
		lines[#lines + 1] = { text = "Optional Verify bridge unavailable" }
		return lines, L.TAB_SELF_VERIFY, "Install or enable Olympus Verify, then open this page again. Guild approval remains /oly verify."
	end
	if notice then lines[#lines + 1] = { text = notice, tooltip = function(tt) tt:AddLine(notice, 1, 1, 1, true) end } end
	lines[#lines + 1] = { text = "Your Discord verification code", input = { text = draft, onChange = V.Edit } }
	lines[#lines + 1] = { text = "Submit once; refresh reads delivery only." }
	local status = Status(bridge)
	if not status then
		lines[#lines + 1] = { text = "Delivery status unavailable or incompatible" }
	else
		local visible = 0
		for i = 1, math.min(20, #status.requests) do
			local request = status.requests[i]
			if type(request) == "table" and type(request.id) == "string" and #request.id == 32
				and request.id:match("^[a-f0-9]+$") and KINDS[request.type] and Timestamp(request.requestedAt) then
				local state = STATES[request.deliveryState] or STATES.unknown
				visible = visible + 1
				lines[#lines + 1] = { text = KINDS[request.type] .. ": " .. state[1],
					tooltip = function(tt) tt:AddLine(state[2], 1, 1, 1, true) end }
				lines[#lines + 1] = { text = "View ID: " .. request.id,
					tooltip = function(tt) tt:AddLine("Opaque display reference only. It is not a transport ID or a match to the code just submitted.", 1, 1, 1, true) end }
			end
		end
		if visible == 0 then lines[#lines + 1] = { text = "No readable local delivery records" } end
		if status.truncated or status.total > visible or #status.requests > 20 then
			lines[#lines + 1] = { text = "Showing at most 20 records; use /olv status." }
		end
	end
	return lines, L.TAB_SELF_VERIFY, "Delivery is not verification or a role. Check Discord /verify-status. Guild approval remains /oly verify. No ordinary-member Watcher or forced reload is required."
end

if ns.UI and ns.UI.AddTab then
	ns.UI.AddTab({ key = "selfverification", label = "TAB_SELF_VERIFY", after = "chat",
		icon = "Interface\\Icons\\INV_Letter_15", build = V.Build,
		buttons = {
			{ "SELF_VERIFY_SUBMIT", V.Submit, enabled = function() return not busy and Bridge() ~= nil end },
			{ "REFRESH", Refresh },
		},
		onLeave = function() draft = "" end,
	})
end
