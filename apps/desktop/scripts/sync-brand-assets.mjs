"use strict"

/**
 * Keeps renderer brand assets in sync with apps/desktop/assets/icon.png before
 * vite build. Taskbar/window icons come from icon.ico (rcedit); in-app UI
 * (install overlay, About, updates) reads public/apple-touch-icon.png.
 */

import { copyFileSync, existsSync, mkdirSync } from "fs"
import { join, resolve } from "path"

const DESKTOP_ROOT = resolve(import.meta.dirname, "..")
const ICON_PNG = join(DESKTOP_ROOT, "assets", "icon.png")
const PUBLIC_DIR = join(DESKTOP_ROOT, "public")
const TOUCH_ICON = join(PUBLIC_DIR, "apple-touch-icon.png")

function main() {
  if (!existsSync(ICON_PNG)) {
    console.warn("[sync-brand-assets] skip: missing assets/icon.png")
    return
  }

  mkdirSync(PUBLIC_DIR, { recursive: true })
  copyFileSync(ICON_PNG, TOUCH_ICON)
  console.log("[sync-brand-assets] public/apple-touch-icon.png <- assets/icon.png")
}

main()
