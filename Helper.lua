-- local f = CreateFrame('FRAME')
-- f:RegisterAllEvents()
-- f:SetScript('OnEvent', function(self, event)
--     DEFAULT_CHAT_FRAME:AddMessage("Self parameter: " .. tostring(self))
--     DEFAULT_CHAT_FRAME:AddMessage("Event triggered: " .. tostring(event))
--     if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
--         if IsInRaid() then
--             DEFAULT_CHAT_FRAME:AddMessage("Checking raid members...")
--             for i = 1, MAX_RAID_MEMBERS do
--                 local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
--                 DEFAULT_CHAT_FRAME:AddMessage("Raid member index " .. i .. ": " .. tostring(name) .. ", online: " .. tostring(online))
--                 if name and online then
--                     DEFAULT_CHAT_FRAME:AddMessage("New raid member: " .. name)
--                 end
--             end
--         elseif IsInGroup() then
--             DEFAULT_CHAT_FRAME:AddMessage("Checking party members...")
--             for i = 1, MAX_PARTY_MEMBERS do
--                 local name = UnitName("party" .. i)
--                 DEFAULT_CHAT_FRAME:AddMessage("Party member index " .. i .. ": " .. tostring(name))
--                 if name then
--                     DEFAULT_CHAT_FRAME:AddMessage("New party member: " .. name)
--                 end
--             end
--         end
--     end
-- end)

-- Register the '/start' command
SLASH_START1 = '/start'
SlashCmdList["START"] = function()
    DEFAULT_CHAT_FRAME:AddMessage("Raid attendance tracking started.")

    local raidMembers = {}

    local function updateRaidMembers()
        local currentMembers = {}
        local raidSize = GetNumRaidMembers()

        for i = 1, raidSize do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name then
                currentMembers[name] = online
                if not raidMembers[name] then
                    DEFAULT_CHAT_FRAME:AddMessage("Member joined: " .. name)
                end
            end
        end

        for name in pairs(raidMembers) do
            if not currentMembers[name] then
                DEFAULT_CHAT_FRAME:AddMessage("Member left: " .. name)
            end
        end

        raidMembers = currentMembers
    end

    local f = CreateFrame('FRAME')
    f:RegisterEvent("RAID_ROSTER_UPDATE")
    f:SetScript('OnEvent', function(self, event)
        if event == "RAID_ROSTER_UPDATE" then
            updateRaidMembers()
        end
    end)
end