-- Utility: Debug log output to chat
local function DebugLog(msg)
	print("[Attendance Debug] " .. tostring(msg))
end

-- Toggle these to control debug verbosity.
local DEBUG_GUILD_DETECTION = true

local function DebugGuild(msg)
	if DEBUG_GUILD_DETECTION then
		DebugLog(msg)
	end
end
-- Utility: Count elements in a table (for WoW Lua compatibility)
local function TableCount(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

-- Attendance Addon for Turtle WoW: Raid Attendance Tracker

-- Local state
local isTrackingRaidChanges = false

-- Utility: Get current date/time string
local function GetDateTimeString()
	return date("%m-%d %H:%M")
end

--
local function GetTimeString()
	return date("%H:%M")
end

local function NormalizePlayerName(name)
	if not name then
		return nil
	end
	name = tostring(name)
	-- Strip realm suffix (e.g., "Name-Realm") if present.
	name = string.gsub(name, "%-.*$", "")
	return name
end

local function FindRaidUnitByName(targetName)
	targetName = NormalizePlayerName(targetName)
	if not targetName or targetName == "" then
		return nil
	end
	local numRaidMembers = GetNumRaidMembers and GetNumRaidMembers() or 0
	for i = 1, numRaidMembers do
		local raidName = GetRaidRosterInfo(i)
		if NormalizePlayerName(raidName) == targetName then
			DebugGuild("FindRaidUnitByName: matched " .. tostring(targetName) .. " -> raid" .. tostring(i))
			return "raid" .. i
		end
	end
	DebugGuild("FindRaidUnitByName: no raid unit for " .. tostring(targetName))
	return nil
end

local function IsRaidUnitInMyGuild(unit)
	if not unit then
		return nil
	end
	-- Prefer guild-name comparison when available so we can detect the "not cached yet" case.
	local guildNameUnit = nil
	local guildNamePlayer = nil
	if GetGuildInfo then
		guildNameUnit = GetGuildInfo(unit)
		guildNamePlayer = GetGuildInfo("player")
		DebugGuild(
			"IsRaidUnitInMyGuild: GetGuildInfo(" .. tostring(unit) .. ")=" .. tostring(guildNameUnit)
				.. ", playerGuild=" .. tostring(guildNamePlayer)
		)
		-- If either side isn't available yet, treat as unknown so we can retry.
		if not guildNameUnit or not guildNamePlayer then
			return nil
		end
		return guildNameUnit == guildNamePlayer
	end

	if UnitIsInMyGuild then
		local result = UnitIsInMyGuild(unit) and true or false
		DebugGuild("IsRaidUnitInMyGuild: UnitIsInMyGuild(" .. tostring(unit) .. ") -> " .. tostring(result))
		return result
	end

	return nil
end

local lastGuildRosterRequestAt = 0
local function EnsureGuildRosterRequested()
	if not GuildRoster then
		DebugGuild("EnsureGuildRosterRequested: GuildRoster() not available")
		return
	end
	local now = (GetTime and GetTime()) or 0
	-- Throttle requests to avoid spamming.
	if now - lastGuildRosterRequestAt < 5 then
		DebugGuild("EnsureGuildRosterRequested: throttled (last=" .. tostring(lastGuildRosterRequestAt) .. ", now=" .. tostring(now) .. ")")
		return
	end
	lastGuildRosterRequestAt = now
	if SetGuildRosterShowOffline then
		SetGuildRosterShowOffline(true)
	end
	DebugGuild("EnsureGuildRosterRequested: calling GuildRoster()")
	GuildRoster()
end


-- Utility: Check if a player is in the guild
local function IsPlayerInGuild(player)
	player = NormalizePlayerName(player)
	local numGuildMembers = (GetNumGuildMembers and GetNumGuildMembers()) or 0
	local name, rank, rankIndex, level, class, zone, note, officernote, online, status

	if not player or player == "" then
		return false
	end
	if numGuildMembers <= 0 then
		-- Guild roster cache may not be ready yet (common right after login).
		DebugGuild("IsPlayerInGuild: roster not ready (GetNumGuildMembers=" .. tostring(numGuildMembers) .. ") for " .. tostring(player))
		EnsureGuildRosterRequested()
		return false
	end

	for i = 1, numGuildMembers, 1 do
		name, rank, rankIndex, level, class, zone, note, officernote, online, status = GetGuildRosterInfo(i)
		name = NormalizePlayerName(name)
		if name == player then
			DebugGuild("IsPlayerInGuild: matched via roster scan for " .. tostring(player))
			return true
		end
	end
	DebugGuild("IsPlayerInGuild: no match in roster scan for " .. tostring(player))

	return false
end

-- Pending joiners whose guild membership couldn't be resolved immediately.
local pendingLateArrivals = {}
local PENDING_LATE_ARRIVAL_MAX_AGE_SECONDS = 15

-- Utility: Get current raid members as a table of names
local function GetCurrentRaidMembers()
	local members = {}
	local numRaidMembers = GetNumRaidMembers and GetNumRaidMembers() or 0
	for i = 1, numRaidMembers do
		local name = GetRaidRosterInfo(i)
		if name then
			table.insert(members, name)
		end
	end
	return members
end

local function GetStartRaidMembers()
	local currentRaidMembers = GetCurrentRaidMembers()

	RaidData = RaidData or {}
	RaidData.StartRaidMembers = currentRaidMembers
	RaidData.StartRaidGuildMembers = {}
	RaidData.StartRaidPugs = {}

	for _, name in ipairs(currentRaidMembers or {}) do
		if name and name ~= "" then
			if IsPlayerInGuild(name) then
				table.insert(RaidData.StartRaidGuildMembers, name)
			else
				table.insert(RaidData.StartRaidPugs, name)
			end
		end
	end

	return currentRaidMembers
end


local function CheckIfLeaverIsRegisteredAsGuildAttendee(playerName)
	if not playerName or playerName == "" then
		return false
	end
	if not RaidData then
		return false
	end

	for _, name in ipairs(RaidData.StartRaidGuildMembers or {}) do
		if name == playerName then
			return true
		end
	end

	for _, entry in ipairs(RaidData.LateArrivalsGuildMembers or {}) do
		local name = (type(entry) == "table") and entry.name or entry
		if name == playerName then
			return true
		end
	end

	return false
end




-- Utility: Print table to chat
local function PrintTable(tbl, indent)
	indent = indent or ""
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			print(indent .. tostring(k) .. ":")
			PrintTable(v, indent .. "  ")
		else
			print(indent .. tostring(k) .. ": " .. tostring(v))
		end
	end
end

local function MessageSquadAttendance(msg)
	if RaidData and RaidData.ChatIndex then
		SendChatMessage(msg, "CHANNEL", nil, RaidData.ChatIndex)
	else
		print("Error: RaidData or ChatIndex not set.")
	end
end

local function MessageSquadAttendanceChunked(parts, delimiter, maxLength)
	delimiter = delimiter or ", "
	maxLength = maxLength or 200 -- Safe limit under 255
	local chunk = nil
	for _, part in ipairs(parts or {}) do
		local piece = tostring(part or "")
		if piece ~= "" then
			if not chunk then
				chunk = piece
			elseif string.len(chunk) + string.len(delimiter) + string.len(piece) <= maxLength then
				chunk = chunk .. delimiter .. piece
			else
				MessageSquadAttendance(chunk)
				chunk = piece
			end
		end
	end
	if chunk and chunk ~= "" then
		MessageSquadAttendance(chunk)
	end
end

-- Utility: Print RaidData to chat
local function PrintRaidData()
	if not RaidData then
		print("No raid data available.")
		return
	end
	print("---- RaidData ----")
	PrintTable(RaidData)
	print("------------------")
end

-- Utility: Send Raid Start Data to squadattendance
local function MessageRaidStart()
	if not RaidData then
		print("No raid data available.")
		return
	end
	---SendChatMessage(" https://tenor.com/view/naxx-gdkp-naxxgdkp-gif-27169327", "CHANNEL", nil, RaidData.ChatIndex)
	MessageSquadAttendance("# ______ Starting " .. RaidData.RaidZone .. " [" .. date("%m-%d %H:%M") .. "] ______")
	MessageSquadAttendance("> Starting Roster:")
	MessageSquadAttendanceChunked(RaidData.StartRaidGuildMembers, ", ", 200)
end

local function MessageRaidEnd()
	MessageSquadAttendance("> Raid Ending. Attendees:")


	if not RaidData then
		print("No raid data available.")
		return
	end

	local attendanceParts = {}
	local seen = {}

	for _, name in ipairs(RaidData.StartRaidGuildMembers or {}) do
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(attendanceParts, name)
		end
	end

	for _, entry in ipairs(RaidData.LateArrivalsGuildMembers or {}) do
		local name = (type(entry) == "table") and entry.name or entry
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(attendanceParts, name)
		end
	end

	RaidData.EndAttendance = table.concat(attendanceParts, ", ")
	MessageSquadAttendanceChunked(attendanceParts, ", ", 250)
	MessageSquadAttendance("# ______" .. RaidData.RaidZone .. " Finished [" .. date("%m-%d %H:%M") .. "] ______")
	---SendChatMessage("https://cdn.discordapp.com/emojis/1380636835713257622.webp?size=96&animated=true", "CHANNEL", nil, RaidData.ChatIndex)
end




-- Utility: Send Raid Start Data to squadattendance
local function RaiderLeaves(left, now)
	for _, name in ipairs(left) do
		if name and name ~= "" then
			local entry = { name = name, time = now }
			-- Keep legacy list for CSV/back-compat
			---table.insert(RaidData.EarlyDeparture, entry)

			if CheckIfLeaverIsRegisteredAsGuildAttendee(name) then
				table.insert(RaidData.EarlyDepartureGuildMembers, entry)
				MessageSquadAttendance(name .. " Leaves @ " .. tostring(now) .. ".")
			else
				table.insert(RaidData.EarlyDeparturePugs, entry)
			end
		end
	end

end
-- Utility: Send Raider Joins to squadattendance
local function RaiderJoins(joined, now)
	RaidData.LateArrivalsGuildMembers = RaidData.LateArrivalsGuildMembers or {}
	RaidData.LateArrivalsPugs = RaidData.LateArrivalsPugs or {}

	for _, rawName in ipairs(joined) do
		local name = NormalizePlayerName(rawName)
		if name and name ~= "" then
			-- Prefer unit-based guild detection; it doesn't depend on the guild roster cache.
			local unit = FindRaidUnitByName(name)
			local unitGuild = IsRaidUnitInMyGuild(unit)
			if unitGuild == true then
				DebugGuild("RaiderJoins: unit-based classified as GUILD: " .. tostring(name))
				table.insert(RaidData.LateArrivalsGuildMembers, { name = name, time = now })
				MessageSquadAttendance(name .. " Joins @ " .. tostring(now) .. ".")
			elseif unitGuild == false then
				-- Unit says "not in my guild". Double-check with roster scan; if the roster isn't ready yet,
				-- queue for retry to avoid misclassifying freshly-logged-in guild members.
				if IsPlayerInGuild(name) then
					DebugGuild("RaiderJoins: unit said PUG but roster-scan says GUILD: " .. tostring(name))
					table.insert(RaidData.LateArrivalsGuildMembers, { name = name, time = now })
					MessageSquadAttendance(name .. " Joins @ " .. tostring(now) .. ".")
				else
					local numGuildMembers = (GetNumGuildMembers and GetNumGuildMembers()) or 0
					if numGuildMembers <= 0 then
						DebugGuild("RaiderJoins: unit said PUG but guild roster not ready; queued for retry: " .. tostring(name))
						pendingLateArrivals[name] = pendingLateArrivals[name] or { time = now, firstSeen = (GetTime and GetTime()) or 0, lastDebugAt = 0 }
						DebugGuild("RaiderJoins: pendingLateArrivals=" .. tostring(TableCount(pendingLateArrivals)))
						EnsureGuildRosterRequested()
					else
						DebugGuild("RaiderJoins: unit-based classified as PUG: " .. tostring(name))
						table.insert(RaidData.LateArrivalsPugs, { name = name, time = now })
					end
				end
			else
				-- Fall back to guild roster scan; if roster cache isn't ready, queue for retry.
				if IsPlayerInGuild(name) then
					DebugGuild("RaiderJoins: roster-scan classified as GUILD: " .. tostring(name))
					table.insert(RaidData.LateArrivalsGuildMembers, { name = name, time = now })
					MessageSquadAttendance(name .. " Joins @ " .. tostring(now) .. ".")
				else
					DebugGuild("RaiderJoins: unknown right now; queued for retry: " .. tostring(name))
					pendingLateArrivals[name] = pendingLateArrivals[name] or { time = now, firstSeen = (GetTime and GetTime()) or 0, lastDebugAt = 0 }
					DebugGuild("RaiderJoins: pendingLateArrivals=" .. tostring(TableCount(pendingLateArrivals)))
					EnsureGuildRosterRequested()
				end
			end
		end
	end
end

local function TryResolvePendingLateArrivals()
	if not next(pendingLateArrivals) then
		return
	end

	RaidData.LateArrivalsGuildMembers = RaidData.LateArrivalsGuildMembers or {}
	RaidData.LateArrivalsPugs = RaidData.LateArrivalsPugs or {}

	EnsureGuildRosterRequested()
	local nowSeconds = (GetTime and GetTime()) or 0
	local numGuildMembers = (GetNumGuildMembers and GetNumGuildMembers()) or 0
	DebugGuild("TryResolvePendingLateArrivals: pending=" .. tostring(TableCount(pendingLateArrivals)) .. ", GetNumGuildMembers=" .. tostring(numGuildMembers))

	for name, info in pairs(pendingLateArrivals) do
		local unit = FindRaidUnitByName(name)
		local unitGuild = IsRaidUnitInMyGuild(unit)
		local isGuild = nil
		if unitGuild ~= nil then
			isGuild = unitGuild
		else
			isGuild = IsPlayerInGuild(name)
		end

		if isGuild == true then
			DebugGuild("TryResolvePendingLateArrivals: resolved as GUILD: " .. tostring(name) .. " (time=" .. tostring(info.time) .. ")")
			table.insert(RaidData.LateArrivalsGuildMembers, { name = name, time = info.time })
			MessageSquadAttendance(name .. " Joins @ " .. tostring(info.time) .. ".")
			pendingLateArrivals[name] = nil
		elseif isGuild == false then
			DebugGuild("TryResolvePendingLateArrivals: resolved as PUG: " .. tostring(name) .. " (time=" .. tostring(info.time) .. ")")
			table.insert(RaidData.LateArrivalsPugs, { name = name, time = info.time })
			pendingLateArrivals[name] = nil
		else
			-- Still unknown; after a short grace period, treat as pug so we don't drop the entry.
			local lastDebugAt = info.lastDebugAt or 0
			if (nowSeconds - lastDebugAt) >= 3 then
				info.lastDebugAt = nowSeconds
				DebugGuild(
					"TryResolvePendingLateArrivals: still unknown: "
						.. tostring(name)
						.. " unit=" .. tostring(unit)
						.. " unitGuild=" .. tostring(unitGuild)
						.. " GetNumGuildMembers=" .. tostring(numGuildMembers)
						.. " age=" .. tostring(nowSeconds - (info.firstSeen or 0))
				)
			end
			if (nowSeconds - (info.firstSeen or 0)) >= PENDING_LATE_ARRIVAL_MAX_AGE_SECONDS then
				DebugGuild("TryResolvePendingLateArrivals: timed out; defaulting to PUG: " .. tostring(name) .. " (time=" .. tostring(info.time) .. ")")
				table.insert(RaidData.LateArrivalsPugs, { name = name, time = info.time })
				pendingLateArrivals[name] = nil
			end
		end
	end
end

-- Utility: Find difference between two member lists
local function FindDifference(oldList, newList)
	local oldSet, newSet = {}, {}
	for _, name in ipairs(oldList) do oldSet[name] = true end
	for _, name in ipairs(newList) do newSet[name] = true end

	local joined, left = {}, {}
	for name in pairs(newSet) do
		if not oldSet[name] then table.insert(joined, name) end
	end
	for name in pairs(oldSet) do
		if not newSet[name] then table.insert(left, name) end
	end
	return joined, left
end

-- Slash command: /startraid
SLASH_STARTRAID1 = '/startraid'
SlashCmdList["STARTRAID"] = function()
	if GetChannelName("SquadAttendance") == 0 then
		print("Error: You must be in the 'SquadAttendance' channel to start raid tracking.")
		return
	end
	RaidData = {}
	RaidData.RaidZone = GetRealZoneText()
	RaidData.ChatIndex = GetChannelName("SquadAttendance")
	GetStartRaidMembers()
	RaidData.LateArrivalsGuildMembers = {}
	RaidData.LateArrivalsPugs = {}
	RaidData.EarlyDepartureGuildMembers = {}
	RaidData.EarlyDeparturePugs = {}
	RaidData.CurrentRaidMembers = RaidData.StartRaidMembers or GetCurrentRaidMembers()
	isTrackingRaidChanges = true
	MessageRaidStart()
end

-- Slash command: /continueraid
SLASH_CONTINUERAID1 = "/continueraid"
SlashCmdList["CONTINUERAID"] = function()
	isTrackingRaidChanges = true
	print("Raid tracking continued.")
end

-- Slash command: /stopraid
SLASH_STOPRAID1 = "/stopraid"
SlashCmdList["STOPRAID"] = function()
	isTrackingRaidChanges = false
	MessageRaidEnd()
end

-- Slash command: /printraiddata
SLASH_PRINTRAIDDATA1 = "/printraiddata"
SlashCmdList["PRINTRAIDDATA"] = function()
	PrintRaidData()
end

SLASH_TESTRAIDSTART1 = "/testraidstart"
SlashCmdList["TESTRAIDSTART"] = function()
	MessageRaidStart()
end

SLASH_ATTDEBUG1 = "/attdebug"
SlashCmdList["ATTDEBUG"] = function()
	DEBUG_GUILD_DETECTION = not DEBUG_GUILD_DETECTION
	print("[Attendance Debug] DEBUG_GUILD_DETECTION=" .. tostring(DEBUG_GUILD_DETECTION))
end

SLASH_ATTDEBUGPENDING1 = "/attdebugpending"
SlashCmdList["ATTDEBUGPENDING"] = function()
	print("[Attendance Debug] pendingLateArrivals=" .. tostring(TableCount(pendingLateArrivals)))
	TryResolvePendingLateArrivals()
end

-- Event handler for RAID_ROSTER_UPDATE
local attendanceFrame = CreateFrame("Frame")
attendanceFrame:RegisterEvent("RAID_ROSTER_UPDATE")
attendanceFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
attendanceFrame:SetScript("OnEvent", function(self, eventName, ...)
	-- Turtle/vanilla compatibility: some clients expose the event name via global `event`.
	local e = eventName or event
	if e == "RAID_ROSTER_UPDATE" then
		DebugGuild("Event: RAID_ROSTER_UPDATE (tracking=" .. tostring(isTrackingRaidChanges) .. ")")
	end
	if e == "RAID_ROSTER_UPDATE" and isTrackingRaidChanges then
		-- Compare previous and current raid members		
		local prevMembers = {}
		for _, name in ipairs(RaidData.CurrentRaidMembers) do
			prevMembers[TableCount(prevMembers) + 1] = name
		end
		local currentMembers = GetCurrentRaidMembers()

		local joined, left = FindDifference(prevMembers, currentMembers)
		local now = GetTimeString()
		DebugGuild("RAID_ROSTER_UPDATE diff: joined=" .. tostring(TableCount(joined)) .. ", left=" .. tostring(TableCount(left)) .. ", now=" .. tostring(now))

		if TableCount(joined) > 0 then
			RaiderJoins(joined, now)
		end
		if TableCount(left) > 0 then
			RaiderLeaves(left, now)
		end

		-- Update the saved raid members list
		RaidData.CurrentRaidMembers = currentMembers
	elseif e == "GUILD_ROSTER_UPDATE" and isTrackingRaidChanges then
		DebugGuild("Event: GUILD_ROSTER_UPDATE (pending=" .. tostring(TableCount(pendingLateArrivals)) .. ")")
		if next(pendingLateArrivals) then
			TryResolvePendingLateArrivals()
		end
	end
end)

local pendingLateArrivalsUpdateAccum = 0
attendanceFrame:SetScript("OnUpdate", function(self, elapsed)
	if not isTrackingRaidChanges then
		return
	end
	if not next(pendingLateArrivals) then
		pendingLateArrivalsUpdateAccum = 0
		return
	end
	-- Avoid per-frame scans; this only needs to run occasionally.
	pendingLateArrivalsUpdateAccum = (pendingLateArrivalsUpdateAccum or 0) + (elapsed or 0)
	if pendingLateArrivalsUpdateAccum >= 0.5 then
		pendingLateArrivalsUpdateAccum = 0
		TryResolvePendingLateArrivals()
	end
end)


local function table_length(t)
	local count = 0
	if t then
		for _ in pairs(t) do count = count + 1 end
	end
	return count
end

local function BuildRaidCSV()
	local csv = "Raid Start, Late Arrival, , Early Departure,;"
	local start = RaidData and RaidData.StartRaidMembers or {}
	local late = RaidData and RaidData.LateArrivals or {}
	local early = RaidData and RaidData.EarlyDeparture or {}
	local maxLen = math.max(table_length(start), table_length(late), table_length(early))
	for i = 1, maxLen do
		local startName = start[i] or ""
		local lateName, lateTime = "", ""
		if late[i] then
			lateName = late[i].name or ""
			lateTime = late[i].time or ""
		end
		local earlyName, earlyTime = "", ""
		if early[i] then
			earlyName = early[i].name or ""
			earlyTime = early[i].time or ""
		end
		csv = csv .. string.format("%s,%s,%s,%s,%s;", startName, lateName, lateTime, earlyName, earlyTime)
	end
	return csv
end

-- Utility: Send Raid Start Data to squadattendance
local function MessageRaidEndCSV()
	RaidData.FinalCsv = BuildRaidCSV()
	MessageSquadAttendance("______Raid Ended. Sending CSV Friendly Data(semicolon denotes new line)______")

	-- Split the CSV into chunks to avoid chat message length limits
	local csv = RaidData.FinalCsv
	local maxLength = 200 -- Safe limit under 255
	local start = 1
	while start <= string.len(csv) do
		local endPos = start + maxLength - 1
		if endPos > string.len(csv) then endPos = string.len(csv) end
		-- Ensure we don't cut in the middle of a row (split on semicolon if possible)
		local lastSemicolon = string.find(string.sub(csv, start, endPos), ";[^;]*$")
		if lastSemicolon then
			endPos = start + lastSemicolon - 1
		end
		local chunk = string.sub(csv, start, endPos)
		MessageSquadAttendance(chunk)
		start = endPos + 1
	end
end

-- End of Attendance.lua
