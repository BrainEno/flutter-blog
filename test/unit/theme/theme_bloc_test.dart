import 'dart:async';

import 'package:belog/core/theme/theme_bloc.dart';
import 'package:belog/core/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeThemeStore implements ThemePreferenceStore {
  ThemeMode mode;
  Completer<ThemeMode>? loadGate;
  final List<ThemeMode> writes = [];

  FakeThemeStore(this.mode);

  @override
  Future<ThemeMode> load() async {
    if (loadGate != null) return loadGate!.future;
    return mode;
  }

  @override
  Future<void> save(ThemeMode value) async {
    writes.add(value);
    mode = value;
  }
}

void main() {
  test('first launch uses system and does not write a preference', () async {
    final store = FakeThemeStore(ThemeMode.system);
    final bloc = ThemeBloc(store);
    addTearDown(bloc.close);
    expect(bloc.state.themeMode, ThemeMode.system);
    final initialized = await bloc.stream.first;
    expect(initialized.themeMode, ThemeMode.system);
    expect(store.writes, isEmpty);
  });

  test('changes survive a new bloc and support explicit system mode', () async {
    final store = FakeThemeStore(ThemeMode.dark);
    final bloc = ThemeBloc(store);
    await bloc.stream.first;
    final light = bloc.stream.first;
    bloc.add(ToggleTheme());
    expect((await light).themeMode, ThemeMode.light);
    final system = bloc.stream.first;
    bloc.add(SetThemeMode(ThemeMode.system));
    expect((await system).themeMode, ThemeMode.system);
    await bloc.close();

    final restarted = ThemeBloc(store);
    addTearDown(restarted.close);
    expect((await restarted.stream.first).themeMode, ThemeMode.system);
    expect(store.writes, [ThemeMode.light, ThemeMode.system]);
  });

  test('toggle from system uses the resolved device brightness', () async {
    final store = FakeThemeStore(ThemeMode.system);
    final bloc = ThemeBloc(store);
    addTearDown(bloc.close);
    await bloc.stream.first;
    final dark = bloc.stream.first;
    bloc.add(ToggleTheme(systemBrightness: Brightness.light));
    expect((await dark).themeMode, ThemeMode.dark);
    final system = bloc.stream.first;
    bloc.add(SetThemeMode(ThemeMode.system));
    await system;
    final light = bloc.stream.first;
    bloc.add(ToggleTheme(systemBrightness: Brightness.dark));
    expect((await light).themeMode, ThemeMode.light);
  });

  test('initial load and rapid toggles are processed in order', () async {
    final store = FakeThemeStore(ThemeMode.dark)
      ..loadGate = Completer<ThemeMode>();
    final bloc = ThemeBloc(store);
    addTearDown(bloc.close);
    final states = bloc.stream.take(3).toList();
    bloc.add(ToggleTheme());
    bloc.add(ToggleTheme());
    store.loadGate!.complete(ThemeMode.dark);
    expect(
      (await states).map((state) => state.themeMode),
      [ThemeMode.dark, ThemeMode.light, ThemeMode.dark],
    );
    expect(store.writes, [ThemeMode.light, ThemeMode.dark]);
  });
}
