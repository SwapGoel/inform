import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../data/content_repository.dart';
import '../../data/local_prefs.dart';

const int _notificationId = 4200;
const String _nextActionId = 'lock_card_next';
const String _channelId = 'lock_card_channel';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

/// A persistent, tap-to-advance card notification — the same standard
/// Android mechanism Spotify/YouTube Music use for lock-screen playback
/// controls (a notification with an action button), not a special
/// permission or OEM partnership. Shows the current card's headline/summary
/// (and photo, when the card has a license-checked one) right on the lock
/// screen; tapping "Next" swaps in another card in place, without
/// unlocking. This is NOT drag-to-scroll — that's not available to any
/// regular app on the lock screen — it's tap-to-advance.
class LockCardNotificationService {
  static Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> setEnabled(bool enabled, LocalPrefs prefs, ContentRepository repository) async {
    if (enabled) {
      await showNext(prefs, repository);
    } else {
      await _plugin.cancel(id: _notificationId);
    }
  }

  /// Picks a card (avoiding an immediate repeat of the last one shown) and
  /// shows/updates the lock-card notification with it.
  static Future<void> showNext(LocalPrefs prefs, ContentRepository repository) async {
    final language = prefs.language;
    final pool = await repository.loadPool(language);
    if (pool.isEmpty) return;

    final lastId = prefs.lastLockCardId;
    final candidates = pool.length > 1 ? pool.where((c) => c.id != lastId).toList() : pool;
    final card = candidates[Random().nextInt(candidates.length)];
    await prefs.setLastLockCardId(card.id);

    final themeMap = await repository.loadTheme();
    final theme = themeMap[card.category];
    final categoryLabel = theme?.labelFor(language) ?? '';
    final headline = card.headlineFor(language);
    final summary = card.summaryFor(language);

    StyleInformation styleInformation;
    if (card.imageUrl.isNotEmpty) {
      final imagePath = await _downloadToTempFile(card.imageUrl);
      styleInformation = imagePath != null
          ? BigPictureStyleInformation(
              FilePathAndroidBitmap(imagePath),
              contentTitle: '<b>$headline</b>',
              htmlFormatContentTitle: true,
              summaryText: summary,
            )
          : BigTextStyleInformation(summary, contentTitle: headline);
    } else {
      styleInformation = BigTextStyleInformation(summary, contentTitle: headline);
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      'Lock screen card',
      channelDescription: 'A fact card you can advance from your lock screen.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      onlyAlertOnce: true,
      styleInformation: styleInformation,
      actions: const [
        AndroidNotificationAction(_nextActionId, 'Next', showsUserInterface: false),
      ],
    );

    await _plugin.show(
      id: _notificationId,
      title: headline,
      body: categoryLabel,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  static Future<String?> _downloadToTempFile(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/lock_card_image.jpg');
      await file.writeAsBytes(res.bodyBytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}

void _onForegroundResponse(NotificationResponse response) {
  if (response.actionId == _nextActionId) {
    _advanceInBackground();
  }
}

@pragma('vm:entry-point')
void _onBackgroundResponse(NotificationResponse response) {
  if (response.actionId == _nextActionId) {
    _advanceInBackground();
  }
}

Future<void> _advanceInBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await LocalPrefs.create();
  final repository = ContentRepository(prefs);
  await repository.ensureBundledDefaults();
  await LockCardNotificationService.showNext(prefs, repository);
}
