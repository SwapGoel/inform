import sourcesConfig from "../../data/sources.json" with { type: "json" };
import type { Category, RawFetchedItem } from "../lib/types.js";

interface NewsDataArticle {
  title?: string;
  description?: string;
  link?: string;
  source_id?: string;
}

// Optional supplemental current-events source. Entirely skipped (returns [])
// if NEWSDATA_API_KEY isn't set, so the pipeline still runs on PIB +
// Wikipedia + the evergreen bank alone if this free-tier key is never added.
export async function fetchNewsDataItems(): Promise<RawFetchedItem[]> {
  const apiKey = process.env.NEWSDATA_API_KEY;
  if (!apiKey) {
    console.log("[newsdata] NEWSDATA_API_KEY not set, skipping this source.");
    return [];
  }

  const results: RawFetchedItem[] = [];
  const categoryMap = sourcesConfig.newsdata_categories as Record<Category, string[]>;

  for (const [category, ndCategories] of Object.entries(categoryMap)) {
    const category_param = ndCategories.join(",");
    const url = `https://newsdata.io/api/1/latest?apikey=${apiKey}&country=in&language=en&category=${category_param}`;
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(15_000) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as { results?: NewsDataArticle[] };
      for (const article of (data.results ?? []).slice(0, 5)) {
        if (!article.title || !article.link) continue;
        results.push({
          category: category as Category,
          headline: article.title.trim(),
          summary: (article.description ?? "").trim().slice(0, 500),
          sourceUrl: article.link,
          sourceName: article.source_id ?? "NewsData.io",
          language: "en",
        });
      }
    } catch (err) {
      console.error(`[newsdata] fetch failed for ${category}:`, (err as Error).message);
    }
  }

  return results;
}
