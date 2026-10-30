import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/entities/user.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/utils/app_logger.dart';
import 'package:belog/core/common/widgets/theme_toggle_button.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:belog/features/user/data/user_data_export.dart';
import 'package:fpdart/fpdart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

class ProfilePage extends StatelessWidget {
  // Account security (e-mail / password changes) is hidden until the
  // no-wave backend grows the corresponding endpoints (gap G2, see
  // docs/supabase-to-nowave-migration.md).
  static const List<(String, String)> items = [
    ('编辑个人资料', '/profile/edit'),
    ('我的文章', '/profile/my-articles'),
    ('阅读历史', '/profile/history'),
    ('关于我们', '/profile/about'),
  ];

  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(width: 55),
            const Text('个人中心'),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [ThemeToggleButton()],
            ),
          ],
        ),
      ),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthLogoutFailure) {
            showSnackBar(context, state.message);
          }
        },
        child: BlocBuilder<AppUserCubit, AppUserState>(
          builder: (context, state) {
            if (state is AppUserLoggedIn) {
              final user = state.user;
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      // Avatar media URLs are immutable (each upload is a
                      // new asset id), so no cache-busting suffix is needed.
                      backgroundImage: user.avatarUrl.isNotEmpty
                          ? CachedNetworkImageProvider(user.avatarUrl)
                          : null,
                      child: user.avatarUrl.isEmpty
                          ? const Icon(Icons.person, size: 60)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18.0),
                      child: Text(
                        user.website.isNotEmpty ? user.website : '',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length + 2,
                        itemBuilder: (context, index) {
                          if (index == items.length) {
                            // Data export (issue #22): profile + own articles
                            // as a JSON file through the system share sheet.
                            return ListTile(
                              leading: Icon(
                                Icons.file_download_outlined,
                                color: Colors.grey.shade700,
                              ),
                              title: const Text(
                                '导出我的数据',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                '将个人资料与全部文章导出为 JSON 文件',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              onTap: () => _exportData(context, user),
                            );
                          }
                          if (index == items.length + 1) {
                            return ListTile(
                              leading: Icon(
                                Icons.logout,
                                color: Colors.grey.shade700,
                              ),
                              title: const Text(
                                '退出登录',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              onTap: () => _onLogoutClick(context),
                            );
                          }
                          final (label, location) = items[index];
                          return ListTile(
                            leading: Icon(
                              _iconFor(index),
                              color: Colors.grey.shade700,
                            ),
                            title: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onTap: () => context.push(location),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            } else {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '您还没有登录',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.push('/login'),
                      child: const Text('登录'),
                    ),
                  ],
                ),
              );
            }
          },
        ),
      ),
    );
  }

  IconData _iconFor(int index) {
    switch (index) {
      case 0:
        return Icons.edit;
      case 1:
        return Icons.article;
      case 2:
        return Icons.history;
      case 3:
        return Icons.info;
      default:
        return Icons.help;
    }
  }

  /// Runs the export behind a non-dismissible progress dialog: the article
  /// fetch is a network call, and a second tap would queue a second one.
  Future<void> _exportData(BuildContext context, User user) async {
    final exporter = GetIt.instance<UserDataExporter>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    Either<Failure, void> result;
    try {
      result = await exporter.exportAndShare(user: user);
    } catch (e, stackTrace) {
      // The share sheet or temp storage can fail outside the repository
      // error mapping; the user still deserves to know it did not work.
      AppLogger.error(
        'exporting user data failed',
        error: e,
        stackTrace: stackTrace,
      );
      result = left(Failure('导出失败，请重试'));
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    result.fold(
      (failure) => showSnackBar(context, failure.message),
      (_) => showSnackBar(context, '已生成导出文件'),
    );
  }

  void _onLogoutClick(BuildContext context) {
    context.read<AuthBloc>().add(AuthLogout());
  }
}
