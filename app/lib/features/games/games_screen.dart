import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/image_cache_config.dart';
import '../../data/models.dart';
import '../../providers.dart';

/// A curated list of external brain-game websites — opened in the browser,
/// never embedded (see ExternalGame's doc comment in models.dart for why:
/// third-party games aren't freely embeddable, but linking out is always
/// fine, same as linking to a news source).
class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final externalGamesAsync = ref.watch(_externalGamesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Brain Games')),
      body: SafeArea(
        child: externalGamesAsync.when(
          data: (games) => games.isEmpty
              ? const Center(child: Text('Check your connection and reopen the app.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: games.length,
                  itemBuilder: (context, i) => _ExternalGameCard(game: games[i], language: language),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('Could not load games.')),
        ),
      ),
    );
  }
}

final _externalGamesProvider = FutureProvider((ref) {
  return ref.watch(contentRepositoryProvider).loadExternalGames();
});

class _ExternalGameCard extends StatelessWidget {
  final ExternalGame game;
  final AppLanguage language;

  const _ExternalGameCard({required this.game, required this.language});

  Future<void> _open() async {
    final uri = Uri.parse(game.url);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!opened) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        // Nothing can open it; nothing more to do.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: _open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (game.imageUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: game.imageUrl,
                  cacheManager: cardImageCacheManager,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.extension_outlined, size: 40)),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(game.name, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(game.descriptionFor(language)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.open_in_new),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
