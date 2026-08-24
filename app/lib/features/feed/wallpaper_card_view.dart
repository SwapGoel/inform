import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/color_utils.dart';
import '../../core/image_cache_config.dart';
import '../../data/models.dart';
import 'category_icons.dart';

/// The pure visual wallpaper design — no buttons, no interaction — so it can
/// be rendered identically both in the scrolling feed and when rasterized
/// for "Set as Wallpaper" (via RepaintBoundary around exactly this widget).
/// When the card has a real, license-checked photo (see ContentCard's doc
/// comment), it fills the background Inshorts-style with a dark scrim for
/// text legibility; otherwise it falls back to the plain gradient design —
/// most cards still render with zero image download at all.
class WallpaperCardView extends StatefulWidget {
  final ContentCard card;
  final CategoryTheme? theme;
  final AppLanguage language;

  const WallpaperCardView({
    super.key,
    required this.card,
    required this.theme,
    required this.language,
  });

  @override
  State<WallpaperCardView> createState() => _WallpaperCardViewState();
}

class _WallpaperCardViewState extends State<WallpaperCardView> {
  // Tracks whether the network photo has actually finished loading — the
  // "Photo: <credit>" caption is only ever shown once this is true, since
  // showing it unconditionally (keyed only on whether the card *has* an
  // imageUrl) produced a confusing mismatch on a slow connection or a load
  // failure: the credit line would appear while the card behind it was
  // still just the plain gradient placeholder, looking like a missing image
  // even though the data was correct.
  bool _imageLoaded = false;

  @override
  void didUpdateWidget(WallpaperCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.imageUrl != widget.card.imageUrl) {
      _imageLoaded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final language = widget.language;
    final t = widget.theme;
    final gradientFrom = t != null ? colorFromHex(t.gradientFrom) : const Color(0xFF1F2937);
    final gradientTo = t != null ? colorFromHex(t.gradientTo) : const Color(0xFF374151);
    final accent = t != null ? colorFromHex(t.accent) : Colors.white70;
    final categoryLabel = t?.labelFor(language) ?? '';
    final hasImage = card.imageUrl.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImage)
          CachedNetworkImage(
            imageUrl: card.imageUrl,
            cacheManager: cardImageCacheManager,
            fit: BoxFit.cover,
            memCacheWidth: 1080,
            fadeInDuration: const Duration(milliseconds: 200),
            fadeOutDuration: const Duration(milliseconds: 0),
            placeholder: (context, url) => Container(
              color: gradientFrom,
            ),
            imageBuilder: (context, imageProvider) {
              if (!_imageLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _imageLoaded = true);
                });
              }
              return Image(image: imageProvider, fit: BoxFit.cover);
            },
            errorWidget: (context, url, error) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [gradientFrom, gradientTo],
                ),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [gradientFrom, gradientTo],
              ),
            ),
          ),
        if (hasImage)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.transparent, Colors.black87],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(iconForName(t?.iconName ?? ''), color: accent, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        categoryLabel,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  card.headlineFor(language),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  card.summaryFor(language),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 17,
                    height: 1.4,
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        card.sourceName,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'INFORM',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                if (_imageLoaded && card.imageAttribution.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Photo: ${card.imageAttribution}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
