import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/common/widgets/no_wave_status.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/features/user/domain/entities/author_relationship.dart';
import 'package:belog/features/user/presentation/bloc/author_relationships/author_relationships_cubit.dart';
import 'package:belog/router/shell_branch_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// A public, online-only relationship list. The backend currently offers no
/// way to request a second page, so a full response must not imply completion.
class AuthorRelationshipsPage extends StatelessWidget {
  const AuthorRelationshipsPage({super.key, required this.kind});

  final AuthorRelationshipKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final followers = kind == AuthorRelationshipKind.followers;
    return BlocBuilder<AuthorRelationshipsCubit, AuthorRelationshipsState>(
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: Text(followers ? l10n.followersTitle : l10n.followingTitle),
          actions: [
            IconButton(
              tooltip: l10n.relationshipRefresh,
              onPressed: state is AuthorRelationshipsLoading
                  ? null
                  : () => context.read<AuthorRelationshipsCubit>().load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: switch (state) {
          AuthorRelationshipsLoading() => Center(
            child: CircularProgressIndicator(semanticsLabel: l10n.loading),
          ),
          AuthorRelationshipsFailed(:final failure) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: NoWaveStatus(
                message: localizedFailure(l10n, failure),
                actionLabel: l10n.actionRetry,
                onAction: () => context.read<AuthorRelationshipsCubit>().load(),
              ),
            ),
          ),
          AuthorRelationshipsLoaded(:final people) when people.isEmpty =>
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: NoWaveStatus(
                  message: followers
                      ? l10n.followersEmpty
                      : l10n.followingEmpty,
                ),
              ),
            ),
          AuthorRelationshipsLoaded(:final people) => _PeopleList(
            people: people,
          ),
        },
      ),
    );
  }
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({required this.people});

  final List<AuthorRelationship> people;

  @override
  Widget build(BuildContext context) {
    final capped = people.length == maxAuthorRelationshipResults;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: people.length + (capped ? 1 : 0),
      itemBuilder: (context, index) {
        if (capped && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                context.l10n.relationshipLimitNotice,
                style: NoWaveTypography.meta(context),
              ),
            ),
          );
        }
        final person = people[index - (capped ? 1 : 0)];
        final name = person.displayName.trim().isEmpty
            ? context.l10n.anonymousAuthor
            : person.displayName;
        return Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.push(
                  shellBranchLocation(
                    GoRouterState.of(context).uri,
                    '/author/${Uri.encodeComponent(person.userId)}',
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NoWaveAvatar(
                        name: name,
                        imageUrl: person.avatarUrl,
                        size: 48,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: NoWaveTypography.title(context, size: 20),
                            ),
                            if (person.bio.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                person.bio,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const ExcludeSemantics(child: Icon(Icons.chevron_right)),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}
