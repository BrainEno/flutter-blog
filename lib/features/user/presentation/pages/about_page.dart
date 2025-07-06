import 'package:belog/core/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  static route() => MaterialPageRoute(builder: (_) => const AboutPage());
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkThemeMode,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('About Us'),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '关于Bottom Think',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Bottom Think是一个文学类博客平台，旨在为用户提供一个自由表达思想和分享创作的平台。我们鼓励用户分享他们的故事、观点和创意，促进思想的碰撞与交流。',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '联系作者',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 16, color: Colors.white),
                  children: [
                    TextSpan(
                        text: '邮箱:  ', style: TextStyle(color: Colors.grey)),
                    TextSpan(
                      text: 'nodeman24@outlook.com',
                      style: TextStyle(decoration: TextDecoration.underline),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final Uri emailUri =
                              Uri.parse('mailto:nodeman24@outlook.com');
                          if (await canLaunchUrl(emailUri)) {
                            await launchUrl(emailUri);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Could not launch $emailUri')),
                            );
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
                        style: TextStyle(color: Colors.grey)),
                    TextSpan(
                      text: 'https://github.com/BrainEno',
                      style: TextStyle(decoration: TextDecoration.underline),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final Uri githubUri =
                              Uri.parse('https://github.com/BrainEno');
                          if (await canLaunchUrl(githubUri)) {
                            await launchUrl(githubUri);
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Could not launch $githubUri')),
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
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '应用版本: Version 1.9',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
