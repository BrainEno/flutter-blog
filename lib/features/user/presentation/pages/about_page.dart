import 'dart:async';
import 'dart:io' show Platform;

import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/network/api_origin_report.dart';
import 'package:belog/core/secrets/app_secrets.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/diagnostics_header.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  /// Injectable for tests; the default reads the real package manifest.
  final Future<PackageInfo> Function() packageInfoLoader;

  /// Opens the diagnostics dialog right away: the login failure snackbar and
  /// the `/about?diagnostics=1` deep link use it to land on the reason
  /// instead of asking the user to find a button.
  final bool openDiagnostics;

  const AboutPage({
    super.key,
    this.packageInfoLoader = PackageInfo.fromPlatform,
    this.openDiagnostics = false,
  });

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<PackageInfo?> _packageInfo = _loadPackageInfo();

  @override
  void initState() {
    super.initState();
    if (widget.openDiagnostics) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDiagnostics(context);
      });
    }
  }

  /// A missing plugin (widget tests, a stripped build) degrades the version
  /// row to its placeholder instead of failing the page.
  Future<PackageInfo?> _loadPackageInfo() async {
    try {
      return await widget.packageInfoLoader();
    } catch (error) {
      AppLogger.debug('package info unavailable: ${error.runtimeType}');
      return null;
    }
  }

  /// Coarse, sanitized context for the diagnostics preamble (issue #49):
  /// app identity, build flavor, OS family and device locale. Never device
  /// identifiers or user data. This continues to report the preferred device
  /// locale, even when the app falls back to a different supported language.
  String _diagnosticsHeader(PackageInfo? info) {
    return buildDiagnosticsHeader(
      appName: (info != null && info.appName.isNotEmpty)
          ? info.appName
          : 'belog',
      version: info == null ? 'unknown' : '${info.version}+${info.buildNumber}',
      buildMode: kReleaseMode
          ? 'release'
          : (kProfileMode ? 'profile' : 'debug'),
      operatingSystem: defaultTargetPlatform.name,
      osVersion: kIsWeb ? null : Platform.operatingSystemVersion,
      locale: WidgetsBinding.instance.platformDispatcher.locale.toString(),
      apiOrigin: _apiOriginLine(),
    );
  }

  /// Which backend this build talks to. `API_BASE_URL` is compiled in, so this
  /// is the fastest way to tell "wrong origin baked into the build" from
  /// "backend down" without a developer console.
  String? _apiOriginLine() {
    final configured = AppSecrets.apiBaseUrl;
    if (configured == null || configured.isEmpty) return null;
    final uri = Uri.tryParse(configured);
    if (uri == null || !uri.hasAuthority) return null;
    return describeApiOrigin(uri, debugBuild: kDebugMode);
  }

  Future<void> _openLink(BuildContext context, Uri uri) async {
    try {
      if (await canLaunchUrl(uri) && await launchUrl(uri)) return;
    } catch (error, stackTrace) {
      AppLogger.error(
        'opening a contact link failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (context.mounted) showSnackBar(context, context.l10n.cannotOpenLink);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aboutHeading,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(l10n.aboutBody),
            const SizedBox(height: 20),
            Text(
              l10n.contactHeading,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(l10n.emailLabel),
            TextButton(
              onPressed: () =>
                  _openLink(context, Uri.parse('mailto:nodeman24@outlook.com')),
              child: const Text('nodeman24@outlook.com'),
            ),
            const SizedBox(height: 10),
            Text(l10n.githubLabel),
            TextButton(
              onPressed: () =>
                  _openLink(context, Uri.parse('https://github.com/BrainEno')),
              child: const Text('https://github.com/BrainEno'),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.versionHeading,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            // Long-press remains a shortcut; the report is still never sent
            // automatically (issue #49).
            InkWell(
              onLongPress: () => _showDiagnostics(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: FutureBuilder<PackageInfo?>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    final version = info == null
                        ? '…'
                        : '${info.version}+${info.buildNumber}';
                    return Text(l10n.appVersionLabel(version));
                  },
                ),
              ),
            ),
            // A support feature nobody can discover is not a support feature:
            // the version row keeps the long-press shortcut, and this entry
            // makes the report reachable without guessing (issue #49).
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showDiagnostics(context),
                icon: const Icon(Icons.bug_report_outlined, size: 18),
                label: Text(l10n.diagnosticsEntry),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The report reviewed and optionally copied/shared by the user: sanitized
  /// context first, followed by the local buffer's entries newest-first.
  String _composeReport(PackageInfo? info) {
    final header = _diagnosticsHeader(info);
    final body = AppLogger.diagnosticsReport();
    return body.isEmpty ? header : '$header\n$body';
  }

  Future<void> _showDiagnostics(BuildContext context) async {
    // The report must never wait on the platform channel: a slow or missing
    // package-info implementation degrades the header instead of hiding the
    // diagnostics (this is exactly the "the app is broken" moment).
    PackageInfo? info;
    try {
      info = await _packageInfo.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      info = null;
    }
    if (!context.mounted) return;
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var report = _composeReport(info);
        return StatefulBuilder(
          builder: (dialogContext, setState) => AlertDialog(
            title: Text(l10n.diagnosticsTitle),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        AppLogger.diagnosticsReport().isEmpty
                            ? '$report\n\n${l10n.diagnosticsEmptyBuffer}\n\n'
                                  '${l10n.diagnosticsEmptyHint}'
                            : report,
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: NoWaveSpacing.small),
                  Text(l10n.diagnosticsPrivacyNote),
                ],
              ),
            ),
            actions: [
              NoWaveButton(
                label: l10n.actionClear,
                variant: NoWaveButtonVariant.quiet,
                onPressed: () {
                  AppLogger.clearDiagnostics();
                  setState(() => report = _composeReport(info));
                },
              ),
              NoWaveButton(
                label: l10n.actionShare,
                variant: NoWaveButtonVariant.quiet,
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  try {
                    await SharePlus.instance.share(
                      ShareParams(
                        title: l10n.diagnosticsShareTitle,
                        text: report,
                      ),
                    );
                  } catch (e, stackTrace) {
                    AppLogger.error(
                      'sharing the diagnostics failed',
                      error: e,
                      stackTrace: stackTrace,
                    );
                    if (context.mounted) {
                      showSnackBar(context, l10n.diagnosticsShareFailed);
                    }
                  }
                },
              ),
              NoWaveButton(
                label: l10n.actionCopy,
                variant: NoWaveButtonVariant.quiet,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: report));
                  Navigator.of(dialogContext).pop();
                  showSnackBar(context, l10n.diagnosticsCopied);
                },
              ),
              NoWaveButton(
                label: l10n.actionClose,
                variant: NoWaveButtonVariant.secondary,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
}
