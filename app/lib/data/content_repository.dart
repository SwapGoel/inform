import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import 'local_prefs.dart';
import 'models.dart';

/// The app's own "backend": on first run it copies the bundled evergreen
/// fact bank + theme out of Flutter assets so the app works fully offline
/// immediately, then best-effort syncs newer content from the CDN in the
/// background. Every fetch failure here is non-fatal — the app always has
/// something to show from the bundled/last-synced local copy.
class ContentRepository {
  final LocalPrefs prefs;
  Directory? _supportDir;

  List<ContentCard>? _evergreenCache;
  List<ContentCard>? _dailyCache;
  Map<Category, CategoryTheme>? _themeCache;
  List<VideoEntry>? _videoCache;
  List<ExternalGame>? _externalGamesCache;

  ContentRepository(this.prefs);

  Future<Directory> get _dir async => _supportDir ??= await getApplicationSupportDirectory();

  Future<File> _localFile(String relPath) async {
    final dir = await _dir;
    final file = File('${dir.path}/$relPath');
    await file.parent.create(recursive: true);
    return file;
  }

  /// Copies bundled assets into local storage if no local copy exists yet.
  /// Safe to call every app start — it's a no-op once local files exist.
  Future<void> ensureBundledDefaults() async {
    await _copyAssetIfMissing('assets/content/evergreen_facts.json', 'evergreen_facts.json');
    await _copyAssetIfMissing('assets/content/theme.json', 'theme.json');
    await _copyAssetIfMissing('assets/content/external_games.json', 'external_games.json');
  }

  Future<void> _copyAssetIfMissing(String assetPath, String localRelPath) async {
    final file = await _localFile(localRelPath);
    if (await file.exists()) return;
    final data = await rootBundle.loadString(assetPath);
    await file.writeAsString(data);
  }

  /// Best-effort network sync — never throws; callers don't need to handle
  /// failure specially, the app just keeps using what it already has.
  Future<void> syncWithRemote() async {
    try {
      final manifest = await _fetchManifest();
      if (manifest == null) return;

      final lastSynced = prefs.lastSyncedManifest;

      if (manifest.evergreenVersion > lastSynced.evergreenVersion) {
        await _fetchAndSave('evergreen_facts.json', 'evergreen_facts.json');
        await _fetchAndSave('theme.json', 'theme.json');
        _evergreenCache = null;
        _themeCache = null;
      }

      if (manifest.videosVersion > lastSynced.videosVersion) {
        await _fetchAndSave('videos/index.json', 'videos/index.json');
        _videoCache = null;
      }

      if (manifest.externalGamesVersion > lastSynced.externalGamesVersion) {
        await _fetchAndSave('external_games.json', 'external_games.json');
        _externalGamesCache = null;
      }

      final alreadyHave = prefs.downloadedDailyDates.toSet();
      final toFetch = manifest.dailyDates
          .where((d) => !alreadyHave.contains(d))
          .toList()
        ..sort();
      final capped = toFetch.length > maxDailyBackfillDays
          ? toFetch.sublist(toFetch.length - maxDailyBackfillDays)
          : toFetch;

      for (final date in capped) {
        final ok = await _fetchAndSave('daily/$date.json', 'daily/$date.json');
        if (ok) alreadyHave.add(date);
      }
      await prefs.setDownloadedDailyDates(alreadyHave.toList()..sort());
      if (capped.isNotEmpty) _dailyCache = null;

      await prefs.setLastSyncedManifest(manifest);
    } catch (_) {
      // Network hiccup, CDN not configured yet, offline — the app keeps
      // working from bundled/local content regardless.
    }
  }

  Future<ContentManifest?> _fetchManifest() async {
    try {
      final res = await http
          .get(Uri.parse('${contentBaseUrl}manifest.json'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return ContentManifest.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _fetchAndSave(String remoteRelPath, String localRelPath) async {
    try {
      final url = '$contentBaseUrl$remoteRelPath';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return false;
      final file = await _localFile(localRelPath);
      await file.writeAsString(res.body);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<ContentCard>> _loadEvergreen() async {
    if (_evergreenCache != null) return _evergreenCache!;
    final file = await _localFile('evergreen_facts.json');
    if (!await file.exists()) return _evergreenCache = [];
    final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
    return _evergreenCache =
        raw.map((e) => ContentCard.fromEvergreenJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ContentCard>> _loadDaily() async {
    if (_dailyCache != null) return _dailyCache!;
    final cards = <ContentCard>[];
    for (final date in prefs.downloadedDailyDates) {
      final file = await _localFile('daily/$date.json');
      if (!await file.exists()) continue;
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      cards.addAll(raw.map((e) => ContentCard.fromDailyJson(e as Map<String, dynamic>)));
    }
    return _dailyCache = cards;
  }

  /// The full pool of cards available locally, evergreen + accumulated
  /// daily content, filtered to ones that actually have [language] content.
  Future<List<ContentCard>> loadPool(AppLanguage language) async {
    final evergreen = await _loadEvergreen();
    final daily = await _loadDaily();
    return [...evergreen, ...daily].where((c) => c.hasLanguage(language)).toList();
  }

  /// The evergreen bank specifically, in stable on-disk order — used as the
  /// sampling source for the on-device daily game (see DailyGameGenerator).
  Future<List<ContentCard>> loadEvergreenForGame() => _loadEvergreen();

  Future<Map<Category, CategoryTheme>> loadTheme() async {
    if (_themeCache != null) return _themeCache!;
    final file = await _localFile('theme.json');
    if (!await file.exists()) return _themeCache = {};
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final map = <Category, CategoryTheme>{};
    raw.forEach((key, value) {
      map[Category.fromWire(key)] = CategoryTheme.fromJson(value as Map<String, dynamic>);
    });
    return _themeCache = map;
  }

  Future<List<VideoEntry>> loadVideos() async {
    if (_videoCache != null) return _videoCache!;
    final file = await _localFile('videos/index.json');
    if (!await file.exists()) return _videoCache = [];
    final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
    return _videoCache = raw
        .map((e) => VideoEntry.fromJson(e as Map<String, dynamic>))
        .where((v) => v.active)
        .toList();
  }

  /// Curated links to external, legitimate brain-game websites — opened in
  /// the browser, never embedded (see ExternalGame's doc comment for why).
  Future<List<ExternalGame>> loadExternalGames() async {
    if (_externalGamesCache != null) return _externalGamesCache!;
    final file = await _localFile('external_games.json');
    if (!await file.exists()) return _externalGamesCache = [];
    final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
    return _externalGamesCache =
        raw.map((e) => ExternalGame.fromJson(e as Map<String, dynamic>)).toList();
  }
}
