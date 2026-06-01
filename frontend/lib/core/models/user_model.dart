class UserModel {
  final String id;
  final String username;
  final String? displayName;
  final String? fullName;
  final String? avatarUrl;
  final String? email;
  final String? phone;
  final String role;
  final String status;
  final bool totpEnabled;
  final DateTime? passwordUpdatedAt;
  final DateTime? lastSeen;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.id,
    required this.username,
    this.displayName,
    this.fullName,
    this.avatarUrl,
    this.email,
    this.phone,
    required this.role,
    required this.status,
    required this.totpEnabled,
    this.passwordUpdatedAt,
    this.lastSeen,
    this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? 'user',
      status: json['status'] as String? ?? 'ACTIVE',
      totpEnabled: json['totp_enabled'] == true || json['totp_enabled'] == 1,
      passwordUpdatedAt: json['password_updated_at'] != null 
          ? DateTime.parse(json['password_updated_at'] as String) 
          : null,
      lastSeen: json['last_seen'] != null 
          ? DateTime.parse(json['last_seen'] as String) 
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'email': email,
      'phone': phone,
      'role': role,
      'status': status,
      'totp_enabled': totpEnabled,
      'password_updated_at': passwordUpdatedAt?.toIso8601String(),
      'last_seen': lastSeen?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
