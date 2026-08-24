import 'dart:io';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/wallpaper_renderer.dart';
import '../../data/content_repository.dart';
import '../../data/local_prefs.dart';
import '../lock_card/lock_card_notification_service.dart';

const String autoWallpaperTaskName = 'inform.autoWallpaperRotation';
const String autoWallpaperUniqueName = 'inform-auto-wallpaper-rotation';
const String immediateRunUniqueName = 'inform-auto-wallpaper-immediate';

/// Sets the actual system wallpaper (home + lock screen) automatically on a
/// schedule, via Android WorkManager — the closest a normal Play Store app
/// can get to "fresh content on your lock screen without opening the app".
/// WorkManager's interval is a *minimum*, not a guarantee: Android may delay
/// runs under battery/doze restrictions, so "every ~4 hours" is honest,
/// "exactly every 4 hours" is not.
class AutoWallpaperService {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  /// The periodic task drives BOTH the auto-wallpaper and the lock-card
  /// notification (see rotateNow), so it must keep running if either
  /// feature is on, and only stop once both are off. Call this any time
  /// either Settings toggle changes — never gate registration on a single
  /// flag in isolation.
  static Future<void> syncScheduledWork(LocalPrefs prefs) async {
    final shouldRun = prefs.autoWallpaperEnabled || prefs.lockCardEnabled;
    if (shouldRun) {
      await Workmanager().registerPeriodicTask(
        autoWallpaperUniqueName,
        autoWallpaperTaskName,
        frequency: const Duration(hours: 4),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      // WorkManager's periodic tasks do NOT run on registration — the first
      // execution waits a full interval (here, ~4 hours), which would mean a
      // fresh install shows nothing happening for hours. A separate one-off
      // task runs the same logic right away; `keep` means it only ever
      // fires once per install, not on every subsequent app launch.
      //
      // The 3-minute initialDelay matters more than it looks: rotateNow()
      // calls WallpaperManager.setBitmap(), and actually changing the live
      // system wallpaper triggers Android to recompute Material You's
      // wallpaper-based theming — which was confirmed (via logcat) to cause
      // a full MainActivity relaunch, sometimes taking 10+ seconds. Firing
      // that within seconds of a fresh install — exactly when a new user is
      // first onboarding and scrolling the feed — looked like the app
      // randomly restarting and reshuffling mid-scroll. Delaying it gives
      // the user a settled first session before this runs invisibly in the
      // background instead.
      await Workmanager().registerOneOffTask(
        immediateRunUniqueName,
        autoWallpaperTaskName,
        initialDelay: const Duration(minutes: 3),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    } else {
      await Workmanager().cancelByUniqueName(autoWallpaperUniqueName);
    }
  }

  /// Forces an immediate (re-)run of the periodic task registration,
  /// intentionally using `replace` — only for the rare case (Settings'
  /// "Update wallpaper now") where the user explicitly asked for a fresh
  /// run right away, not for routine enable/disable toggling.
  static Future<void> reregisterForImmediateRun() async {
    await Workmanager().registerPeriodicTask(
      autoWallpaperUniqueName,
      autoWallpaperTaskName,
      frequency: const Duration(hours: 4),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// The actual rotation logic — shared by the background callback and by
  /// "preview / do it now" if ever exposed in Settings. Also refreshes the
  /// lock-screen "tap next" card notification on the same cycle, so that
  /// doesn't go stale for users who never tap Next — one periodic
  /// background job covers both features rather than running two.
  static Future<bool> rotateNow() async {
    final prefs = await LocalPrefs.create();
    final repository = ContentRepository(prefs);
    await repository.ensureBundledDefaults();
    await repository.syncWithRemote();

    if (prefs.lockCardEnabled) {
      await LockCardNotificationService.showNext(prefs, repository);
    }

    if (!prefs.autoWallpaperEnabled) return true;

    // Actually changing the system wallpaper while the app is on screen was
    // confirmed (via logcat) to sometimes force a full Activity relaunch —
    // Android's Material You theming reacts to the new wallpaper by
    // recomputing a resource overlay, which briefly froze/reset the app
    // mid-scroll. Skipping this cycle when foregrounded is a better
    // trade-off than that: the wallpaper simply updates on the next
    // periodic run instead (every ~4 hours), once the app isn't actively
    // being looked at. The lock-card notification above still refreshes
    // either way, since posting a notification doesn't have this problem.
    if (prefs.isAppInForeground) return true;

    final language = prefs.language;
    final pool = await repository.loadPool(language);
    if (pool.isEmpty) return false;

    final lastId = prefs.lastAutoWallpaperCardId;
    final candidates = pool.length > 1 ? pool.where((c) => c.id != lastId).toList() : pool;
    final card = candidates[Random().nextInt(candidates.length)];

    final themeMap = await repository.loadTheme();
    final bytes = await WallpaperRenderer.render(
      card: card,
      theme: themeMap[card.category],
      language: language,
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/inform_auto_wallpaper.png');
    await file.writeAsBytes(bytes);

    final ok = await WallpaperManagerFlutter().setWallpaper(file, WallpaperManagerFlutter.bothScreens);
    if (ok) await prefs.setLastAutoWallpaperCardId(card.id);
    return ok;
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      return await AutoWallpaperService.rotateNow();
    } catch (_) {
      // A missed rotation isn't worth crash-looping the background task —
      // it just quietly tries again next cycle.
      return false;
    }
  });
}
