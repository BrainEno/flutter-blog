import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/content_locale.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:belog/core/l10n/locale_preference_store.dart';
import 'package:belog/core/l10n/sqlite_locale_preference_store.dart';
import 'package:belog/core/storage/app_database.dart';
import 'package:belog/core/theme/sqlite_theme_store.dart';
import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:belog/features/blog/data/datasources/sqlite_reading_history_store.dart';
import 'package:belog/features/blog/data/read_aloud/platform_speech_engine.dart';
import 'package:belog/features/blog/data/read_aloud/sqlite_read_aloud_preferences.dart';
import 'package:belog/features/blog/data/reader/sqlite_reader_text_size_store.dart';
import 'package:belog/features/blog/domain/read_aloud/read_aloud_settings.dart';
import 'package:belog/features/blog/domain/reader/reader_text_size.dart';
import 'package:belog/features/blog/domain/repositories/reading_history_store.dart';
import 'package:belog/features/blog/presentation/read_aloud/speech_coordinator.dart';
import 'package:belog/features/blog/presentation/viewer/reader_text_size_controller.dart';
import 'package:get_it/get_it.dart';

/// App-wide state that every feature reads: the database, the authenticated
/// client and its session, theme and language, device-local reading history,
/// read-aloud, the article text size, and the signed-in user.
void registerCoreModule(GetIt locator, DependencyContext context) {
  final database = context.database;
  locator
    ..registerLazySingleton(() => database)
    ..registerLazySingleton(() => context.apiClient)
    ..registerLazySingleton(() => context.sessionManager)
    ..registerLazySingleton<ThemePreferenceStore>(
      () => SqliteThemePreferenceStore(locator<AppDatabase>()),
    )
    // Device-local reading history (issue #22); never synced anywhere.
    ..registerLazySingleton<ReadingHistoryStore>(
      () => SqliteReadingHistoryStore(database, apiBaseUrl: context.apiBaseUrl),
    )
    ..registerLazySingleton<ReadAloudPreferences>(
      () => SqliteReadAloudPreferences(database),
    )
    // The article text size: one device-wide choice every open article
    // listens to.
    ..registerLazySingleton<ReaderTextSizeStore>(
      () => SqliteReaderTextSizeStore(database),
    )
    ..registerLazySingleton(() => ReaderTextSizeController(locator()))
    // One coordinator/channel for the whole app, shared by retained tab stacks.
    ..registerLazySingleton(() => SpeechCoordinator(PlatformSpeechEngine()))
    ..registerLazySingleton(() => ThemeBloc(locator()))
    // Issue #108: the in-app language choice, persisted next to the theme.
    ..registerLazySingleton<LocalePreferenceStore>(
      () => SqliteLocalePreferenceStore(locator<AppDatabase>()),
    )
    // The one content language every request and the offline cache read from;
    // the language bloc writes it before the interface rebuilds.
    ..registerLazySingleton<ContentLocale>(() => ContentLocale())
    ..registerLazySingleton(
      () => LocaleBloc(locator(), contentLocale: locator()),
    )
    ..registerLazySingleton(() => AppUserCubit());
}
