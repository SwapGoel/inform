import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/content_repository.dart';
import '../../data/local_prefs.dart';
import '../../data/models.dart';
import '../../providers.dart';
import 'feed_item.dart';

class FeedState {
  final List<FeedItem> items;
  final bool isLoading;
  final bool isEmpty;

  const FeedState({required this.items, required this.isLoading, required this.isEmpty});

  static const initial = FeedState(items: [], isLoading: true, isEmpty: false);

  FeedState copyWith({List<FeedItem>? items, bool? isLoading, bool? isEmpty}) => FeedState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isEmpty: isEmpty ?? this.isEmpty,
      );
}

/// Owns the endless-scroll feed: samples from the local content pool
/// (rebuilt via ContentRepository, which merges the bundled evergreen bank
/// with anything synced from the CDN), interleaves video cards, and
/// reshuffles-excluding-recent once the current batch runs low so scrolling
/// never visibly "ends" even though the underlying pool is finite.
class FeedController extends StateNotifier<FeedState> {
  final ContentRepository _repository;
  final LocalPrefs _prefs;
  final AppLanguage _language;
  final Random _random = Random();

  List<ContentCard> _pool = [];
  List<VideoEntry> _videos = [];
  final List<String> _sessionShown = [];

  FeedController(this._repository, this._prefs, this._language) : super(FeedState.initial) {
    _load();
  }

  Future<void> _load() async {
    _pool = await _repository.loadPool(_language);
    _videos = await _repository.loadVideos();
    if (_pool.isEmpty) {
      state = state.copyWith(isLoading: false, isEmpty: true);
      return;
    }
    final batch = _buildBatch();
    state = FeedState(items: batch, isLoading: false, isEmpty: false);
  }

  List<FeedItem> _buildBatch() {
    final recentlySeen = _prefs.recentlySeenIds.toSet();
    var candidates = _pool.where((c) => !recentlySeen.contains(c.id)).toList();
    if (candidates.length < 10) {
      // Pool nearly exhausted relative to the recent-exclusion window —
      // recycle everything rather than starving the feed.
      candidates = List.of(_pool);
    }
    candidates.shuffle(_random);

    final items = <FeedItem>[];
    var sinceLastVideo = 0;
    for (final card in candidates) {
      items.add(CardFeedItem(card));
      sinceLastVideo++;
      if (_videos.isNotEmpty && sinceLastVideo >= feedVideoInterval) {
        items.add(VideoFeedItem(_videos[_random.nextInt(_videos.length)]));
        sinceLastVideo = 0;
      }
    }
    return items;
  }

  /// Call as the user scrolls; extends the feed once they're near the end.
  void onIndexViewed(int index) {
    if (index >= state.items.length - 5) {
      state = state.copyWith(items: [...state.items, ..._buildBatch()]);
    }

    final viewed = state.items[index];
    if (viewed is CardFeedItem) {
      _sessionShown.add(viewed.card.id);
      if (_sessionShown.length >= 20) {
        _flushSeen();
      }
    }
  }

  void _flushSeen() {
    if (_sessionShown.isEmpty) return;
    final combined = [..._prefs.recentlySeenIds, ..._sessionShown];
    final capped =
        combined.length > recentlySeenCap ? combined.sublist(combined.length - recentlySeenCap) : combined;
    _prefs.setRecentlySeenIds(capped);
    _sessionShown.clear();
  }

  @override
  void dispose() {
    _flushSeen();
    super.dispose();
  }
}

final feedControllerProvider = StateNotifierProvider<FeedController, FeedState>((ref) {
  final language = ref.watch(languageProvider);
  return FeedController(
    ref.watch(contentRepositoryProvider),
    ref.watch(localPrefsProvider),
    language,
  );
});
