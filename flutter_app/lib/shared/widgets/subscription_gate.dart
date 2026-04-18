import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';

/// Subscription paywall widget displayed when a user tries to access
/// Pro or Premium gated content (API returns HTTP 402).
///
/// Shown as either:
///  - Full-screen replacement (on top of video area before stream loads)
///  - Bottom sheet overlay (tapping a locked feature mid-browsing)
class SubscriptionGate extends StatelessWidget {
  final String     requiredPlan;   // 'pro' | 'premium'
  final String     currentPlan;    // 'free' | 'pro'
  final String     reason;
  final bool       fullscreen;

  const SubscriptionGate({
    super.key,
    required this.requiredPlan,
    required this.currentPlan,
    required this.reason,
    this.fullscreen = false,
  });

  static const _plans = [
    _PlanCard(
      name:    'Free',
      price:   '\$0',
      period:  '',
      color:   AppColors.textSecondary,
      perks: ['480p streaming', '5 uploads/month', 'Basic analytics'],
    ),
    _PlanCard(
      name:    'Pro',
      price:   '\$4.99',
      period:  '/month',
      color:   AppColors.accentOrange,
      perks: ['1080p HD streaming', 'Unlimited uploads',
              'Advanced analytics', 'No ads', 'Offline downloads'],
      popular: true,
    ),
    _PlanCard(
      name:    'Premium',
      price:   '\$9.99',
      period:  '/month',
      color:   Color(0xFF9B59B6),
      perks: ['4K streaming', 'Unlimited uploads',
              'Real-time analytics', 'Custom domain',
              'Priority support', 'Exclusive features'],
    ),
  ];

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.darkBg,
      borderRadius: fullscreen ? null : const BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!fullscreen)
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: AppColors.darkBorder,
                  borderRadius: BorderRadius.circular(2))),

          // ── Lock icon ──────────────────────────────────────────────
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              gradient: requiredPlan == 'premium'
                  ? const LinearGradient(colors: [Color(0xFF9B59B6), Color(0xFF6C3483)])
                  : AppColors.brandGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_rounded, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),

          Text(
            requiredPlan == 'premium' ? 'Premium Content' : 'Pro Feature',
            style: const TextStyle(color: AppColors.textPrimary,
                fontWeight: FontWeight.w800, fontSize: 22),
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 28),

          // ── Plan cards ──────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _plans.map((plan) => _PlanCardWidget(
                plan:      plan,
                isCurrent: plan.name.toLowerCase() == currentPlan,
                isTarget:  plan.name.toLowerCase() == requiredPlan,
              )).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // ── CTA ─────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient:     AppColors.brandGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor:     Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _showUpgradeBottomSheet(context),
                icon:  const Icon(Icons.rocket_launch_rounded, color: Colors.white),
                label: Text(
                  'Upgrade to ${requiredPlan[0].toUpperCase()}${requiredPlan.substring(1)}',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Maybe later',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  void _showUpgradeBottomSheet(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment integration coming in Phase 5 (Stripe/RevenueCat)')),
    );
  }

  static void showAsSheet(BuildContext context, {
    required String requiredPlan,
    required String currentPlan,
    required String reason,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => SubscriptionGate(
        requiredPlan: requiredPlan,
        currentPlan:  currentPlan,
        reason:       reason,
      ),
    );
  }
}

class _PlanCard {
  final String       name;
  final String       price;
  final String       period;
  final Color        color;
  final List<String> perks;
  final bool         popular;
  const _PlanCard({
    required this.name, required this.price, required this.period,
    required this.color, required this.perks, this.popular = false,
  });
}

class _PlanCardWidget extends StatelessWidget {
  final _PlanCard plan;
  final bool      isCurrent;
  final bool      isTarget;
  const _PlanCardWidget({super.key, required this.plan,
      required this.isCurrent, required this.isTarget});

  @override
  Widget build(BuildContext context) => Container(
    width: 175,
    margin: const EdgeInsets.only(right: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        isTarget ? plan.color.withOpacity(0.08) : AppColors.darkCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isTarget ? plan.color : AppColors.darkBorder,
        width: isTarget ? 2 : 1,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.popular)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient:     AppColors.brandGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('POPULAR', style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
          ),

        Text(plan.name,
          style: TextStyle(color: plan.color, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(text: plan.price,
                style: const TextStyle(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800, fontSize: 22)),
              TextSpan(text: plan.period,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...plan.perks.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 14, color: plan.color),
              const SizedBox(width: 6),
              Expanded(child: Text(p,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))),
            ],
          ),
        )),
        const SizedBox(height: 4),
        if (isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:        AppColors.darkElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Current plan',
              style: TextStyle(color: AppColors.textSecondary,
                  fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ],
    ),
  );
}
