import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import type { ContentManifest } from "./types.js";

// The "database" is just the content/ directory, committed to git by the
// GitHub Actions workflow after each script runs. A CDN in front of the
// public repo (jsDelivr) serves it to the app — no server, no Firestore.
export const CONTENT_ROOT = fileURLToPath(new URL("../../content/", import.meta.url));

export function readJson<T>(relPath: string, fallback: T): T {
  const full = join(CONTENT_ROOT, relPath);
  if (!existsSync(full)) return fallback;
  return JSON.parse(readFileSync(full, "utf-8")) as T;
}

export function writeJson(relPath: string, data: unknown): void {
  const full = join(CONTENT_ROOT, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, JSON.stringify(data, null, 2) + "\n");
}

const EMPTY_MANIFEST: ContentManifest = {
  evergreenVersion: 0,
  dailyDates: [],
  videosVersion: 0,
  externalGamesVersion: 0,
  updatedAt: 0,
};

export function readManifest(): ContentManifest {
  // Merge with defaults so an older manifest.json missing a newly-added
  // field (e.g. externalGamesVersion) doesn't produce `undefined` and
  // silently poison arithmetic like `version += 1` into NaN.
  return { ...EMPTY_MANIFEST, ...readJson<Partial<ContentManifest>>("manifest.json", {}) };
}

export function writeManifest(manifest: ContentManifest): void {
  writeJson("manifest.json", manifest);
}
