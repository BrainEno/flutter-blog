import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/storage/reading_history_store.dart';
import 'package:belog/core/utils/format_date.dart';
import 'package:belog/router/app_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

/// The device-local reading history of the signed-in account (issue #22).
///
/// Everything shown lives in SQLite and never leaves the device. The list
/// refreshes when the viewer above it pops (a re-read bumps the entry to
/// the top) and each row can be removed individually or wholesale.
class ReadingHistoryPage extends StatefulWidget {
  /// Injectable for tests; resolved from the service locator when absent.
  final ReadingHistoryStore? store;
  const ReadingHistoryPage({super.key, this.store});

  @override
  State<ReadingHistoryPage> createState() => _ReadingHistoryPageState();
}

class _ReadingHistoryPageState extends State<ReadingHistoryPage>
    with RouteAware {
  late final ReadingHistoryStore _store;
  List<ReadingHistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? GetIt.instance<ReadingHistoryStore>();
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      profileRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    profileRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Returning from the viewer: the just-read article moved to the top.
    _reload();
  }

  String? get _userId {
    final state = context.read<AppUserCubit>().state;
    return state is AppUserLoggedIn ? state.user.id : null;
  }

  Future<void> _reload() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final entries = await _store.list(userId: userId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      // Local bookkeeping: never block the page on a storage hiccup.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _remove(ReadingHistoryEntry entry) async {
    final userId = _userId;
    if (userId == null) return;
    setState(() => _entries.removeWhere((e) => e.blogId == entry.blogId));
    await _store.remove(userId: userId, blogId: entry.blogId);
  }

  Future<void> _confirmClearAll() async {
    final userId = _userId;
    if (userId == null) return;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.clearHistoryTitle),
        content: Text(l10n.clearHistoryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.actionClear),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.clear(userId: userId);
    if (mounted) setState(() => _entries = []);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(context.l10n.historyTitle),
        elevation: 1.0,
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: context.l10n.clearHistoryTitle,
              icon: const Icon(Icons.delete_sweep),
              onPressed: _confirmClearAll,
            ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                semanticsLabel: context.l10n.loading,
              ),
            )
          : _entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.historyEmpty,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.historyEmptyHint,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final readAtLabel = formatDate(Localizations.localeOf(context), entry.readAt);
                return Dismissible(
                  key: ValueKey(entry.blogId),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _remove(entry),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Semantics(
                        image: true,
                        label: context.l10n.coverOf(entry.title),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: entry.imageUrl.isEmpty
                              ? Icon(
                                  Icons.article,
                                  size: 32,
                                  color: Colors.grey.shade400,
                                )
                              : CachedNetworkImage(
                                  imageUrl: entry.imageUrl,
                                  fit: BoxFit.cover,
                                  width: 56,
                                  height: 56,
                                  errorWidget: (context, error, stackTrace) =>
                                      Icon(
                                        Icons.broken_image,
                                        size: 32,
                                        color: Colors.grey.shade400,
                                      ),
                                ),
                        ),
                      ),
                    ),
                    title: Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      entry.posterName.isEmpty
                          ? readAtLabel
                          : '${entry.posterName} · $readAtLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: context.l10n.removeHistoryEntry,
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: Colors.grey.shade500,
                      ),
                      onPressed: () => _remove(entry),
                    ),
                    onTap: () => context.push('/view/${entry.blogId}'),
                  ),
                );
              },
            ),
    );
  }
}
