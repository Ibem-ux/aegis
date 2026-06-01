import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../../app/theme.dart';
import '../../../core/models/user_model.dart';
import '../../../core/secure_storage/secure_storage.dart';
import 'profile_providers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_endpoints.dart';
import '../../auth/presentation/auth_providers.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _storage = SecureStorage();
  final _formKey = GlobalKey<FormState>();
  
  bool _isEditing = false;
  bool _isLoading = false;
  bool _isAvatarUploading = false;
  String _currentDeviceId = '';
  
  // Controllers for Profile Edit
  late TextEditingController _displayNameController;
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _avatarUrlController;

  // Controllers for Password Change
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isPasswordObscured = true;
  bool _isNewPasswordObscured = true;
  bool _isConfirmPasswordObscured = true;
  bool _isPasswordExpanderOpen = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _fullNameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _avatarUrlController = TextEditingController();
    _loadCurrentDeviceId();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _avatarUrlController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentDeviceId() async {
    final devId = await _storage.getDeviceId();
    if (mounted) {
      setState(() {
        _currentDeviceId = devId ?? '';
      });
    }
  }

  void _populateFields(UserModel user) {
    _displayNameController.text = user.displayName ?? '';
    _fullNameController.text = user.fullName ?? '';
    _emailController.text = user.email ?? '';
    _phoneController.text = user.phone ?? '';
    _avatarUrlController.text = user.avatarUrl ?? '';
  }

  // Password complexity checks
  bool get _hasMinLength => _newPasswordController.text.length >= 8;
  bool get _hasUppercase => _newPasswordController.text.contains(RegExp(r'[A-Z]'));
  bool get _hasNumber => _newPasswordController.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecialChar => _newPasswordController.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
  bool get _isPasswordValid => _hasMinLength && _hasUppercase && _hasNumber && _hasSpecialChar;

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    try {
      final repository = ref.read(profileRepositoryProvider);
      await repository.updateProfile(
        displayName: _displayNameController.text.trim(),
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        avatarUrl: _avatarUrlController.text.trim(),
      );
      
      // Refresh current user info and exit editing mode
      ref.invalidate(currentUserProfileProvider);
      setState(() {
        _isEditing = false;
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AegisTheme.accentGreen,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: AegisTheme.errorRed,
          ),
        );
      }
    }
  }

  Future<void> _changePassword() async {
    if (!_isPasswordValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password does not meet complexity requirements.'),
          backgroundColor: AegisTheme.errorRed,
        ),
      );
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match.'),
          backgroundColor: AegisTheme.errorRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repository = ref.read(profileRepositoryProvider);
      await repository.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      
      // Clear password fields and close expander
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      
      setState(() {
        _isPasswordExpanderOpen = false;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully. Other active sessions revoked.'),
            backgroundColor: AegisTheme.accentGreen,
          ),
        );
      }
      ref.invalidate(activeSessionsProvider);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update password: $e'),
            backgroundColor: AegisTheme.errorRed,
          ),
        );
      }
    }
  }

  Future<void> _revokeDeviceSession(String sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Device Session?'),
        content: const Text('Are you sure you want to terminate this active device session? They will be signed out immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AegisTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AegisTheme.errorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final repository = ref.read(profileRepositoryProvider);
        await repository.revokeSession(sessionId);
        ref.invalidate(activeSessionsProvider);
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session revoked successfully'),
              backgroundColor: AegisTheme.accentGreen,
            ),
          );
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to revoke session: $e'),
              backgroundColor: AegisTheme.errorRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final XFile? imageFile = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (imageFile == null) return;

    setState(() => _isAvatarUploading = true);

    try {
      Uint8List bytes = await imageFile.readAsBytes();
      String filename = imageFile.name;
      String mimeType = imageFile.mimeType ?? _getMimeType(filename);
      
      const int maxOriginalSize = 2 * 1024 * 1024; // 2MB threshold
      if (bytes.length > maxOriginalSize) {
        final shouldCompress = await _showCompressionDialog(bytes.length);
        if (shouldCompress == null || !shouldCompress) {
          setState(() => _isAvatarUploading = false);
          return;
        }
        
        // Compress on background thread
        bytes = await compute(_compressImageBytes, bytes);
        filename = '${filename.split('.').first}_compressed.jpg';
        mimeType = 'image/jpeg';
      }

      final fileSize = bytes.length;

      // 1. Get pre-signed upload details from backend
      final apiClient = ref.read(apiClientProvider);
      final uploadResponse = await apiClient.dio.get<Map<String, dynamic>>(
        '/media/upload',
        queryParameters: {
          'filename': filename,
          'mime_type': mimeType,
          'file_size': fileSize,
        },
      );

      final uploadDetails = uploadResponse.data!;
      final uploadUrl = (uploadDetails['uploadUrl'] ?? uploadDetails['upload_url']) as String;
      final mediaId = (uploadDetails['mediaId'] ?? uploadDetails['media_id']) as String;

      // 2. Perform direct binary PUT request to upload the raw bytes
      final uploadResponseResult = await Dio().put<dynamic>(
        uploadUrl,
        data: bytes,
        options: Options(
          headers: {
            Headers.contentLengthHeader: fileSize,
            'Content-Type': mimeType,
          },
        ),
      );

      // 3. Construct public download URL from backend response or fallback
      final responseData = uploadResponseResult.data;
      final myUserId = await _storage.getUserId() ?? '';
      final extension = filename.contains('.') ? filename.split('.').last : 'jpg';
      final fallbackUrl = 'http://${ApiEndpoints.host}/uploads/$myUserId/$mediaId.$extension';
      
      String downloadUrl = fallbackUrl;
      if (responseData is Map<String, dynamic>) {
        downloadUrl = (responseData['downloadUrl'] ?? responseData['download_url'] ?? fallbackUrl) as String;
      }

      // 4. Update the user profile with the new avatar url
      final repository = ref.read(profileRepositoryProvider);
      await repository.updateProfile(avatarUrl: downloadUrl);

      // 5. Invalidate current profile provider to trigger rebuild
      ref.invalidate(currentUserProfileProvider);
      
      setState(() {
        _isAvatarUploading = false;
        _avatarUrlController.text = downloadUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Avatar uploaded successfully'),
            backgroundColor: AegisTheme.accentGreen,
          ),
        );
      }
    } catch (e) {
      setState(() => _isAvatarUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload avatar: $e'),
            backgroundColor: AegisTheme.errorRed,
          ),
        );
      }
    }
  }

  Future<void> _deleteAvatar() async {
    setState(() => _isAvatarUploading = true);
    try {
      final repository = ref.read(profileRepositoryProvider);
      await repository.updateProfile(avatarUrl: ''); // Clear avatar in DB
      
      ref.invalidate(currentUserProfileProvider);
      
      setState(() {
        _isAvatarUploading = false;
        _avatarUrlController.text = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Avatar removed successfully'),
            backgroundColor: AegisTheme.accentGreen,
          ),
        );
      }
    } catch (e) {
      setState(() => _isAvatarUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove avatar: $e'),
            backgroundColor: AegisTheme.errorRed,
          ),
        );
      }
    }
  }

  String _getMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    if (ext == 'png') return 'image/png';
    if (ext == 'gif') return 'image/gif';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }

  Future<bool?> _showCompressionDialog(int sizeInBytes) {
    final sizeMb = (sizeInBytes / (1024 * 1024)).toStringAsFixed(1);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: AegisTheme.darkBackground.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_size_select_large, size: 48, color: AegisTheme.accentCyan),
              const SizedBox(height: 16),
              const Text(
                'Large Image Detected',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AegisTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This image is $sizeMb MB, which exceeds our 2.0 MB limit for untouched originals.\n\nWould you like to compress it on your device to save space and upload it quickly, or cancel?',
                style: const TextStyle(color: AegisTheme.textSecondary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel', style: TextStyle(color: AegisTheme.textSecondary)),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.compress, size: 18),
                    label: const Text('Compress'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAvatarOptionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
          decoration: BoxDecoration(
            color: AegisTheme.darkBackground.withValues(alpha: 0.75),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white10),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'Profile Picture',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AegisTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AegisTheme.cardColor,
                    child: Icon(Icons.photo_library_outlined, color: AegisTheme.accentCyan),
                  ),
                  title: const Text('Upload Image File', style: TextStyle(color: AegisTheme.textPrimary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadAvatar();
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AegisTheme.cardColor,
                    child: Icon(Icons.link, color: AegisTheme.accentBlue),
                  ),
                  title: const Text('Set Image URL', style: TextStyle(color: AegisTheme.textPrimary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAvatarUrlDialog();
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AegisTheme.cardColor,
                    child: Icon(Icons.delete_outline, color: AegisTheme.errorRed),
                  ),
                  title: const Text('Remove Picture', style: TextStyle(color: AegisTheme.errorRed)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteAvatar();
                  },
                ),
              ],
            ),
          ),
        ),
        ),
        );
      },
    );
  }

  Future<void> _generateMasterRecoveryKey() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate Master Recovery Key?'),
        content: const Text('This will generate a new account recovery key. Any previous key will be immediately invalidated. Please keep it extremely safe.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AegisTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final repository = ref.read(profileRepositoryProvider);
        final key = await repository.generateMasterRecoveryKey();
        setState(() => _isLoading = false);
        
        if (mounted) {
          _showRecoveryKeyDialog(key);
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to generate key: $e'),
              backgroundColor: AegisTheme.errorRed,
            ),
          );
        }
      }
    }
  }

  void _showRecoveryKeyDialog(String key) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AegisTheme.accentCyan),
            SizedBox(width: 8),
            Text('Save Your Recovery Key'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Write down or securely copy this key. It is the ONLY way to regain access to your account if you forget your password. We store it securely hashed, meaning we CANNOT recover it for you.',
              style: TextStyle(color: AegisTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AegisTheme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AegisTheme.accentCyan.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      key,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AegisTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: AegisTheme.accentCyan),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: key));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Recovery key copied to clipboard')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('I Have Safely Saved It'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(currentUserProfileProvider);
    final sessionsState = ref.watch(activeSessionsProvider);

    return Scaffold(
      body: Container(
        decoration: AegisTheme.backgroundGradient,
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: AegisTheme.textPrimary),
                      onPressed: () => context.pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'Secure Profile Dashboard',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AegisTheme.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48), // Balancing back button
                  ],
                ),
              ),
              
              Expanded(
                child: profileState.when(
                  data: (user) {
                    // Populate text fields once
                    if (!_isEditing && _displayNameController.text.isEmpty && _fullNameController.text.isEmpty) {
                      _populateFields(user);
                    }
                    
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          _buildProfileCard(user),
                          const SizedBox(height: 20),
                          _buildSecuritySection(),
                          const SizedBox(height: 20),
                          _buildSessionsSection(sessionsState),
                          const SizedBox(height: 32),
                        ],
                      ),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AegisTheme.errorRed),
                        const SizedBox(height: 16),
                        Text('Error loading profile: $err'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => ref.refresh(currentUserProfileProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(UserModel user) {
    final String initial = (user.displayName ?? user.username).substring(0, 1).toUpperCase();
    
    return Card(
      elevation: 4,
      shadowColor: Colors.black26,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Avatar with glowing neon borders
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AegisTheme.accentCyan, AegisTheme.accentBlue],
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: AegisTheme.darkBackground,
                        backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty && !_isAvatarUploading
                            ? CachedNetworkImageProvider(user.avatarUrl!)
                            : null,
                        child: _isAvatarUploading
                            ? const CircularProgressIndicator(color: AegisTheme.accentCyan)
                            : (user.avatarUrl == null || user.avatarUrl!.isEmpty
                                ? Text(
                                    initial,
                                    style: const TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.bold,
                                      color: AegisTheme.accentCyan,
                                    ),
                                  )
                                : null),
                      ),
                    ),
                    if (_isEditing && !_isAvatarUploading)
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AegisTheme.accentBlue,
                        child: IconButton(
                          icon: const Icon(Icons.edit, size: 16, color: Colors.white),
                          onPressed: _showAvatarOptionsSheet,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              if (!_isEditing) ...[
                Text(
                  user.displayName ?? user.username,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AegisTheme.textPrimary),
                ),
                Text(
                  '@${user.username}',
                  style: const TextStyle(color: AegisTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 24),
                _buildReadOnlyField(Icons.badge_outlined, 'Full Name', user.fullName ?? 'Not Set'),
                _buildReadOnlyField(Icons.email_outlined, 'Email Address', user.email ?? 'Not Set'),
                _buildReadOnlyField(Icons.phone_android_outlined, 'Phone Number', user.phone ?? 'Not Set'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AegisTheme.accentCyan,
                      side: const BorderSide(color: AegisTheme.accentCyan, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Profile Details', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => setState(() => _isEditing = true),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                _buildEditField(
                  controller: _displayNameController,
                  icon: Icons.person_outline,
                  label: 'Display Name',
                  hint: 'Choose a nickname',
                  validator: (val) => val == null || val.trim().isEmpty ? 'Display name is required' : null,
                ),
                const SizedBox(height: 12),
                _buildEditField(
                  controller: _fullNameController,
                  icon: Icons.badge_outlined,
                  label: 'Full Name',
                  hint: 'Enter your full name',
                ),
                const SizedBox(height: 12),
                _buildEditField(
                  controller: _emailController,
                  icon: Icons.email_outlined,
                  label: 'Email',
                  hint: 'name@example.com',
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return null;
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    return emailRegex.hasMatch(val.trim()) ? null : 'Please enter a valid email address';
                  },
                ),
                const SizedBox(height: 12),
                _buildEditField(
                  controller: _phoneController,
                  icon: Icons.phone_android_outlined,
                  label: 'Phone Number',
                  hint: '+1234567890',
                ),
                const SizedBox(height: 24),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AegisTheme.textSecondary,
                            side: const BorderSide(color: AegisTheme.cardColor),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            setState(() => _isEditing = false);
                            _populateFields(user);
                          },
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AegisTheme.accentBlue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _saveProfile,
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AegisTheme.accentCyan),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AegisTheme.textSecondary, fontSize: 11)),
              Text(value, style: const TextStyle(color: AegisTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: AegisTheme.accentCyan),
        labelText: label,
        hintText: hint,
      ),
    );
  }

  void _showAvatarUrlDialog() {
    final tempController = TextEditingController(text: _avatarUrlController.text);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Avatar URL'),
        content: TextField(
          controller: tempController,
          decoration: const InputDecoration(
            hintText: 'https://example.com/avatar.jpg',
            labelText: 'Avatar Image URL',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AegisTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _avatarUrlController.text = tempController.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection() {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.shield_outlined, color: AegisTheme.accentCyan),
                SizedBox(width: 8),
                Text(
                  'Security & Keys',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AegisTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Expandable Change Password
            ExpansionPanelList(
              elevation: 0,
              expandedHeaderPadding: EdgeInsets.zero,
              expansionCallback: (index, isExpanded) {
                setState(() {
                  _isPasswordExpanderOpen = isExpanded;
                });
              },
              children: [
                ExpansionPanel(
                  backgroundColor: Colors.transparent,
                  headerBuilder: (ctx, isExpanded) => const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.password, color: AegisTheme.accentBlue),
                    title: Text('Change Password'),
                    subtitle: Text('Manage password complexity history'),
                  ),
                  body: Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _currentPasswordController,
                          obscureText: _isPasswordObscured,
                          decoration: InputDecoration(
                            labelText: 'Current Password',
                            prefixIcon: const Icon(Icons.lock_outline, color: AegisTheme.textSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(_isPasswordObscured ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _isPasswordObscured = !_isPasswordObscured),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: _isNewPasswordObscured,
                          onChanged: (_) => setState(() {}), // Trigger checklist refresh
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            prefixIcon: const Icon(Icons.lock_outline, color: AegisTheme.textSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(_isNewPasswordObscured ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _isNewPasswordObscured = !_isNewPasswordObscured),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _isConfirmPasswordObscured,
                          decoration: InputDecoration(
                            labelText: 'Confirm New Password',
                            prefixIcon: const Icon(Icons.lock_outline, color: AegisTheme.textSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(_isConfirmPasswordObscured ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _isConfirmPasswordObscured = !_isConfirmPasswordObscured),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Password Checklist UI
                        const Text('Complexity Requirements:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AegisTheme.textSecondary)),
                        const SizedBox(height: 8),
                        _buildCheckItem('At least 8 characters long', _hasMinLength),
                        _buildCheckItem('Contains an uppercase letter', _hasUppercase),
                        _buildCheckItem('Contains a number', _hasNumber),
                        _buildCheckItem('Contains a special character (!@#\$%^&...)', _hasSpecialChar),
                        
                        const SizedBox(height: 20),
                        if (_isLoading)
                          const Center(child: CircularProgressIndicator())
                        else
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isPasswordValid ? _changePassword : null,
                              child: const Text('Update Password'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  isExpanded: _isPasswordExpanderOpen,
                ),
              ],
            ),
            
            const Divider(color: Colors.white10, height: 24),
            
            // Master Recovery Key Generator Row
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key, color: AegisTheme.accentGreen),
              title: const Text('Master Recovery Key'),
              subtitle: const Text('Regain account access in emergency self-service'),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AegisTheme.accentCyan,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                onPressed: _generateMasterRecoveryKey,
                child: const Text('Generate'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckItem(String label, bool isMet) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 16,
            color: isMet ? AegisTheme.accentGreen : AegisTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isMet ? AegisTheme.accentGreen : AegisTheme.textSecondary,
              decoration: isMet ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsSection(AsyncValue<List<Map<String, dynamic>>> sessionsState) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.devices_outlined, color: AegisTheme.accentCyan),
                SizedBox(width: 8),
                Text(
                  'Active Device Sessions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AegisTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            sessionsState.when(
              data: (sessions) {
                if (sessions.isEmpty) {
                  return const Text('No active device sessions recorded.', style: TextStyle(color: AegisTheme.textSecondary));
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 16),
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final sessionId = session['session_id'] as String;
                    final devId = session['device_id'] as String;
                    final userAgent = session['user_agent'] as String? ?? 'Unknown agent';
                    final ip = session['ip_address'] as String? ?? 'Unknown IP';
                    final lastActiveRaw = session['last_active'] as String?;
                    final isCurrentDevice = devId == _currentDeviceId;

                    // Choose device icon
                    IconData deviceIcon = Icons.devices;
                    final String ua = userAgent.toLowerCase();
                    if (ua.contains('windows') || ua.contains('macintosh') || ua.contains('linux')) {
                      deviceIcon = Icons.computer;
                    } else if (ua.contains('iphone') || ua.contains('android')) {
                      deviceIcon = Icons.phone_android;
                    }

                    // Format date
                    String lastActiveStr = 'Unknown';
                    if (lastActiveRaw != null) {
                      try {
                        final dt = DateTime.parse(lastActiveRaw).toLocal();
                        lastActiveStr = DateFormat('yyyy-MM-dd HH:mm').format(dt);
                      } catch (_) {}
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AegisTheme.cardColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCurrentDevice ? AegisTheme.accentCyan.withValues(alpha: 0.3) : Colors.transparent,
                            ),
                          ),
                          child: Icon(deviceIcon, color: isCurrentDevice ? AegisTheme.accentCyan : AegisTheme.textSecondary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      session['device_name'] as String? ?? userAgent,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isCurrentDevice)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AegisTheme.accentCyan.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'This Device',
                                        style: TextStyle(
                                          color: AegisTheme.accentCyan,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('IP: $ip', style: const TextStyle(color: AegisTheme.textSecondary, fontSize: 12)),
                              Text('Last Active: $lastActiveStr', style: const TextStyle(color: AegisTheme.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                        if (!isCurrentDevice)
                          IconButton(
                            icon: const Icon(Icons.logout, color: AegisTheme.errorRed, size: 20),
                            onPressed: () => _revokeDeviceSession(sessionId),
                            tooltip: 'Revoke device authorization',
                          ),
                      ],
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Could not load sessions: $err', style: const TextStyle(color: AegisTheme.errorRed)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compresses image bytes using native flutter_image_compress on mobile,
/// falling back to the pure-Dart `image` package on web where native
/// codecs are unavailable.
Future<Uint8List> _compressImageBytes(Uint8List originalBytes) async {
  if (kIsWeb) {
    // Pure-Dart fallback for web
    final image = img.decodeImage(originalBytes);
    if (image == null) return originalBytes;
    final img.Image resized;
    if (image.width > 1024) {
      resized = img.copyResize(image, width: 1024);
    } else {
      resized = image;
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  // Native platform — use flutter_image_compress for high-speed WebP/JPEG encoding
  final result = await FlutterImageCompress.compressWithList(
    originalBytes,
    minWidth: 1024,
    minHeight: 1024,
    quality: 82,
    format: CompressFormat.jpeg,
  );
  return result;
}
