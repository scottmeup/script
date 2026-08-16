/*
File role:
- Single-file end-to-end scraper for Amazon Alexa voice history using Playwright.
- Combines the prior Playwright login flow, utterance cleanup, and recognized-speech extraction into one script.
- Opens TARGET_URL with a persistent Chromium/Chrome profile, handles Amazon email/password re-authentication, prompts for MFA/TOTP in the terminal when required, optionally checks "Don't require code on this browser", scrapes Alexa history rows, normalizes date/device metadata, strips configured wake words from the recognized speech, and writes JSON/CSV/screenshot outputs.
- Does not store MFA/TOTP and does not write password or OTP values to diagnostics.
- Stops on CAPTCHA, passkey-only/app-approval/manual challenge pages, Amazon error pages, or pages that do not reach Alexa history content.

Inputs:
- .env file: optional key-value text file in current working directory. Lines use KEY=VALUE format. Blank lines and lines beginning with # are ignored. Used by loadDotEnvFile().
- TARGET_URL: required string URL to scrape. Recommended: https://www.amazon.com.au/alexa-privacy/apd/rvh. Used by main().
- CHROME_PROFILE_DIR: optional persistent browser profile directory. Defaults to ./chrome-amazon-profile. Used by main().
- HEADLESS: optional boolean-like string. Defaults to true. Used by main().
- CHROME_EXECUTABLE_PATH: optional Chrome or Chromium executable path. If omitted, Playwright uses installed Chromium. Used by main().
- AMAZON_EMAIL: required if the visible email textbox appears. Used by loginIfNeeded(). Redacted in diagnostics.
- AMAZON_PASSWORD: required if the visible Password textbox appears. Used by loginIfNeeded(). Never written to diagnostics.
- PROMPT_FOR_MFA: optional boolean-like string. Defaults to true. When true, asks for MFA/TOTP in terminal if required. Used by loginIfNeeded().
- CHECK_DONT_REQUIRE_MFA: optional boolean-like string. Defaults to true. When true, checks Amazon's "Don't require code on this" checkbox if visible. Used by loginIfNeeded().
- STRIP_WAKE_WORD: optional boolean-like value. Defaults to true. When true, strips configured wake words from the start of recognized speech while preserving original recognized speech. Used by stripWakeWord().
- WAKE_WORDS: optional comma-separated string list of wake words. Defaults to alexa,echo,amazon,computer,ziggy. Used by parseWakeWords().
- WAIT_MS: optional non-negative integer wait after initial navigation. Defaults to 5000. Used by main().
- AUTH_WAIT_MS: optional non-negative integer wait after each auth submit. Defaults to 7000. Used by loginIfNeeded().
- SCROLL_ROUNDS: optional non-negative integer scroll rounds. Defaults to 16. Used by scrollForLazyContent().
- SCROLL_DELAY_MS: optional non-negative integer delay between scroll rounds. Defaults to 800. Used by scrollForLazyContent().
- MAX_AUTH_STEPS: optional positive integer maximum authentication steps. Defaults to 5. Used by loginIfNeeded().
- VIEWPORT_WIDTH: optional positive integer viewport width. Defaults to 1366. Used by main().
- VIEWPORT_HEIGHT: optional positive integer viewport height. Defaults to 768. Used by main().
- OUTPUT_BASENAME: optional basename for generated outputs. Defaults to alexa-speech. Used by writeOutputs().

Outputs:
- <OUTPUT_BASENAME>-full.json: complete scraper output equivalent to the combined scraper diagnostic/output object. Created by writeOutputs().
- <OUTPUT_BASENAME>-speech.json: extracted-speech JSON matching the top-level output contract from extract-alexa-recognized-speech-v4.js. Created by writeOutputs().
- <OUTPUT_BASENAME>-speech.csv: extracted-speech CSV matching extract-alexa-recognized-speech-v4.js. Created by writeOutputs().
- <OUTPUT_BASENAME>.png: screenshot of final page when supported. Created by safeScreenshot().
- Console JSON summary containing success flag, latest recognized speech, recognized speech list, output paths, counts, auth verdict, and page state. Created by main().

Functions:
- loadDotEnvFile(filePath): reads .env values without external dependencies.
- envValue(name, fallback): returns process.env value first, then .env file value, then fallback.
- requiredEnv(name): validates and returns a required value from process.env or .env file.
- boolEnv(name, fallback): parses a boolean-like environment value.
- intEnv(name, fallback, minimum): parses a bounded integer-like environment value.
- sleep(ms): waits for a specified number of milliseconds.
- ask(question): prompts the operator for terminal input.
- redactedEmail(email): masks an email or phone-like identifier for diagnostics.
- parseWakeWords(value): parses configured wake words.
- getState(page): extracts URL, title, login/MFA/challenge/error/target-content indicators, and body preview.
- classifyState(state): maps page state to target_reached, email_required, password_required, mfa_required, manual_challenge_required, amazon_error, or unknown.
- loginIfNeeded(page, config): reproduces the working Playwright login flow using role locators for email, password, MFA code, buttons, and target-page validation.
- scrollForLazyContent(page, rounds, delayMs): scrolls to load lazy content.
- parseSectionMeta(text): parses activity date, user, and device from Alexa section metadata.
- closestSectionMeta(row): finds the closest date/device section metadata for an utterance row.
- extractUtteranceRecords(page): extracts row-level utterance records and cleaned activity metadata.
- isIgnoredRecognizedRecord(record): filters non-user-speech records.
- stripWakeWord(text, wakeWords, enabled): removes a configured wake word from the start of recognized speech and reports the detected wake word.
- toRecognizedRecord(record, wakeWords, stripWakeWords): maps one clean utterance record to the recognized speech schema.
- buildRecognizedSpeechPayload(cleanRecords, config): creates latest speech, speech lists, recognized records, and ignored records.
- csvEscape(value): escapes one CSV field.
- writeOutputs(baseName, payload): writes JSON and CSV outputs.
- safeScreenshot(page, filePath): captures a screenshot without failing if unavailable.
- main(): loads config, launches persistent context, navigates, handles auth, scrapes, normalizes, writes outputs, and exits.
*/

