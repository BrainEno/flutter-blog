import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ThemeState {
  final ThemeMode themeMode;
  const ThemeState(this.themeMode);
}

sealed class ThemeEvent {}

class InitializeTheme extends ThemeEvent {}

class ToggleTheme extends ThemeEvent {
  /// The resolved brightness is needed only while following the system theme.
  final Brightness systemBrightness;
  ToggleTheme({this.systemBrightness = Brightness.dark});
}

class SetThemeMode extends ThemeEvent {
  final ThemeMode themeMode;
  SetThemeMode(this.themeMode);
}

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  final ThemePreferenceStore _store;

  ThemeBloc(this._store) : super(const ThemeState(ThemeMode.system)) {
    // Serialize initialization and every change. A slow load or write must
    // never overwrite a newer choice or lose rapid toggles.
    on<ThemeEvent>(
      _onThemeEvent,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    add(InitializeTheme());
  }

  Future<void> _onThemeEvent(
    ThemeEvent event,
    Emitter<ThemeState> emit,
  ) async {
    if (event is InitializeTheme) {
      emit(ThemeState(await _store.load()));
      return;
    }

    final ThemeMode mode;
    if (event is SetThemeMode) {
      mode = event.themeMode;
    } else if (event is ToggleTheme) {
      final isDark = state.themeMode == ThemeMode.dark ||
          (state.themeMode == ThemeMode.system &&
              event.systemBrightness == Brightness.dark);
      mode = isDark ? ThemeMode.light : ThemeMode.dark;
    } else {
      return;
    }
    await _store.save(mode);
    emit(ThemeState(mode));
  }
}
