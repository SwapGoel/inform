import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'color_utils.dart';
import '../features/feed/category_icons.dart';
import '../data/models.dart';

/// Renders a wallpaper card straight to PNG bytes using raw dart:ui drawing
/// (PictureRecorder/Canvas/TextPainter) — no widget tree, no BuildContext.
/// This is what makes it possible to generate a fresh wallpaper from a
/// background task (WorkManager isolate has no attached UI to build
/// widgets against), mirroring the same visual design as WallpaperCardView.
class WallpaperRenderer {
  static const int width = 1080;
  static const int height = 2280;

  static Future<Uint8List> render({
    required ContentCard card,
    required CategoryTheme? theme,
    required AppLanguage language,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    final gradientFrom = theme != null ? colorFromHex(theme.gradientFrom) : const Color(0xFF1F2937);
    final gradientTo = theme != null ? colorFromHex(theme.gradientTo) : const Color(0xFF374151);
    final accent = theme != null ? colorFromHex(theme.accent) : Colors.white70;

    ui.Image? photo;
    if (card.imageUrl.isNotEmpty) {
      photo = await _tryDownloadImage(card.imageUrl);
    }

    final fullRect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    if (photo != null) {
      _drawImageCover(canvas, photo, fullRect);
      final scrimPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, height * 0.45),
          Offset(0, height.toDouble()),
          [Colors.transparent, Colors.black87],
        );
      canvas.drawRect(fullRect, scrimPaint);
    } else {
      final bgPaint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(width.toDouble(), height.toDouble()),
          [gradientFrom, gradientTo],
        );
      canvas.drawRect(fullRect, bgPaint);
    }

    _drawCategoryBadge(canvas, theme, language, accent);
    _drawText(canvas, card, language);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static Future<ui.Image?> _tryDownloadImage(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final codec = await ui.instantiateImageCodec(res.bodyBytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static void _drawImageCover(Canvas canvas, ui.Image image, Rect dstRect) {
    final srcAspect = image.width / image.height;
    final dstAspect = dstRect.width / dstRect.height;
    late Rect srcRect;
    if (srcAspect > dstAspect) {
      final srcWidth = image.height * dstAspect;
      final dx = (image.width - srcWidth) / 2;
      srcRect = Rect.fromLTWH(dx, 0, srcWidth, image.height.toDouble());
    } else {
      final srcHeight = image.width / dstAspect;
      final dy = (image.height - srcHeight) / 2;
      srcRect = Rect.fromLTWH(0, dy, image.width.toDouble(), srcHeight);
    }
    canvas.drawImageRect(image, srcRect, dstRect, Paint());
  }

  static void _drawCategoryBadge(
    Canvas canvas,
    CategoryTheme? theme,
    AppLanguage language,
    Color accent,
  ) {
    const badgeLeft = 56.0;
    const badgeTop = 96.0;
    const badgeSize = 88.0;

    final badgePaint = Paint()..color = Colors.white.withValues(alpha: 0.16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(badgeLeft, badgeTop, badgeSize, badgeSize),
        const Radius.circular(22),
      ),
      badgePaint,
    );

    final iconData = iconForName(theme?.iconName ?? '');
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          fontSize: 44,
          color: accent,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(
        badgeLeft + (badgeSize - iconPainter.width) / 2,
        badgeTop + (badgeSize - iconPainter.height) / 2,
      ),
    );

    final label = theme?.labelFor(language) ?? '';
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 30, letterSpacing: 0.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - badgeLeft * 2 - badgeSize - 28);
    labelPainter.paint(canvas, Offset(badgeLeft + badgeSize + 28, badgeTop + (badgeSize - labelPainter.height) / 2));
  }

  static void _drawText(Canvas canvas, ContentCard card, AppLanguage language) {
    const leftPad = 56.0;
    final rightPad = width - 56.0;
    final maxWidth = rightPad - leftPad;
    double y = height - 220;

    final footerBrand = TextPainter(
      text: const TextSpan(
        text: 'INFORM',
        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 26, letterSpacing: 2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    footerBrand.paint(canvas, Offset(rightPad - footerBrand.width, height - 96.0));

    if (card.sourceName.isNotEmpty) {
      final sourcePainter = TextPainter(
        text: TextSpan(
          text: card.sourceName,
          style: const TextStyle(color: Colors.white60, fontSize: 26),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth - footerBrand.width - 20);
      sourcePainter.paint(canvas, Offset(leftPad, height - 96.0));
    }

    final summaryPainter = TextPainter(
      text: TextSpan(
        text: card.summaryFor(language),
        style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 34, height: 1.4),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 6,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    y -= summaryPainter.height;
    summaryPainter.paint(canvas, Offset(leftPad, y));

    y -= 28;
    final headlinePainter = TextPainter(
      text: TextSpan(
        text: card.headlineFor(language),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 58, height: 1.2),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    y -= headlinePainter.height;
    headlinePainter.paint(canvas, Offset(leftPad, y));
  }
}
