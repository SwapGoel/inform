/// Primary image source: looks up a real photo for a Wikipedia page, but
/// only returns it if Wikimedia Commons' own machine-readable license
/// metadata confirms it's freely reusable (public domain, CC0, CC-BY/CC-BY-SA,
/// or a government open data license like GODL-India). No AI, no guessing —
/// Commons tracks a license per file, and this only trusts that field. If
/// the license is anything else (including "fair use" rationales Wikipedia
/// itself relies on, which do NOT extend to third-party reuse), this
/// returns null and the caller falls back to Openverse (see
/// openverseImages.ts) and finally the plain native-rendered card design.
///
/// Commons is tried first, not as an afterthought: a page's own infobox
/// photo was picked by a human editor specifically for that subject, which
/// is a much stronger relevance guarantee than any keyword search — see
/// openverseImages.ts's own doc comment for a concrete case (a "Ganges
/// Shopping Mall" photo matching a search for the Ganges river) where
/// keyword search alone isn't enough.
///
/// Checks the page's lead/infobox image first (cheap, usually right), and
/// if that isn't freely licensed, falls back to checking every other image
/// used on the page (capped) — many articles carry several images even when
/// the infobox one is a non-free "fair use" file.

const PERMISSIVE_LICENSE_PATTERNS = [
  /^cc0/i,
  /^cc[-\s]?by(?!.*nc)/i, // CC BY / CC BY-SA — but not CC BY-NC (non-commercial)
  /public domain/i,
  /^pd[-\s]/i,
  /godl/i, // Government Open Data License (e.g. GODL-India)
];

function isLicensePermissive(licenseShortName: string): boolean {
  return PERMISSIVE_LICENSE_PATTERNS.some((p) => p.test(licenseShortName));
}

// Common Wikipedia template/UI iconography that turns up in prop=images
// listings but is never the actual subject photo — filtered out so the
// fallback scan doesn't waste API calls (or worse, use a padlock icon as a
// card's "photo") checking these.
const JUNK_FILENAME_PATTERNS = [
  /wiktionary/i,
  /commons-logo/i,
  /^edit[-_]/i,
  /ambox/i,
  /disambig/i,
  /wikisource/i,
  /folder/i,
  /question_book/i,
  /symbol_/i,
  /^flag_of/i,
  /wiki_letter/i,
  /padlock/i,
  /nowrap/i,
  /_icon/i,
  /-icon/i,
  /logo/i,
  /crystal_clear/i,
  /oojs/i,
  /portal[-_]icon/i,
  /star_full/i,
  /star_empty/i,
  /red_pog/i,
  /blue_pog/i,
  /increase\d*\.svg/i,
  /decrease\d*\.svg/i,
  /steady\d*\.svg/i,
];

function isLikelyJunkFile(fileTitle: string): boolean {
  return JUNK_FILENAME_PATTERNS.some((p) => p.test(fileTitle));
}

// Photos that are freely licensed and turn up as incidental illustrations on
// dozens of unrelated pages (a scheme's launch photo, an infobox template,
// "current officeholder" boxes) — legitimate as *that person/subject's* own
// photo, but wrong as the generic fallback image for every scheme, ministry,
// or policy page that happens to embed them. Only applied to the broad
// page-image fallback scan, never to a page's own lead/infobox image (so the
// Narendra Modi or Emblem of India Wikipedia articles themselves are
// unaffected).
const GENERIC_FALLBACK_BLACKLIST = [
  /narendra_modi/i,
  /prime_minister_of_india/i,
  /president_of_india/i,
  /droupadi_murmu/i,
  /emblem_of_india/i,
  /flag_of_india/i,
  /national_emblem/i,
  /ashoka_chakra/i,
  /rashtrapati_bhavan/i,
  /satyamev_jayate/i,
];

function isGenericFallbackImage(fileTitle: string): boolean {
  return GENERIC_FALLBACK_BLACKLIST.some((p) => p.test(fileTitle));
}

interface WikipediaSummary {
  originalimage?: { source: string };
  thumbnail?: { source: string };
}

interface CommonsImageInfo {
  url: string;
  thumburl?: string;
  extmetadata?: {
    LicenseShortName?: { value: string };
    Artist?: { value: string };
    Credit?: { value: string };
    AttributionRequired?: { value: string };
  };
}

function extractCommonsFilename(uploadUrl: string): string | null {
  try {
    const segments = new URL(uploadUrl).pathname.split("/").filter(Boolean);
    // Thumbnail URLs look like .../commons/thumb/5/55/Real_Name.svg/500px-Real_Name.svg.png
    // — the actual Commons filename is the segment right before the resized
    // variant, not the last segment (which is a resized-copy filename that
    // doesn't exist as its own Commons page). This mainly affects SVG
    // diagrams, which Wikipedia serves as a rasterized thumbnail even for
    // "originalimage" — direct (non-thumb) photo URLs are unaffected.
    const thumbIndex = segments.indexOf("thumb");
    const filename = thumbIndex !== -1 ? segments[segments.length - 2] : segments[segments.length - 1];
    if (!filename) return null;
    return decodeURIComponent(filename);
  } catch {
    return null;
  }
}

