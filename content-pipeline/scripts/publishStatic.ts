import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { writeJson, readManifest, writeManifest } from "./lib/contentStore.js";
import { getLicensedImageForWikipediaPage } from "./lib/wikimediaImages.js";
import { getOpenverseImage } from "./lib/openverseImages.js";
import { fetchOgImage } from "./lib/ogImage.js";
import type { EvergreenFact, ExternalGame } from "./lib/types.js";

// Publishes the hand-authored evergreen fact bank, the shared visual theme,
// and the curated external brain-game link list from content-pipeline/data/
// into content/ (the git-committed, CDN-served bundle the app fetches). No
// server-side wallpaper rendering happens here — the app renders the card
// design on-device — but this step DOES enrich facts/games with real,
// license-checked images where available (see openverseImages.ts/ogImage.ts).
// Rerun any time data/evergreen_facts.json, data/theme.json, or
// data/external_games.json change.

function loadJson<T>(relPath: string): T {
  const full = fileURLToPath(new URL(`../data/${relPath}`, import.meta.url));
  return JSON.parse(readFileSync(full, "utf-8")) as T;
}

function validateFacts(facts: EvergreenFact[]): void {
  const ids = new Set<string>();
  const requiredFields: (keyof EvergreenFact)[] = [
    "id",
    "category",
    "headline_en",
    "summary_en",
    "headline_hi",
    "summary_hi",
  ];
  for (const fact of facts) {
    if (ids.has(fact.id)) {
      throw new Error(`Duplicate evergreen fact id: ${fact.id}`);
    }
    ids.add(fact.id);
    for (const field of requiredFields) {
      if (!fact[field]) {
        throw new Error(`Fact ${fact.id} is missing required field "${field}"`);
      }
    }
  }
}

