import 'package:belog/core/l10n/app_language.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/l10n/locale_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Opens the in-app language picker (issue #108).
///
/// The button renders without reading any state: the current choice is only
/// consulted when the menu opens, so the button is safe to mount on public
/// screens and in widget tests that pump a page without the app-wide blocs.
class LanguageMenuButton extends StatelessWidget {
  const LanguageMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppLanguage>(
      tooltip: context.l10n.languageSettingTitle,
      icon: const Icon(Icons.language),
      onSelected: (language) {
        context.read<LocaleBloc>().add(SetAppLanguage(language));
      },
      itemBuilder: (context) {
        final current = context.read<LocaleBloc>().state.language;
        return [
          for (final language in AppLanguage.values)
            CheckedPopupMenuItem<AppLanguage>(
              value: language,
              checked: current == language,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(languageLabel(context, language)),
                  // The fallback is stated instead of silently swapping the
                  // language on an unsupported device.
                  if (language == AppLanguage.system)
                    Text(
                      context.l10n.languageSystemHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
        ];
      },
    );
  }
}

/// The name of [language] in its own language, so the menu is readable no
/// matter which language is active.
String languageLabel(BuildContext context, AppLanguage language) {
  final l10n = context.l10n;
  switch (language) {
    case AppLanguage.system:
      return l10n.languageSystem;
    case AppLanguage.zh:
      return l10n.languageChinese;
    case AppLanguage.en:
      return l10n.languageEnglish;
  }
}
