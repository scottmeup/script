/**
 * Garmin Workout Data Importer for Google Sheets
 */

const GARMIN_IMPORT_CONFIG = {
  scriptPropertyFolderId: 'GARMIN_IMPORT_FOLDER_ID',

  archiveExistingManagedSheets: true,

  managedSheetPrefix: '',

  sourceFiles: {
    activityTypes: {
      label: 'activity_types',
      type: 'AUTO',
      aliases: [
        'activity_types',
        'activity_types.txt',
        'activity-types.txt',
        'activity_types.json',
        'activity-types.json'
      ]
    },
    benchmarks: {
      label: 'benchmarks.json',
      type: 'JSON',
      aliases: ['benchmarks.json']
    },
    exerciseEquipmentText: {
      label: 'exercise-equipment.txt',
      type: 'KV',
      aliases: ['exercise-equipment.txt', 'exercise_equipment.txt']
    },
    exercises: {
      label: 'exercises.json',
      type: 'JSON',
      aliases: ['exercises.json']
    },
    exerciseToEquipments: {
      label: 'exercise-to-equipments.json',
      type: 'JSON',
      aliases: [
        'exercise-to-equimpents.json',
        'exercise-to-equipments.json',
        'exercises-to-equipments.json',
        'exercise-to-equipment.json',
        'exercises-to-equipment.json'
      ]
    },
    exerciseTypes: {
      label: 'exercise-types.txt',
      type: 'KV',
      aliases: ['exercise-types.txt', 'exercise_types.txt']
    },
    msnWorkouts: {
      label: 'msn-workouts.txt',
      type: 'KV',
      aliases: ['msn-workouts.txt', 'msn_workouts.txt']
    },
    units: {
      label: 'units.txt',
      type: 'KV',
      aliases: ['units.txt']
    },
    workoutProperties: {
      label: 'workout-properties.txt',
      type: 'KV',
      aliases: ['workout-properties.txt', 'workout_properties.txt']
    }
  },

  sheets: {
    importLog: '_Import_Log',
    sourceIndex: '_Source_Index',
    summary: '_Summary',

    rawJson: 'Raw_JSON',
    rawKeyValue: 'Raw_KeyValue',

    activityTypes: 'ActivityTypes',
    benchmarks: 'Benchmarks',
    exerciseCatalog: 'ExerciseCatalog',
    exerciseEquipmentMap: 'ExerciseEquipmentMap',
    exerciseLabels: 'ExerciseLabels',
    exerciseEquipmentText: 'ExerciseEquipmentText',
    msnWorkoutText: 'MsnWorkoutText',
    units: 'Units',
    workoutProperties: 'WorkoutProperties',

    exerciseDescriptions: 'ExerciseDescriptions',
    exerciseTips: 'ExerciseTips',
    exerciseSteps: 'ExerciseSteps',
    workoutNames: 'WorkoutNames',
    workoutDescriptions: 'WorkoutDescriptions',

    muscleTypes: 'MuscleTypes',
    categoryTypes: 'CategoryTypes',
    equipmentTypes: 'EquipmentTypes',

    exerciseMaster: 'ExerciseMaster'
  }
};

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Garmin Import')
    .addItem('Set Drive Folder ID', 'setGarminImportFolderId')
    .addItem('Import Available Files', 'importGarminWorkoutFiles')
    .addSeparator()
    .addItem('Remove Archive Sheets', 'removeArchiveSheets')
    .addSeparator()
    .addItem('Organize Sheets', 'organizeSheetsByCategory')
    .addToUi();
}

function organizeSheetsByCategory() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheets = ss.getSheets();

  var categories = {
    IMPORT: {
      color: '#D9EAD3',
      names: ['_Import_Log', '_Source_Index', '_Summary', 'Raw_JSON', 'Raw_KeyValue']
    },
    DATABASE: {
      color: '#CFE2F3',
      names: [
        'ExerciseCatalog',
        'ExerciseEquipmentMap',
        'ExerciseLabels',
        'ExerciseMaster',
        'ExerciseDescriptions',
        'ExerciseTips',
        'ExerciseSteps',
        'WorkoutNames',
        'WorkoutDescriptions',
        'Units',
        'WorkoutProperties',
        'MuscleTypes',
        'CategoryTypes',
        'EquipmentTypes'
      ]
    },
    OUTPUT: {
      color: '#FFF2CC',
      names: [
        'Final_Output',
        'Garmin_Workout_Constructor',
        'Garmin_Export'
      ]
    },
    HELPER: {
      color: '#F4CCCC',
      names: [
        'Day_Block_Map',
        'Settings',
        'Setup',
        'Day_Overrides',
        'Sessions',
        'Validation_Options',
        'Activity_Library',
        'URLs',
        'Cycle_Log_Columns',
        'Conditional_Formatting',
        'Log_Display'
      ]
    }
  };

  var orderedSheets = [];

  Object.keys(categories).forEach(function(catKey) {
    var cat = categories[catKey];

    var matched = sheets.filter(function(s) {
      return cat.names.indexOf(s.getName()) !== -1;
    });

    matched.sort(function(a, b) {
      return a.getName().localeCompare(b.getName());
    });

    matched.forEach(function(sheet) {
      sheet.setTabColor(cat.color);
      orderedSheets.push(sheet);
    });
  });

  // Any remaining sheets (not categorized)
  var remaining = sheets.filter(function(s) {
    return orderedSheets.indexOf(s) === -1;
  });

  remaining.sort(function(a, b) {
    return a.getName().localeCompare(b.getName());
  });

  remaining.forEach(function(sheet) {
    sheet.setTabColor(null);
    orderedSheets.push(sheet);
  });

  // Reorder in sheet
  for (var i = 0; i < orderedSheets.length; i++) {
    ss.setActiveSheet(orderedSheets[i]);
    ss.moveActiveSheet(i + 1);
  }

  SpreadsheetApp.getUi().alert('Sheets organized successfully.');
}