const fs = require('node:fs/promises');
const path = require('node:path');
const readline = require('node:readline/promises');
const { stdin: input, stdout: output } = require('node:process');
const { chromium } = require('playwright');

let envFileValues = {};

async function loadDotEnvFile(filePath) {
  try {
    const raw = await fs.readFile(filePath, 'utf8');
    const parsed = {};
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const equalsIndex = trimmed.indexOf('=');
      if (equalsIndex === -1) continue;
      const key = trimmed.slice(0, equalsIndex).trim();
      let value = trimmed.slice(equalsIndex + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
      if (key) parsed[key] = value;
    }
    return parsed;
  } catch (error) {
    if (error.code === 'ENOENT') return {};
    throw error;
  }
}

function envValue(name, fallback) {
  if (process.env[name] && process.env[name].trim()) return process.env[name].trim();
  if (envFileValues[name] && envFileValues[name].trim()) return envFileValues[name].trim();
  return fallback;
}

function requiredEnv(name) {
  const value = envValue(name, '');
  if (!value || !value.trim()) throw new Error(`Missing required environment variable or .env entry: ${name}`);
  return value.trim();
}

function boolEnv(name, fallback) {
  const value = envValue(name, '');
  if (!value || !value.trim()) return fallback;
  return ['1', 'true', 'yes', 'y', 'on'].includes(value.trim().toLowerCase());
}

function intEnv(name, fallback, minimum = 0) {
  const value = envValue(name, '');
  if (!value || !value.trim()) return fallback;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < minimum) throw new Error(`${name} must be an integer greater than or equal to ${minimum}`);
  return parsed;
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function ask(question) {
  const rl = readline.createInterface({ input, output });
  try {
    return await rl.question(question);
  } finally {
    rl.close();
  }
}

function redactedEmail(email) {
  const value = String(email || '');
  const at = value.indexOf('@');
  if (at > 1) return `${value.slice(0, 2)}***${value.slice(at)}`;
  if (value.length > 4) return `${value.slice(0, 2)}***${value.slice(-2)}`;
  return value ? '***' : '';
}

function normalise(text) {
  return String(text || '').replace(/\s+/g, ' ').trim();
}

function parseWakeWords(value) {
  return String(value || '')
    .split(',')
    .map((part) => normalise(part).toLowerCase())
    .filter(Boolean)
    .sort((a, b) => b.length - a.length);
}

