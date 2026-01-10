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

-- Join/leave logic is now in RaidChanges.lua
local RaidChanges = AttendanceRaidChanges

-- Keep a simple roster-scan helper here for /startraid classification.
local function NormalizePlayerName(name)
	if not name then
		return nil
	end
	name = tostring(name)
	name = string.gsub(name, "%-.*$", "")
	return name
end

local function IsPlayerInGuild_RosterScanOnly(player)
	player = NormalizePlayerName(player)
	local numGuildMembers = (GetNumGuildMembers and GetNumGuildMembers()) or 0
	local name
	if not player or player == "" or numGuildMembers <= 0 then
		return false
	end
	for i = 1, numGuildMembers do
		name = GetGuildRosterInfo(i)
		name = NormalizePlayerName(name)
		if name == player then
			return true
		end
	end
	return false
end

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
			if IsPlayerInGuild_RosterScanOnly(name) then
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

local function MessageSquadAttendanceChunked(parts, delimiter, maxLength, addspoilers)
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
				if addspoilers then
					chunk = "||" .. chunk .. "||"
				end
				MessageSquadAttendance(chunk)
				chunk = piece
			end
		end
	end
	if chunk and chunk ~= "" then
		if addspoilers then
			chunk = "||" .. chunk .. "||"
		end
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
	MessageSquadAttendanceChunked(RaidData.StartRaidGuildMembers, ", ", 200, false)
	MessageSquadAttendance("||> Starting PUGs:||")
	MessageSquadAttendanceChunked(RaidData.StartRaidPugs, ", ", 200, true)
end

local function MessageRaidEnd()
	MessageSquadAttendance("> Raid Ending.")
	MessageSquadAttendance("> Guild Attendees:")

	if not RaidData then
		print("No raid data available.")
		return
	end

	local attendancePartsGuild = {}
	local seen = {}

	for _, name in ipairs(RaidData.StartRaidGuildMembers or {}) do
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(attendancePartsGuild, name)
		end
	end

	for _, entry in ipairs(RaidData.LateArrivalsGuildMembers or {}) do
		local name = (type(entry) == "table") and entry.name or entry
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(attendancePartsGuild, name)
		end
	end
	
	RaidData.EndAttendanceGuildMembers = table.concat(attendancePartsGuild, ", ")
	MessageSquadAttendanceChunked(attendancePartsGuild, ", ", 250,false)
	

	MessageSquadAttendance("||> Pug Attendees:||")
	local attendancePartsPugs = {}
	for _, name in ipairs(RaidData.StartRaidPugs or {}) do
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(attendancePartsPugs, name)
		end
	end
	for _, entry in ipairs(RaidData.LateArrivalsPugs or {}) do
		local name = (type(entry) == "table") and entry.name or entry
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(attendancePartsPugs, name)
		end
	end
	RaidData.EndAttendancePugs = table.concat(attendancePartsPugs, ", ")
	MessageSquadAttendanceChunked(attendancePartsPugs, ", ", 250,true)
	MessageSquadAttendance("# ______" .. RaidData.RaidZone .. " Finished [" .. date("%m-%d %H:%M") .. "] ______")

	---SendChatMessage("https://cdn.discordapp.com/emojis/1380636835713257622.webp?size=96&animated=true", "CHANNEL", nil, RaidData.ChatIndex)
end




-- Utility: Send Raid Start Data to squadattendance
local function RaiderLeaves(left, now)
	if RaidChanges and RaidChanges.RaiderLeaves then
		RaidChanges.RaiderLeaves(left, now)
	end

end
-- Utility: Send Raider Joins to squadattendance
local function RaiderJoins(joined, now)
	if RaidChanges and RaidChanges.RaiderJoins then
		RaidChanges.RaiderJoins(joined, now)
	end
end

-- Utility: Find difference between two member lists
local function FindDifference(oldList, newList)
	if RaidChanges and RaidChanges.FindDifference then
		return RaidChanges.FindDifference(oldList, newList)
	end
	-- Fallback local implementation
	local oldSet, newSet = {}, {}
	for _, name in ipairs(oldList or {}) do oldSet[name] = true end
	for _, name in ipairs(newList or {}) do newSet[name] = true end
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
	local pending = (RaidChanges and RaidChanges.GetPendingCount and RaidChanges.GetPendingCount()) or 0
	print("[Attendance Debug] pendingLateArrivals=" .. tostring(pending))
	if RaidChanges and RaidChanges.TryResolvePendingLateArrivals then
		RaidChanges.TryResolvePendingLateArrivals()
	end
end

-- Event handler for RAID_ROSTER_UPDATE
local attendanceFrame = CreateFrame("Frame")
attendanceFrame:RegisterEvent("RAID_ROSTER_UPDATE")
attendanceFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
attendanceFrame:SetScript("OnEvent", function(self, eventName, ...)
	-- Turtle/vanilla compatibility: some clients expose the event name via global `event`.
	local e = eventName or event
	if RaidChanges and RaidChanges.Init then
		RaidChanges.Init({
			DebugGuild = DebugGuild,
			MessageSquadAttendance = MessageSquadAttendance,
			CheckIfLeaverIsRegisteredAsGuildAttendee = CheckIfLeaverIsRegisteredAsGuildAttendee,
		})
	end
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
		local pending = (RaidChanges and RaidChanges.GetPendingCount and RaidChanges.GetPendingCount()) or 0
		DebugGuild("Event: GUILD_ROSTER_UPDATE (pending=" .. tostring(pending) .. ")")
		if pending > 0 and RaidChanges and RaidChanges.TryResolvePendingLateArrivals then
			RaidChanges.TryResolvePendingLateArrivals()
		end
	end
end)

attendanceFrame:SetScript("OnUpdate", function(self, elapsed)
	if RaidChanges and RaidChanges.OnUpdate then
		RaidChanges.OnUpdate(elapsed, isTrackingRaidChanges)
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
