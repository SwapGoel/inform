import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/image_cache_config.dart';
import '../../data/models.dart';
import '../../providers.dart';

/// An educational video interleaved into the feed. Uses the IFrame player
/// (lightweight, no full in-app WebView browser) and only initializes
/// playback when the user taps play — never autoplays, to keep scrolling
/// light on data/battery.
class YoutubeCardTile extends ConsumerStatefulWidget {
  final VideoEntry video;

  const YoutubeCardTile({super.key, required this.video});

  @override
  ConsumerState<YoutubeCardTile> createState() => _YoutubeCardTileState();
}

class _YoutubeCardTileState extends ConsumerState<YoutubeCardTile> {
  YoutubePlayerController? _controller;

  void _startPlayback() {
    setState(() {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: widget.video.videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(showFullscreenButton: true),
      );
    });
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final controller = _controller;

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: controller == null
                    ? _PlayPrompt(onTap: _startPlayback, video: widget.video)
                    : YoutubePlayer(controller: controller),
              ),
              const SizedBox(height: 20),
              Text(
                widget.video.titleFor(language),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                widget.video.channelTitle,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayPrompt extends StatelessWidget {
  final VoidCallback onTap;
  final VideoEntry video;

  const _PlayPrompt({required this.onTap, required this.video});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(16),
          image: DecorationImage(
            image: CachedNetworkImageProvider(
              'https://i.ytimg.com/vi/${video.videoId}/hqdefault.jpg',
              cacheManager: cardImageCacheManager,
            ),
            fit: BoxFit.cover,
            onError: (_, _) {},
          ),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
          ),
        ),
      ),
    );
  }
}
