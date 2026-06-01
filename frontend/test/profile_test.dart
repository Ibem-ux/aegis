import 'package:aegis_chat/core/models/user_model.dart';
import 'package:aegis_chat/core/network/api_client.dart';
import 'package:aegis_chat/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeApiClient extends ApiClient {
  final Map<String, dynamic> mockResponseData;
  final int mockStatusCode;
  String? lastRequestPath;
  dynamic lastRequestData;
  String? lastRequestMethod;

  FakeApiClient({required this.mockResponseData, this.mockStatusCode = 200});

  @override
  Dio get dio {
    final fakeDio = Dio(BaseOptions(baseUrl: 'http://localhost:3000/api'));
    fakeDio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        lastRequestPath = options.path;
        lastRequestData = options.data;
        lastRequestMethod = options.method;
        
        final response = Response(
          requestOptions: options,
          data: mockResponseData,
          statusCode: mockStatusCode,
        );
        return handler.resolve(response);
      },
    ));
    return fakeDio;
  }
}

void main() {
  group('UserModel Serialization', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'user-123',
        'username': 'john_doe',
        'display_name': 'John',
        'full_name': 'John Doe',
        'avatar_url': 'http://avatar.com/1',
        'email': 'john@email.com',
        'phone': '12345678',
        'role': 'user',
        'status': 'ACTIVE',
        'totp_enabled': true,
        'password_updated_at': '2026-06-01T10:00:00Z',
        'last_seen': '2026-06-01T10:30:00Z',
        'created_at': '2026-06-01T09:00:00Z',
        'updated_at': '2026-06-01T09:30:00Z',
      };

      final user = UserModel.fromJson(json);

      expect(user.id, 'user-123');
      expect(user.username, 'john_doe');
      expect(user.displayName, 'John');
      expect(user.fullName, 'John Doe');
      expect(user.email, 'john@email.com');
      expect(user.phone, '12345678');
      expect(user.role, 'user');
      expect(user.status, 'ACTIVE');
      expect(user.totpEnabled, true);
      expect(user.passwordUpdatedAt, DateTime.parse('2026-06-01T10:00:00Z'));
      expect(user.lastSeen, DateTime.parse('2026-06-01T10:30:00Z'));
    });

    test('toJson serializes correctly', () {
      final user = UserModel(
        id: 'user-123',
        username: 'john_doe',
        displayName: 'John',
        fullName: 'John Doe',
        email: 'john@email.com',
        phone: '12345678',
        role: 'user',
        status: 'ACTIVE',
        totpEnabled: true,
        passwordUpdatedAt: DateTime.parse('2026-06-01T10:00:00Z'),
        lastSeen: DateTime.parse('2026-06-01T10:30:00Z'),
      );

      final json = user.toJson();

      expect(json['id'], 'user-123');
      expect(json['username'], 'john_doe');
      expect(json['display_name'], 'John');
      expect(json['full_name'], 'John Doe');
      expect(json['email'], 'john@email.com');
      expect(json['phone'], '12345678');
      expect(json['totp_enabled'], true);
    });
  });

  group('ProfileRepository API Client Integration', () {
    test('getMe retrieves correct profile', () async {
      final mockData = {
        'id': 'my-user-id',
        'username': 'me',
        'display_name': 'My Display Name',
        'role': 'user',
        'status': 'ACTIVE',
        'totp_enabled': false,
      };

      final fakeClient = FakeApiClient(mockResponseData: mockData);
      final repo = ProfileRepository(fakeClient);

      final result = await repo.getMe();

      expect(fakeClient.lastRequestMethod, 'GET');
      expect(fakeClient.lastRequestPath, '/users/me');
      expect(result.id, 'my-user-id');
      expect(result.username, 'me');
      expect(result.displayName, 'My Display Name');
    });

    test('updateProfile passes correct put payload', () async {
      final mockData = {
        'user': {
          'id': 'my-user-id',
          'username': 'me',
          'display_name': 'New Nickname',
          'role': 'user',
          'status': 'ACTIVE',
          'totp_enabled': false,
        }
      };

      final fakeClient = FakeApiClient(mockResponseData: mockData);
      final repo = ProfileRepository(fakeClient);

      final result = await repo.updateProfile(displayName: 'New Nickname');

      expect(fakeClient.lastRequestMethod, 'PUT');
      expect(fakeClient.lastRequestPath, '/users/me');
      expect(fakeClient.lastRequestData, {'display_name': 'New Nickname'});
      expect(result.displayName, 'New Nickname');
    });

    test('changePassword sends correct post payload', () async {
      final fakeClient = FakeApiClient(mockResponseData: {'message': 'Success'});
      final repo = ProfileRepository(fakeClient);

      await repo.changePassword(currentPassword: 'old_pass', newPassword: 'new_pass_123A!');

      expect(fakeClient.lastRequestMethod, 'POST');
      expect(fakeClient.lastRequestPath, '/users/password/change');
      expect(fakeClient.lastRequestData, {
        'current_password': 'old_pass',
        'new_password': 'new_pass_123A!',
      });
    });

    test('recoverAccount sends correct post payload without auth check', () async {
      final fakeClient = FakeApiClient(mockResponseData: {'message': 'Success'});
      final repo = ProfileRepository(fakeClient);

      await repo.recoverAccount(
        username: 'victim',
        recoveryKey: 'AEGIS-1234',
        newPassword: 'newPassword123!',
      );

      expect(fakeClient.lastRequestMethod, 'POST');
      expect(fakeClient.lastRequestPath, '/users/recovery/recover');
      expect(fakeClient.lastRequestData, {
        'username': 'victim',
        'recovery_key': 'AEGIS-1234',
        'new_password': 'newPassword123!',
      });
    });
  });
}
