import 'dart:async';

import 'package:belog/core/design/components/no_wave_confirm_dialog.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/well_formed_utf16.dart';
import 'package:belog/features/blog/domain/editing/local_structured_session.dart';
import 'package:belog/features/blog/domain/editing/structured_article_draft.dart';
import 'package:belog/features/blog/domain/editing/structured_block_properties.dart';
import 'package:flutter/material.dart';

/// One-shot route handoff. The owner clears its reference even if navigation
/// fails, and the page immediately consumes it. It is not a recovery token.
class StructuredBlockPropertiesSeed {
  StructuredBlockPropertiesSeed(this._body);
  StructuredArticleDraft? _body;
  StructuredArticleDraft? take() {
    final body = _body;
    _body = null;
    return body;
  }

  void clear() => _body = null;
}

/// Edits selected block properties in a temporary form. Only a confirmed,
/// valid edit enters the existing local body coordinator and its CAS writer.
/// The form is intentionally not a durable intermediate input buffer.
class StructuredBlockPropertiesPage extends StatefulWidget {
  const StructuredBlockPropertiesPage({
    super.key,
    required this.session,
    required this.blockId,
    required this.seed,
  });
  final LocalStructuredSession session;
  final String blockId;
  final StructuredBlockPropertiesSeed seed;

  @override
  State<StructuredBlockPropertiesPage> createState() =>
      _StructuredBlockPropertiesPageState();
}

