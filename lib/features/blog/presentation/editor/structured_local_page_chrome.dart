import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// How a local editing session closes: once normally, and once more with
/// `abandonUnsaved` after the reader has agreed to lose what did not save.
///
/// Every local session (`LocalStructuredSession`, the text and rich-text
/// sessions built on `LocalBufferSession`) exposes exactly this tear-off.
typedef StructuredSessionClose = Future<bool> Function({bool abandonUnsaved});

/// The chrome every local structured editing page shares (#291).
///
/// Leaving is never a plain pop: a page saves into a recoverable local buffer,
/// and the system back gesture, the predictive-back swipe and the app bar's
/// arrow all have to run the same [onLeave] - which may ask before throwing an
/// unsaved write away. Putting the [PopScope] and the leading button in one
/// widget means a new editing page cannot wire one and forget the other.
class StructuredLocalScaffold extends StatelessWidget {
  const StructuredLocalScaffold({
    super.key,
    required this.title,
    required this.onLeave,
    required this.body,
    this.actions = const [],
  });

  final String title;

  /// Called for every way out. The page decides whether it actually pops.
  final Future<void> Function() onLeave;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(onLeave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.actionBack,
            icon: const Icon(Icons.arrow_back),
            onPressed: onLeave,
          ),
          title: Text(title),
          actions: actions,
        ),
        body: SafeArea(child: body),
      ),
    );
  }
}

/// Closes a local session for leaving, asking first when the last write did
/// not reach the buffer.
///
/// Returns whether the page may pop. `false` means the reader kept editing,
/// the abandoning close was refused, or the page went away meanwhile; the
/// caller re-arms its own exit guard in every one of those cases.
Future<bool> closeStructuredSessionForExit(
  BuildContext context,
  StructuredSessionClose close,
) async {
  final closed = await close();
  if (!context.mounted) return false;
  if (closed) return true;
  final l10n = context.l10n;
  final confirmed = await showNoWaveConfirmDialog(
    context,
    title: l10n.structuredExitTitle,
    message: l10n.structuredExitBody,
    cancelLabel: l10n.actionCancel,
    confirmLabel: l10n.structuredExitAction,
  );
  if (!context.mounted || !confirmed) return false;
  final abandoned = await close(abandonUnsaved: true);
  return context.mounted && abandoned;
}

/// The one-line, centred state a local editing page shows instead of its
/// editor: loading, a changed session, a local failure, a conflict.
///
/// It keeps the page margin so a long translation wraps inside the column
/// instead of running to the screen edge. [live] announces it to screen
/// readers when it replaces content on its own (the loading line), rather than
/// as the answer to something the reader did.
class StructuredLocalNotice extends StatelessWidget {
  const StructuredLocalNotice(this.message, {super.key, this.live = false});

  final String message;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final text = Text(message, textAlign: TextAlign.center);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.page),
        child: live ? Semantics(liveRegion: true, child: text) : text,
      ),
    );
  }
}