function stripHtml(html: string): string {
  return html.replace(/<[^>]*>/g, "").trim();
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Wikipedia/Commons occasionally 429/5xx or reset a connection under rapid
// sequential requests (publishing dozens of facts in one run does exactly
// that) — retrying a couple of times with backoff turns a transient hiccup
// into a normal success instead of a silently-wrong "no license found".
async function fetchWithRetry(url: string, attempts = 3): Promise<Response | null> {
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url, {
        headers: { "User-Agent": "InformApp/1.0 (content pipeline)" },
        signal: AbortSignal.timeout(15_000),
      });
      if (res.ok) return res;
      if (res.status === 429 || res.status >= 500) {
        await sleep(500 * (i + 1));
        continue;
      }
      return null; // a real 4xx (e.g. 404) — no point retrying
    } catch {
      await sleep(500 * (i + 1));
    }
  }
  return null;
}

async function fetchCommonsLicenseByFilename(filename: string): Promise<CommonsImageInfo | null> {
  // iiurlwidth asks MediaWiki to compute a real, servable thumbnail URL
  // (returned as `thumburl`) — needed because Commons only serves a fixed,
  // per-file set of thumbnail widths from direct upload.wikimedia.org URLs
  // (guessing a width like 800px often 400s; the API picks a size that's
  // guaranteed to work). Only matters for SVGs, which get rewritten to this
  // thumbnail in toRenderableImageUrl below, but requesting it is harmless
  // for raster files too since they just ignore it.
  const url =
    "https://commons.wikimedia.org/w/api.php?action=query&prop=imageinfo&iiprop=extmetadata%7Curl&iiurlwidth=800&format=json&titles=" +
    encodeURIComponent(`File:${filename}`);
  const res = await fetchWithRetry(url);
  if (!res) return null;
  try {
    const data = (await res.json()) as {
      query?: { pages?: Record<string, { imageinfo?: CommonsImageInfo[]; missing?: string }> };
    };
    const pages = Object.values(data.query?.pages ?? {});
    const page = pages[0];
    if (!page || page.missing !== undefined) return null;
    return page.imageinfo?.[0] ?? null;
  } catch {
    return null;
  }
}

function isSvgUrl(url: string): boolean {
  return /\.svg$/i.test(url.split("?")[0]);
}

// Commons serves vector (.svg) originals directly at their real file URL,
// which Flutter's built-in Image decoder cannot render at all — the app has
// no SVG plugin, so handing it an .svg imageUrl doesn't show a broken image,
// it shows NOTHING (the plain gradient card persists, silently, while the
// attribution text still prints). `info.thumburl` (requested via iiurlwidth
// in fetchCommonsLicenseByFilename) is a real, MediaWiki-computed PNG
// rendering of the same file that's guaranteed servable — unlike guessing a
// width ourselves, which 400s for any width outside that file's specific
// allowed thumbnail sizes (confirmed by hand: some files only serve their
// SVG at e.g. 500px, not the 800px this code originally assumed).
function toRenderableImageUrl(info: CommonsImageInfo): string {
  if (isSvgUrl(info.url) && info.thumburl) return info.thumburl;
  return info.url;
}

// Used only when we DON'T have a CommonsImageInfo object already (Openverse
// results are plain URLs) — same idea as toRenderableImageUrl, but fetches
// its own thumburl since there's no prior API response to read one from.
// Returns null (never the raw .svg URL) if no renderable thumbnail can be
// resolved — see ensureRenderable's comment for why this never falls back
// to shipping something Flutter can't display.
export async function resolveRenderableImageUrl(originalUrl: string): Promise<string | null> {
  if (!isSvgUrl(originalUrl)) return originalUrl;
  try {
    const u = new URL(originalUrl);
    if (u.hostname !== "upload.wikimedia.org") return null; // non-Commons SVG: no rasterization path available
    const filename = decodeURIComponent(u.pathname.split("/").filter(Boolean).pop() ?? "");
    if (!filename) return null;
    const info = await fetchCommonsLicenseByFilename(filename);
    if (info?.thumburl) return info.thumburl;
    const retried = await fetchCommonsLicenseByFilename(filename);
    return retried?.thumburl ?? null;
  } catch {
    return null;
  }
}

// Commons' imageinfo API is expected to return `thumburl` whenever
// `iiurlwidth` is set, but under the request volume a full publish run
// makes, it's been observed to sometimes omit it for an SVG file even
// though a direct, isolated request for that same file returns it fine —
// transient, not reproducible on retry with certainty, but real. Rather
// than ever ship the raw (unrenderable) .svg URL when that happens, this
// re-fetches once; if it's STILL missing, the candidate is rejected outright
// so the caller moves on to a different image instead of a broken one.
async function ensureRenderable(info: CommonsImageInfo, filename: string): Promise<CommonsImageInfo | null> {
  if (!isSvgUrl(info.url)) return info;
  if (info.thumburl) return info;
  const retried = await fetchCommonsLicenseByFilename(filename);
  return retried?.thumburl ? retried : null;
}