function setGarminImportFolderId() {
  const ui = SpreadsheetApp.getUi();
  const response = ui.prompt(
    'Set Drive Folder ID',
    'Paste the Google Drive folder ID that contains your Garmin source files.',
    ui.ButtonSet.OK_CANCEL
  );

  if (response.getSelectedButton() !== ui.Button.OK) return;

  const folderId = response.getResponseText().trim();
  if (!folderId) {
    ui.alert('No folder ID entered.');
    return;
  }

  PropertiesService.getScriptProperties().setProperty(
    GARMIN_IMPORT_CONFIG.scriptPropertyFolderId,
    folderId
  );

  ui.alert('Folder ID saved.');
}

function showGarminImportFolderId() {
  const folderId = PropertiesService.getScriptProperties().getProperty(
    GARMIN_IMPORT_CONFIG.scriptPropertyFolderId
  );

  SpreadsheetApp.getUi().alert(folderId || 'No folder ID has been set.');
}

function importGarminWorkoutFiles() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const startedAt = new Date();

  const importState = {
    startedAt,
    logs: [],
    sources: {},
    rawJsonRows: [],
    rawKeyValueRows: [],
    parsed: {
      activityTypes: [],
      benchmarks: [],
      exerciseCatalog: [],
      exerciseEquipmentMap: [],
      exerciseLabels: [],
      exerciseEquipmentText: [],
      msnWorkoutText: [],
      units: [],
      workoutProperties: [],
      exerciseDescriptions: [],
      exerciseTips: [],
      exerciseSteps: [],
      workoutNames: [],
      workoutDescriptions: [],
      muscleTypes: [],
      categoryTypes: [],
      equipmentTypes: []
    }
  };

  try {
    const folder = getConfiguredFolder_();
    log_(importState, 'INFO', 'Import started.', '', '');

    Object.keys(GARMIN_IMPORT_CONFIG.sourceFiles).forEach(sourceKey => {
      importOneSource_(folder, sourceKey, importState);
    });

    buildDerivedSheets_(importState);

    writeAllSheets_(ss, importState);

    log_(importState, 'INFO', 'Import completed.', '', '');
    writeLogSheet_(ss, importState);

    SpreadsheetApp.getUi().alert(
      'Import complete.\n\nFiles found: ' +
        Object.values(importState.sources).filter(s => s.status === 'FOUND').length +
        '\nFiles missing: ' +
        Object.values(importState.sources).filter(s => s.status === 'MISSING').length +
        '\n\nCheck _Import_Log and _Summary for details.'
    );
  } catch (err) {
    log_(importState, 'ERROR', 'Import failed unexpectedly.', '', errToString_(err));
    writeLogSheet_(ss, importState);
    SpreadsheetApp.getUi().alert('Import failed unexpectedly. Check _Import_Log.');
  }
}

function getConfiguredFolder_() {
  const folderId = PropertiesService.getScriptProperties().getProperty(
    GARMIN_IMPORT_CONFIG.scriptPropertyFolderId
  );

  if (!folderId) {
    throw new Error('No Drive folder ID set. Use Garmin Import → Set Drive Folder ID first.');
  }

  return DriveApp.getFolderById(folderId);
}

function importOneSource_(folder, sourceKey, importState) {
  const sourceConfig = GARMIN_IMPORT_CONFIG.sourceFiles[sourceKey];
  const file = findFirstMatchingFile_(folder, sourceConfig.aliases);

  if (!file) {
    importState.sources[sourceKey] = {
      sourceKey,
      expected: sourceConfig.label,
      matchedFileName: '',
      status: 'MISSING',
      mimeType: '',
      size: '',
      lastUpdated: ''
    };
    log_(importState, 'WARN', 'Source file missing; continuing.', sourceKey, sourceConfig.label);
    return;
  }

  const fileName = file.getName();
  const text = file.getBlob().getDataAsString('UTF-8');

  importState.sources[sourceKey] = {
    sourceKey,
    expected: sourceConfig.label,
    matchedFileName: fileName,
    status: 'FOUND',
    mimeType: file.getMimeType(),
    size: file.getSize(),
    lastUpdated: file.getLastUpdated()
  };

  log_(importState, 'INFO', 'Source file found.', sourceKey, fileName);

  const type = sourceConfig.type === 'AUTO' ? detectSourceType_(fileName, text) : sourceConfig.type;

  if (type === 'JSON') {
    importJsonSource_(sourceKey, fileName, text, importState);
  } else if (type === 'KV') {
    importKeyValueSource_(sourceKey, fileName, text, importState);
  } else {
    log_(importState, 'WARN', 'Unknown file type; storing as raw key/value-style text.', sourceKey, fileName);
    importKeyValueSource_(sourceKey, fileName, text, importState);
  }
}

