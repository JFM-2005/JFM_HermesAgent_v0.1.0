"use strict"

/**
 * Writes apps/desktop/build/install-stamp.json with the git ref the desktop
 * .exe should pin to at first-launch bootstrap time.  This file ships inside
 * the packaged app via electron-builder's extraResources entry and is read
 * by electron/main.ts to drive the install.ps1 stage bootstrap flow.
 *
 * Schema (subject to bump via STAMP_SCHEMA_VERSION):
 *   {
 *     "schemaVersion": 1,
 *     "commit":        "<40-char SHA>",
 *     "branch":        "<branch name>",
 *     "repository":    "<GitHub owner/repo>",
 *     "builtAt":       "<ISO 8601 UTC timestamp>",
 *     "dirty":         true|false,
 *     "source":        "ci" | "local"
 *   }
 */

import { mkdirSync, writeFileSync } from "fs"
import { resolve, join, relative } from "path"
import { execSync } from "child_process"

const STAMP_SCHEMA_VERSION = 1
const DEFAULT_REPOSITORY = "JFM-2005/JFM_HermesAgent_v0.1.0"
const DEFAULT_BRANCH = "master"

const DESKTOP_ROOT = resolve(import.meta.dirname, "..")
const REPO_ROOT = resolve(DESKTOP_ROOT, "..", "..")
const OUT_DIR = join(DESKTOP_ROOT, "build")
const OUT_FILE = join(OUT_DIR, "install-stamp.json")

function normalizeGitHubRepository(value) {
  if (!value) return null
  const raw = String(value).trim().replace(/^git\+/, "")
  if (/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(raw)) return raw.replace(/\.git$/i, "")
  const match = raw.match(/github\.com[/:]([^/]+)\/([^/#]+?)(?:\.git)?$/i)
  return match ? `${match[1]}/${match[2].replace(/\.git$/i, "")}` : null
}

function tryExec(cmd, opts) {
  try {
    return execSync(cmd, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], ...opts }).trim()
  } catch {
    return null
  }
}

function fromCI() {
  const sha = process.env.GITHUB_SHA
  if (!sha) return null
  const branch = process.env.GITHUB_REF_NAME || process.env.GITHUB_HEAD_REF || null
  return {
    commit: sha,
    branch: branch,
    repository:
      normalizeGitHubRepository(process.env.HERMES_BUILD_REPOSITORY) ||
      normalizeGitHubRepository(process.env.GITHUB_REPOSITORY) ||
      DEFAULT_REPOSITORY,
    dirty: false,
    source: "ci"
  }
}

function fromLocalGit() {
  const sha = tryExec("git rev-parse HEAD", { cwd: REPO_ROOT })
  if (!sha) return null
  const branch = tryExec("git rev-parse --abbrev-ref HEAD", { cwd: REPO_ROOT })
  const status = tryExec("git status --porcelain -uno", { cwd: REPO_ROOT })
  const repository =
    normalizeGitHubRepository(process.env.HERMES_BUILD_REPOSITORY) ||
    normalizeGitHubRepository(tryExec("git remote get-url origin", { cwd: REPO_ROOT })) ||
    DEFAULT_REPOSITORY
  const dirty = status !== null && status.length > 0
  return {
    commit: sha,
    branch: branch === "HEAD" ? null : branch,
    repository,
    dirty: dirty,
    source: "local"
  }
}

function main() {
  const stamp = fromCI() || fromLocalGit()
  if (stamp && !stamp.repository) {
    stamp.repository = DEFAULT_REPOSITORY
  }
  if (!stamp || !stamp.commit || !stamp.repository) {
    console.error(
      "[write-build-stamp] ERROR: could not determine git commit and repository.\n" +
        "  Run from a git checkout with origin remote, or set $GITHUB_SHA and $HERMES_BUILD_REPOSITORY."
    )
    process.exit(1)
  }

  if (stamp.dirty) {
    console.warn(
      "[write-build-stamp] WARNING: working tree is dirty.\n" +
        "  Pinning to " +
        stamp.commit.slice(0, 12) +
        " but the packaged code may differ from that commit."
    )
  }

  const payload = {
    schemaVersion: STAMP_SCHEMA_VERSION,
    commit: stamp.commit,
    branch: stamp.branch || DEFAULT_BRANCH,
    repository: stamp.repository,
    builtAt: new Date().toISOString(),
    dirty: stamp.dirty,
    source: stamp.source
  }

  mkdirSync(OUT_DIR, { recursive: true })
  writeFileSync(OUT_FILE, JSON.stringify(payload, null, 2) + "\n", "utf8")
  console.log(
    "[write-build-stamp] wrote " +
      relative(REPO_ROOT, OUT_FILE) +
      " -> " +
      stamp.commit.slice(0, 12) +
      (stamp.branch ? " (" + stamp.branch + ")" : "") +
      " from " +
      stamp.repository +
      (stamp.dirty ? " [DIRTY]" : "")
  )
}

main()
