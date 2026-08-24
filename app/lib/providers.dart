import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/content_repository.dart';
import 'data/local_prefs.dart';
import 'data/models.dart';

/// Both overridden with real instances in main() before runApp — these
/// throw if read before that override is in place, which should never
/// happen since ProviderScope's overrides apply from the first frame.
final localPrefsProvider = Provider<LocalPrefs>((ref) => throw UnimplementedError());
final contentRepositoryProvider =
    Provider<ContentRepository>((ref) => throw UnimplementedError());

final languageProvider = StateProvider<AppLanguage>(
  (ref) => ref.watch(localPrefsProvider).language,
);