function findFirstMatchingFile_(folder, aliases) {
  const normalizedAliases = aliases.map(a => a.toLowerCase());

  const files = folder.getFiles();
  while (files.hasNext()) {
    const file = files.next();
    const name = file.getName().toLowerCase();

    if (normalizedAliases.indexOf(name) !== -1) return file;
  }

  return null;
}

function detectSourceType_(fileName, text) {
  if (/\.json$/i.test(fileName)) return 'JSON';
  const trimmed = text.trim();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) return 'JSON';
  return 'KV';
}

function removeArchiveSheets() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheets = ss.getSheets();
  var removedCount = 0;

  for (var i = sheets.length - 1; i >= 0; i--) {
    var name = sheets[i].getName();

    if (name.indexOf('__archive_') !== -1) {
      ss.deleteSheet(sheets[i]);
      removedCount++;
    }
  }

  SpreadsheetApp.getUi().alert(
    removedCount + ' archive sheet(s) removed successfully.'
  );
}

function importJsonSource_(sourceKey, fileName, text, importState) {
  let data;

  try {
    data = JSON.parse(text);
  } catch (err) {
    importState.rawJsonRows.push([
      sourceKey,
      fileName,
      '',
      '',
      '',
      '',
      'PARSE_ERROR',
      errToString_(err),
      text.slice(0, 50000)
    ]);
    log_(importState, 'ERROR', 'JSON parse failed; continuing.', sourceKey, errToString_(err));
    return;
  }

  const flattened = flattenJson_(data);
  flattened.forEach(row => {
    importState.rawJsonRows.push([
      sourceKey,
      fileName,
      row.path,
      row.key,
      row.index,
      row.type,
      'OK',
      '',
      stringifyCell_(row.value)
    ]);
  });

  if (sourceKey === 'exercises') {
    parseExercisesJson_(data, sourceKey, fileName, importState);
  } else if (sourceKey === 'exerciseToEquipments') {
    parseExerciseToEquipmentsJson_(data, sourceKey, fileName, importState);
  } else if (sourceKey === 'benchmarks') {
    parseBenchmarksJson_(data, sourceKey, fileName, importState);
  } else if (sourceKey === 'activityTypes') {
    parseActivityTypesJson_(data, sourceKey, fileName, importState);
  }
}

function importKeyValueSource_(sourceKey, fileName, text, importState) {
  const rows = parseKeyValueText_(text);

  rows.forEach(row => {
    importState.rawKeyValueRows.push([
      sourceKey,
      fileName,
      row.lineNumber,
      row.key,
      row.value,
      row.status,
      row.error
    ]);
  });

  if (sourceKey === 'exerciseTypes') {
    parseExerciseTypesKeyValues_(rows, sourceKey, fileName, importState);
  } else if (sourceKey === 'msnWorkouts') {
    parseMsnWorkoutKeyValues_(rows, sourceKey, fileName, importState);
  } else if (sourceKey === 'units') {
    parseGenericKeyValues_(rows, importState.parsed.units, sourceKey, fileName);
  } else if (sourceKey === 'workoutProperties') {
    parseGenericKeyValues_(rows, importState.parsed.workoutProperties, sourceKey, fileName);
  } else if (sourceKey === 'exerciseEquipmentText') {
    parseExerciseEquipmentText_(rows, sourceKey, fileName, importState);
  } else if (sourceKey === 'activityTypes') {
    parseGenericKeyValues_(rows, importState.parsed.activityTypes, sourceKey, fileName);
  }
}

function parseKeyValueText_(text) {
  const lines = text.split(/\r?\n/);
  const rows = [];

  lines.forEach((line, i) => {
    const lineNumber = i + 1;
    const raw = line;

    if (!raw.trim()) return;

    const eqIndex = raw.indexOf('=');
    if (eqIndex === -1) {
      rows.push({
        lineNumber,
        key: raw.trim(),
        value: '',
        status: 'NO_EQUALS',
        error: 'Line does not contain "=".'
      });
      return;
    }

    rows.push({
      lineNumber,
      key: raw.slice(0, eqIndex).trim(),
      value: decodeHtml_(raw.slice(eqIndex + 1).trim()),
      status: 'OK',
      error: ''
    });
  });

  return rows;
}


