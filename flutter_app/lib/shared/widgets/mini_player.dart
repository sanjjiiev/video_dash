import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/constants/app_colors.dart';
import '../../core/providers/player_provider.dart';

/// Persistent mini-player strip rendered at the very bottom of MainShell,
/// just above the bottom navigation bar, when the user navigates away from
/// a playing video — exactly like YouTube's mini player.
///
/// Tap → expand back to full PlayerScreen
/// Swipe down → dismiss
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  static const double _height = 68.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state  = ref.watch(globalPlayerProvider);
    final notifier = ref.read(globalPlayerProvider.notifier);

    if (!state.isVisible || !state.hasVideo) return const SizedBox.shrink();

    final progress = state.duration.inMilliseconds > 0
        ? state.position.inMilliseconds / state.duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTap:          () => context.push('/video/${state.videoId}'),
      onVerticalDragEnd: (d) {
        if (d.primaryVelocity != null && d.primaryVelocity! > 200) {
          notifier.dismiss();
        }
      },
      child: Container(
        height: _height,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color:        AppColors.darkCard,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: AppColors.darkBorder),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, -2)),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // ── Progress bar at top ──────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(
                value:            progress.clamp(0.0, 1.0),
                backgroundColor:  Colors.transparent,
                valueColor:       const AlwaysStoppedAnimation(AppColors.accentOrange),
                minHeight:        2,
              ),
            ),

            // ── Content row ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
              child: Row(
                children: [
                  // Thumbnail / animated icon
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color:        AppColors.darkElevated,
                      borderRadius: BorderRadius.circular(6),
                      gradient: state.isPlaying ? AppColors.brandGradient : null,
                    ),
                    child: state.isPlaying
                        ? const _PulsingPlay()
                        : const Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white70, size: 24),
                  ),
                  const SizedBox(width: 10),

                  // Title + channel
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment:  MainAxisAlignment.center,
                      children: [
                        Text(
                          state.videoTitle ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color:      AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize:   13,
                          ),
                        ),
                        if (state.channelName != null)
                          Text(
                            state.channelName!,
                            style: const TextStyle(
                              color:   AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Play / Pause
                  IconButton(
                    onPressed: ref.read(globalPlayerProvider.notifier).toggle,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key:   ValueKey(state.isPlaying),
                        color: Colors.white,
                        size:  28,
                      ),
                    ),
                  ),

                  // Next (stub)
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white60, size: 22),
                  ),

                  // Close
                  IconButton(
                    onPressed: ref.read(globalPlayerProvider.notifier).dismiss,
                    icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .slideY(begin: 1, duration: 250.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 200.ms);
  }
}

/// Animated pulsing play icon for the mini player thumbnail.
class _PulsingPlay extends StatefulWidget {
  const _PulsingPlay();

  @override
  State<_PulsingPlay> createState() => _PulsingPlayState();
}

class _PulsingPlayState extends State<_PulsingPlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.5, end: 1.0).animate(_ctrl),
    child: const Icon(Icons.equalizer_rounded, color: Colors.white, size: 24),
  );
}
