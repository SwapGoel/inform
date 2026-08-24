# Inform

A general-knowledge Android app: an endless scroll of auto-generated, natively-rendered "wallpaper cards" covering Current Events, History, Geography, Polity & Governance, Economy & Society, Environment, Science, and Maths — plus a daily on-device mind game and occasional embedded educational STEM videos. Runs on a genuine $0/month backend with no Firebase project, no database, and no server.

## Architecture in one paragraph

There is no backend server or database. A GitHub Actions workflow fetches and curates content (PIB, Wikipedia, optionally NewsData.io/YouTube) and commits small JSON files into `content-pipeline/content/`. That directory is served for free, at any scale, by the jsDelivr CDN fronting the public GitHub repo. The Flutter app fetches those JSON files directly, renders the wallpaper cards itself (as native widgets — no server-side image generation, no image storage/bandwidth cost), and generates the daily mind game itself (a deterministic, date-seeded pick from the on-device evergreen fact bank — identical logic on every phone, no network round-trip required for it at all).

See [`docs/plan.md`](docs/plan.md) *(or ask Claude — the original plan and its revision lives in the Claude Code plan file)* for the full rationale.

## Repo Layout

- `app/` — the Flutter Android app. Fetches content, renders wallpapers, generates the daily game, all on-device.
- `content-pipeline/` — Node/TypeScript scripts, scheduled via GitHub Actions, that fetch + curate + de-duplicate content and commit it as static JSON under `content-pipeline/content/`. No server, no database, no image rendering.
- `docs/` — privacy policy and Play Store listing copy.
- `.github/workflows/` — the scheduled jobs (daily content ingest, weekly video refresh) plus one manual job (publish the evergreen fact bank / theme).

## One-Time Setup

1. **Create a GitHub repo for this project and make it public.** It must be public for the free jsDelivr CDN trick to work with no extra setup. This is safe — API keys stay in GitHub Actions encrypted secrets, which are never exposed even in a public repo; only the *content* (facts, headlines, category theme) is public, which is fine since that's exactly what the app needs to fetch anyway. Push this code to it, with **Settings → Actions → General → Workflow permissions** set to "Read and write permissions" (the workflows commit generated content back to the repo using the built-in `GITHUB_TOKEN` — no service account or credentials to manage).
2. **Add GitHub Actions secrets** (repo Settings → Secrets and variables → Actions) — both optional, the pipeline works without them using PIB + Wikipedia + the evergreen bank alone:
   - `NEWSDATA_API_KEY` — free-tier key from https://newsdata.io for supplemental English current-events coverage.
   - `YOUTUBE_API_KEY` — from Google Cloud Console (enable "YouTube Data API v3") if you want the weekly video refresh to run.
3. **Publish the evergreen fact bank**: from the GitHub repo's Actions tab, manually run the "Publish static content" workflow (or run `npm run publish:static` locally, then commit+push `content-pipeline/content/`). Rerun it any time `content-pipeline/data/evergreen_facts.json` or `data/theme.json` change.
4. The daily-ingest and weekly-video workflows run automatically on schedule once the repo is public with write permissions — no further action needed.
5. **Point the app at your repo**: edit `app/lib/core/constants.dart`'s `contentBaseUrl` to `https://cdn.jsdelivr.net/gh/<your-github-username>/<your-repo>@main/content-pipeline/content/`.

## Running the Content Pipeline Locally (for testing)

```bash
cd content-pipeline
npm install

npm run publish:static   # one-time / rerunnable — publishes evergreen_facts.json + theme.json
npm run ingest:daily     # fetches PIB/Wikipedia/(NewsData) and appends today's content/daily/<date>.json
npm run videos:weekly    # only does anything once YOUTUBE_API_KEY + data/youtube_playlists.json are set

git add content && git commit -m "Update content" && git push   # a local run must commit+push manually; CI does this automatically
```

## Running the Flutter App

See `app/README.md`.

## Known Follow-Ups (see plan for full detail)

- `content-pipeline/scripts/dailyIngest.ts`'s summary normalization is a naive truncation, not real paraphrasing — recommended to upgrade to a genuine rewrite step before public launch to minimize any near-verbatim overlap with source text.
- `content-pipeline/data/sources.json` ships with one verified-working PIB feed, and it's Hindi-only (confirmed by fetching real output — the feed's `Lang` parameter does not reliably switch to English, so no English PIB feed is claimed). English current-events coverage currently comes from Wikipedia + optional NewsData.io. Adding more/better PIB feeds requires manually browsing pib.gov.in's RSS section (it's JavaScript-rendered, so it can't be scraped automatically) and verifying the actual output language before trusting it.
- `content-pipeline/data/youtube_playlists.json` ships empty — add curated channel "uploads playlist IDs" (see the file's `_readme` field for how to find them) before the weekly video workflow does anything.
- Content repetition resets on app uninstall (all "seen" tracking is local to the device, on purpose — there's no server to track it against) — see the plan's "honest guarantee" section.
