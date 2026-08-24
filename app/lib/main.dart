import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/content_repository.dart';
import 'data/local_prefs.dart';
import 'features/auto_wallpaper/auto_wallpaper_service.dart';
import 'features/lock_card/lock_card_notification_service.dart';
import 'providers.dart';

// Kept alive only to hold the listener registration; never read directly
// (see where it's assigned, in main()).
// ignore: unused_element
AppLifecycleListener? _lifecycleListener;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await LocalPrefs.create();
  final repository = ContentRepository(prefs);
  // Guarantees the app has content to show even fully offline on first
  // launch, before any network sync has had a chance to run. This is the
  // only thing that must finish before the first frame.
  await repository.ensureBundledDefaults();

  // See LocalPrefs.isAppInForeground's doc comment — this is how
  // AutoWallpaperService's background isolate knows not to change the
  // system wallpaper while the app is actively on screen. Set immediately
  // (not just on future transitions), since a fresh launch starts resumed.
  // Held in a top-level variable (not just a local) so it isn't eligible
  // for garbage collection for the lifetime of the app.
  await prefs.setAppInForeground(true);
  _lifecycleListener = AppLifecycleListener(
    onResume: () => prefs.setAppInForeground(true),
    onInactive: () => prefs.setAppInForeground(false),
    onHide: () => prefs.setAppInForeground(false),
    onPause: () => prefs.setAppInForeground(false),
    onDetach: () => prefs.setAppInForeground(false),
  );

  runApp(
    ProviderScope(
      overrides: [
        localPrefsProvider.overrideWithValue(prefs),
        contentRepositoryProvider.overrideWithValue(repository),
      ],
      child: const InformApp(),
    ),
  );

  // Everything below is best-effort background setup — none of it should
  // delay the first frame the user sees.
  unawaited(repository.syncWithRemote());
  unawaited(_setupBackgroundFeatures(prefs));
}

Future<void> _setupBackgroundFeatures(LocalPrefs prefs) async {
  await AutoWallpaperService.initialize();
  await AutoWallpaperService.syncScheduledWork(prefs);

  await LockCardNotificationService.initialize();
}
