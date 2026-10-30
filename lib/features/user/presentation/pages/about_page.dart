import 'dart:io' show Platform;

import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/diagnostics_header.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  /// app identity, build flavor, OS family and UI locale. Never device
  /// identifiers or user data.
  String _diagnosticsHeader(PackageInfo? info, BuildContext context) {
    return buildDiagnosticsHeader(
      appName: (info != null && info.appName.isNotEmpty) ? info.appName : 'belog',
      version: info == null
          ? 'unknown'
          : '${info.version}+${info.buildNumber}',
      buildMode: kReleaseMode
          ? 'release'
          : (kProfileMode ? 'profile' : 'debug'),
      operatingSystem: defaultTargetPlatform.name,
      osVersion: kIsWeb ? null : Platform.operatingSystemVersion,
      locale: Localizations.maybeLocaleOf(context)?.toString() ?? 'unknown',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkThemeMode,
      child: Scaffold(
        appBar: AppBar(title: const Text('About Us')),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '关于Bottom Think',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Bottom Think是一个文学类博客平台，旨在为用户提供一个自由表达思想和分享创作的平台。我们鼓励用户分享他们的故事、观点和创意，促进思想的碰撞与交流。',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              const Text(
                '联系作者',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 16, color: Colors.white),
                  children: [
                    TextSpan(
                      text: '邮箱:  ',
                      style: TextStyle(color: Colors.grey),
                    ),
                    TextSpan(
                      text: 'nodeman24@outlook.com',
                      style: TextStyle(decoration: TextDecoration.underline),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final Uri emailUri = Uri.parse(
                            'mailto:nodeman24@outlook.com',
                          );
                          if (await canLaunchUrl(emailUri)) {
                            await launchUrl(emailUri);
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Could not launch $emailUri'),
                                ),
                              );
                            }
                          }
                        },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 16, color: Colors.white),
                  children: [
                    TextSpan(
                      text: 'Github:  ',
                      style: TextStyle(color: Colors.grey),
                    ),
                    TextSpan(
                      text: 'https://github.com/BrainEno',
                      style: TextStyle(decoration: TextDecoration.underline),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final Uri githubUri = Uri.parse(
                            'https://github.com/BrainEno',
                          );
                          if (await canLaunchUrl(githubUri)) {
                            await launchUrl(githubUri);
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Could not launch $githubUri'),
                                ),
                              );
                            }
                          }
                        },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '版本信息',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                // Hidden support entry (issue #49): long-press the version
                // to review - and optionally copy or share - the sanitized
                // local diagnostics buffer.
                onLongPress: () => _showDiagnostics(context),
                child: FutureBuilder<PackageInfo>(
                  future: _packageInfo,
                  builder: (context, snapshot) => Text(
                    // The real manifest version - a hardcoded string here
                    // went stale once already.
                    '应用版本: ${snapshot.data == null ? '…' : '${snapshot.data!.version}+${snapshot.data!.buildNumber}'}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full report as the user sees (and copies) it: the sanitized context
  /// header first, then the buffer's entries newest-first.
  String _composeReport(PackageInfo? info, BuildContext context) {
    final header = _diagnosticsHeader(info, context);
    final body = AppLogger.diagnosticsReport();
    return body.isEmpty ? header : '$header\n$body';
  }

  Future<void> _showDiagnostics(BuildContext context) async {
    // Resolved before the dialog opens: the builder below is synchronous.
    final info = await _packageInfo;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        // The buffer is process-local and mutable; the dialog reflects it
        // live so "clear" visibly empties what would be copied.
        var report = _composeReport(info, dialogContext);
        return StatefulBuilder(
          builder: (dialogContext, setState) => AlertDialog(
            title: const Text('诊断信息'),
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
                            ? '$report\n\n'
                                  '诊断缓冲为空。\n\n'
                                  '应用失败时会在这里记录脱敏摘要（错误类别、接口路径、'
                                  '状态码与耗时），不包含任何账号信息。'
                            : report,
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '以上内容仅保存在本机内存中，不会自动发送给任何人；'
                    '复制或分享与否由你决定。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  AppLogger.clearDiagnostics();
                  setState(
                    () => report = _composeReport(info, dialogContext),
                  );
                },
                child: const Text('清空'),
              ),
              // Same user-controlled exit as copy, one tap fewer: the
              // system share sheet receives exactly the text reviewed
              // above - the header plus the buffer, nothing else.
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  try {
                    await SharePlus.instance.share(
                      ShareParams(title: 'Belog 诊断信息', text: report),
                    );
                  } catch (e, stackTrace) {
                    // Not every surface has a share target (desktop, or
                    // the test binding); copying must remain possible.
                    AppLogger.error(
                      'sharing the diagnostics failed',
                      error: e,
                      stackTrace: stackTrace,
                    );
                    if (context.mounted) {
                      showSnackBar(context, '分享失败，请尝试复制');
                    }
                  }
                },
                child: const Text('分享'),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: report));
                  // Pop before the snackbar, and use the page context:
                  // the dialog context is deactivated by the pop.
                  Navigator.of(dialogContext).pop();
                  showSnackBar(context, '诊断信息已复制');
                },
                child: const Text('复制'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      },
    );
  }
}
