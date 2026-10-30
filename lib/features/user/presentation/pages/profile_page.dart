import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/common/widgets/theme_toggle_button.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/user/data/user_data_export.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  // Account security is hidden until the backend exposes those endpoints.
  static const _locations = [
    '/profile/edit',
    '/profile/my-articles',
    '/profile/history',
    '/profile/about',
  ];
  static const _icons = [Icons.edit, Icons.article, Icons.history, Icons.info];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = [
      l10n.menuEditProfile,
      l10n.menuMyArticles,
      l10n.menuReadingHistory,
      l10n.menuAbout,
    ];
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(l10n.profileTitle),
        actions: const [ThemeToggleButton(), SizedBox(width: 16)],
      ),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthLogoutFailure) {
            showSnackBar(context, localizedFailure(l10n, state.failure));
          }
        },
        child: BlocBuilder<AppUserCubit, AppUserState>(
          builder: (context, state) {
            if (state is! AppUserLoggedIn) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.notSignedIn),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.push('/login'),
                      child: Text(l10n.signIn),
                    ),
                  ],
                ),
              );
            }
            final user = state.user;
            final name = user.name.trim().isEmpty
                ? l10n.anonymousAuthor
                : user.name;
            // A single scrollable prevents the profile header and actions
            // from overflowing when the system text size is enlarged.
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Semantics(
                    image: true,
                    label: l10n.avatarOf(name),
                    child: CircleAvatar(
                      radius: 60,
                      backgroundImage: user.avatarUrl.isNotEmpty
                          ? CachedNetworkImageProvider(user.avatarUrl)
                          : null,
                      child: user.avatarUrl.isEmpty
                          ? const Icon(Icons.person, size: 60)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (user.website.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(user.website, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                const Divider(),
                for (var i = 0; i < _locations.length; i++)
                  ListTile(
                    leading: Icon(_icons[i]),
                    title: Text(labels[i]),
                    onTap: () => context.push(_locations[i]),
                  ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text(l10n.exportMyData),
                  subtitle: Text(l10n.exportMyDataHint),
                  onTap: () => _exportData(context, user),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(l10n.logout),
                  onTap: () => context.read<AuthBloc>().add(AuthLogout()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Runs the export behind a non-dismissible progress dialog so a second
  /// tap cannot queue another network request or system share sheet.
  Future<void> _exportData(BuildContext context, User user) async {
    final exporter = GetIt.instance<UserDataExporter>();
    final l10n = context.l10n;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: l10n.loading),
        ),
      ),
    );
    Either<Failure, void> result;
    try {
      result = await exporter.exportAndShare(
        user: user,
        shareTitle: l10n.exportShareTitle,
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'exporting user data failed',
        error: e,
        stackTrace: stackTrace,
      );
      result = left(Failure('导出失败，请重试', code: 'export.failed'));
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    result.fold(
      (failure) => showSnackBar(context, localizedFailure(l10n, failure)),
      (_) => showSnackBar(context, l10n.exportDone),
    );
  }
}
