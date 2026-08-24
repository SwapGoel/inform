/// Base URL the app fetches published content from. jsDelivr serves the
/// public GitHub repo's content-pipeline/content/ directory as a free CDN —
/// no server, no API keys, no bandwidth quota to worry about.
///
/// TODO(founder): replace with your own repo once it's pushed to GitHub:
///   `https://cdn.jsdelivr.net/gh/YOUR_USERNAME/YOUR_REPO@main/content-pipeline/content/`
const String contentBaseUrl =
    'https://cdn.jsdelivr.net/gh/YOUR_GITHUB_USERNAME/inform@main/content-pipeline/content/';

/// How many of the most-recent daily content files to keep fetching on a
/// fresh install / long-idle return, so a phone that hasn't opened the app
/// in months doesn't try to backfill years of small files.
const int maxDailyBackfillDays = 90;

/// Roughly one video card for every this-many content cards in the feed.
const int feedVideoInterval = 9;

/// How many recently-shown card ids to remember, to avoid immediate repeats
/// within a session/install without needing to remember everything forever.
const int recentlySeenCap = 400;

/// Number of term/clue pairs sampled into each day's on-device mind game.
const int dailyGameTermCount = 8;
