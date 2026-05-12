/**
 * Workout Workbook Generator for Google Sheets
 *


function buildWorkoutWorkbookTemplate() {
  const ss = SpreadsheetApp.getActive();

  const targetSheets = getWorkoutTemplateSheetNames_();

  const existing = targetSheets.filter(name => ss.getSheetByName(name));
  if (existing.length > 0) {
    throw new Error(
      "Aborting to avoid overwriting existing sheets. Existing target tabs: " +
      existing.join(", ") +
      ". Run this in a blank Google Sheet, or rename/delete these generated tabs first."
    );
  }

  const cfg = {
    weeks: 4,
    days: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
    cycleId: "C1",

    // Final_Output geometry
    // Week block columns:
    // Set, Activity, Target, Work Done, Notes, Rest, URL, Instructions, spacer
    weekWidth: 9,
    weekGap: 2,
    startColWeek1: 2, // column B
    blockDayHeight: 33,
    blankRowsBetweenDays: 2,

    colors: {
      header: "#111827",
      subheader: "#1F2937",
      white: "#FFFFFF",
      green: "#16A34A",
      amber: "#F59E0B",
      gray: "#4B5563",
      lightGreen: "#DCFCE7",
      lightAmber: "#FEF3C7",
      lightGray: "#F1F5F9",
      lightOrange: "#FFF7ED",
      border: "#D1D5DB",
      link: "#2563EB",
    },
  };

  createReadme_(ss, cfg);
  createSettings_(ss, cfg);
  createSetup_(ss, cfg);
  createDayOverrides_(ss, cfg);
  createSessions_(ss, cfg);
  createValidationOptions_(ss, cfg);
  createActivityLibrary_(ss, cfg);
  createUrls_(ss, cfg);
  createGarminSheets_(ss, cfg);

  const finalOutputInfo = createFinalOutput_(ss, cfg);

  createDayBlockMap_(ss, cfg, finalOutputInfo);
  createGuidanceSheets_(ss, cfg);

  reorderSheets_(ss, targetSheets);

  SpreadsheetApp.getActive().toast("Workout workbook template created.");
}

/**
 * Sheet names created by this generator.
 */
function getWorkoutTemplateSheetNames_() {
  return [
    "README",
    "Final_Output",
    "Day_Block_Map",
    "Settings",
    "Setup",
    "Day_Overrides",
    "Sessions",
    "Validation_Options",
    "Activity_Library",
    "URLs",
    "Cycle_Log_Columns",
    "Conditional_Formatting",
    "Log_Display",
    "Garmin_Workout_Constructor",
    "Garmin_Export",
  ];
}

/**
 * Ensures a sheet has enough rows and columns before writing/merging out-of-bounds ranges.
 * This fixes: "Exception: Those columns are out of bounds."
 */
function ensureSheetSize_(sheet, minRows, minCols) {
  const currentRows = sheet.getMaxRows();
  const currentCols = sheet.getMaxColumns();

  if (currentRows < minRows) {
    sheet.insertRowsAfter(currentRows, minRows - currentRows);
  }

  if (currentCols < minCols) {
    sheet.insertColumnsAfter(currentCols, minCols - currentCols);
  }
}

/**
 * Safely merges across columns without crossing frozen/non-frozen boundaries.
 *
 * Google Sheets does not allow merging a range that crosses the boundary between
 * frozen and non-frozen columns. This helper shifts the merge start to the first
 * non-frozen column if needed.
 */
function mergeAcrossNonFrozenColumns_(sheet, row, startCol, endCol) {
  const frozenCols = sheet.getFrozenColumns();

  let safeStartCol = startCol;

  if (startCol <= frozenCols && endCol > frozenCols) {
    safeStartCol = frozenCols + 1;
  }

  if (safeStartCol > endCol) {
    return sheet.getRange(row, startCol);
  }

  const width = endCol - safeStartCol + 1;
  const range = sheet.getRange(row, safeStartCol, 1, width);
  range.merge();

  return range;
}

/**
 *  Common helpers 
 */

