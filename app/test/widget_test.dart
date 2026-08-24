import 'package:flutter_test/flutter_test.dart';

import 'package:inform/data/models.dart';

void main() {
  test('ContentCard.hasLanguage reflects which language actually has content', () {
    const card = ContentCard(
      id: 'x',
      category: Category.science,
      headlineEn: 'Hello',
      summaryEn: 'World',
      headlineHi: '',
      summaryHi: '',
      sourceUrl: '',
      sourceName: '',
      isEvergreen: false,
    );

    expect(card.hasLanguage(AppLanguage.en), isTrue);
    expect(card.hasLanguage(AppLanguage.hi), isFalse);
  });

  test('Category.fromWire round-trips through wireValue', () {
    for (final category in Category.values) {
      expect(Category.fromWire(category.wireValue), category);
    }
  });
}