async function getState(page) {
  const bodyText = await page.locator('body').innerText({ timeout: 5000 }).catch(() => '');
  const compactBodyText = normalise(bodyText);
  const lowerBodyText = compactBodyText.toLowerCase();
  const title = await page.title().catch(() => '');
  const url = page.url();

  const hasEmailInput = await page.getByRole('textbox', { name: /Enter mobile number or email/i }).isVisible().catch(() => false) || await page.locator('input#ap_email_login, input#ap_email, input[name="email"]').first().isVisible().catch(() => false);
  const hasPasswordInput = await page.getByRole('textbox', { name: /^Password$/i }).isVisible().catch(() => false) || await page.locator('input#ap_password, input[name="password"]').first().isVisible().catch(() => false);
  const hasMfaInput = await page.getByRole('textbox', { name: /Enter code/i }).isVisible().catch(() => false) || await page.locator('input#auth-mfa-otpcode, input[name="otpCode"], input[name="code"], input[id*="otp" i]').first().isVisible().catch(() => false);
  const hasUtterances = await page.locator('.utterance-title, .utterance-row').count().then((count) => count > 0).catch(() => false);
  const hasAlexaHistoryText = lowerBodyText.includes('review alexa history') || lowerBodyText.includes('review voice history') || lowerBodyText.includes('displaying:last 7 days') || lowerBodyText.includes('displaying: last 7 days');
  const hasCaptchaOrChallenge = lowerBodyText.includes('captcha') || lowerBodyText.includes('enter the characters') || lowerBodyText.includes('approve the notification') || lowerBodyText.includes('verify your identity');
  const hasPasskeyOnly = lowerBodyText.includes('sign in with a passkey') && !hasPasswordInput;
  const hasAmazonError = compactBodyText.includes("We're sorry") || compactBodyText.includes('An error occurred when we tried to process your request') || title.includes('500 - An error occurred');

  return { url, title, hasEmailInput, hasPasswordInput, hasMfaInput, hasUtterances, hasAlexaHistoryText, hasCaptchaOrChallenge, hasPasskeyOnly, hasAmazonError, bodyPreview: compactBodyText.slice(0, 900) };
}

function classifyState(state) {
  if (state.hasAmazonError) return 'amazon_error';
  if (state.hasMfaInput) return 'mfa_required';
  if (state.hasPasswordInput) return 'password_required';
  if (state.hasEmailInput) return 'email_required';
  if (state.hasCaptchaOrChallenge || state.hasPasskeyOnly) return 'manual_challenge_required';
  if (state.hasUtterances || state.hasAlexaHistoryText) return 'target_reached';
  return 'unknown';
}

async function loginIfNeeded(page, config) {
  const steps = [];

  for (let attempt = 1; attempt <= config.maxAuthSteps; attempt += 1) {
    const state = await getState(page);
    const verdict = classifyState(state);
    steps.push({ attempt, event: 'state', verdict, state });

    if (['target_reached', 'amazon_error', 'manual_challenge_required', 'unknown'].includes(verdict)) break;

    if (verdict === 'email_required') {
      if (!config.amazonEmail) throw new Error('Email field is visible but AMAZON_EMAIL is not set.');
      const emailBox = page.getByRole('textbox', { name: /Enter mobile number or email/i });
      await emailBox.fill(config.amazonEmail);
      await emailBox.press('Enter').catch(async () => page.getByRole('button', { name: /^Continue$/i }).click());
      steps.push({ attempt, event: 'email_submit', redactedEmail: redactedEmail(config.amazonEmail), method: 'role_textbox_enter_or_continue' });
      await sleep(config.authWaitMs);
      continue;
    }

    if (verdict === 'password_required') {
      if (!config.amazonPassword) throw new Error('Password field is visible but AMAZON_PASSWORD is not set.');
      const passwordBox = page.getByRole('textbox', { name: /^Password$/i });
      await passwordBox.fill(config.amazonPassword);
      await page.getByRole('button', { name: /^Sign-In$/i }).click().catch(async () => passwordBox.press('Enter'));
      steps.push({ attempt, event: 'password_submit', passwordProvided: true, method: 'role_password_signin_or_enter' });
      await sleep(config.authWaitMs);
      continue;
    }

    if (verdict === 'mfa_required') {
      if (!config.promptForMfa) break;

      const checkbox = page.getByRole('checkbox', { name: /Don't require code on this/i });
      if (config.checkDontRequireMfa && await checkbox.isVisible().catch(() => false)) {
        await checkbox.check().catch(() => undefined);
        steps.push({ attempt, event: 'mfa_remember_device_checked' });
      }

      const otp = (await ask('Enter Amazon MFA/TOTP code, then press Enter: ')).trim();
      if (!otp) throw new Error('MFA/TOTP was required but no code was entered.');
      const codeBox = page.getByRole('textbox', { name: /Enter code/i });
      await codeBox.fill(otp);
      await page.getByRole('button', { name: /^Sign in$/i }).click().catch(async () => codeBox.press('Enter'));
      steps.push({ attempt, event: 'mfa_submit', otpProvided: true, otpLength: otp.length, method: 'role_code_signin_or_enter' });
      await sleep(config.authWaitMs);
      continue;
    }
  }

  const finalState = await getState(page);
  return { finalVerdict: classifyState(finalState), finalState, steps };
}

async function scrollForLazyContent(page, rounds, delayMs) {
  for (let round = 0; round < rounds; round += 1) {
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight || document.documentElement.scrollHeight || 0));
    await sleep(delayMs);
  }
  await page.evaluate(() => window.scrollTo(0, 0));
  await sleep(delayMs);
}

