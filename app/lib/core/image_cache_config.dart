import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// A capped, LRU-evicting disk cache for the (relatively small) subset of
/// cards that have a real, license-checked photo — most cards are pure
/// native-rendered gradient/text and never touch this at all, so this stays
/// small even as the content pool grows into the thousands.
final CacheManager cardImageCacheManager = CacheManager(
  Config(
    'informCardImages',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 300,
  ),
);
