import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/image_cache_config.dart';
import 'feed_controller.dart';
import 'feed_item.dart';
import 'feed_card_tile.dart';
import 'youtube_card_tile.dart';

/// How many cards ahead of the current one to start downloading images for,
/// so by the time the user swipes there the image is already decoded and
/// cached — no visible pop-in/loading flash on the card itself.
const int _precacheAhead = 3;

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _pageController = PageController();
  int _lastPrecacheFromIndex = -1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _precacheFrom(List<FeedItem> items, int index) {
    if (index == _lastPrecacheFromIndex) return;
    _lastPrecacheFromIndex = index;
    final end = (index + _precacheAhead).clamp(0, items.length);
    for (var i = index; i < end; i++) {
      final item = items[i];
      if (item is CardFeedItem && item.card.imageUrl.isNotEmpty) {
        precacheImage(
          CachedNetworkImageProvider(item.card.imageUrl, cacheManager: cardImageCacheManager),
          context,
        );
      }
    }
  }

  void _onPageChanged(int index, List<FeedItem> items) {
    ref.read(feedControllerProvider.notifier).onIndexViewed(index);
    _precacheFrom(items, index);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(feedControllerProvider);

    if (state.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (state.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "No content yet — check your connection and reopen the app.",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // First frame after content loads: get a head start on the opening
    // cards before the user has even swiped once.
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheFrom(state.items, 0));

    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: state.items.length,
        onPageChanged: (index) => _onPageChanged(index, state.items),
        itemBuilder: (context, index) {
          final item = state.items[index];
          return switch (item) {
            CardFeedItem() => FeedCardTile(card: item.card),
            VideoFeedItem() => YoutubeCardTile(video: item.video),
          };
        },
      ),
    );
  }
}
