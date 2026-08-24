import Parser from "rss-parser";
import sourcesConfig from "../../data/sources.json" with { type: "json" };
import type { RawFetchedItem } from "../lib/types.js";

const parser = new Parser({ timeout: 15_000 });

// PIB releases are official government text — safe to summarize, but we still
// never republish the feed's own title/description verbatim (see
// normalizeToSummary in dailyIngest.ts); we just extract raw fields here.
export async function fetchPibItems(): Promise<RawFetchedItem[]> {
  const results: RawFetchedItem[] = [];

  for (const feed of sourcesConfig.pib_feeds) {
    try {
      const parsed = await parser.parseURL(feed.url);
      for (const item of parsed.items.slice(0, 10)) {
        if (!item.title || !item.link) continue;
        results.push({
          category: feed.category as RawFetchedItem["category"],
          headline: item.title.trim(),
          summary: (item.contentSnippet ?? item.content ?? "").trim().slice(0, 500),
          sourceUrl: item.link,
          sourceName: "PIB",
          language: feed.language as "en" | "hi",
        });
      }
    } catch (err) {
      console.error(`[pib] failed to fetch ${feed.url}:`, (err as Error).message);
    }
  }

  return results;
}
