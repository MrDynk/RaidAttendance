function splitStringToTable() {
  var sheet = SpreadsheetApp.getActiveSheet();
  var cell = sheet.getRange(1, 1); // A1
  var raw = String(cell.getDisplayValue() || "");

  if (!raw.trim()) return;

  // Normalize newlines
  var text = raw.replace(/\r\n/g, "\n").replace(/\r/g, "\n");

  // Remove Discord/WoW export noise (line-based)
  text = text.replace(/^\[\d{1,2}:\d{2}\s*(AM|PM)\]\s*$/gmi, "");
  text = text.replace(/^\s*APP\s*$/gmi, "");
  text = text.replace(/^\s*WoW Chat:\s*\[[^\]]+\]:\s*/gmi, "");
  text = text.replace(/^\s*_{3,}Raid Ended\..*_{3,}\s*$/gmi, "");

  // Drop empty lines created by stripping
  text = text.replace(/^\s*$/gm, "");

  // Join remaining lines (each chat message chunk becomes part of one CSV)
  text = text.split("\n").join("");

  // Split into rows and columns
  var rows = text
    .split(";")
    .map(function (r) { return r.trim(); })
    .filter(function (r) { return r !== ""; });

  // Optional: remove duplicate header rows if they appear multiple times
  var headerString = null;
  var parsed = [];
  for (var i = 0; i < rows.length; i++) {
    var cols = rows[i].split(",").map(function (c) { return c.trim(); });
    var rowString = cols.join(",");

    if (!headerString && cols[0] === "Raid Start") headerString = rowString;
    if (headerString && rowString === headerString && parsed.length > 0) continue;

    parsed.push(cols);
  }

  if (parsed.length === 0) return;

  // Pad to rectangle for setValues()
  var maxCols = 0;
  for (var r = 0; r < parsed.length; r++) {
    if (parsed[r].length > maxCols) maxCols = parsed[r].length;
  }
  for (var r2 = 0; r2 < parsed.length; r2++) {
    while (parsed[r2].length < maxCols) parsed[r2].push("");
  }

  // Write back starting at A1 (clears A1 content first)
  cell.clearContent();
  sheet.getRange(1, 1, parsed.length, maxCols).setValues(parsed);
}