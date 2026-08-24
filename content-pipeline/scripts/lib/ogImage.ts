/// Fetches a page's own "og:image" (or "twitter:image") meta tag — the
/// exact image a site publishes for the purpose of being shown in link
/// previews (the same mechanism WhatsApp/Slack/iMessage link previews use).
/// This is meaningfully different from scraping a photo out of an article
/// body: the site is explicitly opting that image in for preview use.
export async function fetchOgImage(pageUrl: string): Promise<string | null> {
  try {
    const res = await fetch(pageUrl, {
      headers: { "User-Agent": "InformApp/1.0 (content pipeline; link preview)" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) return null;
    const html = await res.text();

    const ogMatch =
      html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i) ??
      html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);
    const twitterMatch =
      html.match(/<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i) ??
      html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+name=["']twitter:image["']/i);

    const found = ogMatch?.[1] ?? twitterMatch?.[1];
    if (!found) return null;

    // Resolve relative URLs against the page's own origin, just in case.
    return new URL(found, pageUrl).href;
  } catch {
    return null;
  }
}
