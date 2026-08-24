enum Category {
  currentEvents,
  history,
  geography,
  polity,
  economy,
  environment,
  science,
  maths;

  /// The wire/JSON representation used by the content pipeline (snake_case).
  String get wireValue => switch (this) {
        Category.currentEvents => 'current_events',
        Category.history => 'history',
        Category.geography => 'geography',
        Category.polity => 'polity',
        Category.economy => 'economy',
        Category.environment => 'environment',
        Category.science => 'science',
        Category.maths => 'maths',
      };

  static Category fromWire(String value) => Category.values.firstWhere(
        (c) => c.wireValue == value,
        orElse: () => Category.currentEvents,
      );
}

enum AppLanguage {
  en,
  hi;

  static AppLanguage fromCode(String? code) =>
      code == 'hi' ? AppLanguage.hi : AppLanguage.en;
}

class CategoryTheme {
  final String labelEn;
  final String labelHi;
  final String gradientFrom;
  final String gradientTo;
  final String accent;
  final String iconName;

  const CategoryTheme({
    required this.labelEn,
    required this.labelHi,
    required this.gradientFrom,
    required this.gradientTo,
    required this.accent,
    required this.iconName,
  });

  factory CategoryTheme.fromJson(Map<String, dynamic> json) => CategoryTheme(
        labelEn: json['label_en'] as String,
        labelHi: json['label_hi'] as String,
        gradientFrom: json['gradientFrom'] as String,
        gradientTo: json['gradientTo'] as String,
        accent: json['accent'] as String,
        iconName: json['iconName'] as String,
      );

  String labelFor(AppLanguage lang) => lang == AppLanguage.hi ? labelHi : labelEn;
}

/// A single item in the feed — either an evergreen fact or a daily-ingested
/// card, normalized to one shape so the feed doesn't need to care which.
class ContentCard {
  final String id;
  final Category category;
  final String headlineEn;
  final String summaryEn;
  final String headlineHi;
  final String summaryHi;
  final String sourceUrl;
  final String sourceName;
  final bool isEvergreen;
  /// Only ever set when Wikimedia Commons' own license metadata confirmed
  /// the photo is freely reusable (see the content-pipeline's
  /// wikimediaImages.ts) — never a scraped news-article image. Empty when
  /// no safe image was found; the card then renders the plain gradient
  /// design instead.
  final String imageUrl;
  final String imageAttribution;

  const ContentCard({
    required this.id,
    required this.category,
    required this.headlineEn,
    required this.summaryEn,
    required this.headlineHi,
    required this.summaryHi,
    required this.sourceUrl,
    required this.sourceName,
    required this.isEvergreen,
    this.imageUrl = '',
    this.imageAttribution = '',
  });

  String headlineFor(AppLanguage lang) => lang == AppLanguage.hi ? headlineHi : headlineEn;
  String summaryFor(AppLanguage lang) => lang == AppLanguage.hi ? summaryHi : summaryEn;

  /// True if this card actually has content in [lang] — daily-ingested cards
  /// are usually single-language; evergreen facts have both.
  bool hasLanguage(AppLanguage lang) => headlineFor(lang).isNotEmpty;

  factory ContentCard.fromEvergreenJson(Map<String, dynamic> json) {
    final sourceUrl = json['sourceUrl'] as String? ?? '';
    return ContentCard(
      id: json['id'] as String,
      category: Category.fromWire(json['category'] as String),
      headlineEn: json['headline_en'] as String,
      summaryEn: json['summary_en'] as String,
      headlineHi: json['headline_hi'] as String,
      summaryHi: json['summary_hi'] as String,
      sourceUrl: sourceUrl,
      // The only source evergreen facts ever link to is the Wikipedia
      // article their wikipediaTitle was derived from.
      sourceName: sourceUrl.isNotEmpty ? 'Wikipedia' : '',
      isEvergreen: true,
      imageUrl: json['imageUrl'] as String? ?? '',
      imageAttribution: json['imageAttribution'] as String? ?? '',
    );
  }