function toLicensedImage(info: CommonsImageInfo): LicensedImage {
  const licenseShortName = info.extmetadata?.LicenseShortName?.value ?? "";
  const artist = info.extmetadata?.Artist?.value ? stripHtml(info.extmetadata.Artist.value) : null;
  const attributionText = artist
    ? `${artist} (${licenseShortName}, via Wikimedia Commons)`
    : `${licenseShortName}, via Wikimedia Commons`;
  return { imageUrl: toRenderableImageUrl(info), attributionText };
}

// Every other image used on the page (English Wikipedia's own listing, not
// Commons) — used only as a fallback when the lead/infobox image isn't
// freely licensed. Raster photos are checked before SVGs, since most SVGs
// turned up here are diagrams/icons rather than photos of the subject.
async function fetchPageImageFilenames(title: string): Promise<string[]> {
  const url =
    `https://en.wikipedia.org/w/api.php?action=query&titles=${encodeURIComponent(title)}` +
    "&prop=images&imlimit=40&format=json";
  const res = await fetchWithRetry(url);
  if (!res) return [];
  try {
    const data = (await res.json()) as {
      query?: { pages?: Record<string, { images?: Array<{ title: string }> }> };
    };
    const pages = Object.values(data.query?.pages ?? {});
    const titles = (pages[0]?.images ?? [])
      .map((i) => i.title.replace(/^File:/, ""))
      .filter((name) => !isLikelyJunkFile(name))
      .filter((name) => !isGenericFallbackImage(name));

    const rasters = titles.filter((t) => !/\.svg$/i.test(t));
    const svgs = titles.filter((t) => /\.svg$/i.test(t));
    return [...rasters, ...svgs];
  } catch {
    return [];
  }
}

export interface LicensedImage {
  imageUrl: string;
  attributionText: string;
}

const MAX_FALLBACK_CANDIDATES_CHECKED = 8;

/// Given a Wikipedia page title, returns a real photo + attribution text IF
/// (and only if) Commons confirms it's freely reusable. Returns null
/// otherwise — callers must treat that as "no image", not an error.
///
/// `usedImageUrls` is shared across an entire publish run (see
/// publishStatic.ts) and mutated in place: once an image is assigned to one
/// fact, it's skipped for every other fact so two unrelated cards never end
/// up wearing the same photo.
export async function getLicensedImageForWikipediaPage(
  title: string,
  usedImageUrls: Set<string> = new Set()
): Promise<LicensedImage | null> {
  // Fast path: the page's own lead/infobox image.
  const summaryRes = await fetchWithRetry(
    `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`
  );
  if (summaryRes) {
    try {
      const summary = (await summaryRes.json()) as WikipediaSummary;
      const imageSource = summary.originalimage?.source ?? summary.thumbnail?.source;
      const rawFilename = imageSource ? extractCommonsFilename(imageSource) : null;
      // Stub or maintenance-flagged articles occasionally surface a Wikipedia
      // template icon (e.g. "Question book-new.svg", the citation-needed
      // icon) as their own lead image — the same junk/generic checks used
      // for the broader fallback scan apply here too, not just there.
      const filename =
        rawFilename && !isLikelyJunkFile(rawFilename) && !isGenericFallbackImage(rawFilename) ? rawFilename : null;
      if (filename) {
        let info = await fetchCommonsLicenseByFilename(filename);
        const licenseShortName = info?.extmetadata?.LicenseShortName?.value;
        if (info && licenseShortName && isLicensePermissive(licenseShortName) && !usedImageUrls.has(info.url)) {
          info = await ensureRenderable(info, filename);
          if (info) {
            usedImageUrls.add(info.url);
            return toLicensedImage(info);
          }
        }
      }
    } catch {
      // fall through to the broader page-image scan below
    }
  }

  // Fallback: scan the page's other images for any one with a permissive
  // license, capped so a heavily-illustrated page doesn't burn unbounded
  // API calls.
  const candidates = await fetchPageImageFilenames(title);
  for (const filename of candidates.slice(0, MAX_FALLBACK_CANDIDATES_CHECKED)) {
    let info = await fetchCommonsLicenseByFilename(filename);
    const licenseShortName = info?.extmetadata?.LicenseShortName?.value;
    if (info && licenseShortName && isLicensePermissive(licenseShortName) && !usedImageUrls.has(info.url)) {
      info = await ensureRenderable(info, filename);
      if (info) {
        usedImageUrls.add(info.url);
        return toLicensedImage(info);
      }
    }
  }

  return null;
}
