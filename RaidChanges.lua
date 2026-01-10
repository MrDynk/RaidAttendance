-- RaidChanges.lua
-- Join/leave + guild classification logic extracted from Attendance.lua

AttendanceRaidChanges = AttendanceRaidChanges or {}

-- Set by Init()
local DebugGuild = function(_) end
local MessageSquadAttendance = function(_) end
local CheckIfLeaverIsRegisteredAsGuildAttendee = function(_) return false end

local function TableCount(tbl)
	local count = 0
	for _ in pairs(tbl or {}) do
		count = count + 1
	end
	return count
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

function AttendanceRaidChanges.Init(opts)
	opts = opts or {}
	DebugGuild = opts.DebugGuild or DebugGuild
	MessageSquadAttendance = opts.MessageSquadAttendance or MessageSquadAttendance
	CheckIfLeaverIsRegisteredAsGuildAttendee = opts.CheckIfLeaverIsRegisteredAsGuildAttendee or CheckIfLeaverIsRegisteredAsGuildAttendee
end

function AttendanceRaidChanges.GetPendingCount()
	return TableCount(pendingLateArrivals)
end

function AttendanceRaidChanges.RaiderLeaves(left, now)
	for _, name in ipairs(left or {}) do
		name = NormalizePlayerName(name)
		if name and name ~= "" then
			local entry = { name = name, time = now }
			if CheckIfLeaverIsRegisteredAsGuildAttendee(name) then
				table.insert(RaidData.EarlyDepartureGuildMembers, entry)
				MessageSquadAttendance(name .. " Leaves @ " .. tostring(now) .. ".")
			else
				-- WoW chat treats '|' as an escape introducer; use '||' to produce a literal pipe.
				MessageSquadAttendance("||" .. name .. " Leaves @ " .. tostring(now) .. ". (PUG)||")
				table.insert(RaidData.EarlyDeparturePugs, entry)
			end
		end
	end
end

function AttendanceRaidChanges.RaiderJoins(joined, now)
	RaidData.LateArrivalsGuildMembers = RaidData.LateArrivalsGuildMembers or {}
	RaidData.LateArrivalsPugs = RaidData.LateArrivalsPugs or {}

	for _, rawName in ipairs(joined or {}) do
		local name = NormalizePlayerName(rawName)
		if name and name ~= "" then
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
						MessageSquadAttendance("||" .. name .. " Joins @ " .. tostring(now) .. ". (PUG)||")
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

function AttendanceRaidChanges.TryResolvePendingLateArrivals()
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
			MessageSquadAttendance("||" .. name .. " Joins @ " .. tostring(info.time) .. ". (PUG)||")
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

function AttendanceRaidChanges.FindDifference(oldList, newList)
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

local pendingLateArrivalsUpdateAccum = 0
function AttendanceRaidChanges.OnUpdate(elapsed, isTrackingRaidChanges)
	if not isTrackingRaidChanges then
		return
	end
	if not next(pendingLateArrivals) then
		pendingLateArrivalsUpdateAccum = 0
		return
	end
	pendingLateArrivalsUpdateAccum = (pendingLateArrivalsUpdateAccum or 0) + (elapsed or 0)
	if pendingLateArrivalsUpdateAccum >= 0.5 then
		pendingLateArrivalsUpdateAccum = 0
		AttendanceRaidChanges.TryResolvePendingLateArrivals()
	end
end
