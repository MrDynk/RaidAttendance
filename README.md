# Attendance Addon for Turtle WoW

The Attendance addon helps Turtle WoW players manage raid attendance and track changes in party or raid members.

## Available Slash Commands

- `/startraid`  
  Begins tracking raid attendance. Captures the current raid members in the global variable `RaidData` (field: `RaidData.RaidMembers`) and prints `RaidData` to chat. Also sets the `isTrackingRaidChanges` boolean to `true`.

- `/continueraid`  
  Sets the `isTrackingRaidChanges` boolean to `true`, allowing the addon to continue tracking raid changes without resetting `RaidData`.

- `/stopraid`  
  Sets the `isTrackingRaidChanges` boolean to `false`.

- `/printraiddata`  
  Prints the current raid data to the chat window.

## Event Handling

- **RAID_ROSTER_UPDATE**: When this event fires, if `isTrackingRaidChanges` is `true`, the addon compares the current raid members to `RaidData.RaidMembers`.
  - If there are more members, it logs the new names to chat and adds them to `RaidData.LateArrivals` with the date/time and player name.
  - If there are fewer members, it logs the names of those who left to chat and adds them to `RaidData.EarlyDeparture` with the date/time and player name.
  - Updates `RaidData.RaidMembers` to reflect the current raid members.

## Saved Variables

- `RaidData` is a saved variable, loaded by the Turtle WoW client from a file named `Attendance.lua` in the `WTF/Account/<YourAccountName>/SavedVariables/` directory.

## File Structure

- `Attendance.lua`: Main logic for the addon.
- `Attendance.toc`: Addon metadata.
- `wow-api-type-definitions-main/`: API definitions for Turtle WoW (not included in this repo).

---
For more details, see the source code or contact the addon author.