function styleHeaderRow_(sheet, row, startCol, numCols, fill) {
  const range = sheet.getRange(row, startCol, 1, numCols);
  range
    .setBackground(fill)
    .setFontColor("#FFFFFF")
    .setFontWeight("bold")
    .setHorizontalAlignment("center")
    .setVerticalAlignment("middle")
    .setWrap(true);
}

function setWidths_(sheet, widths) {
  Object.keys(widths).forEach(col => {
    sheet.setColumnWidth(Number(col), widths[col]);
  });
}

function writeTable_(sheet, startRow, startCol, headers, rows) {
  ensureSheetSize_(
    sheet,
    startRow + Math.max(rows ? rows.length : 0, 1) + 5,
    startCol + headers.length + 5
  );

  sheet.getRange(startRow, startCol, 1, headers.length).setValues([headers]);
  styleHeaderRow_(sheet, startRow, startCol, headers.length, "#111827");

  if (rows && rows.length > 0) {
    sheet.getRange(startRow + 1, startCol, rows.length, headers.length).setValues(rows);
    sheet.getRange(startRow + 1, startCol, rows.length, headers.length).setWrap(true);
    sheet.getRange(startRow + 1, startCol, rows.length, headers.length).setVerticalAlignment("top");
  }
}

function colLetter_(col) {
  let temp = "";
  let letter = "";

  while (col > 0) {
    temp = (col - 1) % 26;
    letter = String.fromCharCode(temp + 65) + letter;
    col = (col - temp - 1) / 26;
  }

  return letter;
}

function makeA1_(row, col) {
  return colLetter_(col) + row;
}

function makeRangeA1_(r1, c1, r2, c2) {
  return makeA1_(r1, c1) + ":" + makeA1_(r2, c2);
}

function reorderSheets_(ss, orderedNames) {
  orderedNames.forEach((name, idx) => {
    const sheet = ss.getSheetByName(name);
    if (sheet) {
      ss.setActiveSheet(sheet);
      ss.moveActiveSheet(idx + 1);
    }
  });
}

/**
 *  README 
 */

function createReadme_(ss, cfg) {
  const sh = ss.insertSheet("README");
  ensureSheetSize_(sh, 20, 3);

  sh.setFrozenRows(1);
  sh.setColumnWidth(1, 260);
  sh.setColumnWidth(2, 900);

  writeTable_(sh, 1, 1, ["Topic", "Details"], [
    [
 
    ],
    [

    ],
    [

    ],
    [

    ],
    [

    ],
    [

    ],
  ]);
}

/**
 * Core config sheets
 */

function createSettings_(ss, cfg) {
  const sh = ss.insertSheet("Settings");
  ensureSheetSize_(sh, 20, 5);

  sh.setFrozenRows(1);

  setWidths_(sh, {
    1: 220,
    2: 180,
    3: 700,
  });

  writeTable_(sh, 1, 1, ["key", "value", "notes"], [
    ["unit_system", "kg", "Use kg or lb"],
    ["completion_marker", "d", "Phone-friendly marker. Automation converts d to Done in work_done cells."],
    ["default_setup_id", "HOME", "References Setup.setup_id"],
    ["weeks_per_cycle", cfg.weeks, "Template default"],
    ["days_per_week", cfg.days.length, "Template default"],
  ]);
}

function createSetup_(ss, cfg) {
  const sh = ss.insertSheet("Setup");
  ensureSheetSize_(sh, 20, 8);

  sh.setFrozenRows(1);

  setWidths_(sh, {
    1: 120,
    2: 220,
    3: 140,
    4: 240,
    5: 600,
  });

  writeTable_(sh, 1, 1, ["setup_id", "setup_name", "bar_weight", "min_plate_pair_increment", "notes"], [
    ["HOME", "Home Gym", 20, 2.5, "Example default"],
    ["GYM", "Commercial Gym", 20, 2.5, "Example alternate setup"],
  ]);
}

