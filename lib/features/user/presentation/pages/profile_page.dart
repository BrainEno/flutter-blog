import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/common/widgets/no_wave_action_row.dart';
import 'package:belog/core/common/widgets/no_wave_avatar.dart';
import 'package:belog/core/common/widgets/theme_toggle_button.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/l10n/failure_l10n.dart';
import 'package:belog/core/l10n/l10n.dart';
import 'package:belog/core/theme/no_wave_typography.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/user/data/user_data_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
            // A single scrollable keeps the header and every action available
            // at large system text sizes. Account security remains hidden until
            // the backend exposes its endpoints.
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NoWaveAvatar(name: name, imageUrl: user.avatarUrl),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      name,
                                      style: NoWaveTypography.title(
                                        context,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                  if (user.website.trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(user.website.trim()),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        NoWaveActionRow(
                          icon: Icons.edit_outlined,
                          label: l10n.menuEditProfile,
                          onTap: () => context.push('/profile/edit'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.article_outlined,
                          label: l10n.menuMyArticles,
                          onTap: () => context.push('/profile/my-articles'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.history,
                          label: l10n.menuReadingHistory,
                          onTap: () => context.push('/profile/history'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.info_outline,
                          label: l10n.menuAbout,
                          onTap: () => context.push('/profile/about'),
                        ),
                        NoWaveActionRow(
                          icon: Icons.file_download_outlined,
                          label: l10n.exportMyData,
                          description: l10n.exportMyDataHint,
                          onTap: () => _exportData(context, user),
                        ),
                        NoWaveActionRow(
                          icon: Icons.logout,
                          label: l10n.logout,
                          onTap: () =>
                              context.read<AuthBloc>().add(AuthLogout()),
                        ),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
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