function parseSectionMeta(text) {
  const source = normalise(text);
  const prefix = normalise(source.split('⋮')[0] || source);
  const parts = prefix.split('•').map((part) => normalise(part)).filter(Boolean);
  const result = { activityHeader: prefix, activityDate: '', activityUser: '', activityDevice: '' };
  if (parts.length > 0) result.activityDate = parts[0];
  if (parts.length === 2) result.activityDevice = parts[1];
  if (parts.length >= 3) {
    result.activityUser = parts[1];
    result.activityDevice = parts.slice(2).join(' • ');
  }
  return result;
}

function csvEscape(value) {
  const text = value === null || value === undefined ? '' : String(value);
  return `"${text.replace(/"/g, '""')}"`;
}

async function extractUtteranceRecords(page) {
  return page.evaluate(() => {
    function normaliseLocal(text) { return String(text || '').replace(/\s+/g, ' ').trim(); }
    function visibleText(element) { return element ? normaliseLocal(element.innerText || element.textContent || '') : ''; }
    function attr(element, name) { return element ? normaliseLocal(element.getAttribute(name) || '') : ''; }
    function isActivityHeader(text) { return /^Activity on\b/i.test(normaliseLocal(text)); }
    function queryFirst(row, selectors) { for (const selector of selectors) { const element = row.querySelector(selector); if (element) return element; } return null; }
    function parseSectionMetaLocal(text) {
      const source = normaliseLocal(text);
      const prefix = normaliseLocal(source.split('⋮')[0] || source);
      const parts = prefix.split('•').map((part) => normaliseLocal(part)).filter(Boolean);
      const result = { activityHeader: prefix, activityDate: '', activityUser: '', activityDevice: '' };
      if (parts.length > 0) result.activityDate = parts[0];
      if (parts.length === 2) result.activityDevice = parts[1];
      if (parts.length >= 3) { result.activityUser = parts[1]; result.activityDevice = parts.slice(2).join(' • '); }
      return result;
    }
    function closestSectionMeta(row) {
      const section = row.closest('.date-section');
      if (!section) return { activityHeader: '', activityDate: '', activityUser: '', activityDevice: '' };
      const rowText = visibleText(row);
      const sectionText = visibleText(section);
      const beforeRow = rowText && sectionText.includes(rowText) ? sectionText.slice(0, sectionText.indexOf(rowText)) : sectionText;
      const candidate = beforeRow && beforeRow.includes('⋮') ? beforeRow : sectionText;
      return parseSectionMetaLocal(candidate);
    }

    const diagnostics = {
      utteranceRowCount: document.querySelectorAll('.utterance-row').length,
      utteranceTitleCount: document.querySelectorAll('.utterance-title').length,
      dateSectionCount: document.querySelectorAll('.date-section').length,
      rejectedActivityHeaderCount: 0,
      rejectedDuplicateCount: 0
    };

    const rows = Array.from(document.querySelectorAll('.utterance-row'));
    const rawRecords = [];

    for (const element of rows) {
      const rawText = visibleText(element);
      const titleElement = element.querySelector('.utterance-title') || queryFirst(element, ['[class*="title"]']);
      const title = visibleText(titleElement) || rawText;
      if (isActivityHeader(title) && normaliseLocal(rawText) === normaliseLocal(title)) {
        diagnostics.rejectedActivityHeaderCount += 1;
        continue;
      }

      const timeElement = queryFirst(element, ['time', '[datetime]', '[class*="date"]', '[class*="time"]', '[data-testid*="date"]', '[data-testid*="time"]']);
      const deviceElement = queryFirst(element, ['[class*="device"]', '[data-testid*="device"]', '[aria-label*="device" i]']);
      const sectionMeta = closestSectionMeta(element);
      const explicitDevice = deviceElement ? visibleText(deviceElement) || attr(deviceElement, 'aria-label') : '';
      const responseText = normaliseLocal(rawText.startsWith(title) ? rawText.slice(title.length) : '');

      rawRecords.push({
        sourceIndex: rawRecords.length + 1,
        utterance: title,
        activityHeader: sectionMeta.activityHeader,
        activityDate: sectionMeta.activityDate,
        activityUser: sectionMeta.activityUser,
        activityDevice: sectionMeta.activityDevice,
        datetime: timeElement ? attr(timeElement, 'datetime') : '',
        timeText: timeElement ? visibleText(timeElement) : sectionMeta.activityDate,
        device: explicitDevice || sectionMeta.activityDevice,
        responseText,
        rawText,
        rowClass: attr(element, 'class'),
        rowId: attr(element, 'id')
      });
    }

    const seen = new Set();
    const records = [];
    for (const record of rawRecords) {
      const key = [record.utterance, record.activityHeader, record.rawText].join('|');
      if (seen.has(key)) { diagnostics.rejectedDuplicateCount += 1; continue; }
      seen.add(key);
      records.push({ ...record, index: records.length + 1 });
    }
    return { records, diagnostics };
  });
}

