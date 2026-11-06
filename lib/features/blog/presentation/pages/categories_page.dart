import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/app_palette.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/blog/domain/entities/category_ref.dart';
import 'package:belog/features/blog/presentation/blocs/categories/categories_cubit.dart';
import 'package:belog/features/blog/presentation/category_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The public category catalog, scoped to the search tab and kept in memory
/// only.
///
/// Categories are the editors' filing system, not the reader's: this page lists
/// what the server has in the current content language, and says so when the
/// server offers no categories at all instead of showing an empty screen that
/// looks like a network failure.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    context.read<CategoriesCubit>().load();
  }

  Widget _contentWidth(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.categoriesTitle)),
      body: BlocBuilder<CategoriesCubit, CategoriesState>(
        builder: (context, state) {
          if (state is CategoriesInitial || state is CategoriesLoading) {
            return Center(
              child: CircularProgressIndicator(semanticsLabel: l10n.loading),
            );
          }
          if (state is CategoriesFailure) {
            return _status(
              NoWaveStatus(
                message: localizedFailure(l10n, state.failure),
                actionLabel: l10n.actionRetry,
                onAction: _load,
              ),
            );
          }
          if (state is CategoriesSuccess) {
            if (state.isEmpty) {
              return _status(
                NoWaveStatus(message: l10n.categoriesEmpty),
              );
            }
            return RefreshIndicator(onRefresh: _refresh, child: _list(state));
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _refresh() async {
    final cubit = context.read<CategoriesCubit>();
    final settled = cubit.stream.firstWhere(
      (state) =>
          state is CategoriesSuccess || state is CategoriesFailure,
    );
    cubit.load();
    await settled;
  }

  Widget _status(Widget status) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(NoWaveSpacing.page),
    children: [
      const SizedBox(height: 48),
      Center(child: status),
    ],
  );

  Widget _list(CategoriesSuccess state) {
    final l10n = context.l10n;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        NoWaveSpacing.page,
        NoWaveSpacing.large,
        NoWaveSpacing.page,
        NoWaveSpacing.section,
      ),
      itemCount: state.categories.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _contentWidth(
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                l10n.categoriesDescription,
                style: NoWaveTypography.meta(context),
              ),
            ),
          );
        }
        if (index == state.categories.length + 1) {
          // The endpoint caps `limit` and offers no total: a full page is the
          // only sign the catalog may continue.
          if (!state.mayBeIncomplete) return const SizedBox(height: 24);
          return _contentWidth(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l10n.categoriesCapped,
                  style: NoWaveTypography.meta(context),
                ),
              ),
            ),
          );
        }
        return _contentWidth(
          _CategoryRow(category: state.categories[index - 1]),
        );
      },
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final CategoryRef category;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => openCategoryArticles(context, category),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: NoWaveTypography.title(context, size: 20),
                        ),
                        if (category.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            category.description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: NoWaveTypography.meta(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
