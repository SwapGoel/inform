import type { RawFetchedItem } from "../lib/types.js";
import { getLicensedImageForWikipediaPage } from "../lib/wikimediaImages.js";
import { getOpenverseImage } from "../lib/openverseImages.js";

interface OnThisDayEvent {
  text: string;
  pages?: Array<{ content_urls?: { desktop?: { page?: string } }; title?: string }>;
}

// Wikipedia's REST API content is CC BY-SA — safe to build short original
// summaries from, always with a link back to the source page. Each item's
// image (if any) comes from Commons' own curated infobox photo first, or
// Openverse's broader keyword search when Commons has nothing licensed —
// see wikimediaImages.ts/openverseImages.ts.
export async function fetchWikipediaOnThisDay(date: Date): Promise<RawFetchedItem[]> {
  const usedImageUrls = new Set<string>();
  const mm = String(date.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(date.getUTCDate()).padStart(2, "0");
  const url = `https://en.wikipedia.org/api/rest_v1/feed/onthisday/events/${mm}/${dd}`;

  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "InformApp/1.0 (content pipeline)" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = (await res.json()) as { events?: OnThisDayEvent[] };

    // Heuristic filter: keep events mentioning India-relevant terms for the
    // History/National-Movement category; a broader geography/science filter
    // can be layered on later once this is proven out.
    const indiaKeywords = /india|indian|delhi|bombay|mumbai|calcutta|kolkata|gandhi|nehru|independence/i;

    const items: RawFetchedItem[] = [];
    for (const event of data.events ?? []) {
      if (!indiaKeywords.test(event.text)) continue;
      const page = event.pages?.[0];
      const link = page?.content_urls?.desktop?.page;
      if (!link || !page?.title) continue;

      const licensedImage =
        (await getLicensedImageForWikipediaPage(page.title, usedImageUrls)) ??
        (await getOpenverseImage(page.title, usedImageUrls));

      items.push({
        category: "history",
        headline: page.title.replace(/_/g, " "),
        summary: event.text,
        sourceUrl: link,
        sourceName: "Wikipedia",
        language: "en",
        imageUrl: licensedImage?.imageUrl,
        imageAttribution: licensedImage?.attributionText,
      });
    }
    return items;
  } catch (err) {
    console.error("[wikipedia] fetch failed:", (err as Error).message);
    return [];
  }
}
