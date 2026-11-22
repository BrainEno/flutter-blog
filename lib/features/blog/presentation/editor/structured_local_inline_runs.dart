part of 'structured_local_inline_page.dart';

// The inline page's runs: reading a block's formatted runs, one card per
// run, and the dialog that edits a run's link.

class _Run {
  const _Run({
    required this.text,
    required this.start,
    required this.end,
    required this.marks,
    required this.href,
    required this.itemIndex,
  });
  final int? itemIndex;
  final String text;
  final int start;
  final int end;
  final Set<String> marks;
  final String? href;
}

List<_Run> _runs(Map<String, Object?> block, {int? itemIndex}) {
  final List raw;
  if (itemIndex == null) {
    raw =
        block['inlines'] as List? ??
        [
          {'text': block['text']},
        ];
  } else {
    final all = block['itemInlines'] as List?;
    raw = all == null
        ? [
            {'text': (block['items'] as List)[itemIndex]},
          ]
        : all[itemIndex] as List;
  }
  var offset = 0;
  return [
    for (final value in raw)
      (() {
        final run = value as Map;
        final text = run['text'] as String;
        final result = _Run(
          text: text,
          start: offset,
          end: offset + text.length,
          marks: Set<String>.of((run['marks'] as List?)?.cast<String>() ?? []),
          href: run['href'] as String?,
          itemIndex: itemIndex,
        );
        offset += text.length;
        return result;
      })(),
  ];
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    super.key,
    required this.run,
    required this.index,
    required this.editable,
    required this.onMark,
    required this.onLink,
  });
  final _Run run;
  final int index;
  final bool editable;
  final void Function(String, bool) onMark;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final safe =
        isWellFormedUtf16(run.text) &&
        (run.href == null || isWellFormedUtf16(run.href!));
    final marks = <(String, String)>[
      ('bold', l10n.structuredInlineBold),
      ('italic', l10n.structuredInlineItalic),
      ('underline', l10n.structuredInlineUnderline),
      ('strikethrough', l10n.structuredInlineStrike),
      ('code', l10n.structuredInlineCode),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l10n.structuredInlineRun} $index'),
            if (safe)
              SelectableText(run.text)
            else
              Text(l10n.structuredInlineUnsupported),
            if (safe && run.href != null) Text(run.href!),
            Wrap(
              spacing: NoWaveSpacing.small,
              children: [
                for (final mark in marks)
                  FilterChip(
                    label: Text(mark.$2),
                    selected: run.marks.contains(mark.$1),
                    onSelected: editable && safe
                        ? (selected) => onMark(mark.$1, selected)
                        : null,
                  ),
              ],
            ),
            OutlinedButton(
              onPressed: editable && safe ? onLink : null,
              child: Text(l10n.structuredInlineLink),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkSeed {
  _LinkSeed(this.selection, this.href, this.listBody);
  StructuredInlineSelection? selection;
  String? href;
  StructuredArticleDraft? listBody;
  void clear() {
    selection = null;
    href = null;
    listBody = null;
  }
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.session, required this.seed});
  final LocalStructuredSession session;
  final _LinkSeed seed;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController _controller;
  late final StreamSubscription<LocalStructuredState> _subscription;
  StructuredInlineSelection? _selection;
  StructuredArticleDraft? _listBody;
  bool _hadLink = false;
  bool _reading = false;
  bool _invalid = false;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    // The route can be scheduled just before an identity change. Check the
    // current fence before adopting private seed values, not only on events.
    final state = widget.session.state;
    final active =
        state.phase == LocalStructuredPhase.editing &&
        (widget.seed.listBody == null ||
            identical(widget.seed.listBody, state.body));
    _listBody = active ? widget.seed.listBody : null;
    _selection = active ? widget.seed.selection : null;
    _hadLink = active && widget.seed.href != null;
    _controller = TextEditingController(
      text: active ? widget.seed.href ?? '' : '',
    );
    widget.seed.clear();
    _subscription = widget.session.changes.listen(_changed);
  }

  void _changed(LocalStructuredState state) {
    if (!mounted) return;
    if (_listBody != null && !identical(_listBody, state.body)) {
      _listBody = null;
      _selection = null;
      _stale = true;
    }
    if (state.phase == LocalStructuredPhase.invalidated ||
        state.phase == LocalStructuredPhase.closed) {
      _selection = null;
      _listBody = null;
      if (_reading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _controller.clear();
            FocusManager.instance.primaryFocus?.unfocus();
          }
        });
      } else {
        _controller.clear();
        FocusManager.instance.primaryFocus?.unfocus();
      }
    }
    if (mounted && !_reading) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _selection = null;
    _listBody = null;
    _controller.dispose();
    super.dispose();
  }

  void _apply({required bool remove}) {
    final state = widget.session.state;
    final selection = _selection;
    if (state.phase != LocalStructuredPhase.editing ||
        state.body == null ||
        selection == null ||
        (_listBody != null && !identical(_listBody, state.body))) {
      setState(() => _stale = true);
      return;
    }
    final href = remove ? null : _controller.text;
    if (href != null && !isValidArticleResourceUrl(href)) {
      setState(() => _invalid = true);
      return;
    }
    try {
      final next = selection.setLink(state.body!, href);
      if (identical(next, state.body)) {
        Navigator.of(context).pop();
        return;
      }
      final applied = widget.session.edit(
        (current) => selection.setLink(current, href),
      );
      if (applied) {
        Navigator.of(context).pop();
      } else {
        setState(() => _stale = true);
      }
    } on ArgumentError {
      setState(() => _stale = true);
    } on FormatException {
      setState(() => _stale = true);
    } on StateError {
      setState(() => _stale = true);
    }
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
    final privateState =
        state.phase != LocalStructuredPhase.invalidated &&
        state.phase != LocalStructuredPhase.closed;
    final editable =
        state.phase == LocalStructuredPhase.editing && _selection != null;
    return AlertDialog(
      title: Text(l10n.structuredInlineLinkTitle),
      content: SingleChildScrollView(
        child: privateState
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.structuredInlineLinkHint),
                  Text(l10n.structuredInlineUnsavedLink),
                  TextField(
                    controller: _controller,
                    enabled: editable,
                    keyboardType: TextInputType.url,
                    inputFormatters: [
                      TextInputFormatter.withFunction(
                        (oldValue, newValue) =>
                            newValue.text.length <= 2048 ? newValue : oldValue,
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.structuredInlineLinkLabel,
                      errorText: _invalid
                          ? l10n.structuredInlineLinkInvalid
                          : null,
                    ),
                    onChanged: (_) {
                      if (_invalid) setState(() => _invalid = false);
                    },
                  ),
                  if (_stale || !editable) Text(l10n.structuredInlineStale),
                ],
              )
            : Text(l10n.structuredSessionChanged),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        if (_hadLink && privateState)
          TextButton(
            onPressed: editable ? () => _apply(remove: true) : null,
            child: Text(l10n.structuredInlineLinkRemove),
          ),
        if (privateState)
          FilledButton(
            onPressed: editable ? () => _apply(remove: false) : null,
            child: Text(l10n.structuredInlineLinkApply),
          ),
      ],
    );
  }
}