function createDayOverrides_(ss, cfg) {
  const sh = ss.insertSheet("Day_Overrides");
  ensureSheetSize_(sh, 20, 10);

  sh.setFrozenRows(1);

  setWidths_(sh, {
    1: 100,
    2: 120,
    3: 120,
    4: 180,
    5: 180,
    6: 280,
    7: 600,
  });

  writeTable_(sh, 1, 1, [
    "cycle_id",
    "week_number",
    "day_of_week",
    "override_setup_id",
    "override_bar_weight",
    "override_min_plate_pair_increment",
    "notes"
  ], [
    ["C1", 1, "Mon", "", "", "", "Example row"],
    ["C1", 1, "Thu", "GYM", "", "", "Example: switch setup"],
  ]);
}

function createSessions_(ss, cfg) {
  const sh = ss.insertSheet("Sessions");
  ensureSheetSize_(sh, 50, 16);

  sh.setFrozenRows(1);

  writeTable_(sh, 1, 1, [
    "session_id",
    "cycle_id",
    "week_number",
    "day_of_week",
    "session_date",
    "effective_setup_id",
    "bar_weight_used",
    "min_plate_pair_increment_used",
    "is_finalized",
    "finalized_at",
    "unfinalized_at",
    "force_live_display"
  ], [
    ["C1-W1-Mon", "C1", 1, "Mon", "", "HOME", 20, 2.5, false, "", "", false],
  ]);

  setWidths_(sh, {
    1: 150,
    2: 100,
    3: 120,
    4: 120,
    5: 140,
    6: 180,
    7: 160,
    8: 280,
    9: 120,
    10: 180,
    11: 180,
    12: 180,
  });
}

function createValidationOptions_(ss, cfg) {
  const sh = ss.insertSheet("Validation_Options");
  ensureSheetSize_(sh, 10, 4);

  sh.getRange("A1").setFormula("=CHAR(8203)");
  sh.getRange("A2").setValue("d");
  sh.getRange("B1").setValue("Dropdown source. A1 is visually blank. A2 is completion marker.");
  sh.getRange("B1").setFontStyle("italic").setFontColor("#374151");

  sh.setColumnWidth(1, 180);
  sh.setColumnWidth(2, 800);
}

/**
 *  Library / URLs / Garmin 
 */

function createActivityLibrary_(ss, cfg) {
  const sh = ss.insertSheet("Activity_Library");
  ensureSheetSize_(sh, 50, 14);

  sh.setFrozenRows(1);

  writeTable_(sh, 1, 1, [
    "activity_id",
    "activity_name",
    "activity_description",
    "work_metric_type",
    "default_sets",
    "default_reps_or_seconds",
    "default_rest_seconds",
    "muscle_group",
    "progression_rule",
    "url_id",
    "instructions"
  ], [
    ["DB_CURL", "Dumbbell Curls", "Dumbbell curls (3x8-12)", "reps", 3, "8-12", 60, "Biceps", "When all sets hit top reps, increase weight", "URL1", "Keep elbows fixed"],
    ["PLANK", "Plank", "Front plank (3x45-60s)", "seconds", 3, "45-60", 45, "Core", "Add 5s when top achieved", "URL2", "Brace and breathe"],
  ]);

  setWidths_(sh, {
    1: 140,
    2: 240,
    3: 300,
    4: 160,
    5: 120,
    6: 200,
    7: 180,
    8: 180,
    9: 300,
    10: 100,
    11: 500,
  });
}

function createUrls_(ss, cfg) {
  const sh = ss.insertSheet("URLs");
  ensureSheetSize_(sh, 30, 8);

  sh.setFrozenRows(1);

  writeTable_(sh, 1, 1, ["url_id", "url", "label", "notes"], [
    ["URL1", "https://example.com/curls", "Curls demo", "Replace with real URL"],
    ["URL2", "https://example.com/plank", "Plank demo", "Replace with real URL"],
  ]);

  setWidths_(sh, {
    1: 100,
    2: 600,
    3: 180,
    4: 400,
  });
}