function parseExercisesJson_(data, sourceKey, fileName, importState) {
  if (!data) return;

  var categories = data.categories || {};

  Object.keys(categories).forEach(function(categoryKey) {
    var category = categories[categoryKey] || {};

    var exercises = category.exercises || {};

    Object.keys(exercises).forEach(function(exerciseKey) {
      var ex = exercises[exerciseKey] || {};

      var primary = ex.primaryMuscles || [];
      var secondary = ex.secondaryMuscles || [];

      if ((!primary || primary.length === 0) && secondary && secondary.length > 0) {
        primary = secondary;
        secondary = [];
      }

      importState.parsed.exerciseCatalog.push([
        categoryKey,
        '', // category-level muscles not present here
        '',
        exerciseKey,
        ex.isBodyWeight === true,
        ex.counterpart || '',
        arrToCsv_(primary),
        arrToCsv_(secondary),
        sourceKey,
        fileName
      ]);
    });
  });
}


function parseExerciseToEquipmentsJson_(data, sourceKey, fileName, importState) {
  if (!Array.isArray(data)) {
    log_(importState, 'WARN', 'Exercise-to-equipment JSON was not an array.', sourceKey, fileName);
    return;
  }

  data.forEach(category => {
    const categoryKey = category.exerciseCategoryKey || '';
    const exercises = category.exercisesInCategory || [];

    exercises.forEach(ex => {
      importState.parsed.exerciseEquipmentMap.push([
        categoryKey,
        ex.exerciseKey || '',
        arrToCsv_(ex.primaryMuscles),
        arrToCsv_(ex.secondaryMuscles),
        arrToCsv_(ex.equipmentKeys),
        sourceKey,
        fileName
      ]);
    });
  });
}

function parseBenchmarksJson_(data, sourceKey, fileName, importState) {
  const flat = flattenJson_(data);

  flat.forEach(row => {
    importState.parsed.benchmarks.push([
      row.path,
      row.key,
      row.index,
      row.type,
      stringifyCell_(row.value),
      sourceKey,
      fileName
    ]);
  });
}

function parseActivityTypesJson_(data, sourceKey, fileName, importState) {
  const flat = flattenJson_(data);

  flat.forEach(row => {
    importState.parsed.activityTypes.push([
      row.path,
      row.key,
      row.index,
      row.type,
      stringifyCell_(row.value),
      sourceKey,
      fileName
    ]);
  });
}

function parseGenericKeyValues_(rows, targetArray, sourceKey, fileName) {
  rows
    .filter(r => r.status === 'OK')
    .forEach(r => {
      targetArray.push([
        r.key,
        r.value,
        classifyKeyNamespace_(r.key),
        sourceKey,
        fileName,
        r.lineNumber
      ]);
    });
}

function parseExerciseEquipmentText_(rows, sourceKey, fileName, importState) {
  rows
    .filter(r => r.status === 'OK')
    .forEach(r => {
      importState.parsed.exerciseEquipmentText.push([
        r.key,
        r.value,
        normalizeKey_(r.key),
        sourceKey,
        fileName,
        r.lineNumber
      ]);

      importState.parsed.equipmentTypes.push([
        normalizeKey_(r.key),
        r.key,
        r.value,
        sourceKey,
        fileName
      ]);
    });
}

function parseExerciseTypesKeyValues_(rows, sourceKey, fileName, importState) {
  rows
    .filter(r => r.status === 'OK')
    .forEach(r => {
      const key = r.key;
      const value = r.value;

      const parsed = parseExerciseTypeKey_(key);

      importState.parsed.exerciseLabels.push([
        key,
        value,
        parsed.kind,
        parsed.categoryKey,
        parsed.exerciseKey,
        parsed.normalizedExerciseKey,
        sourceKey,
        fileName,
        r.lineNumber
      ]);

      if (parsed.kind === 'CATEGORY_TYPE') {
        importState.parsed.categoryTypes.push([
          parsed.categoryKey,
          value,
          key,
          sourceKey,
          fileName
        ]);
      }

      if (parsed.kind === 'MUSCLE_TYPE') {
        importState.parsed.muscleTypes.push([
          parsed.exerciseKey,
          value,
          key,
          sourceKey,
          fileName
        ]);
      }
    });
}

