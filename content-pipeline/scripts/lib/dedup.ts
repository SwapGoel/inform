import { createHash } from "node:crypto";
import { readJson, writeJson } from "./contentStore.js";

// How many days of hashes to keep before pruning — long enough to catch a
// story re-covered weeks later, short enough that _hashes.json stays small.
const RETENTION_DAYS = 180;

interface HashEntry {
  h: string;
  t: number;
}

function normalize(text: string): string {
  return text.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
}

export function contentHash(headline: string, summary: string): string {
  return createHash("sha256").update(normalize(headline) + normalize(summary)).digest("hex");
}

// Returns true if this hash was already seen (a duplicate). Either way, the
// on-disk hash list is pruned to the retention window and (if new) appended
// — call sites are responsible for git-committing content/_hashes.json.
export function checkAndRecordHash(hash: string): boolean {
  const now = Date.now();
  const cutoff = now - RETENTION_DAYS * 24 * 60 * 60 * 1000;
  const entries = readJson<HashEntry[]>("_hashes.json", []).filter((e) => e.t >= cutoff);

  const isDuplicate = entries.some((e) => e.h === hash);
  if (!isDuplicate) {
    entries.push({ h: hash, t: now });
  }
  writeJson("_hashes.json", entries);
  return isDuplicate;
}