function createGarminSheets_(ss, cfg) {
  const sh1 = ss.insertSheet("Garmin_Workout_Constructor");
  ensureSheetSize_(sh1, 50, 12);

  sh1.setFrozenRows(1);

  writeTable_(sh1, 1, 1, [
    "workout_name",
    "sport",
    "step_order",
    "step_type",
    "target_type",
    "target_value",
    "duration_type",
    "duration_value",
    "notes"
  ], []);

  setWidths_(sh1, {
    1: 220,
    2: 120,
    3: 120,
    4: 140,
    5: 140,
    6: 140,
    7: 140,
    8: 140,
    9: 400,
  });

  const sh2 = ss.insertSheet("Garmin_Export");
  ensureSheetSize_(sh2, 50, 10);

  sh2.setFrozenRows(1);

  writeTable_(sh2, 1, 1, [
    "export_id",
    "workout_name",
    "format",
    "payload",
    "created_at",
    "notes"
  ], []);

  setWidths_(sh2, {
    1: 120,
    2: 220,
    3: 120,
    4: 700,
    5: 180,
    6: 400,
  });
}

/**
 *  Final_Output 
 */

function createFinalOutput_(ss, cfg) {
  const sh = ss.insertSheet("Final_Output");

  const requiredCols =
    cfg.startColWeek1 +
    cfg.weeks * (cfg.weekWidth + cfg.weekGap) -
    cfg.weekGap -
    1;

  const estimatedRows =
    100 +
    cfg.days.length * (cfg.blockDayHeight + cfg.blankRowsBetweenDays);

  ensureSheetSize_(sh, estimatedRows, requiredCols);

  sh.setFrozenRows(1);
  sh.setFrozenColumns(1);

  const cols = {
    set: 0,
    activity: 1,
    target: 2,
    work: 3,
    notes: 4,
    rest: 5,
    url: 6,
    inst: 7,
    spacer: 8,
  };

  const weekWidths = [50, 260, 140, 120, 200, 140, 240, 300, 20];

  sh.setColumnWidth(1, 100);

  for (let w = 0; w < cfg.weeks; w++) {
    const startCol = cfg.startColWeek1 + w * (cfg.weekWidth + cfg.weekGap);

    for (let j = 0; j < weekWidths.length; j++) {
      sh.setColumnWidth(startCol + j, weekWidths[j]);
    }

    sh.getRange(1, startCol, 1, cfg.weekWidth).merge();
    sh.getRange(1, startCol)
      .setValue(`Week ${w + 1}`)
      .setBackground(cfg.colors.header)
      .setFontColor(cfg.colors.white)
      .setFontWeight("bold")
      .setHorizontalAlignment("center");
  }

  sh.getRange(1, 1)
    .setValue("Day")
    .setBackground(cfg.colors.header)
    .setFontColor(cfg.colors.white)
    .setFontWeight("bold")
    .setHorizontalAlignment("center");

  const dayBlockAnchors = {};

  createJumpGrid_(ss, sh, cfg);
  const programStartRow = createTopConfigAreas_(sh, cfg);

  createProgramBlocks_(ss, sh, cfg, cols, programStartRow, dayBlockAnchors);
  fillJumpGridLinks_(ss, sh, cfg, dayBlockAnchors);
  applyWorkDoneValidation_(ss, sh, cfg, cols, dayBlockAnchors);
  applyWorkDoneConditionalFormatting_(sh, cfg, cols, dayBlockAnchors);

  return {
    cols,
    programStartRow,
    dayBlockAnchors,
  };
}

function createJumpGrid_(ss, sh, cfg) {
  const row = 2;

  sh.getRange(row, 1)
    .setValue("Jump to Day")
    .setBackground(cfg.colors.subheader)
    .setFontColor(cfg.colors.white)
    .setFontWeight("bold")
    .setHorizontalAlignment("center");

  for (let w = 0; w < cfg.weeks; w++) {
    const startCol = cfg.startColWeek1 + w * (cfg.weekWidth + cfg.weekGap);
    sh.getRange(row, startCol, 1, cfg.weekWidth).merge();
    sh.getRange(row, startCol)
      .setValue(`W${w + 1}`)
      .setBackground(cfg.colors.subheader)
      .setFontColor(cfg.colors.white)
      .setFontWeight("bold")
      .setHorizontalAlignment("center");
  }

  cfg.days.forEach((day, i) => {
    const r = row + 1 + i;
    sh.getRange(r, 1)
      .setValue(day)
      .setBackground(cfg.colors.subheader)
      .setFontColor(cfg.colors.white)
      .setFontWeight("bold")
      .setHorizontalAlignment("center");

    for (let w = 0; w < cfg.weeks; w++) {
      const startCol = cfg.startColWeek1 + w * (cfg.weekWidth + cfg.weekGap);
      sh.getRange(r, startCol)
        .setValue("Go")
        .setFontColor(cfg.colors.link)
        .setFontLine("underline")
        .setHorizontalAlignment("center");
    }
  });
}

