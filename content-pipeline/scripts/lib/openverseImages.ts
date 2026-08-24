/// Secondary image source, tried only when wikimediaImages.ts finds nothing
/// licensed for a page (see publishStatic.ts). Openverse is a free, keyless
/// search engine over openly-licensed images pulled from Flickr, museums,
/// and other sources — much broader than Wikimedia Commons alone, at the
/// cost of being a keyword search rather than a curated per-topic photo, so
/// it carries real relevance risk on top of the license check (see
/// titleMatchesQuery below).
///
/// No API key required for the request volume this pipeline makes (a few
/// hundred lookups per publish run, run manually/on a schedule — not
/// per-app-install). If Openverse's unauthenticated rate limit ever becomes
/// a problem, a free client id/secret can be registered at
/// https://api.openverse.org and passed via OPENVERSE_CLIENT_ID/SECRET env
/// vars — not needed to start.

import { resolveRenderableImageUrl } from "./wikimediaImages.js";

const PERMISSIVE_LICENSES = new Set(["cc0", "pdm", "by", "by-sa"]);

const STOPWORDS = new Set(["of", "the", "in", "and", "on", "at", "to", "a", "an", "for", "is"]);

// Openverse's search does stemmed/fuzzy full-text matching over titles,
// descriptions, and tags — which means a query like "Ganges" can genuinely
// come back with a photo titled "Gathering the Gang of Four Cats" (its
// analyzer treats "Ganges" and "Gang" as sharing a stem). Trusting that
// alone would put an actively wrong photo on a factual card, which is worse
// than showing no image at all. This re-checks, in plain string matching,
// that every significant word of the query appears as a whole word in the
// candidate's own title — a blunt but reliable filter for "is this even
// about the same thing," since Openverse's relevance ranking isn't.
function significantWords(text: string): string[] {
  return text
    .replace(/\([^)]*\)/g, " ") // drop disambiguation parentheticals, e.g. "Aryabhata (satellite)"
    .split(/[^a-z0-9]+/i)
    .map((w) => w.toLowerCase())
    .filter((w) => w.length >= 3 && !STOPWORDS.has(w));
}

// "all" (the default) is right for a specific topic query like "Ganges" or
// "Fibonacci sequence" — every word must show up, or it's probably a
// different subject entirely. It's the wrong bar for a deliberately generic
// category query like "India nature conservation" (used only as a last
// resort when a fact's own title and headline both found nothing): requiring
// all three words to co-occur in some photo's title is unrealistically
// strict for a query that was never claiming topic-level precision in the
// first place. "any" is used there instead.
function titleMatchesQuery(candidateTitle: string, queryWords: string[], mode: "all" | "any" = "all"): boolean {
  if (queryWords.length === 0) return true;
  const title = candidateTitle.toLowerCase();
  const matcher = (word: string) => new RegExp(`\\b${word}\\b`).test(title);
  return mode === "all" ? queryWords.every(matcher) : queryWords.some(matcher);
}

interface OpenverseResult {
  url: string;
  license: string;
  license_version?: string;
  creator?: string;
  title?: string;
  foreign_landing_url?: string;
  provider?: string;
}

function isAcceptableCandidate(
  result: OpenverseResult,
  usedImageUrls: Set<string>,
  queryWords: string[],
  matchMode: "all" | "any"
): boolean {
  if (!result.url || usedImageUrls.has(result.url)) return false;
  if (!result.license || !PERMISSIVE_LICENSES.has(result.license.toLowerCase())) return false;
  return titleMatchesQuery(result.title ?? "", queryWords, matchMode);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchWithRetry(url: string, attempts = 3): Promise<Response | null> {
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url, {
        headers: { "User-Agent": "InformApp/1.0 (content pipeline)" },
        signal: AbortSignal.timeout(15_000),
      });
      if (res.ok) return res;
      if (res.status === 429 || res.status >= 500) {
        await sleep(800 * (i + 1));
        continue;
      }
      return null;
    } catch {
      await sleep(800 * (i + 1));
    }
  }
  return null;
}

export interface LicensedImage {
  imageUrl: string;
  attributionText: string;
}

/// Searches Openverse for `query`, returning the first result whose license
/// both (a) Openverse tags as commercial-safe and (b) this function's own
/// allowlist confirms permits commercial reuse without a share-alike-only
/// non-commercial clause slipping through. `usedImageUrls` is shared across
/// an entire publish run (mutated in place) so the same photo never gets
/// assigned to two different facts.
export async function getOpenverseImage(
  query: string,
  usedImageUrls: Set<string>,
  matchMode: "all" | "any" = "all"
): Promise<LicensedImage | null> {
  const url =
    "https://api.openverse.org/v1/images/?" +
    new URLSearchParams({
      q: query,
      license_type: "commercial",
      mature: "false",
      page_size: "20",
    }).toString();

  const res = await fetchWithRetry(url);
  if (!res) return null;

  const queryWords = significantWords(query);

  try {
    const data = (await res.json()) as { results?: OpenverseResult[] };
    const candidates = (data.results ?? []).filter((r) =>
      isAcceptableCandidate(r, usedImageUrls, queryWords, matchMode)
    );

    // Wikimedia-hosted results tend to come from a specific Commons category
    // for the actual subject, versus an arbitrary Flickr upload that merely
    // mentions the right words — prefer those when both are available,
    // without discarding Flickr results entirely (they're often the only
    // hit for topics Commons never covers).
    const wikimediaFirst = [
      ...candidates.filter((r) => r.provider === "wikimedia"),
      ...candidates.filter((r) => r.provider !== "wikimedia"),
    ];

    for (const result of wikimediaFirst) {
      const renderableUrl = await resolveRenderableImageUrl(result.url);
      if (!renderableUrl) continue; // an SVG with no resolvable thumbnail — try the next candidate

      const licenseLabel = result.license_version
        ? `${result.license.toUpperCase()} ${result.license_version}`
        : result.license.toUpperCase();
      const attributionText = result.creator
        ? `${result.creator} (${licenseLabel}, via Openverse)`
        : `${licenseLabel}, via Openverse`;

      usedImageUrls.add(result.url);
      return { imageUrl: renderableUrl, attributionText };
    }
    return null;
  } catch {
    return null;
  }
}
