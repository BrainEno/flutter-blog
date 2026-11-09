import 'dart:async';

import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/error/error_mapper.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/features/messages/domain/entities/conversation.dart';
import 'package:belog/features/messages/domain/entities/message_participant.dart';
import 'package:belog/features/user/domain/entities/author_search_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';

/// Search is deliberately limited to profiles the public author directory can
/// return; the conversation API itself accepts unchecked user IDs.
typedef MessageParticipantAuthorSearch =
    Future<Either<Failure, List<AuthorSearchResult>>> Function(String query);

typedef MessageParticipantUpdate =
    Future<Failure?> Function({
      required List<String> addUserIds,
      required List<String> removeUserIds,
    });

/// Creator-only member manager. Adding is confirmed separately because the
/// server gives every new or re-added member access to the entire history.
class MessageParticipantsSheet extends StatefulWidget {
  const MessageParticipantsSheet({
    super.key,
    required this.conversation,
    required this.viewerId,
    required this.participants,
    required this.searchAuthors,
    required this.updateParticipants,
  });

  final Conversation conversation;
  final String viewerId;
  final Map<String, MessageParticipant> participants;
  final MessageParticipantAuthorSearch searchAuthors;
  final MessageParticipantUpdate updateParticipants;

  @override
  State<MessageParticipantsSheet> createState() =>
      _MessageParticipantsSheetState();
}

class _MessageParticipantsSheetState extends State<MessageParticipantsSheet> {
  static const Duration _searchDebounce = Duration(milliseconds: 300);

  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  Timer? _searchTimer;
  int _searchGeneration = 0;
  bool _adding = false;
  bool _searching = false;
  bool _updating = false;
  bool _actionsBlocked = false;
  bool _queryTooLong = false;
  String _query = '';
  Failure? _searchFailure;
  Failure? _updateFailure;
  List<AuthorSearchResult> _results = const [];

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _beginAdding() {
    _searchGeneration++;
    _searchTimer?.cancel();
    _searchController.clear();
    setState(() {
      _adding = true;
      _query = '';
      _queryTooLong = false;
      _searching = false;
      _searchFailure = null;
      _updateFailure = null;
      _results = const [];
      _selectedIds.clear();
    });
  }

  void _returnToMembers() {
    _searchGeneration++;
    _searchTimer?.cancel();
    setState(() {
      _adding = false;
      _query = '';
      _queryTooLong = false;
      _searching = false;
      _searchFailure = null;
      _updateFailure = null;
      _results = const [];
      _selectedIds.clear();
    });
    _searchController.clear();
  }

  void _queryChanged(String input) {
    _searchTimer?.cancel();
    final generation = ++_searchGeneration;
    final query = input.trim();
    final tooLong = query.length > maxAuthorSearchQueryLength;
    setState(() {
      _query = query;
      _queryTooLong = tooLong;
      _searchFailure = null;
      _results = const [];
      _searching = query.isNotEmpty && !tooLong;
    });
    if (query.isEmpty || tooLong) return;
    _searchTimer = Timer(_searchDebounce, () {
      unawaited(_search(query, generation));
    });
  }

  Future<void> _search(String query, int generation) async {
    Either<Failure, List<AuthorSearchResult>> result;
    try {
      result = await widget.searchAuthors(query);
    } catch (error) {
      result = left(mapErrorToFailure(error).forPresentation());
    }
    if (!mounted || generation != _searchGeneration) return;
    result.fold(
      (failure) => setState(() {
        _searching = false;
        _searchFailure = failure.forPresentation();
        _results = const [];
      }),
      (people) => setState(() {
        _searching = false;
        _searchFailure = null;
        _results = _eligibleAuthors(people);
      }),
    );
  }

  List<AuthorSearchResult> _eligibleAuthors(
    List<AuthorSearchResult> people,
  ) {
    final activeIds = widget.conversation.participantIds.toSet();
    final seen = <String>{};
    return List.unmodifiable([
      for (final person in people)
        if (person.userId.isNotEmpty &&
            person.userId == person.userId.trim() &&
            !activeIds.contains(person.userId) &&
            seen.add(person.userId))
          person,
    ]);
  }