function createTopConfigAreas_(sh, cfg) {
  const maxCol = cfg.startColWeek1 + cfg.weeks * (cfg.weekWidth + cfg.weekGap) - cfg.weekGap - 1;
  const gridTop = 2;
  const cycleSettingsStart = gridTop + 1 + cfg.days.length + 1;

  let r = cycleSettingsStart;

  sh.getRange(r, 1)
    .setValue("Config")
    .setBackground(cfg.colors.subheader)
    .setFontColor(cfg.colors.white)
    .setFontWeight("bold")
    .setHorizontalAlignment("center");

  mergeAcrossNonFrozenColumns_(sh, r, 2, maxCol);
  sh.getRange(r, 2)
    .setValue("Cycle-wide Settings")
    .setBackground(cfg.colors.subheader)
    .setFontColor(cfg.colors.white)
    .setFontWeight("bold")
    .setHorizontalAlignment("center");

  const fields = [
    "1RM Squat",
    "1RM Bench",
    "1RM Deadlift",
    "1RM OHP",
    "Default Bar Weight",
    "Default Rounding Increment",
    "5/3/1 Variant",
    "Leader/Anchor",
    "7th Week Protocol",
    "Next Cycle 1RM Squat",
    "Next Cycle 1RM Bench",
    "Next Cycle 1RM Deadlift",
    "Next Cycle 1RM OHP"
  ];

  r += 1;

  fields.forEach((field, idx) => {
    const row = r + Math.floor(idx / 4);
    const col = 1 + (idx % 4) * 3;

    sh.getRange(row, col)
      .setValue(field)
      .setFontWeight("bold")
      .setWrap(true);

    sh.getRange(row, col + 1)
      .setBorder(true, true, true, true, true, true, cfg.colors.border, SpreadsheetApp.BorderStyle.SOLID);
  });

  r = cycleSettingsStart + 1 + Math.ceil(fields.length / 4);

  sh.getRange(r, 1)
    .setValue("Selections")
    .setBackground(cfg.colors.subheader)
    .setFontColor(cfg.colors.white)
    .setFontWeight("bold")
    .setHorizontalAlignment("center");

  mergeAcrossNonFrozenColumns_(sh, r, 2, maxCol);
  sh.getRange(r, 2)
    .setValue("Daily Selections (IDs only)")
    .setBackground(cfg.colors.subheader)
    .setFontColor(cfg.colors.white)
    .setFontWeight("bold")
    .setHorizontalAlignment("center");

  r += 1;

  const selHeaders = [
    [1, "Week"],
    [2, "Day"],
    [3, "Warmup IDs"],
    [5, "Accessory IDs"],
    [7, "Cooldown IDs"],
    [9, "Rebuild UI"]
  ];

  selHeaders.forEach(([col, label]) => {
    sh.getRange(r, col).setValue(label).setFontWeight("bold");
  });

  cfg.days.forEach((day, i) => {
    const rr = r + 1 + i;
    sh.getRange(rr, 1).setValue(1);
    sh.getRange(rr, 2).setValue(day);
    sh.getRange(rr, 9)
      .setValue("Rebuild")
      .setFontColor(cfg.colors.link)
      .setFontLine("underline");
  });

  const capsStart = r + 1 + cfg.days.length + 1;

  sh.getRange(capsStart, 1)
    .setValue("Caps")
    .setBackground(cfg.colors.subheader)
    .setFontColor(cfg.colors.white)
    .setFontWeight("bold")
    .setHorizontalAlignment("center");

  mergeAcrossNonFrozenColumns_(sh, capsStart, 2, maxCol);
  sh.getRange(capsStart, 2)
    .setValue("Weekly Muscle Group Volume Caps")
    .setBackground(cfg.colors.subheader)
    .setFontColor(cfg.colors.white)
    .setFontWeight("bold")
    .setHorizontalAlignment("center");

  const capsHeader = capsStart + 1;

  sh.getRange(capsHeader, 1, 1, 4).setValues([[
    "Week",
    "Muscle Group",
    "Planned Sets",
    "Cap"
  ]]);

  sh.getRange(capsHeader, 1, 1, 4).setFontWeight("bold");

  const muscles = [
    "Chest",
    "Back",
    "Shoulders",
    "Biceps",
    "Triceps",
    "Quads",
    "Hamstrings",
    "Calves",
    "Core"
  ];

  const rows = [];

  for (let w = 1; w <= cfg.weeks; w++) {
    muscles.forEach(m => rows.push([w, m, "", ""]));
  }

  sh.getRange(capsHeader + 1, 1, rows.length, 4).setValues(rows);

  return capsHeader + 1 + rows.length + 2;
}

