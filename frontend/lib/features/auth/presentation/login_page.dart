import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'auth_providers.dart';
import '../data/auth_repository.dart';
import '../../../app/theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  
  bool _isLoading = false;
  bool _isOtpMode = false;
  bool _otpSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(authRepositoryProvider);
      final result = await repository.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        switch (result.status) {
          case LoginStatus.success:
            context.go('/home');
            break;
          case LoginStatus.requires2FA:
            context.go('/totp-verify?tempToken=${result.tempToken}');
            break;
          case LoginStatus.requiresDeviceTrust:
            context.go('/device-verify?deviceId=${result.untrustedDeviceId}');
            break;
        }
      }
    } catch (e) {
      String message;
      if (e is DioException) {
        switch (e.response?.statusCode) {
          case 401:
            message = 'Invalid username or password';
            break;
          case 400:
            final data = e.response?.data;
            message = 'Validation error: ${data is Map ? data['message'] : 'Bad request'}';
            break;
          case 403:
            final data = e.response?.data;
            message = 'Access denied: ${data is Map ? data['message'] : 'Forbidden'}';
            break;
          case 500:
            message = 'Server error — please check backend logs';
            break;
          default:
            if (e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout) {
              message = 'Connection timed out — is the server running?';
            } else if (e.type == DioExceptionType.connectionError) {
              message = 'Cannot connect to server. Verify backend is running on port 3000.';
            } else {
              message = 'Network error: ${e.message}';
            }
        }
      } else {
        message = 'Unexpected error: ${e.toString()}';
      }
      setState(() {
        _errorMessage = message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleOtpSend() async {
    final email = _usernameController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(authRepositoryProvider);
      await repository.sendOtp(email: email);
      setState(() {
        _otpSent = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification code sent to your email!')),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to send verification code';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleOtpVerify() async {
    final email = _usernameController.text.trim();
    final code = _otpController.text.trim();
    if (code.length < 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(authRepositoryProvider);
      await repository.verifyOtp(email: email, code: code);
      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Invalid or expired verification code';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AegisTheme.backgroundGradient,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 64,
                      color: AegisTheme.accentCyan,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Sign In to Aegis',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isOtpMode 
                          ? 'Passwordless access via email verification.'
                          : 'Enter credentials to unlock secure session.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AegisTheme.textSecondary),
                    ),
                    const SizedBox(height: 32),
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AegisTheme.errorRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AegisTheme.errorRed.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AegisTheme.errorRed, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // Username / Email input
                    TextFormField(
                      controller: _usernameController,
                      keyboardType: _isOtpMode ? TextInputType.emailAddress : TextInputType.name,
                      textInputAction: TextInputAction.next,
                      enabled: !_otpSent,
                      decoration: InputDecoration(
                        labelText: _isOtpMode ? 'Email Address' : 'Username',
                        prefixIcon: Icon(
                          _isOtpMode ? Icons.email_outlined : Icons.person_outline, 
                          color: AegisTheme.textSecondary
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return _isOtpMode ? 'Please enter your email' : 'Please enter your username';
                        }
                        if (_isOtpMode && !value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password input (Credential mode only)
                    if (!_isOtpMode)
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline, color: AegisTheme.textSecondary),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _handleLogin(),
                      ),

                    // OTP input (Passwordless mode only when sent)
                    if (_isOtpMode && _otpSent)
                      TextFormField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: '6-Digit Verification Code',
                          prefixIcon: Icon(Icons.password_outlined, color: AegisTheme.textSecondary),
                          counterText: '',
                        ),
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return 'Please enter the 6-digit code';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _handleOtpVerify(),
                      ),
                    
                    const SizedBox(height: 24),

                    // Actions buttons
                    ElevatedButton(
                      onPressed: _isLoading 
                          ? null 
                          : (_isOtpMode 
                              ? (_otpSent ? _handleOtpVerify : _handleOtpSend)
                              : _handleLogin),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(_isOtpMode 
                              ? (_otpSent ? 'Verify & Connect' : 'Send Code') 
                              : 'Sign In'),
                    ),
                    const SizedBox(height: 16),

                    // Mode toggle
                    TextButton(
                      onPressed: _isLoading ? null : () {
                        setState(() {
                          _isOtpMode = !_isOtpMode;
                          _otpSent = false;
                          _errorMessage = null;
                          _passwordController.clear();
                          _otpController.clear();
                        });
                      },
                      child: Text(
                        _isOtpMode 
                            ? 'Switch to Password Login' 
                            : 'Use Passwordless Email Access',
                        style: const TextStyle(color: AegisTheme.accentCyan, fontWeight: FontWeight.bold),
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        context.push('/register');
                      },
                      child: RichText(
                        text: const TextSpan(
                          text: 'Have an invitation? ',
                          style: TextStyle(color: AegisTheme.textSecondary),
                          children: [
                            TextSpan(
                              text: 'Claim Invite',
                              style: TextStyle(color: AegisTheme.accentCyan, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