  factory ContentCard.fromDailyJson(Map<String, dynamic> json) {
    final language = json['language'] as String;
    final headline = json['headline'] as String;
    final summary = json['summary'] as String;
    return ContentCard(
      id: json['cardId'] as String,
      category: Category.fromWire(json['category'] as String),
      headlineEn: language == 'en' ? headline : '',
      summaryEn: language == 'en' ? summary : '',
      headlineHi: language == 'hi' ? headline : '',
      summaryHi: language == 'hi' ? summary : '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      isEvergreen: false,
      imageUrl: json['imageUrl'] as String? ?? '',
      imageAttribution: json['imageAttribution'] as String? ?? '',
    );
  }
}

class VideoEntry {
  final String videoId;
  final String titleEn;
  final String titleHi;
  final String channelTitle;
  final Category category;
  final bool active;

  const VideoEntry({
    required this.videoId,
    required this.titleEn,
    required this.titleHi,
    required this.channelTitle,
    required this.category,
    required this.active,
  });

  String titleFor(AppLanguage lang) =>
      lang == AppLanguage.hi && titleHi.isNotEmpty ? titleHi : titleEn;

  factory VideoEntry.fromJson(Map<String, dynamic> json) => VideoEntry(
        videoId: json['videoId'] as String,
        titleEn: json['title_en'] as String? ?? '',
        titleHi: json['title_hi'] as String? ?? '',
        channelTitle: json['channelTitle'] as String? ?? '',
        category: Category.fromWire(json['category'] as String),
        active: json['active'] as bool? ?? false,
      );
}

class ContentManifest {
  final int evergreenVersion;
  final List<String> dailyDates;
  final int videosVersion;
  final int externalGamesVersion;

  const ContentManifest({
    required this.evergreenVersion,
    required this.dailyDates,
    required this.videosVersion,
    required this.externalGamesVersion,
  });

  static const empty =
      ContentManifest(evergreenVersion: 0, dailyDates: [], videosVersion: 0, externalGamesVersion: 0);

  factory ContentManifest.fromJson(Map<String, dynamic> json) => ContentManifest(
        evergreenVersion: json['evergreenVersion'] as int? ?? 0,
        dailyDates: (json['dailyDates'] as List<dynamic>? ?? []).cast<String>(),
        videosVersion: json['videosVersion'] as int? ?? 0,
        externalGamesVersion: json['externalGamesVersion'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'evergreenVersion': evergreenVersion,
        'dailyDates': dailyDates,
        'videosVersion': videosVersion,
        'externalGamesVersion': externalGamesVersion,
      };
}

class ExternalGame {
  final String id;
  final String name;
  final String descriptionEn;
  final String descriptionHi;
  final String url;
  final String imageUrl;

  const ExternalGame({
    required this.id,
    required this.name,
    required this.descriptionEn,
    required this.descriptionHi,
    required this.url,
    this.imageUrl = '',
  });

  String descriptionFor(AppLanguage lang) =>
      lang == AppLanguage.hi ? descriptionHi : descriptionEn;

  factory ExternalGame.fromJson(Map<String, dynamic> json) => ExternalGame(
        id: json['id'] as String,
        name: json['name'] as String,
        descriptionEn: json['description_en'] as String? ?? '',
        descriptionHi: json['description_hi'] as String? ?? '',
        url: json['url'] as String,
        imageUrl: json['imageUrl'] as String? ?? '',
      );
}

/// One term/clue pair in the daily mind game.
class GameTerm {
  final String term;
  final String clueEn;
  final String clueHi;
  final Category category;

  const GameTerm({
    required this.term,
    required this.clueEn,
    required this.clueHi,
    required this.category,
  });

  String clueFor(AppLanguage lang) => lang == AppLanguage.hi ? clueHi : clueEn;
}