function createProgramBlocks_(ss, sh, cfg, cols, startRow, dayBlockAnchors) {
  let currentRow = startRow;

  cfg.days.forEach(day => {
    sh.getRange(currentRow, 1)
      .setValue(day)
      .setBackground(cfg.colors.subheader)
      .setFontColor(cfg.colors.white)
      .setFontWeight("bold")
      .setHorizontalAlignment("center");

    for (let w = 1; w <= cfg.weeks; w++) {
      const startCol = cfg.startColWeek1 + (w - 1) * (cfg.weekWidth + cfg.weekGap);
      dayBlockAnchors[`${w}|${day}`] = { row: currentRow, col: startCol };

      createSingleDayBlock_(sh, cfg, cols, currentRow, startCol, w, day);
    }

    currentRow += cfg.blockDayHeight + cfg.blankRowsBetweenDays;
  });
}

function createSingleDayBlock_(sh, cfg, cols, row, col, week, day) {
  const titleStartCol = col + cols.activity;
  const titleEndCol = col + cols.inst;

  mergeAcrossNonFrozenColumns_(sh, row, titleStartCol, titleEndCol);

  sh.getRange(row, titleStartCol)
    .setValue(`${day} - Week ${week}`)
    .setFontSize(12)
    .setFontWeight("bold")
    .setHorizontalAlignment("left");

  const ctrl = row + 1;

  sh.getRange(ctrl, col + cols.set)
    .setValue("Finalize")
    .setFontWeight("bold");

  sh.getRange(ctrl, col + cols.activity)
    .insertCheckboxes();

  sh.getRange(ctrl, col + cols.notes)
    .setValue("Status")
    .setFontWeight("bold");

  sh.getRange(ctrl, col + cols.work)
    .setValue("LIVE")
    .setBackground(cfg.colors.green)
    .setFontColor(cfg.colors.white)
    .setFontWeight("bold")
    .setHorizontalAlignment("center");

  sh.getRange(ctrl, col + cols.rest)
    .setValue("Show Live Plan")
    .setFontWeight("bold");

  sh.getRange(ctrl, col + cols.url)
    .insertCheckboxes();

  sh.getRange(ctrl, col + cols.inst)
    .setValue("Completed: 0 / 0")
    .setHorizontalAlignment("right");

  let r = row + 3;

  r = writeActivitySection_(sh, cfg, cols, r, col, "Warmup", 3, "Warmup Activity (ID)", "", "", 1);
  r += 1;

  r = writeActivitySection_(sh, cfg, cols, r, col, "5/3/1 Main Lift", 6, "Main Lift (auto)", "e.g., 60kg x 5", "3-5 min", 4);
  r += 1;

  r = writeActivitySection_(sh, cfg, cols, r, col, "Accessories", 8, "Accessory (ID)", "e.g., 3x8-12 @ 12kg", "60-90s", 10);
  r += 1;

  writeActivitySection_(sh, cfg, cols, r, col, "Cooldown", 3, "Cooldown Activity (ID)", "", "", 18);
}

