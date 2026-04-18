import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool  _obscure   = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authStateProvider.notifier)
        .login(_emailCtrl.text.trim(), _passCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider).value;
    final isLoading = authState?.isLoading ?? false;
    final error     = authState?.error;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),

                // ── Logo ────────────────────────────────────────────
                Center(
                  child: ShaderMask(
                    shaderCallback: (b) => AppColors.brandGradient.createShader(b),
                    child: const Text('HUB',
                      style: TextStyle(color: Colors.white, fontSize: 56,
                          fontWeight: FontWeight.w900, letterSpacing: -2)),
                  ),
                ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),

                const SizedBox(height: 8),

                Center(
                  child: Text('Stream anything, anywhere.',
                    style: Theme.of(context).textTheme.bodyMedium),
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 48),

                // ── TITLE ───────────────────────────────────────────
                Text('Welcome back',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.3),

                const SizedBox(height: 8),

                Text('Sign in to continue',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 150.ms),

                const SizedBox(height: 32),

                // ── Error banner ─────────────────────────────────────
                if (error != null)
                  Container(
                    margin:  const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:  AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(error,
                          style: const TextStyle(color: AppColors.error, fontSize: 13))),
                      ],
                    ),
                  ).animate().shakeX(),

                // ── Email ─────────────────────────────────────────────
                TextFormField(
                  controller:   _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText:  'Email',
                    prefixIcon: Icon(Icons.email_outlined, size: 20),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty)   return 'Email is required';
                    if (!v.contains('@'))          return 'Enter a valid email';
                    return null;
                  },
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2),

                const SizedBox(height: 16),

                // ── Password ─────────────────────────────────────────
                TextFormField(
                  controller:     _passCtrl,
                  obscureText:    _obscure,
                  style:          const TextStyle(color: AppColors.textPrimary),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText:  'Password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (v.length < 8)           return 'Must be at least 8 characters';
                    return null;
                  },
                ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.2),

                const SizedBox(height: 12),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {},
                    child: const Text('Forgot password?'),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Sign In button ────────────────────────────────────
                SizedBox(
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient:     isLoading ? null : AppColors.brandGradient,
                      color:        isLoading ? AppColors.darkElevated : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor:     Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isLoading ? null : _login,
                      child: isLoading
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Sign In',
                              style: TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3),

                const SizedBox(height: 24),

                // ── Divider ───────────────────────────────────────────
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.darkDivider)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    const Expanded(child: Divider(color: AppColors.darkDivider)),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Register link ─────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Don't have an account?",
                        style: Theme.of(context).textTheme.bodyMedium),
                    TextButton(
                      onPressed: () => context.go('/register'),
                      child: const Text('Create one',
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
