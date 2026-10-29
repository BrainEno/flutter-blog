import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/common/widgets/theme_toggle_button.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:belog/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class ProfilePage extends StatelessWidget {
  static const List<(String, String)> items = [
    ('编辑个人资料', '/profile/edit'),
    ('我的文章', '/profile/my-articles'),
    ('账号设置', '/profile/account'),
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
                      backgroundImage: user.avatarUrl.isNotEmpty
                          ? CachedNetworkImageProvider(
                              '${user.avatarUrl}?v=${user.updatedAt.millisecondsSinceEpoch}',
                            )
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
                        itemCount: items.length + 1,
                        itemBuilder: (context, index) {
                          if (index == items.length) {
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
        return Icons.settings;
      case 3:
        return Icons.info;
      default:
        return Icons.help;
    }
  }

  void _onLogoutClick(BuildContext context) {
    context.read<AuthBloc>().add(AuthLogout());
  }
}
