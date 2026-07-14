#!/usr/bin/env node
// Dev/source launcher: stamp the local Electron binary (Windows) then exec it.
// Replaces bare `electron .` so the taskbar icon matches packaged builds.

import { spawn } from 'node:child_process'
import { resolve } from 'node:path'

import { ensureDevElectronIcon, DEV_APP_USER_MODEL_ID } from './ensure-dev-electron-icon.mjs'
import { isMain } from './utils.mjs'

const DESKTOP_ROOT = resolve(import.meta.dirname, '..')

export async function launchElectron(argv = process.argv.slice(2)) {
  const electronExe = await ensureDevElectronIcon()
  const args = argv.length > 0 ? argv : ['.']

  const code = await new Promise((resolvePromise, reject) => {
    const child = spawn(electronExe, args, {
      cwd: DESKTOP_ROOT,
      env: {
        ...process.env,
        HERMES_DESKTOP_APP_USER_MODEL_ID: DEV_APP_USER_MODEL_ID
      },
      stdio: 'inherit',
      windowsHide: false
    })

    child.on('error', reject)
    child.on('exit', (exitCode, signal) => {
      if (signal) {
        process.kill(process.pid, signal)
        return
      }
      resolvePromise(exitCode ?? 0)
    })
  })

  return code
}

if (isMain(import.meta.url)) {
  launchElectron()
    .then(code => process.exit(code))
    .catch(err => {
      console.error(`[launch-electron] ${err.message}`)
      process.exit(1)
    })
}
