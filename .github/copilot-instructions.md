# Copilot Instructions for Attendance Addon


## Purpose
The Attendance addon is designed for Turtle WoW to assist players in managing raid attendance and tracking changes in party or raid members.

## Key Details
- **Slash Commands**:
  - `/startraid`: Begins tracking raid attendance. captures the current raid members in the global variable RaidData in a field which is a table called "RaidData.RaidMembers" and  prints RaidData to chat. it also flips the "isTrackingRaidChanges" boolean to true.
  - `/continueraid`: flips the "isTrackingRaidChanges" boolean to true, allowing the addon to continue tracking raid changes without resetting "RaidData".
  - `/stopraid`: flips the "isTrackingRaidChanges" boolean to false.
  - `/printraiddata`: Prints the current raid data to the chat window. 

- **Event Handling**:
  - `RaidMemberUpdate`: an event listener for the "RAID_ROSTER_UPDATE" event. when the event fires, first it will check the "isTrackingRaidChanges" boolean, then it compares the current raid members to the RaidData.RaidMembers table. If there are more members, it will isolate their names, log them to the chat window, and populate a new field on the RaidData variable called "RaidData.LateArrivals" with the date time and the players name. If there are less members than the saved "RaidData.RaidMembers" table, it will isolate the names of the players who left, log them to the chat window, and populate a new global field on the RaidData variable called "RaidData.EarlyDeparture" with the date time and the players name. Finally, it updates the "RaidData.RaidMembers" table to reflect the current raid members. RaidData is a saved variable. saved variables are loaded by the twow client from file names matching the addon, like "Attendance.lua"from the "WTF/Account/<YourAccountName>/SavedVariables/" directory.
 

- **File Structure**:
  - `Attendance.lua`: Contains the main logic for the addon.
  - `Attendance.toc`: Metadata file listing the addon's components.
  - `wow-api-type-definitions-main`: Contains API definitions for Turtle WoW, including available events and functions. any functions or events used in Attendance.lua must be present here to ensure compatibility with Turtle WoW's Lua environment.

## LLM Reference Notes
- When answering questions about the Attendance addon, reference the `wow-api-type-definitions-main` folder for API details.
- Emphasize the addon's purpose: tracking raid attendance and logging changes.

---