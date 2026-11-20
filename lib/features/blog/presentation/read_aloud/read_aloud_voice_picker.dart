import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/domain/read_aloud/read_aloud_settings.dart';
import 'package:belog/features/blog/domain/read_aloud/speech_engine.dart';
import 'package:belog/features/blog/presentation/read_aloud/read_aloud_controller.dart';
import 'package:belog/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// An installed-system-voice chooser for the languages in the open article.
///
/// It does not download, preview, record or upload voices. A choice is an
/// opaque device identifier saved locally; reopening this sheet always reads
/// the controller's current installed-voice list, so an OS-removed voice falls
/// back to automatic speech instead of becoming an unusable selection.
class ReadAloudVoicePicker extends StatefulWidget {
  const ReadAloudVoicePicker({super.key, required this.controller});

  final ReadAloudController controller;

  static Future<void> show(
    BuildContext context,
    ReadAloudController controller,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ReadAloudVoicePicker(controller: controller),
    );
  }

  @override
  State<ReadAloudVoicePicker> createState() => _ReadAloudVoicePickerState();
}

class _ReadAloudVoicePickerState extends State<ReadAloudVoicePicker> {
  String? _language;

  @override
  void initState() {
    super.initState();
    _language = _firstLanguage(widget.controller.voiceChoices);
  }

  @override
  void didUpdateWidget(covariant ReadAloudVoicePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _language = _firstLanguage(widget.controller.voiceChoices);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final groups = controller.voiceChoices;
        final language = _validLanguage(groups);
        if (language == null) return const SizedBox.shrink();
        final l10n = context.l10n;
        final choices = groups[language]!;
        final selectedId = controller.preferredVoiceIdFor(language);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .62,
          minChildSize: .36,
          maxChildSize: .9,
          builder: (context, scrollController) => Material(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                NoWaveSpacing.medium,
                NoWaveSpacing.small,
                NoWaveSpacing.medium,
                NoWaveSpacing.large,
              ),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(NoWaveRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: NoWaveSpacing.medium),
                Text(
                  l10n.readAloudVoiceTitle,
                  style: NoWaveTypography.title(context),
                ),
                const SizedBox(height: NoWaveSpacing.xs),
                Text(
                  l10n.readAloudVoiceDescription,
                  style: NoWaveTypography.meta(context),
                ),
                const SizedBox(height: NoWaveSpacing.medium),
                if (groups.length > 1)
                  Wrap(
                    spacing: NoWaveSpacing.small,
                    runSpacing: NoWaveSpacing.xs,
                    children: [
                      for (final entry in groups.entries)
                        ChoiceChip(
                          key: ValueKey(
                            'read-aloud-voice-language-${entry.key}',
                          ),
                          label: Text(_languageLabel(l10n, entry.key)),
                          selected: entry.key == language,
                          onSelected: (_) => setState(() {
                            _language = entry.key;
                          }),
                        ),
                    ],
                  ),
                if (groups.length > 1)
                  const SizedBox(height: NoWaveSpacing.small),
                Text(
                  _languageLabel(l10n, language),
                  style: NoWaveTypography.meta(context),
                ),
                const SizedBox(height: NoWaveSpacing.xs),
                _VoiceChoiceTile(
                  key: const ValueKey('read-aloud-voice-automatic'),
                  title: l10n.readAloudVoiceAutomatic,
                  subtitle: l10n.readAloudVoiceAutomaticHint,
                  selected: selectedId == null,
                  onTap: () => controller.setPreferredVoice(language, null),
                ),
                for (final voice in choices)
                  _VoiceChoiceTile(
                    key: ValueKey('read-aloud-voice-${voice.id}'),
                    title: voice.displayName,
                    subtitle: voice.language,
                    selected: selectedId == voice.id,
                    onTap: () =>
                        controller.setPreferredVoice(language, voice.id),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _validLanguage(Map<String, List<SpeechVoice>> groups) {
    final current = _language;
    if (current != null && groups.containsKey(current)) return current;
    final first = _firstLanguage(groups);
    if (first != current) {
      // The engine can be reinitialized while the sheet is open. Do not call
      // setState during build; a post-frame repair keeps the selected tab real.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _language = first);
      });
    }
    return first;
  }

  String? _firstLanguage(Map<String, List<SpeechVoice>> groups) =>
      groups.keys.isEmpty ? null : groups.keys.first;
}

class _VoiceChoiceTile extends StatelessWidget {
  const _VoiceChoiceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

String _languageLabel(AppLocalizations l10n, String language) {
  return switch (speechLanguageFamily(language)) {
    'en' => l10n.readAloudVoiceLanguageEnglish,
    'zh' => l10n.readAloudVoiceLanguageChinese,
    _ => language,
  };
}
