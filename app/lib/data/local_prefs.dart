import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Thin wrapper around SharedPreferences — the only local persistence this
/// app needs (no Hive/Isar/sqflite; content JSON lives as plain files via
/// ContentRepository, not here).
class LocalPrefs {
  final SharedPreferences _prefs;

  LocalPrefs(this._prefs);

  static Future<LocalPrefs> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalPrefs(prefs);
  }

  // --- Onboarding / identity (all local-only, never transmitted) ---

  bool get hasOnboarded => _prefs.getBool('has_onboarded') ?? false;
  Future<void> setHasOnboarded(bool value) => _prefs.setBool('has_onboarded', value);

  String? get displayName => _prefs.getString('display_name');
  Future<void> setDisplayName(String? name) =>
      name == null || name.isEmpty ? _prefs.remove('display_name') : _prefs.setString('display_name', name);

  AppLanguage get language => AppLanguage.fromCode(_prefs.getString('language_code'));
  Future<void> setLanguage(AppLanguage lang) => _prefs.setString('language_code', lang.name);

  // --- Content sync bookkeeping ---

  ContentManifest get lastSyncedManifest {
    final raw = _prefs.getString('last_manifest');
    if (raw == null) return ContentManifest.empty;
    return ContentManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setLastSyncedManifest(ContentManifest manifest) =>
      _prefs.setString('last_manifest', jsonEncode(manifest.toJson()));

  List<String> get downloadedDailyDates =>
      _prefs.getStringList('downloaded_daily_dates') ?? [];

  Future<void> setDownloadedDailyDates(List<String> dates) =>
      _prefs.setStringList('downloaded_daily_dates', dates);

  // --- Feed dedup within this install ---

  List<String> get recentlySeenIds => _prefs.getStringList('recently_seen_ids') ?? [];

  Future<void> setRecentlySeenIds(List<String> ids) =>
      _prefs.setStringList('recently_seen_ids', ids);

  // --- Auto-rotating wallpaper ---

  /// On by default — it's the app's headline feature ("content on your lock
  /// screen without opening the app"), with an explicit off switch in
  /// Settings for anyone who finds automatic wallpaper changes unwelcome.
  bool get autoWallpaperEnabled => _prefs.getBool('auto_wallpaper_enabled') ?? true;

  Future<void> setAutoWallpaperEnabled(bool value) => _prefs.setBool('auto_wallpaper_enabled', value);

  /// Avoids repeating the same card back-to-back across rotations.
  String? get lastAutoWallpaperCardId => _prefs.getString('last_auto_wallpaper_card_id');

  Future<void> setLastAutoWallpaperCardId(String id) =>
      _prefs.setString('last_auto_wallpaper_card_id', id);

  // --- Lock-screen "tap next" card notification ---

  bool get lockCardEnabled => _prefs.getBool('lock_card_enabled') ?? true;

  Future<void> setLockCardEnabled(bool value) => _prefs.setBool('lock_card_enabled', value);

  String? get lastLockCardId => _prefs.getString('last_lock_card_id');

  Future<void> setLastLockCardId(String id) => _prefs.setString('last_lock_card_id', id);

  // --- Foreground state, for the background isolate to read ---

  /// Written by an AppLifecycleListener in the main isolate (see main.dart)
  /// and read by AutoWallpaperService's WorkManager callback, which runs in
  /// a completely separate isolate with no direct way to ask "is the app
  /// currently on screen?". SharedPreferences is the one piece of state
  /// both isolates actually share (same underlying file). This exists
  /// because calling WallpaperManager.setBitmap() while the app is
  /// foregrounded was confirmed (via logcat) to sometimes force a full
  /// MainActivity relaunch — Android's Material You theming reacts to the
  /// new wallpaper by recomputing a resource overlay, which isn't something
  /// any AndroidManifest configChanges declaration can suppress.
  bool get isAppInForeground => _prefs.getBool('is_app_in_foreground') ?? false;

  Future<void> setAppInForeground(bool value) => _prefs.setBool('is_app_in_foreground', value);
}
