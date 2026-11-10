import 'dart:async';

import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/core/nowave/session/session_identity.dart';
import 'package:belog/core/design/design_tokens.dart';
import 'package:belog/core/design/components/no_wave_loading_label.dart';
import 'package:belog/core/design/components/no_wave_skeleton.dart';
import 'package:belog/features/user/domain/entities/user_media_asset.dart';
import 'package:belog/features/user/domain/entities/user_media_page.dart';
import 'package:belog/features/user/domain/usecases/get_user_media_library_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

enum UserMediaPickerPurpose { cover, avatar }

/// A read-only, cursor-paginated view of the signed-in user's media assets.
///
/// The caller captures the session when opening the sheet. Every request uses
/// that fence, and a changed identity clears the visible assets. The owning
/// editor also dismisses the modal route when its own session fence changes.
class UserMediaPickerSheet extends StatefulWidget {
  const UserMediaPickerSheet({
    super.key,
    required this.getPage,
    required this.sessionFence,
    required this.sessionIdentity,
    this.purpose = UserMediaPickerPurpose.cover,
  });

  final GetUserMediaLibraryPage getPage;
  final NowaveSessionFence sessionFence;
  final NowaveSessionIdentity sessionIdentity;
  final UserMediaPickerPurpose purpose;

  @override
  State<UserMediaPickerSheet> createState() => _UserMediaPickerSheetState();
}

class _UserMediaPickerSheetState extends State<UserMediaPickerSheet> {
  final List<UserMediaAsset> _items = [];
  StreamSubscription<void>? _identitySubscription;
  String? _nextCursor;
  Failure? _failure;
  bool _loading = false;
  bool _sessionInvalidated = false;
  bool _paginationUnavailable = false;
  int _requestGeneration = 0;

  bool get _matchesSession {
    final identity = widget.sessionIdentity;
    return identity.activeUserId == widget.sessionFence.userId &&
        identity.sessionGeneration == widget.sessionFence.generation &&
        !(identity.accessToken?.isEmpty ?? true);
  }

