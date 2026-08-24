import '../../data/models.dart';

sealed class FeedItem {
  const FeedItem();
}

class CardFeedItem extends FeedItem {
  final ContentCard card;
  const CardFeedItem(this.card);
}

class VideoFeedItem extends FeedItem {
  final VideoEntry video;
  const VideoFeedItem(this.video);
}
