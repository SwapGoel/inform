export type Category =
  | "current_events"
  | "history"
  | "geography"
  | "polity"
  | "economy"
  | "environment"
  | "science"
  | "maths";

export const CATEGORIES: Category[] = [
  "current_events",
  "history",
  "geography",
  "polity",
  "economy",
  "environment",
  "science",
  "maths",
];

export interface EvergreenFact {
  id: string;
  category: Category;
  headline_en: string;
  summary_en: string;
  headline_hi: string;
  summary_hi: string;
  tags: string[];
  // Optional: a Wikipedia page title to look up a real photo for at publish
  // time (see publishStatic.ts). Only ever authored in data/evergreen_facts
  // .json as a lookup hint — the actual imageUrl/imageAttribution fields
  // below are populated in the PUBLISHED copy under content/, never in the
  // source file, since they're derived and only valid if Commons' or
  // Openverse's own license metadata confirms reuse is safe (see
  // lib/wikimediaImages.ts and lib/openverseImages.ts).
  wikipediaTitle?: string;
  imageUrl?: string;
  imageAttribution?: string;
  // Derived from wikipediaTitle at publish time (see publishStatic.ts) —
  // lets the app's "tap card to read more" behavior work for evergreen
  // facts too, not just daily-ingested news items.
  sourceUrl?: string;
}

export interface RawFetchedItem {
  category: Category;
  headline: string;
  summary: string;
  sourceUrl: string;
  sourceName: string;
  language: "en" | "hi";
  // Only ever set when Commons' or Openverse's own license metadata confirms
  // the image is freely reusable (see lib/wikimediaImages.ts and
  // lib/openverseImages.ts) — never guessed, never scraped from an arbitrary
  // news article. Absent for every other source, in which case the client
  // renders the plain text/gradient design.
  imageUrl?: string;
  imageAttribution?: string;
}

// A daily-ingested card, published as plain text (usually with no image —
// the Flutter client renders the wallpaper design on-device from this data)
// unless a license-checked real photo was found for it.
export interface DailyCard {
  cardId: string;
  category: Category;
  language: "en" | "hi";
  headline: string;
  summary: string;
  sourceUrl: string;
  sourceName: string;
  publishedDate: string; // YYYY-MM-DD
  imageUrl?: string;
  imageAttribution?: string;
}

// NOTE: the daily game is generated entirely on-device (deterministic,
// seeded by the date, sampling from the evergreen bank the app already has)
// — no server-side game generation or publishing step exists.

// A curated link to an external, legitimate mind/brain-game website (e.g.
// Lumosity, Sporcle, NYT Games). The app only ever LINKS to these — opens
// them in the phone's browser — never embeds them via WebView/iframe.
// Embedding third-party games would need a license from each game's owner
// (most aren't freely embeddable elsewhere); linking out has no such issue,
// same as linking to a news source.
export interface ExternalGame {
  id: string;
  name: string;
  description_en: string;
  description_hi: string;
  url: string;
  // Populated at publish time from the site's own og:image meta tag (the
  // image it publishes for link previews) — never scraped from page
  // content. Empty string if the site doesn't publish one.
  imageUrl?: string;
}

export interface VideoEntry {
  videoId: string;
  title_en: string;
  title_hi: string;
  channelTitle: string;
  category: Category;
  addedAt: number;
  active: boolean;
}

export interface ContentManifest {
  evergreenVersion: number;
  dailyDates: string[];
  videosVersion: number;
  externalGamesVersion: number;
  updatedAt: number;
}