  @override
  void initState() {
    super.initState();
    _identitySubscription = widget.sessionIdentity.identityChanges.listen((_) {
      if (!_matchesSession) _invalidateSession();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadPage());
    });
  }

  @override
  void dispose() {
    _requestGeneration++;
    unawaited(_identitySubscription?.cancel());
    super.dispose();
  }

  void _invalidateSession() {
    if (_sessionInvalidated) return;
    _requestGeneration++;
    if (mounted) {
      setState(() {
        _sessionInvalidated = true;
        _items.clear();
        _nextCursor = null;
        _failure = null;
        _loading = false;
      });
    }
  }

  Future<void> _loadPage() async {
    if (_loading || _sessionInvalidated || _paginationUnavailable) return;
    if (!_matchesSession) {
      _invalidateSession();
      return;
    }
    final cursor = _nextCursor;
    if (_items.isNotEmpty && cursor == null) return;
    final requestGeneration = ++_requestGeneration;
    setState(() {
      _loading = true;
      _failure = null;
    });

    try {
      final result = await widget.getPage(
        GetUserMediaLibraryPageParams(
          sessionFence: widget.sessionFence,
          cursor: cursor,
        ),
      );
      if (!mounted || requestGeneration != _requestGeneration) return;
      if (!_matchesSession) {
        _invalidateSession();
        return;
      }
      result.fold(
        (failure) => setState(() {
          _failure = failure;
          _loading = false;
        }),
        (page) => _appendPage(page, requestedCursor: cursor),
      );
    } catch (_) {
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _failure = const Failure(
          'The media library could not be loaded.',
          kind: FailureKind.unknown,
          code: 'user.mediaLibraryUnavailable',
        );
        _loading = false;
      });
    }
  }

  void _appendPage(UserMediaPage page, {required String? requestedCursor}) {
    final previousIds = _items.map((item) => item.id).toSet();
    final newItems = page.items
        .where((item) => previousIds.add(item.id))
        .toList(growable: false);
    if (page.nextCursor != null &&
        (page.nextCursor == requestedCursor ||
            (page.items.isNotEmpty && newItems.isEmpty))) {
      setState(() {
        _paginationUnavailable = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _items.addAll(newItems);
      _nextCursor = page.nextCursor;
      _failure = null;
      _loading = false;
    });
  }

  void _select(UserMediaAsset asset) {
    if (!_matchesSession) {
      _invalidateSession();
      return;
    }
    Navigator.of(context).pop(asset);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            const SizedBox(height: NoWaveSpacing.small),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(NoWaveRadius.badge),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NoWaveSpacing.large,
                NoWaveSpacing.medium,
                NoWaveSpacing.small,
                NoWaveSpacing.medium,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.purpose == UserMediaPickerPurpose.avatar
                              ? context.l10n.userMediaPickerAvatarTitle
                              : context.l10n.userMediaPickerTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: NoWaveSpacing.small),
                        Text(
                          context.l10n.userMediaPickerDescription,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _content(context)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_sessionInvalidated) {
      return Center(child: Text(context.l10n.userMediaPickerSessionChanged));
    }
    if (_items.isEmpty) {
      if (_loading) {
        return Center(
          child: NoWaveLoadingLabel(label: context.l10n.userMediaPickerLoading),
        );
      }
      if (_failure != null) {
        return _emptyState(
          context,
          localizedFailure(context.l10n, _failure!),
          onRetry: () => unawaited(_loadPage()),
        );
      }
      return Center(child: Text(context.l10n.userMediaPickerEmpty));
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(NoWaveSpacing.medium),
          sliver: SliverGrid.builder(
            itemCount: _items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: NoWaveSpacing.small,
              mainAxisSpacing: NoWaveSpacing.medium,
              childAspectRatio: 0.76,
            ),
            itemBuilder: (context, index) => _assetTile(context, _items[index]),
          ),
        ),
        if (_failure != null || _paginationUnavailable || _nextCursor != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                NoWaveSpacing.medium,
                0,
                NoWaveSpacing.medium,
                NoWaveSpacing.large,
              ),
              child: _pageFooter(context),
            ),
          ),
      ],
    );
  }

  Widget _emptyState(
    BuildContext context,
    String message, {
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NoWaveSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: NoWaveSpacing.medium),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(context.l10n.userMediaPickerRetry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageFooter(BuildContext context) {
    if (_loading) {
      return Center(
        child: NoWaveLoadingLabel(
          label: context.l10n.userMediaPickerLoading,
          compact: true,
        ),
      );
    }
    if (_failure != null) {
      return Column(
        children: [
          Text(
            localizedFailure(context.l10n, _failure!),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: NoWaveSpacing.small),
          TextButton(
            onPressed: () => unawaited(_loadPage()),
            child: Text(context.l10n.userMediaPickerRetry),
          ),
        ],
      );
    }
    if (_paginationUnavailable) {
      return Text(
        context.l10n.userMediaPickerPaginationUnavailable,
        textAlign: TextAlign.center,
      );
    }
    if (_nextCursor != null) {
      return Center(
        child: TextButton.icon(
          onPressed: () => unawaited(_loadPage()),
          icon: const Icon(Icons.expand_more),
          label: Text(context.l10n.userMediaPickerLoadMore),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _assetTile(BuildContext context, UserMediaAsset asset) {
    final date = MaterialLocalizations.of(
      context,
    ).formatShortDate(asset.createdAt.toLocal());
    return Semantics(
      button: true,
      label: context.l10n.userMediaPickerAssetSemantics(
        asset.width,
        asset.height,
      ),
      child: InkWell(
        onTap: () => _select(asset),
        borderRadius: BorderRadius.circular(NoWaveRadius.none),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(NoWaveRadius.none),
                child: CachedNetworkImage(
                  imageUrl: asset.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const NoWaveSkeletonBlock(),
                  errorWidget: (context, url, error) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
            const SizedBox(height: NoWaveSpacing.small),
            Text(
              '${asset.width} × ${asset.height}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
