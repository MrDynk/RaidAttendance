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
	RaidData = {}
	RaidData.StartRaidMembers= GetCurrentRaidMembers()
	RaidData.LateArrivals = {}
	RaidData.EarlyDeparture = {}
    RaidData.CurrentRaidMembers = GetCurrentRaidMembers()
	isTrackingRaidChanges = true
	print("Raid tracking started.")
	PrintRaidData()
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
	print("Raid tracking stopped.")
end

-- Slash command: /printraiddata
SLASH_PRINTRAIDDATA1 = "/printraiddata"
SlashCmdList["PRINTRAIDDATA"] = function()
	PrintRaidData()
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
			for _, name in ipairs(joined) do
				print(name .. " joined the raid at " .. now)
				table.insert(RaidData.LateArrivals, { name = name, time = now })
			end
		end
		if TableCount(left) > 0 then
			for _, name in ipairs(left) do
				print(name .. " left the raid at " .. now)
				table.insert(RaidData.EarlyDeparture, { name = name, time = now })
			end
		end

		-- Update the saved raid members list
		RaidData.CurrentRaidMembers = currentMembers
	end
    
end)

-- End of Attendance.lua