function isIgnoredRecognizedRecord(record) {
  const utterance = normalise(record.utterance).toLowerCase();
  const rawText = normalise(record.rawText).toLowerCase();
  if (!utterance && !rawText) return true;
  if (utterance === 'audio was not intended for this device') return true;
  if (rawText === 'audio was not intended for this device') return true;
  if (/^activity on\b/i.test(utterance)) return true;
  if (/^activity on\b/i.test(rawText)) return true;
  return false;
}

function stripWakeWord(text, wakeWords, enabled) {
  const original = normalise(text);
  if (!enabled || !original) return { recognizedSpeech: original, wakeWordDetected: '' };
  const lower = original.toLowerCase();
  for (const wakeWord of wakeWords) {
    if (lower === wakeWord) return { recognizedSpeech: '', wakeWordDetected: wakeWord };
    if (lower.startsWith(`${wakeWord} `)) {
      return { recognizedSpeech: normalise(original.slice(wakeWord.length + 1)), wakeWordDetected: wakeWord };
    }
  }
  return { recognizedSpeech: original, wakeWordDetected: '' };
}

function toRecognizedRecord(record, wakeWords, stripWakeWords) {
  const recognizedSpeechOriginal = normalise(record.utterance);
  const normalization = stripWakeWord(recognizedSpeechOriginal, wakeWords, stripWakeWords);
  return {
    index: record.index ?? '',
    sourceIndex: record.sourceIndex ?? '',
    recognizedSpeech: normalization.recognizedSpeech,
    recognizedSpeechOriginal,
    wakeWordDetected: normalization.wakeWordDetected,
    responseText: normalise(record.responseText),
    activityDate: normalise(record.activityDate),
    activityUser: normalise(record.activityUser),
    activityDevice: normalise(record.activityDevice || record.device),
    device: normalise(record.device || record.activityDevice),
    timeText: normalise(record.timeText),
    datetime: normalise(record.datetime),
    rawText: normalise(record.rawText)
  };
}

