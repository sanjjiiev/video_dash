import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool  _obscure      = true;
  bool  _agreedToTos  = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the Terms of Service')),
      );
      return;
    }
    await ref.read(authStateProvider.notifier)
        .register(_emailCtrl.text.trim(), _passCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider).value;
    final isLoading = authState?.isLoading ?? false;
    final error     = authState?.error;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkBg,
        leading: BackButton(color: AppColors.textPrimary,
            onPressed: () => context.go('/login')),
        title: const Text('Create account'),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Text('Join HUB 2.0',
                  style: Theme.of(context).textTheme.headlineMedium,
                ).animate().fadeIn().slideY(begin: 0.2),
                const SizedBox(height: 6),
                Text('Stream, upload, and discover amazing content.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ).animate().fadeIn(delay: 80.ms),
                const SizedBox(height: 32),

                if (error != null)
                  Container(
                    margin:  const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(error,
                          style: const TextStyle(color: AppColors.error, fontSize: 13))),
                    ]),
                  ).animate().shakeX(),

                // Email
                TextFormField(
                  controller:   _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.email_outlined, size: 20)),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    if (!v.contains('@'))        return 'Enter a valid email';
                    return null;
                  },
                ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.2),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller:  _passCtrl,
                  obscureText: _obscure,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (v.length < 8)           return 'At least 8 characters required';
                    return null;
                  },
                ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.2),
                const SizedBox(height: 16),

                // Confirm password
                TextFormField(
                  controller:     _confirmCtrl,
                  obscureText:    _obscure,
                  style:          const TextStyle(color: AppColors.textPrimary),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: Icon(Icons.lock_outline, size: 20),
                  ),
                  validator: (v) {
                    if (v != _passCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2),
                const SizedBox(height: 16),

                // Password strength indicator
                _PasswordStrength(password: _passCtrl.text),
                const SizedBox(height: 16),

                // ToS checkbox
                Row(
                  children: [
                    Checkbox(
                      value:        _agreedToTos,
                      onChanged:    (v) => setState(() => _agreedToTos = v ?? false),
                      activeColor:  AppColors.accentOrange,
                      side:         const BorderSide(color: AppColors.darkBorder),
                      shape:        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.bodySmall,
                          children: const [
                            TextSpan(text: 'I agree to the '),
                            TextSpan(text: 'Terms of Service',
                                style: TextStyle(color: AppColors.accentOrange,
                                    fontWeight: FontWeight.w600)),
                            TextSpan(text: ' and '),
                            TextSpan(text: 'Privacy Policy',
                                style: TextStyle(color: AppColors.accentOrange,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Sign up button
                SizedBox(
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient:     (!isLoading && _agreedToTos) ? AppColors.brandGradient : null,
                      color:        (!isLoading && _agreedToTos) ? null : AppColors.darkElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor:     Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: (isLoading || !_agreedToTos) ? null : _register,
                      child: isLoading
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Create Account',
                              style: TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Already have an account?',
                        style: Theme.of(context).textTheme.bodyMedium),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Sign in',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordStrength extends StatelessWidget {
  final String password;
  const _PasswordStrength({required this.password});

  int get _strength {
    if (password.isEmpty) return 0;
    int score = 0;
    if (password.length >= 8)               score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[!@#\$%^&*]'))) score++;
    return score;
  }

  Color get _color => switch (_strength) {
    1 => AppColors.error,
    2 => AppColors.warning,
    3 => Color(0xFF90EE90),
    4 => AppColors.success,
    _ => AppColors.darkBorder,
  };

  String get _label => switch (_strength) {
    1 => 'Weak',
    2 => 'Fair',
    3 => 'Good',
    4 => 'Strong',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) => Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
              decoration: BoxDecoration(
                color: i < _strength ? _color : AppColors.darkDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )),
        ),
        const SizedBox(height: 4),
        Text('Password strength: $_label',
          style: TextStyle(color: _color, fontSize: 11)),
      ],
    );
  }
}