function writeActivitySection_(sh, cfg, cols, row, col, sectionName, setRows, activityText, targetText, restText, startSetNumber) {
  const sectionStartCol = col + cols.activity;
  const sectionEndCol = col + cols.inst;

  mergeAcrossNonFrozenColumns_(sh, row, sectionStartCol, sectionEndCol);

  sh.getRange(row, sectionStartCol)
    .setValue(sectionName)
    .setBackground(cfg.colors.subheader)
    .setFontColor(cfg.colors.white)
    .setFontWeight("bold");

  const headerRow = row + 1;

  const headers = [
    "Set",
    "Activity",
    "Target",
    "Work Done",
    "Notes",
    "Rest",
    "URL",
    "Instructions",
    ""
  ];

  sh.getRange(headerRow, col, 1, headers.length).setValues([headers]);
  styleHeaderRow_(sh, headerRow, col, headers.length, cfg.colors.header);

  const rows = [];

  for (let i = 0; i < setRows; i++) {
    rows.push([
      startSetNumber + i,
      activityText,
      targetText,
      "",
      "",
      restText,
      "",
      "",
      "",
    ]);
  }

  const dataStart = headerRow + 1;

  sh.getRange(dataStart, col, rows.length, headers.length).setValues(rows);
  sh.getRange(dataStart, col, rows.length, headers.length).setWrap(true);

  sh.getRange(dataStart, col, rows.length, headers.length)
    .setBorder(true, true, true, true, true, true, cfg.colors.border, SpreadsheetApp.BorderStyle.SOLID);

  return dataStart + setRows;
}

function fillJumpGridLinks_(ss, sh, cfg, anchors) {
  const gridTop = 2;
  const gid = sh.getSheetId();

  cfg.days.forEach((day, i) => {
    const r = gridTop + 1 + i;

    for (let w = 1; w <= cfg.weeks; w++) {
      const startCol = cfg.startColWeek1 + (w - 1) * (cfg.weekWidth + cfg.weekGap);
      const anchor = anchors[`${w}|${day}`];
      const rangeA1 = makeA1_(anchor.row, anchor.col);
      const formula = `=HYPERLINK("#gid=${gid}&range=${rangeA1}","Go")`;

      sh.getRange(r, startCol).setFormula(formula);
    }
  });
}

function applyWorkDoneValidation_(ss, sh, cfg, cols, anchors) {
  const validationOptions = ss.getSheetByName("Validation_Options");
  const source = validationOptions.getRange("A1:A2");

  const rule = SpreadsheetApp.newDataValidation()
    .requireValueInRange(source, true)
    .setAllowInvalid(true)
    .setHelpText("Enter reps/seconds, or 'd' to mark Done. Automation converts d to Done.")
    .build();

  Object.keys(anchors).forEach(key => {
    const anchor = anchors[key];
    const workCol = anchor.col + cols.work;

    const r1 = anchor.row + 5;
    const r2 = anchor.row + cfg.blockDayHeight - 2;

    sh.getRange(r1, workCol, r2 - r1 + 1, 1).setDataValidation(rule);
  });
}

function applyWorkDoneConditionalFormatting_(sh, cfg, cols, anchors) {
  const rules = [];

  Object.keys(anchors).forEach(key => {
    const anchor = anchors[key];
    const workCol = anchor.col + cols.work;

    const r1 = anchor.row + 5;
    const r2 = anchor.row + cfg.blockDayHeight - 2;
    const range = sh.getRange(r1, workCol, r2 - r1 + 1, 1);

    const topLeft = makeA1_(r1, workCol);

    const completeRule = SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied(`=OR(ISNUMBER(${topLeft}),LOWER(TRIM(${topLeft}))="done")`)
      .setBackground(cfg.colors.lightGreen)
      .setRanges([range])
      .build();

    const invalidRule = SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied(`=AND(${topLeft}<>"",NOT(ISNUMBER(${topLeft})),LOWER(TRIM(${topLeft}))<>"done")`)
      .setBackground(cfg.colors.lightAmber)
      .setRanges([range])
      .build();

    rules.push(completeRule, invalidRule);
  });

  sh.setConditionalFormatRules(rules);
}

/**
 *  Day_Block_Map 
 */

