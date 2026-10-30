/// Composes the sanitized preamble of the diagnostics report (issue #49).
///
/// Every field is coarse-grained on purpose: app identity, build flavor, OS
/// family and UI locale - exactly what a support conversation needs to
/// reproduce a failure, and nothing that identifies the user or the device.
/// The values are assembled from caller-owned constants; no free-form text
/// flows in from the network or the platform.
String buildDiagnosticsHeader({
  required String appName,
  required String version,
  required String buildMode,
  required String operatingSystem,
  String? osVersion,
  required String locale,
}) {
  return [
    'app $appName $version',
    'build $buildMode',
    'platform $operatingSystem'
        '${osVersion == null || osVersion.isEmpty ? '' : ' ($osVersion)'}',
    'locale $locale',
  ].join('\n');
}
