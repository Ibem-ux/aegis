import '../../../core/models/user_model.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class ProfileRepository {
  final ApiClient _apiClient;

  ProfileRepository(this._apiClient);

  /// Fetch current user's profile info
  Future<UserModel> getMe() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      ApiEndpoints.me,
    );
    return UserModel.fromJson(response.data!);
  }

  /// Update user's profile details
  Future<UserModel> updateProfile({
    String? displayName,
    String? fullName,
    String? email,
    String? phone,
    String? avatarUrl,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) data['display_name'] = displayName;
    if (fullName != null) data['full_name'] = fullName;
    if (email != null) data['email'] = email;
    if (phone != null) data['phone'] = phone;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;

    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      ApiEndpoints.me,
      data: data,
    );
    
    final responseData = response.data!;
    return UserModel.fromJson(responseData['user'] as Map<String, dynamic>);
  }

  /// Change current user's password
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      ApiEndpoints.passwordChange,
      data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  /// Fetch active device sessions list
  Future<List<Map<String, dynamic>>> getSessions() async {
    final response = await _apiClient.dio.get<List<dynamic>>(
      ApiEndpoints.sessions,
    );
    return response.data!.map((item) => item as Map<String, dynamic>).toList();
  }

  /// Revoke a specific active device session
  Future<void> revokeSession(String sessionId) async {
    await _apiClient.dio.delete<Map<String, dynamic>>(
      '${ApiEndpoints.sessions}/$sessionId',
    );
  }

  /// Generates a new Master Recovery Key for the user
  Future<String> generateMasterRecoveryKey() async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      ApiEndpoints.recoveryGenerate,
    );
    final responseData = response.data!;
    return responseData['recovery_key'] as String;
  }

  /// Public API to perform self-service account recovery and password update
  Future<void> recoverAccount({
    required String username,
    required String recoveryKey,
    required String newPassword,
  }) async {
    // Note: This endpoint is public and bypasses JWT validation on the backend
    await _apiClient.dio.post<Map<String, dynamic>>(
      ApiEndpoints.recoveryRecover,
      data: {
        'username': username,
        'recovery_key': recoveryKey,
        'new_password': newPassword,
      },
    );
  }
}
