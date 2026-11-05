import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The release identity (#109) is spread over pubspec, three platform
/// projects, scripts and licensing files. This test keeps them in sync: a
/// rename that misses one side fails here instead of at publish time.
void main() {
  const expectedId = 'com.nodeman24.nowave';

  test('the version is a real release version, not the template default', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml needs a version line');
    final version = match!.group(1)!;
    // The same shape tool/release/validate_release.py accepts for a tag.
    final releaseVersion = RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+([1-9]\d*)$',
    );
    expect(
      version,
      matches(releaseVersion),
      reason: 'the release workflow only accepts MAJOR.MINOR.PATCH+BUILD',
    );
    expect(version, isNot(startsWith('0.0.0+')), reason: 'placeholder version');
  });

  test('Android compiles with the agreed application id', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();
    expect(_assigned(gradle, 'namespace'), expectedId);
    expect(_assigned(gradle, 'applicationId'), expectedId);

    final activity = File(
      'android/app/src/main/kotlin/${expectedId.replaceAll('.', '/')}'
      '/MainActivity.kt',
    );
    expect(
      activity.existsSync(),
      isTrue,
      reason: 'the Kotlin package directory must match the application id',
    );
    expect(
      activity.readAsStringSync(),
      contains('package $expectedId'),
      reason: 'MainActivity must declare the application id package',
    );
  });

  test('Apple projects use the same bundle id', () {
    final iosIds = _bundleIds('ios/Runner.xcodeproj/project.pbxproj');
    expect(iosIds, isNotEmpty);
    expect(iosIds, contains(expectedId));
    for (final id in iosIds) {
      expect(
        id == expectedId || id == '$expectedId.RunnerTests',
        isTrue,
        reason: 'unexpected iOS bundle id: $id',
      );
    }

    final macosConfig = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    expect(_assigned(macosConfig, 'PRODUCT_BUNDLE_IDENTIFIER'), expectedId);

    for (final id in _bundleIds('macos/Runner.xcodeproj/project.pbxproj')) {
      expect(
        id == expectedId || id == '$expectedId.RunnerTests',
        isTrue,
        reason: 'unexpected macOS bundle id: $id',
      );
    }
  });

  test('no placeholder identifier survives in the platform projects', () {
    for (final path in [
      'android/app/build.gradle',
      'ios/Runner.xcodeproj/project.pbxproj',
      'macos/Runner/Configs/AppInfo.xcconfig',
      'macos/Runner.xcodeproj/project.pbxproj',
      'windows/runner/Runner.rc',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('com.example')),
        reason: '$path still carries a template identifier',
      );
    }
  });

  test('the release tooling validates the same id', () {
    // The publish gate compares the approved id with the compiled one, so the
    // constant it holds must be the id in the Android project.
    final validator = File(
      'tool/release/validate_release.py',
    ).readAsStringSync();
    expect(validator, contains('"$expectedId"'));
    final apkCheck = File('tool/mobile/verify_android_package.sh');
    expect(apkCheck.readAsStringSync(), contains(expectedId));
  });

  test('the license and the bundled notices are in place', () {
    final license = File('LICENSE').readAsStringSync();
    expect(license, contains('Apache License'));
    expect(license, contains('Version 2.0, January 2004'));
    expect(license, contains('Copyright 2026 No Wave'));

    final notice = File('NOTICE').readAsStringSync();
    // Every font that ships in assets/fonts must be named in the notice, and
    // each one must still carry its license text next to it.
    final fonts = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .map((file) => file.path.split('/').last)
        .where((name) => name.endsWith('.ttf'))
        .toList();
    expect(fonts, isNotEmpty);
    for (final font in fonts) {
      expect(notice, contains(font), reason: 'NOTICE does not name $font');
    }
    for (final ofl in Directory(
      'assets/fonts',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.txt'))) {
      expect(
        ofl.readAsStringSync(),
        contains('SIL Open Font License'),
        reason: '${ofl.path} is not the OFL text it claims to be',
      );
    }
  });
}

/// Reads `key = "value"` (Gradle) or `KEY = value` (xcconfig).
String? _assigned(String text, String key) {
  final match = RegExp(
    '^\\s*$key\\s*=\\s*"?([^"\\s]+)"?\\s*\$',
    multiLine: true,
  ).firstMatch(text);
  return match?.group(1);
}

/// Every `PRODUCT_BUNDLE_IDENTIFIER = …;` in an Xcode project file.
List<String> _bundleIds(String path) {
  final text = File(path).readAsStringSync();
  return RegExp(
    r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
  ).allMatches(text).map((match) => match.group(1)!.trim()).toList();
}