function parseMsnWorkoutKeyValues_(rows, sourceKey, fileName, importState) {
  rows
    .filter(r => r.status === 'OK')
    .forEach(r => {
      const parsed = parseMsnKey_(r.key);

      importState.parsed.msnWorkoutText.push([
        r.key,
        r.value,
        parsed.kind,
        parsed.entityKey,
        parsed.index,
        sourceKey,
        fileName,
        r.lineNumber
      ]);

      if (parsed.kind === 'EXERCISE_DESCRIPTION') {
        importState.parsed.exerciseDescriptions.push([
          parsed.entityKey,
          r.value,
          r.key,
          sourceKey,
          fileName
        ]);
      }

      if (parsed.kind === 'EXERCISE_TIP') {
        importState.parsed.exerciseTips.push([
          parsed.entityKey,
          parsed.index,
          r.value,
          r.key,
          sourceKey,
          fileName
        ]);
      }

      if (parsed.kind === 'EXERCISE_STEP') {
        importState.parsed.exerciseSteps.push([
          parsed.entityKey,
          parsed.index,
          r.value,
          r.key,
          sourceKey,
          fileName
        ]);
      }

      if (parsed.kind === 'WORKOUT_NAME') {
        importState.parsed.workoutNames.push([
          parsed.entityKey,
          r.value,
          r.key,
          sourceKey,
          fileName
        ]);
      }

      if (parsed.kind === 'WORKOUT_DESCRIPTION') {
        importState.parsed.workoutDescriptions.push([
          parsed.entityKey,
          r.value,
          r.key,
          sourceKey,
          fileName
        ]);
      }
    });
}

function parseExerciseTypeKey_(key) {
  if (key.indexOf('category_type_') === 0) {
    return {
      kind: 'CATEGORY_TYPE',
      categoryKey: key.replace('category_type_', ''),
      exerciseKey: '',
      normalizedExerciseKey: ''
    };
  }

  if (key.indexOf('muscle_type_') === 0) {
    const muscleKey = key.replace('muscle_type_', '');
    return {
      kind: 'MUSCLE_TYPE',
      categoryKey: '',
      exerciseKey: muscleKey,
      normalizedExerciseKey: muscleKey
    };
  }

  if (key.indexOf('exercise_type_') === 0) {
    const exerciseKey = key.replace('exercise_type_', '');
    return {
      kind: 'EXERCISE_TYPE',
      categoryKey: '',
      exerciseKey,
      normalizedExerciseKey: exerciseKey
    };
  }

  const categoryMatch = key.match(/^([A-Z0-9_]+?)_(.+)$/);
  if (categoryMatch) {
    return {
      kind: 'CATEGORY_EXERCISE_LABEL',
      categoryKey: categoryMatch[1],
      exerciseKey: categoryMatch[2],
      normalizedExerciseKey: categoryMatch[2]
    };
  }

  return {
    kind: 'OTHER',
    categoryKey: '',
    exerciseKey: key,
    normalizedExerciseKey: key
  };
}

function parseMsnKey_(key) {
  let m;

  m = key.match(/^exercise_description_(.+)$/);
  if (m) {
    return { kind: 'EXERCISE_DESCRIPTION', entityKey: normalizeExerciseEntityKey_(m[1]), index: '' };
  }

  m = key.match(/^(.+)_tip_(\d+)$/);
  if (m) {
    return { kind: 'EXERCISE_TIP', entityKey: normalizeExerciseEntityKey_(m[1]), index: Number(m[2]) };
  }

  m = key.match(/^(.+)_step_(\d+)$/);
  if (m) {
    return { kind: 'EXERCISE_STEP', entityKey: normalizeExerciseEntityKey_(m[1]), index: Number(m[2]) };
  }

  m = key.match(/^workout_name_(.+)$/);
  if (m) {
    return { kind: 'WORKOUT_NAME', entityKey: m[1], index: '' };
  }

  m = key.match(/^(?:workout_description|description)_(.+)$/);
  if (m) {
    return { kind: 'WORKOUT_DESCRIPTION', entityKey: m[1], index: '' };
  }

  return { kind: classifyKeyNamespace_(key), entityKey: key, index: '' };
}

