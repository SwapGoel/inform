import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { readJson, writeJson, readManifest, writeManifest } from "./lib/contentStore.js";
import type { Category, VideoEntry } from "./lib/types.js";

interface PlaylistConfig {
  playlistId: string;
  category: Category;
}

interface YoutubePlaylistItem {
  snippet?: {
    title?: string;
    channelTitle?: string;
    resourceId?: { videoId?: string };
  };
  status?: { privacyStatus?: string };
}

const configPath = fileURLToPath(new URL("../data/youtube_playlists.json", import.meta.url));
const config = JSON.parse(readFileSync(configPath, "utf-8")) as { playlists: PlaylistConfig[] };

async function fetchPlaylistVideos(apiKey: string, playlistId: string): Promise<YoutubePlaylistItem[]> {
  const url = `https://www.googleapis.com/youtube/v3/playlistItems?part=snippet,status&maxResults=15&playlistId=${playlistId}&key=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(15_000) });
  if (!res.ok) throw new Error(`HTTP ${res.status} for playlist ${playlistId}`);
  const data = (await res.json()) as { items?: YoutubePlaylistItem[] };
  return data.items ?? [];
}

async function revalidate(apiKey: string, byId: Map<string, VideoEntry>): Promise<void> {
  const activeIds = [...byId.values()].filter((v) => v.active).map((v) => v.videoId).slice(0, 50);
  if (activeIds.length === 0) return;

  const url = `https://www.googleapis.com/youtube/v3/videos?part=status&id=${activeIds.join(",")}&key=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(15_000) });
  if (!res.ok) {
    console.error(`[revalidate] HTTP ${res.status}`);
    return;
  }
  const data = (await res.json()) as {
    items?: Array<{ id: string; status?: { privacyStatus?: string; embeddable?: boolean } }>;
  };
  const stillGood = new Set(
    (data.items ?? [])
      .filter((v) => v.status?.privacyStatus === "public" && v.status?.embeddable !== false)
      .map((v) => v.id)
  );

  for (const id of activeIds) {
    if (!stillGood.has(id)) {
      const entry = byId.get(id);
      if (entry) {
        entry.active = false;
        console.log(`[revalidate] deactivated ${id}`);
      }
    }
  }
}

async function main() {
  const apiKey = process.env.YOUTUBE_API_KEY;
  if (!apiKey) {
    console.log("YOUTUBE_API_KEY not set — skipping weekly video refresh entirely.");
    return;
  }
  if (config.playlists.length === 0) {
    console.log("No playlists configured in data/youtube_playlists.json — nothing to fetch.");
    return;
  }

  const existing = readJson<VideoEntry[]>("videos/index.json", []);
  const byId = new Map(existing.map((v) => [v.videoId, v]));

  for (const { playlistId, category } of config.playlists) {
    try {
      const items = await fetchPlaylistVideos(apiKey, playlistId);
      for (const item of items) {
        const videoId = item.snippet?.resourceId?.videoId;
        const title = item.snippet?.title;
        if (!videoId || !title) continue;
        const isPublic = item.status?.privacyStatus === "public";
        byId.set(videoId, {
          videoId,
          title_en: title,
          title_hi: byId.get(videoId)?.title_hi ?? "",
          channelTitle: item.snippet?.channelTitle ?? "",
          category,
          addedAt: byId.get(videoId)?.addedAt ?? Date.now(),
          active: isPublic,
        });
      }
      console.log(`[ok] playlist ${playlistId}: processed ${items.length} items`);
    } catch (err) {
      console.error(`[error] playlist ${playlistId}:`, (err as Error).message);
    }
  }

  await revalidate(apiKey, byId);

  writeJson("videos/index.json", [...byId.values()]);

  const manifest = readManifest();
  manifest.videosVersion += 1;
  manifest.updatedAt = Date.now();
  writeManifest(manifest);

  console.log(`Published ${byId.size} videos (version ${manifest.videosVersion}).`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
