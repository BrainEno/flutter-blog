import 'dart:async';
import 'dart:io' show Platform;

import 'package:belog/core/common/widgets/no_wave_action_row.dart';
import 'package:belog/core/common/widgets/no_wave_menu_group.dart';
import 'package:belog/core/config/app_durations.dart';
import 'package:belog/core/design/components/no_wave_button.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/network/api_origin_report.dart';
import 'package:belog/core/secrets/app_secrets.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/diagnostics_file_export.dart';
import 'package:belog/core/utils/diagnostics_header.dart';
import 'package:belog/core/utils/diagnostics_report.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// The author's addresses, shown as written and opened as links.
const _email = 'nodeman24@outlook.com';
const _github = 'https://github.com/BrainEno';

class AboutPage extends StatefulWidget {
  /// Injectable for tests; the default reads the real package manifest.
  final Future<PackageInfo> Function() packageInfoLoader;

  /// Opens the diagnostics dialog right away: the login failure snackbar and
  /// the `/about?diagnostics=1` deep link use it to land on the reason
  /// instead of asking the user to find a button.
  final bool openDiagnostics;

  /// Writes the diagnostics export and opens the share sheet (issue #306).
  /// Injectable for tests; null uses [DiagnosticsFileExporter].
  final DiagnosticsExportAction? exportDiagnostics;

  const AboutPage({
    super.key,
    this.packageInfoLoader = PackageInfo.fromPlatform,
    this.openDiagnostics = false,
    this.exportDiagnostics,
  });

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<PackageInfo?> _packageInfo = _loadPackageInfo();
  late final DiagnosticsExportAction _exportDiagnostics =
      widget.exportDiagnostics ?? DiagnosticsFileExporter().exportAndShare;

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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          NoWaveSpacing.page,
          NoWaveSpacing.large,
          NoWaveSpacing.page,
          NoWaveSpacing.section,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: NoWaveSizes.contentColumn,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The one heading on the page, in the serif like every
                  // other page's title; the two blocks under it are labelled
                  // like the profile's groups, and their entries are the same
                  // rows - the about page is reached from that menu and now
                  // reads as part of it.
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.aboutHeading,
                      style: NoWaveTypography.title(
                        context,
                        size: NoWaveTypeScale.pageTitle,
                      ),
                    ),
                  ),
                  const SizedBox(height: NoWaveSpacing.medium),
                  Text(
                    l10n.aboutBody,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(height: 1.7),
                  ),
                  NoWaveMenuGroup(
                    title: l10n.contactHeading,
                    children: [
                      NoWaveActionRow(
                        icon: Icons.mail_outline,
                        label: l10n.emailLabel,
                        description: _email,
                        onTap: () =>
                            _openLink(context, Uri.parse('mailto:$_email')),
                      ),
                      NoWaveActionRow(
                        icon: Icons.code,
                        label: l10n.githubLabel,
                        description: _github,
                        onTap: () => _openLink(context, Uri.parse(_github)),
                      ),
                    ],
                  ),
                  NoWaveMenuGroup(
                    title: l10n.versionHeading,
                    children: [
                      // Long-press remains a shortcut; the report is still
                      // never sent automatically (issue #49).
                      InkWell(
                        onLongPress: () => _showDiagnostics(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: NoWaveSpacing.medium,
                          ),
                          child: FutureBuilder<PackageInfo?>(
                            future: _packageInfo,
                            builder: (context, snapshot) {
                              final info = snapshot.data;
                              final version = info == null
                                  ? '…'
                                  : '${info.version}+${info.buildNumber}';
                              return Text(
                                l10n.appVersionLabel(version),
                                style: NoWaveTypography.meta(context),
                              );
                            },
                          ),
                        ),
                      ),
                      // A support feature nobody can discover is not a
                      // support feature: the version row keeps the long-press
                      // shortcut, and this entry makes the report reachable
                      // without guessing (issue #49).
                      NoWaveActionRow(
                        icon: Icons.bug_report_outlined,
                        label: l10n.diagnosticsEntry,
                        onTap: () => _showDiagnostics(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The report reviewed and optionally copied/shared by the user: sanitized
  /// context first, followed by the local buffer's entries newest-first.
  /// The redaction pass is defense in depth (issue #306): the buffer only
  /// stores pre-scrubbed lines, but what is on screen is what gets copied.
  String _composeReport(PackageInfo? info) {
    final header = _diagnosticsHeader(info);
    final body = AppLogger.diagnosticsReport();
    return redactDiagnosticsText(body.isEmpty ? header : '$header\n$body');
  }

  /// The exported file: the same sanitized header plus a format tag, the
  /// export instant, the retention window and at most
  /// [kDiagnosticsExportMaxEntries] newest records (issue #306).
  String _composeExport(PackageInfo? info) => composeDiagnosticsExport(
    header: _diagnosticsHeader(info),
    entries: AppLogger.diagnostics.entries,
    generatedAt: DateTime.now(),
    window: AppLogger.diagnostics.maxAge,
  );

  /// Only ever runs from the user's tap: nothing is uploaded, scheduled or
  /// retried, and the share sheet decides where the file goes.
  Future<void> _export(BuildContext context, PackageInfo? info) async {
    final l10n = context.l10n;
    final document = _composeExport(info);
    try {
      await _exportDiagnostics(
        report: document,
        shareTitle: l10n.diagnosticsShareTitle,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'exporting the diagnostics failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) showSnackBar(context, l10n.diagnosticsExportFailed);
    }
  }

  Future<void> _showDiagnostics(BuildContext context) async {
    // The report must never wait on the platform channel: a slow or missing
    // package-info implementation degrades the header instead of hiding the
    // diagnostics (this is exactly the "the app is broken" moment).
    PackageInfo? info;
    try {
      info = await _packageInfo.timeout(AppDurations.packageInfoLookup);
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
                          fontSize: NoWaveTypeScale.codeBlock,
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
                label: l10n.diagnosticsExportFile,
                variant: NoWaveButtonVariant.quiet,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_export(context, info));
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