class _StructuredBlockPropertiesPageState
    extends State<StructuredBlockPropertiesPage> {
  final _primary = TextEditingController();
  final _secondary = TextEditingController();
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredArticleDraft? _source;
  String? _type;
  int _level = 2;
  bool _ordered = false;
  bool _optional = false;
  bool _dirty = false;
  bool _invalid = false;
  bool _busy = false;
  bool _clearing = false;
  bool _reading = false;
  bool _unrenderable = false;

  @override
  void initState() {
    super.initState();
    final selected = widget.seed.take();
    final state = widget.session.state;
    if (selected != null &&
        identical(state.body, selected) &&
        state.phase == LocalStructuredPhase.editing) {
      final blocks = selected.blocks.where((b) => b['id'] == widget.blockId);
      if (blocks.length == 1) _load(selected, blocks.single);
    }
    _primary.addListener(_changed);
    _secondary.addListener(_changed);
    _subscription = widget.session.changes.listen(_onSession);
  }

  void _load(StructuredArticleDraft source, Map<String, Object?> block) {
    final type = block['type'];
    if (type is! String ||
        !const {'image', 'code', 'quote', 'heading', 'list'}.contains(type)) {
      return;
    }
    _source = source;
    _type = type;
    switch (type) {
      case 'image':
        _primary.text = block['alt'] as String;
        _optional = block.containsKey('caption');
        _secondary.text = (block['caption'] as String?) ?? '';
      case 'code':
        _primary.text = block['language'] as String;
        _secondary.text = block['code'] as String;
      case 'quote':
        _optional = block.containsKey('attribution');
        _primary.text = (block['attribution'] as String?) ?? '';
      case 'heading':
        _level = block['level'] as int;
      case 'list':
        _ordered = block['ordered'] as bool;
    }
    _unrenderable =
        !isWellFormedUtf16(_primary.text) ||
        !isWellFormedUtf16(_secondary.text);
    if (_unrenderable) {
      _primary.clear();
      _secondary.clear();
    }
  }

  void _changed() {
    if (_clearing) return;
    if (mounted)
      setState(() {
        _dirty = true;
        _invalid = false;
      });
  }

  void _onSession(LocalStructuredState state) {
    if (state.phase == LocalStructuredPhase.invalidated ||
        state.phase == LocalStructuredPhase.closed) {
      _source = null;
      _type = null;
      _clearing = true;
      _primary.clear();
      _secondary.clear();
      _clearing = false;
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (mounted && !_reading) setState(() {});
  }

  @override
  void dispose() {
    widget.seed.clear();
    _source = null;
    _primary.removeListener(_changed);
    _secondary.removeListener(_changed);
    unawaited(_subscription.cancel());
    _primary.dispose();
    _secondary.dispose();
    super.dispose();
  }

  bool _editable(LocalStructuredState state) =>
      !_busy &&
      !_unrenderable &&
      _source != null &&
      identical(state.body, _source) &&
      state.phase == LocalStructuredPhase.editing;

  StructuredBlockProperties? _operation() {
    final body = _source;
    if (body == null) return null;
    return switch (_type) {
      'image' => StructuredImageProperties(
        body: body,
        blockId: widget.blockId,
        alt: _primary.text,
        captionPresent: _optional,
        caption: _secondary.text,
      ),
      'code' => StructuredCodeProperties(
        body: body,
        blockId: widget.blockId,
        language: _primary.text,
        code: _secondary.text,
      ),
      'quote' => StructuredQuoteProperties(
        body: body,
        blockId: widget.blockId,
        attributionPresent: _optional,
        attribution: _primary.text,
      ),
      'heading' => StructuredHeadingProperties(
        body: body,
        blockId: widget.blockId,
        level: _level,
      ),
      'list' => StructuredListProperties(
        body: body,
        blockId: widget.blockId,
        ordered: _ordered,
      ),
      _ => null,
    };
  }

  void _apply() {
    final state = widget.session.state;
    if (!_editable(state)) return;
    final operation = _operation();
    if (operation == null) return;
    if ((_primary.value.composing.isValid &&
            !_primary.value.composing.isCollapsed) ||
        (_secondary.value.composing.isValid &&
            !_secondary.value.composing.isCollapsed)) {
      setState(() => _invalid = true);
      return;
    }
    try {
      final accepted = widget.session.edit(operation.apply);
      if (!mounted) return;
      if (!accepted) {
        setState(() => _invalid = true);
        return;
      }
      _dirty = false;
      Navigator.of(context).pop();
    } on FormatException {
      setState(() => _invalid = true);
    } on ArgumentError {
      setState(() => _invalid = true);
    } on StateError {
      setState(() => _invalid = true);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_dirty && _source != null) {
      setState(() => _busy = true);
      final l10n = context.l10n;
      final confirmed = await showNoWaveConfirmDialog(
        context,
        title: l10n.structuredPropertiesLeaveTitle,
        message: l10n.structuredPropertiesLeaveBody,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.structuredPropertiesLeave,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (!confirmed) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    _reading = true;
    final LocalStructuredState state;
    try {
      state = widget.session.state;
    } finally {
      _reading = false;
    }
    final l10n = context.l10n;
    final enabled = _editable(state);
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.structuredPropertiesTitle),
          leading: IconButton(
            tooltip: l10n.actionBack,
            icon: const Icon(Icons.arrow_back),
            onPressed: _leave,
          ),
        ),
        body: SafeArea(
          child: _source == null
              ? Center(child: Text(l10n.structuredSessionChanged))
              : ListView(
                  padding: const EdgeInsets.all(NoWaveSpacing.page),
                  children: [
                    Text(l10n.structuredPropertiesIntro),
                    const SizedBox(height: NoWaveSpacing.medium),
                    if (_unrenderable)
                      Text(l10n.structuredInlineUnsupported)
                    else
                      ..._fields(context, enabled),
                    if (!enabled && !_unrenderable)
                      Semantics(
                        liveRegion: true,
                        child: Text(l10n.structuredPropertiesStale),
                      ),
                    if (_invalid)
                      Semantics(
                        liveRegion: true,
                        child: Text(l10n.structuredPropertiesInvalid),
                      ),
                    const SizedBox(height: NoWaveSpacing.medium),
                    FilledButton(
                      onPressed: enabled && _dirty ? _apply : null,
                      child: Text(l10n.structuredPropertiesApply),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  List<Widget> _fields(BuildContext context, bool enabled) {
    final l10n = context.l10n;
    switch (_type) {
      case 'image':
        return [
          TextField(
            key: const ValueKey('structured-image-alt'),
            controller: _primary,
            enabled: enabled,
            maxLines: null,
            decoration: InputDecoration(
              labelText: l10n.structuredPropertiesAlt,
            ),
          ),
          SwitchListTile(
            value: _optional,
            title: Text(l10n.structuredPropertiesCaptionPresent),
            onChanged: enabled
                ? (value) => setState(() {
                    _optional = value;
                    _dirty = true;
                  })
                : null,
          ),
          if (_optional)
            TextField(
              key: const ValueKey('structured-image-caption'),
              controller: _secondary,
              enabled: enabled,
              maxLines: null,
              decoration: InputDecoration(
                labelText: l10n.structuredPropertiesCaption,
              ),
            ),
        ];
      case 'code':
        return [
          TextField(
            key: const ValueKey('structured-code-language'),
            controller: _primary,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: l10n.structuredPropertiesLanguage,
            ),
          ),
          TextField(
            key: const ValueKey('structured-code-text'),
            controller: _secondary,
            enabled: enabled,
            minLines: 5,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: l10n.structuredPropertiesCode,
            ),
          ),
        ];
      case 'quote':
        return [
          SwitchListTile(
            value: _optional,
            title: Text(l10n.structuredPropertiesAttributionPresent),
            onChanged: enabled
                ? (value) => setState(() {
                    _optional = value;
                    _dirty = true;
                  })
                : null,
          ),
          if (_optional)
            TextField(
              key: const ValueKey('structured-quote-attribution'),
              controller: _primary,
              enabled: enabled,
              maxLines: null,
              decoration: InputDecoration(
                labelText: l10n.structuredPropertiesAttribution,
              ),
            ),
        ];
      case 'heading':
        return [
          Wrap(
            spacing: NoWaveSpacing.small,
            children: [
              for (final level in [2, 3, 4])
                ChoiceChip(
                  label: Text('${l10n.structuredPropertiesLevel} $level'),
                  selected: _level == level,
                  onSelected: enabled
                      ? (_) => setState(() {
                          _level = level;
                          _dirty = true;
                        })
                      : null,
                ),
            ],
          ),
        ];
      case 'list':
        return [
          SwitchListTile(
            value: _ordered,
            title: Text(l10n.structuredPropertiesOrdered),
            onChanged: enabled
                ? (value) => setState(() {
                    _ordered = value;
                    _dirty = true;
                  })
                : null,
          ),
        ];
      default:
        return [];
    }
  }
}
