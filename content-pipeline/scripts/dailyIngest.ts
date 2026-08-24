import { randomUUID } from "node:crypto";
import { contentHash, checkAndRecordHash } from "./lib/dedup.js";
import { readJson, writeJson, readManifest, writeManifest } from "./lib/contentStore.js";
import { fetchPibItems } from "./sources/pib.js";
import { fetchWikipediaOnThisDay } from "./sources/wikipedia.js";
import { fetchNewsDataItems } from "./sources/newsApi.js";
import type { DailyCard, RawFetchedItem } from "./lib/types.js";

// NOTE (flagged for the founder, see plan's legal risk section): this is a
// naive truncation, not real paraphrasing. It keeps summaries short and
// always cites + links the source, which is the safe "curation digest"
// pattern, but a genuine rewrite (small LLM call, likely cents/day) is
// recommended before public launch to reduce any near-verbatim overlap risk.
function normalizeSummary(raw: string): string {
  const sentences = raw.split(/(?<=[.!?])\s+/).slice(0, 3);
  return sentences.join(" ").slice(0, 400);
}

function dateKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function toCard(item: RawFetchedItem, publishedDate: string): DailyCard {
  return {
    cardId: randomUUID(),
    category: item.category,
    language: item.language,
    headline: item.headline,
    summary: normalizeSummary(item.summary),
    sourceUrl: item.sourceUrl,
    sourceName: item.sourceName,
    publishedDate,
    imageUrl: item.imageUrl,
    imageAttribution: item.imageAttribution,
  };
}

async function main() {
  const todayKey = dateKey(new Date());

  const [pibItems, wikiItems, newsItems] = await Promise.all([
    fetchPibItems(),
    fetchWikipediaOnThisDay(new Date()),
    fetchNewsDataItems(),
  ]);
  const allItems = [...pibItems, ...wikiItems, ...newsItems];
  console.log(`Fetched ${allItems.length} raw items from all sources.`);

  const existing = readJson<DailyCard[]>(`daily/${todayKey}.json`, []);
  const newCards: DailyCard[] = [];

  for (const item of allItems) {
    const summary = normalizeSummary(item.summary);
    const hash = contentHash(item.headline, summary);
    if (checkAndRecordHash(hash)) {
      console.log(`[skip] duplicate: ${item.headline}`);
      continue;
    }
    newCards.push(toCard(item, todayKey));
  }

  writeJson(`daily/${todayKey}.json`, [...existing, ...newCards]);

  const manifest = readManifest();
  if (!manifest.dailyDates.includes(todayKey)) {
    manifest.dailyDates.push(todayKey);
    manifest.dailyDates.sort();
  }
  manifest.updatedAt = Date.now();
  writeManifest(manifest);

  console.log(`Done. ${newCards.length}/${allItems.length} new cards written to content/daily/${todayKey}.json`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
