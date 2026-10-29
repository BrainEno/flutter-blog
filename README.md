# belog

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


# cmd info
The configured version of Java detected may conflict with the Gradle version in your new Flutter app.

To keep the default AGP version Gradle version 8.3, download a compatible Java version
(Java 17 <= (Java 17 <= compatible Java version < Java 21) Java version < Java 21). Configure this Java version
globally for Flutter by running:

  flutter config --jdk-dir=<JDK_DIRECTORY>


Alternatively, to continue using your configured Java version, update the Gradle
version specified in the following file to a compatible Gradle version (compatible Gradle version range: 8.4 - 8.7):
F:\flutter\belog\android/gradle/wrapper/gradle-wrapper.properties

You may also update the Gradle version used by running
`./gradlew wrapper --gradle-version=<COMPATIBLE_GRADLE_VERSION>`.

See
https://docs.gradle.org/current/userguide/compatibility.html#java for details
on compatible Java/Gradle versions, and see
https://docs.gradle.org/current/userguide/gradle_wrapper.html#sec:upgrading_wrapper
for more details on using the Gradle Wrapper command to update the Gradle version
used.

## Builds and releases

CI uses Flutter 3.47.8 and JDK 17. Release-mode QA builds require an explicit
`BELOG_QA_BUILD=true` opt-in and use a debug key; they must not be distributed
as production builds. Production signing, tag/version rules, and the pending
application identity decision are documented in [docs/releasing.md](docs/releasing.md).