  void _toggleSelected(AuthorSearchResult person, bool selected) {
    setState(() {
      if (selected) {
        if (_selectedIds.length < 20) _selectedIds.add(person.userId);
      } else {
        _selectedIds.remove(person.userId);
      }
      _updateFailure = null;
    });
  }

  Future<void> _confirmAdd() async {
    if (_selectedIds.isEmpty || _updating || _actionsBlocked) return;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.messagesParticipantsAddConfirmTitle(_selectedIds.length)),
        content: Text(l10n.messagesParticipantsHistoryWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.messagesParticipantsConfirmAdd),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _apply(addUserIds: _selectedIds.toList(growable: false));
  }

  Future<void> _confirmRemove(String userId) async {
    if (userId == widget.viewerId || _updating || _actionsBlocked) return;
    final l10n = context.l10n;
    final member = widget.participants[userId];
    final name = member != null && member.displayName.trim().isNotEmpty
        ? member.displayName
        : l10n.messagesUnknownParticipant;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.messagesParticipantsRemoveTitle(name)),
        content: Text(l10n.messagesParticipantsRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.messagesParticipantsRemoveAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _apply(removeUserIds: [userId]);
  }

  Future<void> _apply({
    List<String> addUserIds = const [],
    List<String> removeUserIds = const [],
  }) async {
    if (_updating || _actionsBlocked) return;
    setState(() {
      _updating = true;
      _updateFailure = null;
    });
    Failure? failure;
    try {
      failure = await widget.updateParticipants(
        addUserIds: addUserIds,
        removeUserIds: removeUserIds,
      );
    } catch (error) {
      failure = mapErrorToFailure(error).forPresentation();
    }
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _updating = false;
      _updateFailure = failure.forPresentation();
      _actionsBlocked =
          _isOutcomeUnknown(failure) ||
          failure.code == 'messages.participantsConflict' ||
          failure.code == 'messages.participantsUnavailable' ||
          failure.code == 'messages.participantsForbidden';
    });
  }

  bool _isOutcomeUnknown(Failure failure) =>
      failure.code == 'network.offline' ||
      failure.code == 'network.unavailable' ||
      failure.code == 'network.timeout' ||
      failure.code == 'auth.sessionChanged' ||
      failure.code == 'client.parse' ||
      failure.code == 'server.error' ||
      failure.code == 'server.SERVICE_UNAVAILABLE' ||
      failure.code == 'unknown';

  String _updateFailureText(Failure failure) {
    if (_isOutcomeUnknown(failure)) {
      return context.l10n.messagesParticipantsOutcomeUnknown;
    }
    return localizedFailure(context.l10n, failure);
  }

  String _memberName(String userId) {
    final participant = widget.participants[userId];
    if (participant != null && participant.displayName.trim().isNotEmpty) {
      return participant.displayName;
    }
    return context.l10n.messagesUnknownParticipant;
  }

  Widget _header(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.medium,
        NoWaveSpacing.small,
        NoWaveSpacing.small,
        NoWaveSpacing.small,
      ),
      child: Row(
        children: [
          if (_adding)
            IconButton(
              tooltip: l10n.actionBack,
              onPressed: _updating || _actionsBlocked ? null : _returnToMembers,
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: Text(
              _adding
                  ? l10n.messagesParticipantsAddTitle
                  : l10n.messagesParticipantsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: l10n.actionClose,
            onPressed: _updating ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _historyNotice(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.medium,
        0,
        NoWaveSpacing.medium,
        NoWaveSpacing.small,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(NoWaveSpacing.small),
          child: Text(
            context.l10n.messagesParticipantsHistoryWarning,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }

  Widget _failureNotice(BuildContext context) {
    final failure = _updateFailure;
    if (failure == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.medium,
        0,
        NoWaveSpacing.medium,
        NoWaveSpacing.small,
      ),
      child: Text(
        _updateFailureText(failure),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _membersView(BuildContext context) {
    final l10n = context.l10n;
    final ids = widget.conversation.participantIds;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NoWaveSpacing.medium,
            NoWaveSpacing.small,
            NoWaveSpacing.medium,
            NoWaveSpacing.xs,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.messagesParticipantsCurrent,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: ids.length,
            itemBuilder: (context, index) {
              final userId = ids[index];
              final person = widget.participants[userId];
              final name = _memberName(userId);
              return ListTile(
                leading: NoWaveAvatar(
                  name: name,
                  imageUrl: person?.avatarUrl ?? '',
                  size: 40,
                ),
                title: Text(name),
                subtitle: userId == widget.viewerId
                    ? Text(l10n.messagesYou)
                    : null,
                trailing: userId == widget.viewerId
                    ? null
                    : IconButton(
                        tooltip: l10n.messagesParticipantsRemoveAction,
                        onPressed: _updating || _actionsBlocked
                            ? null
                            : () => _confirmRemove(userId),
                        icon: const Icon(Icons.person_remove_outlined),
                      ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(NoWaveSpacing.medium),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _updating || _actionsBlocked ? null : _beginAdding,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(l10n.messagesParticipantsAddAction),
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchContent(BuildContext context) {
    final l10n = context.l10n;
    if (_queryTooLong) {
      return NoWaveStatus(message: l10n.authorSearchTooLong);
    }
    final failure = _searchFailure;
    if (failure != null) {
      return NoWaveStatus(message: localizedFailure(l10n, failure));
    }
    if (_searching) {
      return Center(
        child: NoWaveLoadingLabel(semanticLabel: l10n.loading),
      );
    }
    if (_query.isEmpty) {
      return NoWaveStatus(message: l10n.messagesParticipantsSearchPrompt);
    }
    if (_results.isEmpty) {
      return NoWaveStatus(message: l10n.messagesParticipantsSearchEmpty);
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final person = _results[index];
        final selected = _selectedIds.contains(person.userId);
        final atLimit = _selectedIds.length >= 20 && !selected;
        final name = person.displayName.trim().isEmpty
            ? l10n.messagesUnknownParticipant
            : person.displayName;
        return CheckboxListTile(
          value: selected,
          onChanged: _updating || _actionsBlocked || atLimit
              ? null
              : (value) => _toggleSelected(person, value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          secondary: const Icon(Icons.person_outline),
          title: Text(name),
        );
      },
    );
  }

  Widget _addingView(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NoWaveSpacing.medium,
            NoWaveSpacing.small,
            NoWaveSpacing.medium,
            0,
          ),
          child: TextField(
            controller: _searchController,
            enabled: !_updating && !_actionsBlocked,
            onChanged: _queryChanged,
            textInputAction: TextInputAction.search,
            maxLength: maxAuthorSearchQueryLength,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            decoration: InputDecoration(
              labelText: l10n.messagesParticipantsSearchHint,
              prefixIcon: const Icon(Icons.search),
              counterText: '',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NoWaveSpacing.medium),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.messagesParticipantsSearchScope,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(child: _searchContent(context)),
        if (_selectedIds.length >= 20)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NoWaveSpacing.medium),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.messagesParticipantsSelectionLimit,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        if (_selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NoWaveSpacing.medium,
              NoWaveSpacing.small,
              NoWaveSpacing.medium,
              NoWaveSpacing.medium,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _updating || _actionsBlocked ? null : _confirmAdd,
                icon: _updating
                    ? const Icon(Icons.hourglass_top_outlined)
                    : const Icon(Icons.group_add_outlined),
                label: Text(
                  _updating
                      ? l10n.messagesParticipantsUpdating
                      : l10n.messagesParticipantsAddSelected(
                          _selectedIds.length,
                        ),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NoWaveSpacing.medium,
              NoWaveSpacing.small,
              NoWaveSpacing.medium,
              NoWaveSpacing.medium,
            ),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _updating || _actionsBlocked ? null : _returnToMembers,
                child: Text(l10n.actionCancel),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final height = MediaQuery.sizeOf(context).height - viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height * 0.86,
          child: Column(
            children: [
              _header(context),
              _historyNotice(context),
              _failureNotice(context),
              if (_updating)
                Padding(
                  padding: const EdgeInsets.only(bottom: NoWaveSpacing.small),
                  child: NoWaveLoadingLabel(
                    semanticLabel: context.l10n.messagesParticipantsUpdating,
                    compact: true,
                  ),
                ),
              Expanded(
                child: _adding ? _addingView(context) : _membersView(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
