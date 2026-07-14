#!/usr/bin/env node
// Windows dev/source launches run a stamped Hermes-dev.exe copy plus a Start
// Menu shortcut (ASCII AppUserModelID + icon.ico). Patching electron.exe alone
// is not enough: non-ASCII install paths break process.execPath AUMIDs, and
// Windows caches the stock Electron taskbar icon for electron.exe.

import { createRequire } from 'node:module'
import { copyFileSync, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { spawnSync } from 'node:child_process'

import { stampExeIdentity } from './set-exe-identity.mjs'
import { isMain } from './utils.mjs'

const require = createRequire(import.meta.url)
const DESKTOP_ROOT = resolve(import.meta.dirname, '..')
const ICON_PATH = join(DESKTOP_ROOT, 'assets', 'icon.ico')
const STAMP_PATH = join(DESKTOP_ROOT, '.cache', 'dev-electron-stamp.json')
const DEV_EXE_NAME = 'Hermes-dev.exe'
export const DEV_APP_USER_MODEL_ID = 'com.nousresearch.hermes.dev'

function resolveElectronExecutable() {
  try {
    const exe = require('electron')
    if (typeof exe === 'string' && existsSync(exe)) {
      return exe
    }
  } catch {
    // Fall through to a direct path probe.
  }

  const fallback = join(DESKTOP_ROOT, 'node_modules', 'electron', 'dist', 'electron.exe')
  if (existsSync(fallback)) {
    return fallback
  }

  throw new Error(
    'Electron executable not found. Run `npm install` in the repo root first.'
  )
}

function readStampRecord() {
  if (!existsSync(STAMP_PATH)) {
    return null
  }

  try {
    return JSON.parse(readFileSync(STAMP_PATH, 'utf8'))
  } catch {
    return null
  }
}

function writeStampRecord(record) {
  mkdirSync(join(DESKTOP_ROOT, '.cache'), { recursive: true })
  writeFileSync(STAMP_PATH, `${JSON.stringify(record, null, 2)}\n`, 'utf8')
}

function ensureDevExecutableCopy(electronExe) {
  const devExe = join(dirname(electronExe), DEV_EXE_NAME)
  const srcStat = statSync(electronExe)

  if (!existsSync(devExe)) {
    copyFileSync(electronExe, devExe)
    return devExe
  }

  const devStat = statSync(devExe)
  if (srcStat.mtimeMs > devStat.mtimeMs || srcStat.size !== devStat.size) {
    copyFileSync(electronExe, devExe)
  }

  return devExe
}

function needsRefresh(devExe, electronExe) {
  if (!existsSync(ICON_PATH)) {
    console.warn('[ensure-dev-electron-icon] skip: missing assets/icon.ico')
    return false
  }

  const iconStat = statSync(ICON_PATH)
  const devStat = statSync(devExe)
  const electronStat = statSync(electronExe)
  const previous = readStampRecord()

  if (!previous) {
    return true
  }

  return (
    previous.devExe !== devExe ||
    previous.iconMtimeMs !== iconStat.mtimeMs ||
    previous.devExeMtimeMs !== devStat.mtimeMs ||
    previous.electronExeMtimeMs !== electronStat.mtimeMs
  )
}

function ensureDevWindowsShortcut(devExe) {
  const ps1 = join(DESKTOP_ROOT, 'scripts', 'ensure-dev-windows-shortcut.ps1')
  const result = spawnSync(
    'powershell.exe',
    [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      ps1,
      '-TargetPath',
      devExe,
      '-WorkingDirectory',
      DESKTOP_ROOT,
      '-IconLocation',
      `${ICON_PATH},0`,
      '-AppId',
      DEV_APP_USER_MODEL_ID
    ],
    { stdio: 'inherit', windowsHide: true }
  )

  if (result.status !== 0) {
    console.warn(
      `[ensure-dev-electron-icon] shortcut setup exited ${result.status ?? 'unknown'}; continuing with Hermes-dev.exe`
    )
  }
}

export async function ensureDevElectronIcon() {
  const electronExe = resolveElectronExecutable()

  if (process.platform !== 'win32') {
    return electronExe
  }

  const devExe = ensureDevExecutableCopy(electronExe)

  if (!needsRefresh(devExe, electronExe)) {
    return devExe
  }

  console.log('[ensure-dev-electron-icon] preparing Hermes-dev.exe for taskbar icon...')
  await stampExeIdentity(devExe, DESKTOP_ROOT)
  ensureDevWindowsShortcut(devExe)

  const iconStat = statSync(ICON_PATH)
  const devStat = statSync(devExe)
  const electronStat = statSync(electronExe)
  writeStampRecord({
    devExe,
    electronExe,
    iconMtimeMs: iconStat.mtimeMs,
    devExeMtimeMs: devStat.mtimeMs,
    electronExeMtimeMs: electronStat.mtimeMs,
    appUserModelId: DEV_APP_USER_MODEL_ID,
    stampedAt: new Date().toISOString()
  })

  return devExe
}

if (isMain(import.meta.url)) {
  ensureDevElectronIcon()
    .then(exe => {
      console.log(exe)
    })
    .catch(err => {
      console.error(`[ensure-dev-electron-icon] ${err.message}`)
      process.exit(1)
    })
}