function validateExternalGames(games: ExternalGame[]): void {
  const ids = new Set<string>();
  for (const game of games) {
    if (ids.has(game.id)) {
      throw new Error(`Duplicate external game id: ${game.id}`);
    }
    ids.add(game.id);
    if (!game.name || !game.url) {
      throw new Error(`External game ${game.id} is missing name or url`);
    }
    if (!game.url.startsWith("https://")) {
      throw new Error(`External game ${game.id} url must be https`);
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function wikipediaPageUrl(title: string): string {
  return `https://en.wikipedia.org/wiki/${encodeURIComponent(title.replace(/ /g, "_"))}`;
}

// Last-resort query when a fact's own page title AND headline both turn up
// nothing licensed (typically abstract legal/procedural topics with no
// natural photo — "Basic structure doctrine", "Directive Principles"). A
// broad, clearly-relevant-to-the-category photo beats an empty card; this
// is deliberately the lowest-priority source, tried only after both
// topic-specific searches fail.
// More than one query per category: if two facts in the same category both
// fall through to this tier, the first one can claim the only dedup-eligible
// result for the category's query, leaving the second with nothing. A short
// list of alternates gives the second fact somewhere else to look instead of
// coming up empty.
const CATEGORY_FALLBACK_QUERIES: Record<string, string[]> = {
  current_events: ["India government", "Indian Parliament building"],
  history: ["Indian independence movement", "colonial India history"],
  geography: ["India landscape", "Indian mountains"],
  polity: ["Indian Parliament", "Supreme Court of India"],
  economy: ["Indian economy", "Indian market"],
  environment: ["India nature conservation", "Indian wildlife"],
  science: ["science laboratory", "scientific research"],
  maths: ["mathematics", "geometry"],
};

async function enrichFactsWithImages(facts: EvergreenFact[]): Promise<EvergreenFact[]> {
  const enriched: EvergreenFact[] = [];
  // Shared across every fact in this run — and across BOTH sources below —
  // so the same photo can't get assigned to more than one card regardless
  // of whether it came from Commons or Openverse.
  const usedImageUrls = new Set<string>();
  for (const fact of facts) {
    const sourceUrl = fact.wikipediaTitle ? wikipediaPageUrl(fact.wikipediaTitle) : undefined;
    const { image, usedCategoryFallback } = await findImageForFact(fact, usedImageUrls);

    enriched.push(
      image
        ? { ...fact, sourceUrl, imageUrl: image.imageUrl, imageAttribution: image.attributionText }
        : { ...fact, sourceUrl }
    );
    console.log(
      `[image] ${fact.id} (${fact.wikipediaTitle ?? fact.headline_en}): ${
        image ? (usedCategoryFallback ? "found (category fallback)" : "found") : "none/no permissive license"
      }`
    );
    // A small pace between requests avoids tripping Wikipedia/Commons' own
    // rate limiting in the first place, on top of the retry-with-backoff
    // already inside getLicensedImageForWikipediaPage.
    await sleep(200);
  }
  return enriched;
}

async function findImageForFact(
  fact: EvergreenFact,
  usedImageUrls: Set<string>
): Promise<{ image: { imageUrl: string; attributionText: string } | null; usedCategoryFallback: boolean }> {
  let image = null;
  if (fact.wikipediaTitle) {
    // Commons first: a page's own infobox photo was picked by a human
    // editor for that exact subject, the strongest relevance guarantee
    // available. Openverse (broader, but keyword-searched) only fills the
    // gap when Commons has nothing freely licensed for this page.
    image =
      (await getLicensedImageForWikipediaPage(fact.wikipediaTitle, usedImageUrls)) ??
      (await getOpenverseImage(fact.wikipediaTitle, usedImageUrls));
  }
  if (!image) {
    // Broader retry: either there's no Wikipedia page mapped at all, or
    // there is one but its exact (often legalistic/formal) title turned up
    // nothing — a plain-English search on the headline itself sometimes
    // catches an illustrative photo the formal title misses.
    image = await getOpenverseImage(fact.headline_en, usedImageUrls);
  }
  let usedCategoryFallback = false;
  if (!image) {
    for (const categoryQuery of CATEGORY_FALLBACK_QUERIES[fact.category] ?? []) {
      image = await getOpenverseImage(categoryQuery, usedImageUrls, "any");
      if (image) {
        usedCategoryFallback = true;
        break;
      }
    }
  }
  return { image, usedCategoryFallback };
}

// Verifies every published imageUrl is actually a fetchable image, not just
// a URL that LOOKED right when it was chosen. This exists because both
// Commons and Openverse have, in practice, occasionally produced URLs that
// don't render in the app despite passing every prior check (a transient
// missing thumbnail from Commons under load; a plain 404 from a Flickr
// upload that's since been deleted) — heuristics that looked airtight at
// the time still let broken URLs through twice already. A fact whose image
// fails this check gets ONE retry through the same search chain (which
// naturally lands on a different candidate, since the broken one is already
// in usedImageUrls) before falling back to no image at all.
async function verifyAndRepairImages(facts: EvergreenFact[]): Promise<EvergreenFact[]> {
  const usedImageUrls = new Set<string>(facts.map((f) => f.imageUrl).filter((u): u is string => Boolean(u)));
  const repaired: EvergreenFact[] = [];
  for (const fact of facts) {
    // A small pace between every check (not just after a repair) — this
    // runs right after the enrichment phase's own large burst of API/image
    // requests, and hitting Wikimedia with 48 more back-to-back GETs with no
    // gap risks transient rate-limit responses that look identical to a
    // genuinely broken image (see isRenderableImage's own retry too).
    await sleep(150);
    if (!fact.imageUrl || (await isRenderableImage(fact.imageUrl))) {
      repaired.push(fact);
      continue;
    }
    console.log(`[verify] ${fact.id}: published image is not renderable, retrying — ${fact.imageUrl}`);
    const { image } = await findImageForFact(fact, usedImageUrls);
    if (image && (await isRenderableImage(image.imageUrl))) {
      repaired.push({ ...fact, imageUrl: image.imageUrl, imageAttribution: image.attributionText });
      console.log(`[verify] ${fact.id}: repaired`);
    } else {
      const { imageUrl: _imageUrl, imageAttribution: _imageAttribution, ...withoutImage } = fact;
      repaired.push(withoutImage);
      console.log(`[verify] ${fact.id}: no replacement found, dropping image`);
    }
  }
  return repaired;
}

// Retries before concluding an image is genuinely broken — a bare single
// fetch here previously produced a burst of false "not renderable" verdicts
// under Wikimedia's transient rate limiting, which would have silently
// stripped dozens of perfectly good images from the published data.
async function isRenderableImage(url: string): Promise<boolean> {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const res = await fetch(url, {
        method: "GET",
        headers: { "User-Agent": "InformApp/1.0 (content pipeline)", Range: "bytes=0-2047" },
        signal: AbortSignal.timeout(15_000),
      });
      if (res.status === 429 || res.status >= 500) {
        await sleep(800 * (attempt + 1));
        continue;
      }
      if (!res.ok) return false; // a real 4xx (e.g. 404) — the file is genuinely gone
      const contentType = res.headers.get("content-type") ?? "";
      return contentType.startsWith("image/") && contentType !== "image/svg+xml";
    } catch {
      await sleep(800 * (attempt + 1));
    }
  }
  return false;
}

async function enrichGamesWithImages(games: ExternalGame[]): Promise<ExternalGame[]> {
  const enriched: ExternalGame[] = [];
  for (const game of games) {
    const imageUrl = await fetchOgImage(game.url);
    enriched.push({ ...game, imageUrl: imageUrl ?? "" });
    console.log(`[og:image] ${game.id}: ${imageUrl ? "found" : "none"}`);
  }
  return enriched;
}

async function main(): Promise<void> {
  const rawFacts = loadJson<EvergreenFact[]>("evergreen_facts.json");
  validateFacts(rawFacts);
  const enrichedFacts = await enrichFactsWithImages(rawFacts);
  const facts = await verifyAndRepairImages(enrichedFacts);
  writeJson("evergreen_facts.json", facts);

  const theme = loadJson<Record<string, unknown>>("theme.json");
  writeJson("theme.json", theme);

  const rawGames = loadJson<ExternalGame[]>("external_games.json");
  validateExternalGames(rawGames);
  const externalGames = await enrichGamesWithImages(rawGames);
  writeJson("external_games.json", externalGames);

  const manifest = readManifest();
  manifest.evergreenVersion += 1;
  manifest.externalGamesVersion += 1;
  manifest.updatedAt = Date.now();
  writeManifest(manifest);

  const withImages = facts.filter((f) => f.imageUrl).length;
  console.log(
    `Published ${facts.length} evergreen facts (${withImages} with real images), theme.json, and ${externalGames.length} external game links (evergreen v${manifest.evergreenVersion}, games v${manifest.externalGamesVersion}).`
  );
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