function buildRecognizedSpeechPayload(cleanRecords, config) {
  const ignoredRecords = [];
  const recognizedSpeechRecords = [];
  const seenRecords = new Set();

  for (const record of cleanRecords) {
    if (isIgnoredRecognizedRecord(record)) {
      ignoredRecords.push(record);
      continue;
    }
    const mapped = toRecognizedRecord(record, config.wakeWords, config.stripWakeWords);
    if (!mapped.recognizedSpeech && !mapped.recognizedSpeechOriginal) {
      ignoredRecords.push(record);
      continue;
    }
    const duplicateKey = [mapped.recognizedSpeechOriginal, mapped.activityDate, mapped.activityDevice, mapped.rawText].join('|');
    if (seenRecords.has(duplicateKey)) continue;
    seenRecords.add(duplicateKey);
    recognizedSpeechRecords.push(mapped);
  }

  const recognizedSpeechList = recognizedSpeechRecords.map((record) => record.recognizedSpeech).filter(Boolean);
  const recognizedSpeechOriginalList = recognizedSpeechRecords.map((record) => record.recognizedSpeechOriginal).filter(Boolean);
  const latestRecognizedSpeech = recognizedSpeechRecords[0] || null;
  return {
    latestRecognizedSpeechText: latestRecognizedSpeech ? latestRecognizedSpeech.recognizedSpeech : '',
    latestRecognizedSpeechOriginalText: latestRecognizedSpeech ? latestRecognizedSpeech.recognizedSpeechOriginal : '',
    latestRecognizedSpeech,
    recognizedSpeechList,
    recognizedSpeechOriginalList,
    recognizedSpeechRecords,
    ignoredRecords
  };
}

async function writeOutputs(baseName, fullPayload, speechPayload) {
  const fullJsonPath = `${baseName}-full.json`;
  const speechJsonPath = `${baseName}-speech.json`;
  const speechCsvPath = `${baseName}-speech.csv`;

  speechPayload.outputPaths = {
    jsonPath: speechJsonPath,
    csvPath: speechCsvPath
  };

  fullPayload.outputFiles = {
    fullJson: fullJsonPath,
    speechJson: speechJsonPath,
    speechCsv: speechCsvPath,
    screenshot: `${baseName}.png`
  };

  await fs.writeFile(fullJsonPath, JSON.stringify(fullPayload, null, 2), 'utf8');
  await fs.writeFile(speechJsonPath, JSON.stringify(speechPayload, null, 2), 'utf8');

  const headers = ['index', 'sourceIndex', 'recognizedSpeech', 'recognizedSpeechOriginal', 'wakeWordDetected', 'responseText', 'activityDate', 'activityUser', 'activityDevice', 'device', 'timeText', 'datetime', 'rawText'];
  const lines = [headers.map(csvEscape).join(',')];
  for (const record of speechPayload.recognizedSpeechRecords) lines.push(headers.map((header) => csvEscape(record[header])).join(','));
  await fs.writeFile(speechCsvPath, `${lines.join('\n')}\n`, 'utf8');

  return { fullJsonPath, speechJsonPath, speechCsvPath };
}

async function safeScreenshot(page, filePath) {
  try {
    await page.screenshot({ path: filePath, fullPage: true });
    return { ok: true, path: filePath };
  } catch (error) {
    return { ok: false, path: filePath, error: error.message };
  }
}

