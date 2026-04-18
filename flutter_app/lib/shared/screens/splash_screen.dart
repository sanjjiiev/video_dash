import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';

/// Animated splash screen shown on cold start while auth state resolves.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.darkBg,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gradient HUB logo
          ShaderMask(
            shaderCallback: (b) => AppColors.brandGradient.createShader(b),
            child: const Text(
              'HUB',
              style: TextStyle(
                color:       Colors.white,
                fontSize:    72,
                fontWeight:  FontWeight.w900,
                letterSpacing: -3,
              ),
            ),
          )
              .animate()
              .scale(duration: 700.ms, curve: Curves.elasticOut, begin: const Offset(0.5, 0.5))
              .fadeIn(duration: 400.ms),

          const SizedBox(height: 8),

          const Text(
            '2.0',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 16,
                fontWeight: FontWeight.w300, letterSpacing: 6),
          )
              .animate()
              .fadeIn(delay: 300.ms, duration: 400.ms)
              .slideY(begin: 0.5),

          const SizedBox(height: 60),

          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(AppColors.accentOrange.withOpacity(0.7)),
            ),
          ).animate().fadeIn(delay: 600.ms),

          const SizedBox(height: 16),

          const Text(
            'Stream anything, anywhere.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12,
                letterSpacing: 0.5),
          ).animate().fadeIn(delay: 700.ms),
        ],
      ),
    ),
  );
}