function normalizeExerciseEntityKey_(key) {
  return String(key || '')
    .replace(/_POSE$/i, '')
    .replace(/[’']/g, '')
    .replace(/&AMP;/gi, 'AND')
    .replace(/&NBSP;/gi, '_')
    .toUpperCase();
}

function buildDerivedSheets_(importState) {
  buildExerciseMaster_(importState);
}

function buildExerciseMaster_(importState) {
  const catalog = importState.parsed.exerciseCatalog;
  const equipmentRows = importState.parsed.exerciseEquipmentMap;
  const labels = importState.parsed.exerciseLabels;
  const descriptions = importState.parsed.exerciseDescriptions;
  const tips = importState.parsed.exerciseTips;
  const steps = importState.parsed.exerciseSteps;

  const labelByExercise = {};
  labels.forEach(r => {
    const key = r[5];
    const display = r[1];
    const category = r[3];

    if (key && !labelByExercise[key]) labelByExercise[key] = display;

    if (category && key) {
      const compound = category + '|' + key;
      if (!labelByExercise[compound]) labelByExercise[compound] = display;
    }
  });

  const equipmentByCompound = {};
  const equipmentByExercise = {};
  equipmentRows.forEach(r => {
    const categoryKey = r[0];
    const exerciseKey = r[1];
    const equipment = r[4];

    if (categoryKey && exerciseKey) equipmentByCompound[categoryKey + '|' + exerciseKey] = equipment;
    if (exerciseKey && !equipmentByExercise[exerciseKey]) equipmentByExercise[exerciseKey] = equipment;
  });

  const descriptionByExercise = {};
  descriptions.forEach(r => {
    if (!descriptionByExercise[r[0]]) descriptionByExercise[r[0]] = r[1];
  });

  const tipCountByExercise = {};
  tips.forEach(r => {
    tipCountByExercise[r[0]] = (tipCountByExercise[r[0]] || 0) + 1;
  });

  const stepCountByExercise = {};
  steps.forEach(r => {
    stepCountByExercise[r[0]] = (stepCountByExercise[r[0]] || 0) + 1;
  });

  const seen = {};
  const master = [];

  catalog.forEach(r => {
    const categoryKey = r[0];
    const exerciseKey = r[3];
    const compoundKey = categoryKey + '|' + exerciseKey;

    if (seen[compoundKey]) return;
    seen[compoundKey] = true;

    const displayName =
      labelByExercise[compoundKey] ||
      labelByExercise[exerciseKey] ||
      toTitleCase_(exerciseKey);

    const equipment =
      equipmentByCompound[compoundKey] ||
      equipmentByExercise[exerciseKey] ||
      '';

    const normalizedForDescriptions = normalizeExerciseEntityKey_(exerciseKey);

    master.push([
      categoryKey,
      exerciseKey,
      displayName,
      r[4],
      r[5],
      r[6],
      r[7],
      equipment,
      descriptionByExercise[normalizedForDescriptions] || '',
      tipCountByExercise[normalizedForDescriptions] || 0,
      stepCountByExercise[normalizedForDescriptions] || 0,
      makeExerciseUid_(categoryKey, exerciseKey)
    ]);
  });

  importState.parsed.exerciseMaster = master;
}

function writeAllSheets_(ss, importState) {
  writeSourceIndexSheet_(ss, importState);
  writeRawSheets_(ss, importState);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.activityTypes, [
    'Path', 'Key', 'Index', 'Type', 'Value', 'SourceKey', 'SourceFile'
  ], importState.parsed.activityTypes);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.benchmarks, [
    'Path', 'Key', 'Index', 'Type', 'Value', 'SourceKey', 'SourceFile'
  ], importState.parsed.benchmarks);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.exerciseCatalog, [
    'CategoryKey',
    'CategoryPrimaryMuscles',
    'CategorySecondaryMuscles',
    'ExerciseKey',
    'IsBodyWeight',
    'Counterpart',
    'PrimaryMuscles',
    'SecondaryMuscles',
    'SourceKey',
    'SourceFile'
  ], importState.parsed.exerciseCatalog);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.exerciseEquipmentMap, [
    'CategoryKey',
    'ExerciseKey',
    'PrimaryMuscles',
    'SecondaryMuscles',
    'EquipmentKeys',
    'SourceKey',
    'SourceFile'
  ], importState.parsed.exerciseEquipmentMap);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.exerciseLabels, [
    'Key',
    'DisplayName',
    'Kind',
    'CategoryKey',
    'ExerciseKey',
    'NormalizedExerciseKey',
    'SourceKey',
    'SourceFile',
    'LineNumber'
  ], importState.parsed.exerciseLabels);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.exerciseEquipmentText, [
    'Key',
    'DisplayName',
    'NormalizedKey',
    'SourceKey',
    'SourceFile',
    'LineNumber'
  ], importState.parsed.exerciseEquipmentText);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.msnWorkoutText, [
    'Key',
    'Text',
    'Kind',
    'EntityKey',
    'Index',
    'SourceKey',
    'SourceFile',
    'LineNumber'
  ], importState.parsed.msnWorkoutText);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.units, [
    'Key',
    'Value',
    'Namespace',
    'SourceKey',
    'SourceFile',
    'LineNumber'
  ], importState.parsed.units);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.workoutProperties, [
    'Key',
    'Value',
    'Namespace',
    'SourceKey',
    'SourceFile',
    'LineNumber'
  ], importState.parsed.workoutProperties);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.exerciseDescriptions, [
    'ExerciseKey',
    'Description',
    'SourceTextKey',
    'SourceKey',
    'SourceFile'
  ], importState.parsed.exerciseDescriptions);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.exerciseTips, [
    'ExerciseKey',
    'TipIndex',
    'Tip',
    'SourceTextKey',
    'SourceKey',
    'SourceFile'
  ], importState.parsed.exerciseTips);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.exerciseSteps, [
    'ExerciseKey',
    'StepIndex',
    'StepInstruction',
    'SourceTextKey',
    'SourceKey',
    'SourceFile'
  ], importState.parsed.exerciseSteps);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.workoutNames, [
    'WorkoutKey',
    'WorkoutName',
    'SourceTextKey',
    'SourceKey',
    'SourceFile'
  ], importState.parsed.workoutNames);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.workoutDescriptions, [
    'WorkoutKey',
    'WorkoutDescription',
    'SourceTextKey',
    'SourceKey',
    'SourceFile'
  ], importState.parsed.workoutDescriptions);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.muscleTypes, [
    'MuscleKey',
    'DisplayName',
    'SourceTextKey',
    'SourceKey',
    'SourceFile'
  ], importState.parsed.muscleTypes);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.categoryTypes, [
    'CategoryKey',
    'DisplayName',
    'SourceTextKey',
    'SourceKey',
    'SourceFile'
  ], importState.parsed.categoryTypes);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.equipmentTypes, [
    'EquipmentKey',
    'SourceKeyName',
    'DisplayName',
    'SourceKey',
    'SourceFile'
  ], importState.parsed.equipmentTypes);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.exerciseMaster, [
    'CategoryKey',
    'ExerciseKey',
    'DisplayName',
    'IsBodyWeight',
    'Counterpart',
    'PrimaryMuscles',
    'SecondaryMuscles',
    'EquipmentKeys',
    'Description',
    'TipCount',
    'StepCount',
    'ExerciseUID'
  ], importState.parsed.exerciseMaster);

  writeSummarySheet_(ss, importState);
  addFormulasAndFormatting_(ss);
  writeLogSheet_(ss, importState);
}

