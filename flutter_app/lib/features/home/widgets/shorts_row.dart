import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

/// Horizontal row of Shorts-style circular preview cards.
/// Displayed at the top of the home feed, just like YouTube Shorts.
class ShortsRow extends StatelessWidget {
  const ShortsRow({super.key});

  // Placeholder data until Phase 4 wires up real Shorts
  static const _placeholders = [
    ('Tech Tips', '2.1M', AppColors.accentOrange),
    ('Gaming', '890K',   AppColors.accentPink),
    ('Music Mix', '1.4M', Color(0xFF3498DB)),
    ('Sports', '340K',   Color(0xFF2ECC71)),
    ('Comedy', '5.2M',   Color(0xFF9B59B6)),
    ('Science', '670K',  Color(0xFFF39C12)),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Shorts',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800,
                    fontSize: 12, letterSpacing: 0.5)),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.bolt_rounded, color: AppColors.accentOrange, size: 16),
          ],
        ),
      ),
      SizedBox(
        height: 130,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _placeholders.length,
          itemBuilder: (_, i) {
            final (title, views, color) = _placeholders[i];
            return GestureDetector(
              onTap: () => context.push('/shorts'),
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  children: [
                    Container(
                      width: 72, height: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end:   Alignment.bottomRight,
                          colors: [color.withOpacity(0.7), color.withOpacity(0.3)],
                        ),
                        border: Border.all(color: color.withOpacity(0.4)),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white.withOpacity(0.9), size: 28),
                          Positioned(
                            bottom: 4, left: 0, right: 0,
                            child: Text(views,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 72,
                      child: Text(title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary,
                            fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}