async function main() {
  envFileValues = await loadDotEnvFile(path.resolve(process.cwd(), '.env'));
  const config = {
    targetUrl: requiredEnv('TARGET_URL'),
    profileDir: envValue('CHROME_PROFILE_DIR', './chrome-amazon-profile'),
    headless: boolEnv('HEADLESS', true),
    executablePath: envValue('CHROME_EXECUTABLE_PATH', ''),
    amazonEmail: envValue('AMAZON_EMAIL', ''),
    amazonPassword: envValue('AMAZON_PASSWORD', ''),
    promptForMfa: boolEnv('PROMPT_FOR_MFA', true),
    checkDontRequireMfa: boolEnv('CHECK_DONT_REQUIRE_MFA', true),
    stripWakeWords: boolEnv('STRIP_WAKE_WORD', true),
    wakeWords: parseWakeWords(envValue('WAKE_WORDS', 'alexa,echo,amazon,computer,ziggy')),
    waitMs: intEnv('WAIT_MS', 5000, 0),
    authWaitMs: intEnv('AUTH_WAIT_MS', 7000, 0),
    maxAuthSteps: intEnv('MAX_AUTH_STEPS', 5, 1),
    scrollRounds: intEnv('SCROLL_ROUNDS', 16, 0),
    scrollDelayMs: intEnv('SCROLL_DELAY_MS', 800, 0),
    viewportWidth: intEnv('VIEWPORT_WIDTH', 1366, 1),
    viewportHeight: intEnv('VIEWPORT_HEIGHT', 768, 1),
    outputBaseName: envValue('OUTPUT_BASENAME', 'alexa-speech')
  };

  const launchOptions = { headless: config.headless, viewport: { width: config.viewportWidth, height: config.viewportHeight }, args: ['--no-sandbox', '--disable-dev-shm-usage'] };
  if (config.executablePath) launchOptions.executablePath = config.executablePath;

  const context = await chromium.launchPersistentContext(config.profileDir, launchOptions);
  const page = context.pages()[0] || await context.newPage();
  const startedAt = new Date().toISOString();

  await page.goto(config.targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await sleep(config.waitMs);

  const authDiagnostics = await loginIfNeeded(page, config);
  if (authDiagnostics.finalVerdict !== 'target_reached') throw new Error(`Cannot scrape because auth verdict is ${authDiagnostics.finalVerdict}`);

  await page.getByText(/Review Alexa History/i).waitFor({ state: 'visible', timeout: 20000 }).catch(() => undefined);
  await page.locator('.utterance-row').first().waitFor({ state: 'visible', timeout: 20000 }).catch(() => undefined);
  await scrollForLazyContent(page, config.scrollRounds, config.scrollDelayMs);

  const finalState = await getState(page);
  if (classifyState(finalState) !== 'target_reached') throw new Error(`Cannot scrape because final page verdict is ${classifyState(finalState)}`);

  const extraction = await extractUtteranceRecords(page);
  const recognized = buildRecognizedSpeechPayload(extraction.records, config);
  const screenshot = await safeScreenshot(page, `${config.outputBaseName}.png`);

  const metadata = {
    startedAt,
    finishedAt: new Date().toISOString(),
    targetUrl: config.targetUrl,
    finalUrl: finalState.url,
    cleanUtteranceRecordCount: extraction.records.length,
    recognizedSpeechCount: recognized.recognizedSpeechRecords.length,
    ignoredRecordCount: recognized.ignoredRecords.length,
    scraper: 'alexa-speech-scraper-playwright-v4.js',
    promptForMfa: config.promptForMfa,
    checkDontRequireMfa: config.checkDontRequireMfa,
    stripWakeWords: config.stripWakeWords,
    wakeWords: config.wakeWords
  };

  const speechPayload = {
    ok: true,
    inputJson: 'live-playwright-scrape',
    outputPaths: {
      jsonPath: `${config.outputBaseName}-speech.json`,
      csvPath: `${config.outputBaseName}-speech.csv`
    },
    latestRecognizedSpeechText: recognized.latestRecognizedSpeechText,
    latestRecognizedSpeechOriginalText: recognized.latestRecognizedSpeechOriginalText,
    recognizedSpeechList: recognized.recognizedSpeechList,
    recognizedSpeechOriginalList: recognized.recognizedSpeechOriginalList,
    recognizedSpeechCount: recognized.recognizedSpeechRecords.length,
    ignoredRecordCount: recognized.ignoredRecords.length,
    stripWakeWords: config.stripWakeWords,
    wakeWords: config.wakeWords,
    latestRecognizedSpeech: recognized.latestRecognizedSpeech,
    recognizedSpeechRecords: recognized.recognizedSpeechRecords,
    ignoredRecords: recognized.ignoredRecords
  };

  const fullPayload = {
    metadata,
    pageState: finalState,
    authDiagnostics,
    extractionDiagnostics: extraction.diagnostics,
    cleanUtteranceRecords: extraction.records,
    latestRecognizedSpeechText: recognized.latestRecognizedSpeechText,
    latestRecognizedSpeechOriginalText: recognized.latestRecognizedSpeechOriginalText,
    latestRecognizedSpeech: recognized.latestRecognizedSpeech,
    recognizedSpeechList: recognized.recognizedSpeechList,
    recognizedSpeechOriginalList: recognized.recognizedSpeechOriginalList,
    recognizedSpeechRecords: recognized.recognizedSpeechRecords,
    ignoredRecords: recognized.ignoredRecords,
    outputFiles: {
      fullJson: `${config.outputBaseName}-full.json`,
      speechJson: `${config.outputBaseName}-speech.json`,
      speechCsv: `${config.outputBaseName}-speech.csv`,
      screenshot: `${config.outputBaseName}.png`
    }
  };

  const outputPaths = await writeOutputs(config.outputBaseName, fullPayload, speechPayload);
  await context.close();

  console.log(JSON.stringify({
    ...speechPayload,
    fullOutputPath: outputPaths.fullJsonPath,
    screenshot
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
