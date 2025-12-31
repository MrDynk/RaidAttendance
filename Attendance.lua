-- Utility: Debug log output to chat
local function DebugLog(msg)
	print("[Attendance Debug] " .. tostring(msg))
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
	return date("%Y-%m-%d %H:%M:%S")
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
	MessageSquadAttendance("______Starting Raid " .. GetRealZoneText() .. "______")
	MessageSquadAttendanceChunked(RaidData.StartRaidMembers, ", ", 200)
end


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
	local maxLength = 200  -- Safe limit under 255
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

local function MessageRaidEnd()
	MessageSquadAttendance("______Raid Ended. Attendees:______")

	if not RaidData then
		print("No raid data available.")
		return
	end

	local attendanceParts = {}
	local seen = {}

	for _, name in ipairs(RaidData.StartRaidMembers or {}) do
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(attendanceParts, name)
		end
	end

	for _, entry in ipairs(RaidData.LateArrivals or {}) do
		local name = (type(entry) == "table") and entry.name or entry
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(attendanceParts, name)
		end
	end

	RaidData.EndAttendance = table.concat(attendanceParts, ", ")
	MessageSquadAttendanceChunked(attendanceParts, ", ", 250)
end


-- Utility: Send Raid Start Data to squadattendance
local function RaiderLeaves(left,now)
	local leaverString
			for _, name in ipairs(left) do
				--print(name .. " left the raid at " .. now)
				table.insert(RaidData.EarlyDeparture, { name = name, time = now })
				leaverString = (leaverString and leaverString .. ", " or "") .. name
			end		
	MessageSquadAttendance(leaverString .. " Leaves @ " .. tostring(now) .. ".")
end
-- Utility: Send Raider Joins to squadattendance
local function RaiderJoins(joined,now)
	local joinerString
			for _, name in ipairs(joined) do
				table.insert(RaidData.LateArrivals, { name = name, time = now })
			joinerString = (joinerString and joinerString .. ", " or "") .. name
			end
	MessageSquadAttendance(joinerString .. " Joins @ " .. tostring(now) .. ".")
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
	RaidData.ChatIndex = GetChannelName("SquadAttendance")
	RaidData.StartRaidMembers= GetCurrentRaidMembers()
	RaidData.LateArrivals = {}
	RaidData.EarlyDeparture = {}
    RaidData.CurrentRaidMembers = GetCurrentRaidMembers()
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

-- Event handler for RAID_ROSTER_UPDATE
local attendanceFrame = CreateFrame("Frame")
attendanceFrame:RegisterAllEvents()
attendanceFrame:RegisterEvent("RAID_ROSTER_UPDATE")
attendanceFrame:SetScript("OnEvent", function()
	if event == "RAID_ROSTER_UPDATE" and isTrackingRaidChanges then
		RaidData = RaidData or {}
		RaidData.CurrentRaidMembers = RaidData.CurrentRaidMembers or {}
		RaidData.LateArrivals = RaidData.LateArrivals or {}
		RaidData.EarlyDeparture = RaidData.EarlyDeparture or {}

		local prevMembers = {}
		for _, name in ipairs(RaidData.CurrentRaidMembers) do
			prevMembers[TableCount(prevMembers) + 1] = name
		end
		local currentMembers = GetCurrentRaidMembers()

		local joined, left = FindDifference(prevMembers, currentMembers)
		local now = GetDateTimeString()

		if TableCount(joined) > 0 then
			RaiderJoins(joined,now)
		end
		if TableCount(left) > 0 then
			RaiderLeaves(left,now)
		end

		-- Update the saved raid members list
		RaidData.CurrentRaidMembers = currentMembers
	end
    
end)

-- End of Attendance.lua
