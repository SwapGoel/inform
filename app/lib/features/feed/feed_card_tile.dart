import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../../data/models.dart';
import 'wallpaper_card_view.dart';

/// A single feed card: tap anywhere to open its source article (if it has
/// one). Deliberately no floating buttons over the card itself — wallpaper
/// setting is handled globally now (Settings' auto-rotating wallpaper),
/// so a per-card control would just be redundant clutter on every card.
class FeedCardTile extends ConsumerWidget {
  final ContentCard card;

  const FeedCardTile({super.key, required this.card});

  Future<void> _openSourceArticle() async {
    final uri = Uri.tryParse(card.sourceUrl);
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!opened) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A Custom Tabs-capable browser isn't guaranteed on every device —
      // fall back to whatever can open a plain link at all.
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        // Nothing can open it; nothing more to do.
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final themeAsync = ref.watch(_categoryThemeProvider);

    return GestureDetector(
      onTap: card.sourceUrl.isNotEmpty ? _openSourceArticle : null,
      child: themeAsync.when(
        data: (themeMap) => WallpaperCardView(card: card, theme: themeMap[card.category], language: language),
        loading: () => WallpaperCardView(card: card, theme: null, language: language),
        error: (_, _) => WallpaperCardView(card: card, theme: null, language: language),
      ),
    );
  }
}

final _categoryThemeProvider = FutureProvider((ref) {
  return ref.watch(contentRepositoryProvider).loadTheme();
});
