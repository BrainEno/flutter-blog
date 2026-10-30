import 'package:belog/core/theme/theme.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

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
                // to review - and optionally copy - the sanitized local
                // diagnostics buffer.
                onLongPress: () => _showDiagnostics(context),
                child: const Text(
                  '应用版本: Version 1.9',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDiagnostics(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        // The buffer is process-local and mutable; the dialog reflects it
        // live so "clear" visibly empties what would be copied.
        var report = AppLogger.diagnosticsReport();
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
                        report.isEmpty
                            ? '诊断缓冲为空。\n\n'
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
                    '复制与否由你决定。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  AppLogger.clearDiagnostics();
                  setState(() => report = AppLogger.diagnosticsReport());
                },
                child: const Text('清空'),
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