function writeSourceIndexSheet_(ss, importState) {
  const rows = Object.keys(GARMIN_IMPORT_CONFIG.sourceFiles).map(sourceKey => {
    const source = importState.sources[sourceKey] || {};
    return [
      sourceKey,
      GARMIN_IMPORT_CONFIG.sourceFiles[sourceKey].label,
      source.matchedFileName || '',
      source.status || 'NOT_CHECKED',
      source.mimeType || '',
      source.size || '',
      source.lastUpdated || ''
    ];
  });

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.sourceIndex, [
    'SourceKey',
    'ExpectedLabel',
    'MatchedFileName',
    'Status',
    'MimeType',
    'SizeBytes',
    'LastUpdated'
  ], rows);
}

function writeRawSheets_(ss, importState) {
  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.rawJson, [
    'SourceKey',
    'SourceFile',
    'Path',
    'Key',
    'Index',
    'Type',
    'Status',
    'Error',
    'Value'
  ], importState.rawJsonRows);

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.rawKeyValue, [
    'SourceKey',
    'SourceFile',
    'LineNumber',
    'Key',
    'Value',
    'Status',
    'Error'
  ], importState.rawKeyValueRows);
}

function writeSummarySheet_(ss, importState) {
  const rows = [
    ['Import Started', importState.startedAt],
    ['Import Finished', new Date()],
    ['Sources Found', Object.values(importState.sources).filter(s => s.status === 'FOUND').length],
    ['Sources Missing', Object.values(importState.sources).filter(s => s.status === 'MISSING').length],
    ['Exercise Catalog Rows', importState.parsed.exerciseCatalog.length],
    ['Exercise Equipment Rows', importState.parsed.exerciseEquipmentMap.length],
    ['Exercise Label Rows', importState.parsed.exerciseLabels.length],
    ['Exercise Master Rows', importState.parsed.exerciseMaster.length],
    ['Exercise Description Rows', importState.parsed.exerciseDescriptions.length],
    ['Exercise Tip Rows', importState.parsed.exerciseTips.length],
    ['Exercise Step Rows', importState.parsed.exerciseSteps.length],
    ['Workout Name Rows', importState.parsed.workoutNames.length],
    ['Workout Description Rows', importState.parsed.workoutDescriptions.length],
    ['Unit Rows', importState.parsed.units.length],
    ['Workout Property Rows', importState.parsed.workoutProperties.length],
    ['Log Rows', importState.logs.length]
  ];

  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.summary, ['Metric', 'Value'], rows);
}

function writeLogSheet_(ss, importState) {
  writeSheet_(ss, GARMIN_IMPORT_CONFIG.sheets.importLog, [
    'Timestamp',
    'Level',
    'Message',
    'SourceKey',
    'Details'
  ], importState.logs);
}

function writeSheet_(ss, sheetName, headers, rows) {
  const sheet = recreateManagedSheet_(ss, sheetName);

  const safeHeaders = headers || [];
  const safeRows = normalizeRowsForHeaders_(rows || [], safeHeaders.length);

  const output = [safeHeaders].concat(safeRows);

  if (output.length > 0 && safeHeaders.length > 0) {
    sheet.getRange(1, 1, output.length, safeHeaders.length).setValues(output);
  }

  sheet.setFrozenRows(1);

  if (output.length > 1) {
    const range = sheet.getRange(1, 1, output.length, safeHeaders.length);
    try {
      range.createFilter();
    } catch (err) {
      // Ignore filter creation failures.
    }
  }

  autoResizeSafe_(sheet, safeHeaders.length);
}


function normalizeRowsForHeaders_(rows, columnCount) {
  return (rows || []).map(row => {
    const safeRow = Array.isArray(row) ? row.slice() : [row];

    while (safeRow.length < columnCount) {
      safeRow.push('');
    }

    if (safeRow.length > columnCount) {
      return safeRow.slice(0, columnCount);
    }

    return safeRow;
  });
}


