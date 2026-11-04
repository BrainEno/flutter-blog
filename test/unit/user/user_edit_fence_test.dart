import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:belog/core/common/cubits/app_user/app_user_cubit.dart';
import 'package:belog/core/error/failures.dart';
import 'package:belog/core/network/connection_checker.dart';
import 'package:belog/core/nowave/nowave_api_client.dart';
import 'package:belog/core/nowave/nowave_session.dart';
import 'package:belog/core/nowave/nowave_session_fence.dart';
import 'package:belog/features/auth/data/models/user_model.dart';
import 'package:belog/features/user/bloc/user_edit_bloc.dart';
import 'package:belog/features/user/data/datasources/user_remote_data_source.dart';
import 'package:belog/features/user/data/repositories/user_repository_impl.dart';
import 'package:belog/features/user/domain/usecases/edit_user_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class _MemoryStore implements NowaveSessionStore {
  NowaveSessionData? stored;

  @override
  Future<void> clear() async => stored = null;

  @override
  Future<NowaveSessionData?> read() async => stored;

  @override
  Future<void> write(NowaveSessionData session) async => stored = session;
}

class _Connected implements ConnectionChecker {
  @override
  Future<bool> get isConnected async => true;
}

class _MockEditUserUseCase extends Mock implements EditUserUseCase {}

NowaveTokenPair _tokens(String id) => NowaveTokenPair(
  accessToken: 'access-$id',
  refreshToken: 'refresh-$id',
  accessExpiresAt: DateTime.utc(2031),
  refreshExpiresAt: DateTime.utc(2031),
);

Map<String, dynamic> _profile(String id) => {
  'userId': id,
  'displayName': '作者 $id',
  'bio': '简介',
  'updatedAt': '2025-01-01T00:00:00.000Z',
};

