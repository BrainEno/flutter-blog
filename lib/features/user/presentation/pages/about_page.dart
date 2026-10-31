import 'dart:io' show Platform;

import 'package:belog/core/l10n/l10n.dart';
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

  const AboutPage({
    super.key,
    this.packageInfoLoader = PackageInfo.fromPlatform,
  });

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<PackageInfo> _packageInfo = widget.packageInfoLoader();

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
    );
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
            // Long-press remains the user-controlled support entry: the
            // report is still never sent automatically (issue #49).
            InkWell(
              onLongPress: () => _showDiagnostics(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: FutureBuilder<PackageInfo>(
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
    final info = await _packageInfo;
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
                  const SizedBox(height: 12),
                  Text(l10n.diagnosticsPrivacyNote),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  AppLogger.clearDiagnostics();
                  setState(() => report = _composeReport(info));
                },
                child: Text(l10n.actionClear),
              ),
              TextButton(
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
                child: Text(l10n.actionShare),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: report));
                  Navigator.of(dialogContext).pop();
                  showSnackBar(context, l10n.diagnosticsCopied);
                },
                child: Text(l10n.actionCopy),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.actionClose),
              ),
            ],
          ),
        );
      },
    );
  }
}
