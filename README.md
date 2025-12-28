# Attendance Addon for Turtle WoW

The Attendance addon helps Turtle WoW players manage raid attendance and track changes in party or raid members.

## Available Slash Commands

- `/startraid`  
  Begins tracking raid attendance. Captures the current raid members in the global variable `RaidData` (field: `RaidData.StartRaidMembers`) then sends instance information and starting raid members to the SquadAttendance channel. Also sets the `isTrackingRaidChanges` boolean to `true`.

- `/continueraid`  
  Sets the `isTrackingRaidChanges` boolean to `true`, allowing the addon to continue tracking raid changes without resetting `RaidData`.

- `/stopraid`  
  Sets the `isTrackingRaidChanges` boolean to `false` and prints a csv friendly format to the SquadAttendance Channel.

- `/printraiddata`  
  Prints the current raid data to the chat window.


## Event Handling & Chat Messages

- **RAID_ROSTER_UPDATE**: When this event fires, if `isTrackingRaidChanges` is `true`, the addon compares GetRaidRosterInfo() to `RaidData.CurrentRaidMembers`.
  - If there are more members, it logs the new names to the Squadattendance channel and adds them to `RaidData.LateArrivals` with the date/time and player name.
  - If there are fewer members, it logs the names of those who left to the Squadattendance channel and adds them to `RaidData.EarlyDeparture` with the date/time and player name.
  - Updates `RaidData.CurrentRaidMembers` to reflect the current raid members.

### Chat Message Functionality, Bot & Discord Integration

Whenever a player joins late or leaves early, the addon automatically sends a message to the the Squadattendance channel. These messages are also parsed by Wagon's bot, which enables automated attendance tracking and integration with external tools, including Discord:

- **Late Arrivals:**
  - When a new player joins the raid after tracking has started, the message "Playername Joins." is printed to the Squadattendance channel. Wagon's bot listens for these messages and forwards the data to Discord.
- **Early Departures:**
  - When a player leaves the raid before tracking ends,the message "Playername Leaves." is printed to the Squadattendance channel. Wagon's bot listens for these messages and forwards the data to Discord.

## Saved Variables

- `RaidData` is a saved variable, loaded by the Turtle WoW client from a file named `Attendance.lua` in the `WTF/Account/<YourAccountName>/SavedVariables/` directory.

## File Structure

- `Attendance.lua`: Main logic for the addon.
- `Attendance.toc`: Addon metadata.

---
For more details, see the source code or contact the addon author.