http.Response _json(Object data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      EditUserParams(
        userId: '',
        name: '',
        bio: '',
        website: '',
        sessionFence: const NowaveSessionFence(userId: '', generation: 0),
      ),
    );
  });

  late _MemoryStore store;
  late NowaveSessionManager manager;
  late List<String> requests;
  late File avatar;

  /// Builds a client whose behaviour per path is supplied by [handler]; the
  /// session manager is the same object the profile form fences against.
  NowaveApiClient clientFor(
    Future<http.Response> Function(http.Request) handler,
  ) {
    return NowaveApiClient(
      baseUrl: Uri.parse('https://api.example.invalid'),
      authenticator: manager,
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return handler(request);
      }),
    );
  }

  Future<void> signInAs(String id) async {
    await manager.adoptSession(_tokens(id), email: '$id@example.invalid');
    await manager.updateUserId(id);
  }

  setUp(() async {
    store = _MemoryStore();
    requests = <String>[];
    manager = NowaveSessionManager(
      client: NowaveApiClient(
        baseUrl: Uri.parse('https://api.example.invalid'),
      ),
      store: store,
    );
    final stamp = DateTime.now().microsecondsSinceEpoch;
    avatar = File('${Directory.systemTemp.path}/fence_avatar_$stamp.jpg');
    await avatar.writeAsBytes(const [1, 2, 3]);
    addTearDown(() async {
      if (await avatar.exists()) await avatar.delete();
    });
  });

  Future<void> pumpSave({
    required NowaveApiClient client,
    required AppUserCubit cubit,
    File? avatarFile,
  }) async {
    final repository = UserRepositoryImpl(
      UserRemoteDataSourceImpl(client, manager),
      _Connected(),
    );
    final bloc = UserEditBloc(
      editUserUseCase: EditUserUseCase(repository),
      appUserCubit: cubit,
      sessionIdentity: manager,
    );
    // Subscribe before dispatching: the form can finish before a late
    // listener would see its terminal state.
    final done = bloc.stream.firstWhere(
      (state) => state is UserEditSuccess || state is UserEditFailure,
    );
    bloc.add(UserEditSubmitted(name: '新名字', bio: '简介', avatar: avatarFile));
    await done;
    await bloc.close();
  }

  test('a switch during the profile read stops the write', () async {
    await signInAs('A');
    final readStarted = Completer<void>();
    final release = Completer<void>();
    final client = clientFor((request) async {
      if (request.url.path == '/api/v1/authors/A') {
        readStarted.complete();
        await release.future;
        return _json(_profile('A'));
      }
      return _json(_profile('A'));
    });
    final cubit = AppUserCubit()
      ..updateUser(
        UserModel(
          id: 'A',
          email: 'A@example.invalid',
          name: 'A',
          updatedAt: DateTime.utc(2024),
        ),
      );
    final before = cubit.state;

    final save = pumpSave(client: client, cubit: cubit);
    await readStarted.future;
    await signInAs('B');
    release.complete();
    await save;

    expect(
      requests,
      isNot(contains('PUT /api/v1/me/profile')),
      reason: 'the form belongs to A and must not write as B',
    );
    expect(cubit.state, before, reason: 'B owns the UI now');
  });

  test('a switch after the avatar upload stops the write', () async {
    await signInAs('A');
    final uploadStarted = Completer<void>();
    final release = Completer<void>();
    final client = clientFor((request) async {
      if (request.url.path == '/api/v1/me/media') {
        uploadStarted.complete();
        await release.future;
        return _json({'id': 'm1', 'contentType': 'image/webp'});
      }
      return _json(_profile('A'));
    });
    final cubit = AppUserCubit()
      ..updateUser(
        UserModel(
          id: 'A',
          email: 'A@example.invalid',
          name: 'A',
          updatedAt: DateTime.utc(2024),
        ),
      );
    final before = cubit.state;

    final save = pumpSave(client: client, cubit: cubit, avatarFile: avatar);
    await uploadStarted.future;
    await signInAs('B');
    release.complete();
    await save;

    expect(
      requests,
      contains('POST /api/v1/me/media'),
      reason: 'the upload started while A was active',
    );
    expect(requests, isNot(contains('PUT /api/v1/me/profile')));
    expect(cubit.state, before);
  });

  test('A -> B -> A is still a different operation', () async {
    await signInAs('A');
    final readStarted = Completer<void>();
    final release = Completer<void>();
    final client = clientFor((request) async {
      if (request.url.path == '/api/v1/authors/A') {
        readStarted.complete();
        await release.future;
        return _json(_profile('A'));
      }
      return _json(_profile('A'));
    });
    final cubit = AppUserCubit()
      ..updateUser(
        UserModel(
          id: 'A',
          email: 'A@example.invalid',
          name: 'A',
          updatedAt: DateTime.utc(2024),
        ),
      );

    final save = pumpSave(client: client, cubit: cubit);
    await readStarted.future;
    await signInAs('B');
    await signInAs('A');
    release.complete();
    await save;

    // Same user id, new generation: the fence compares both, so the old form
    // is not silently re-used.
    expect(requests, isNot(contains('PUT /api/v1/me/profile')));
  });

  test('an unchanged session saves normally', () async {
    await signInAs('A');
    final client = clientFor((_) async => _json(_profile('A')));
    final cubit = AppUserCubit()
      ..updateUser(
        UserModel(
          id: 'A',
          email: 'A@example.invalid',
          name: 'A',
          updatedAt: DateTime.utc(2024),
        ),
      );

    await pumpSave(client: client, cubit: cubit);

    expect(requests, contains('PUT /api/v1/me/profile'));
    expect((cubit.state as AppUserLoggedIn).user.name, '作者 A');
  });

  test('a switch after the write does not repaint the new account', () async {
    final useCase = _MockEditUserUseCase();
    final cubit = AppUserCubit()
      ..updateUser(
        UserModel(
          id: 'A',
          email: 'A@example.invalid',
          name: 'A',
          updatedAt: DateTime.utc(2024),
        ),
      );
    final before = cubit.state;
    when(() => useCase(any())).thenAnswer((_) async {
      // The save landed, then the account changed before the UI update.
      await signInAs('B');
      return Right<Failure, UserModel>(
        UserModel(
          id: 'A',
          email: 'A@example.invalid',
          name: 'A saved',
          updatedAt: DateTime.utc(2024),
        ),
      );
    });
    final bloc = UserEditBloc(
      editUserUseCase: useCase,
      appUserCubit: cubit,
      sessionIdentity: manager,
    );
    await signInAs('A');

    final done = bloc.stream.firstWhere(
      (state) => state is UserEditSuccess || state is UserEditFailure,
    );
    bloc.add(const UserEditSubmitted(name: '新名字'));
    final state = await done;

    expect(state, isA<UserEditFailure>());
    expect((state as UserEditFailure).failure.code, 'auth.sessionChanged');
    expect(cubit.state, before, reason: "A's profile must not paint B's UI");
    await bloc.close();
  });

  test('signed out means nothing is sent', () async {
    final client = clientFor((_) async => _json(_profile('A')));
    final cubit = AppUserCubit()
      ..updateUser(
        UserModel(
          id: 'A',
          email: 'A@example.invalid',
          name: 'A',
          updatedAt: DateTime.utc(2024),
        ),
      );

    await pumpSave(client: client, cubit: cubit);

    expect(requests, isEmpty);
    expect(cubit.state, isA<AppUserLoggedIn>());
  });
}