function recreateManagedSheet_(ss, sheetName) {
  const existing = ss.getSheetByName(sheetName);

  if (existing) {
    if (GARMIN_IMPORT_CONFIG.archiveExistingManagedSheets) {
      archiveSheet_(ss, existing, sheetName);
    } else {
      existing.clear();
      return existing;
    }
  }

  return ss.insertSheet(sheetName);
}

function archiveSheet_(ss, sheet, originalName) {
  const timestamp = Utilities.formatDate(
    new Date(),
    Session.getScriptTimeZone(),
    'yyyyMMdd_HHmmss'
  );

  const base = originalName + '__archive_' + timestamp;
  let archiveName = base.slice(0, 99);
  let i = 1;

  while (ss.getSheetByName(archiveName)) {
    archiveName = (base + '_' + i).slice(0, 99);
    i++;
  }

  sheet.setName(archiveName);
}

function addFormulasAndFormatting_(ss) {
  const exerciseMaster = ss.getSheetByName(GARMIN_IMPORT_CONFIG.sheets.exerciseMaster);
  if (exerciseMaster) {
    exerciseMaster.autoResizeColumns(1, 12);
  }

  const summary = ss.getSheetByName(GARMIN_IMPORT_CONFIG.sheets.summary);
  if (summary) {
    summary.getRange('A:A').setFontWeight('bold');
    summary.autoResizeColumns(1, 2);
  }
}

function flattenJson_(value, path) {
  path = path || '$';

  const rows = [];

  if (Array.isArray(value)) {
    value.forEach((item, index) => {
      const childPath = path + '[' + index + ']';
      rows.push({
        path,
        key: '',
        index,
        type: getType_(item),
        value: isPrimitive_(item) ? item : ''
      });
      rows.push.apply(rows, flattenJson_(item, childPath));
    });
    return rows;
  }

  if (value && typeof value === 'object') {
    Object.keys(value).forEach(key => {
      const item = value[key];
      const childPath = path + '.' + key;

      rows.push({
        path,
        key,
        index: '',
        type: getType_(item),
        value: isPrimitive_(item) ? item : ''
      });

      if (!isPrimitive_(item)) {
        rows.push.apply(rows, flattenJson_(item, childPath));
      }
    });
    return rows;
  }

  rows.push({
    path,
    key: '',
    index: '',
    type: getType_(value),
    value
  });

  return rows;
}

function classifyKeyNamespace_(key) {
  if (!key) return '';

  if (key.indexOf('exercise_description_') === 0) return 'EXERCISE_DESCRIPTION';
  if (key.indexOf('workout_name_') === 0) return 'WORKOUT_NAME';
  if (key.indexOf('workout_description_') === 0) return 'WORKOUT_DESCRIPTION';
  if (key.indexOf('description_') === 0) return 'WORKOUT_DESCRIPTION';
  if (key.indexOf('exercise_type_') === 0) return 'EXERCISE_TYPE';
  if (key.indexOf('category_type_') === 0) return 'CATEGORY_TYPE';
  if (key.indexOf('muscle_type_') === 0) return 'MUSCLE_TYPE';
  if (/_tip_\d+$/.test(key)) return 'TIP';
  if (/_step_\d+$/.test(key)) return 'STEP';
  if (key.indexOf('label_') === 0) return 'LABEL';
  if (key.indexOf('workout.') === 0) return 'WORKOUT_UI';
  if (key.indexOf('workout_') === 0) return 'WORKOUT';
  return 'OTHER';
}

function makeExerciseUid_(categoryKey, exerciseKey) {
  return categoryKey + '::' + exerciseKey;
}

function arrToCsv_(arr) {
  if (!arr) return '';
  if (!Array.isArray(arr)) return String(arr);
  return arr.filter(v => v !== '').join(', ');
}

function stringifyCell_(value) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function getType_(value) {
  if (Array.isArray(value)) return 'array';
  if (value === null) return 'null';
  return typeof value;
}

function isPrimitive_(value) {
  return value === null || ['string', 'number', 'boolean', 'undefined'].indexOf(typeof value) !== -1;
}

function normalizeKey_(key) {
  return String(key || '').trim().toUpperCase().replace(/[^A-Z0-9]+/g, '_');
}

function toTitleCase_(key) {
  return String(key || '')
    .toLowerCase()
    .split('_')
    .filter(Boolean)
    .map(part => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function decodeHtml_(text) {
  if (!text) return '';

  return String(text)
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ');
}

function log_(importState, level, message, sourceKey, details) {
  importState.logs.push([
    new Date(),
    level,
    message,
    sourceKey || '',
    details || ''
  ]);
}

function errToString_(err) {
  if (!err) return '';
  return err.stack || err.message || String(err);
}

function autoResizeSafe_(sheet, colCount) {
  try {
    if (colCount > 0) sheet.autoResizeColumns(1, colCount);
  } catch (err) {
    // Ignore resize errors for very large sheets.
  }
}