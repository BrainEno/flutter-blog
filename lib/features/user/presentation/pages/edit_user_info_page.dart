import 'dart:io';
import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/utils/pick_image.dart';
import 'package:belog/core/utils/show_snackbar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';

class EditUserInfoPage extends StatefulWidget {
  const EditUserInfoPage({super.key});
  @override
  State<EditUserInfoPage> createState() => _EditUserInfoPageState();
}

class _EditUserInfoPageState extends State<EditUserInfoPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  File? image;
  bool isNewImageSelected = false;
  String? avatarUrl;
  DateTime? updatedAt;
  bool _isDisposed = false; // Add this flag

  @override
  void didChangeDependencies() {
    final state = context.read<AppUserCubit>().state;
    if (state is AppUserLoggedIn) {
      if (!_isDisposed) {
        _nameController.text = state.user.name;
        _emailController.text = state.user.email;
        _websiteController.text = state.user.website;
        avatarUrl = state.user.avatarUrl;
        updatedAt = state.user.updatedAt;
      }
    }
    super.didChangeDependencies();
  }

  void selectImage() async {
    final pickedImage = await pickImage();
    if (pickedImage != null && !_isDisposed) {
      // check if disposed
      setState(() {
        image = pickedImage;
        isNewImageSelected = true;
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true; // Set the flag
    _nameController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑个人资料'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              context.read<UserEditBloc>().add(
                UserEditSubmitted(
                  name: _nameController.text,
                  email: _emailController.text,
                  website: _websiteController.text,
                  avatar: isNewImageSelected ? image : null,
                ),
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<UserEditBloc, UserEditState>(
        listener: (context, state) {
          if (state is UserEditSuccess) {
            Navigator.pop(context);
            showSnackBar(context, '个人资料更新成功!');
          } else if (state is UserEditFailure) {
            showSnackBar(context, state.message);
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circle Avatar
                GestureDetector(
                  onTap: selectImage,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        backgroundImage: isNewImageSelected
                            ? (image != null
                                  ? FileImage(image!) as ImageProvider<Object>?
                                  : null) // Added null check
                            : avatarUrl != null && avatarUrl!.isNotEmpty
                            ? CachedNetworkImageProvider(
                                '$avatarUrl?v=${updatedAt?.millisecondsSinceEpoch ?? ''}',
                              )
                            : null,
                        child: isNewImageSelected || avatarUrl != null
                            ? null
                            : const Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.grey,
                              ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Name Field
                TextFormField(
                  controller: _nameController,
                  autofocus: false,
                  decoration: const InputDecoration(
                    labelText: '姓名',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _websiteController,
                  autofocus: false,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '简介',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 32),
                // Save Button or Loading Indicator
                if (state is UserEditLoading)
                  const CircularProgressIndicator()
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        context.read<UserEditBloc>().add(
                          UserEditSubmitted(
                            name: _nameController.text,
                            email: _emailController.text,
                            website: _websiteController.text,
                            avatar: isNewImageSelected ? image : null,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '保存更改',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