function createDayBlockMap_(ss, cfg, info) {
  const sh = ss.insertSheet("Day_Block_Map");

  const expectedRows = 5 + cfg.weeks * cfg.days.length;
  ensureSheetSize_(sh, expectedRows, 15);

  sh.setFrozenRows(1);

  const headers = [
    "cycle_id",
    "week_number",
    "day_of_week",
    "session_id",
    "finalize_checkbox_cell",
    "show_live_checkbox_cell",
    "status_cell",
    "show_live_label_cell",
    "summary_cell",
    "work_done_range",
    "day_block_range",
    "planned_sets_range"
  ];

  const rows = [];
  const cols = info.cols;

  cfg.days.forEach(day => {
    for (let w = 1; w <= cfg.weeks; w++) {
      const anchor = info.dayBlockAnchors[`${w}|${day}`];

      const row = anchor.row;
      const col = anchor.col;
      const ctrl = row + 1;

      const finalizeCell = makeA1_(ctrl, col + cols.activity);
      const showLiveCell = makeA1_(ctrl, col + cols.url);
      const statusCell = makeA1_(ctrl, col + cols.work);
      const labelCell = makeA1_(ctrl, col + cols.rest);
      const summaryCell = makeA1_(ctrl, col + cols.inst);

      const workCol = col + cols.work;
      const workRange = makeRangeA1_(row + 5, workCol, row + cfg.blockDayHeight - 2, workCol);

      const blockRange = makeRangeA1_(row, col, row + cfg.blockDayHeight - 1, col + cfg.weekWidth - 1);

      rows.push([
        cfg.cycleId,
        w,
        day,
        `${cfg.cycleId}-W${w}-${day}`,
        finalizeCell,
        showLiveCell,
        statusCell,
        labelCell,
        summaryCell,
        workRange,
        blockRange,
        ""
      ]);
    }
  });

  writeTable_(sh, 1, 1, headers, rows);

  setWidths_(sh, {
    1: 100,
    2: 120,
    3: 120,
    4: 160,
    5: 220,
    6: 220,
    7: 140,
    8: 180,
    9: 180,
    10: 240,
    11: 240,
    12: 180,
  });
}

/**
 *  Guidance sheets 
 */

function createGuidanceSheets_(ss, cfg) {
  const cl = ss.insertSheet("Cycle_Log_Columns");
  ensureSheetSize_(cl, 20, 5);

  cl.setFrozenRows(1);

  writeTable_(cl, 1, 1, ["Column to add", "Type", "Purpose / Notes"], [
    ["session_id", "text", "Links each log row to Sessions.session_id. Required for finalize/snapshot logic."],
    ["work_done", "user input", "Single input per set: number OR d → Done."],
    ["bar_weight_snapshot", "number", "Written on finalize."],
    ["min_plate_pair_increment_snapshot", "number", "Written on finalize."],
    ["target_total_weight_snapshot", "number", "Written on finalize if live column exists."],
    ["actual_total_weight_snapshot", "number", "Written on finalize if live column exists."],
  ]);

  setWidths_(cl, {
    1: 300,
    2: 140,
    3: 900,
  });

  const cf = ss.insertSheet("Conditional_Formatting");
  ensureSheetSize_(cf, 20, 6);

  cf.setFrozenRows(1);

  writeTable_(cf, 1, 1, ["Applies to", "Rule name", "Custom formula example", "Suggested format"], [
    ["work_done cells", "Completed", '=OR(ISNUMBER(F10), LOWER(TRIM(F10))="done")', "Green fill"],
    ["work_done cells", "Invalid entry", '=AND(F10<>"", NOT(ISNUMBER(F10)), LOWER(TRIM(F10))<>"done")', "Amber fill"],
  ]);

  setWidths_(cf, {
    1: 220,
    2: 220,
    3: 700,
    4: 400,
  });

  const ld = ss.insertSheet("Log_Display");
  ensureSheetSize_(ld, 50, 12);

  ld.setFrozenRows(1);

  writeTable_(ld, 1, 1, [
    "session_id",
    "date",
    "activity",
    "set",
    "planned",
    "done",
    "target_total",
    "actual_total",
    "notes"
  ], []);

  setWidths_(ld, {
    1: 140,
    2: 120,
    3: 280,
    4: 80,
    5: 140,
    6: 140,
    7: 140,
    8: 140,
    9: 400,
  });
}