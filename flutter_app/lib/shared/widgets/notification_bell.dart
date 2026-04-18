import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/services/notification_service.dart';

/// Animated notification bell icon for the AppBar.
/// Shows a gradient badge with unread count.
/// Tap → opens the notification panel bottom sheet.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);

    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => _showNotificationSheet(context, ref),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_outlined,
            color: unread > 0 ? AppColors.accentOrange : AppColors.textSecondary,
            size: 24,
          ),
          if (unread > 0)
            Positioned(
              top: -4, right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  gradient:     AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(8),
                  border:       Border.all(color: AppColors.darkBg, width: 1.5),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   9,
                    fontWeight: FontWeight.w800,
                    height:     1,
                  ),
                ),
              ).animate(key: ValueKey(unread))
               .scale(begin: const Offset(0.5, 0.5), duration: 300.ms, curve: Curves.elasticOut)
               .fadeIn(duration: 150.ms),
            ),
        ],
      ),
    );
  }

  void _showNotificationSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder:            (_) => ProviderScope(parent: ref, child: const _NotificationPanel()),
    );
  }
}

// ── Notification Panel (bottom sheet) ────────────────────────────────────────
class _NotificationPanel extends ConsumerWidget {
  const _NotificationPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state    = ref.watch(notificationServiceProvider);
    final service  = ref.read(notificationServiceProvider.notifier);
    final notifs   = state.notifications;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize:     0.4,
      maxChildSize:     0.92,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color:        AppColors.darkSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
              child: Row(
                children: [
                  const Text('Notifications',
                    style: TextStyle(color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800, fontSize: 18)),
                  const Spacer(),
                  if (state.unreadCount > 0)
                    TextButton.icon(
                      onPressed: service.markAllRead,
                      icon:  const Icon(Icons.done_all_rounded,
                          color: AppColors.accentOrange, size: 16),
                      label: const Text('Mark all read',
                          style: TextStyle(color: AppColors.accentOrange,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.darkDivider),

            // ── Notification list ────────────────────────────────────────
            Expanded(
              child: state.loading && notifs.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accentOrange))
                  : notifs.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          color:    AppColors.accentOrange,
                          onRefresh: service.fetch,
                          child: ListView.builder(
                            controller: ctrl,
                            itemCount:  notifs.length,
                            itemBuilder: (_, i) => _NotifTile(
                              notif:   notifs[i],
                              onTap:   () {
                                service.markRead(notifs[i].id);
                                Navigator.pop(context);
                                if (notifs[i].actionUrl != null) {
                                  context.push(notifs[i].actionUrl!);
                                }
                              },
                            ).animate()
                             .fadeIn(delay: (i * 30).ms)
                             .slideX(begin: 0.05),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.notifications_none_rounded, size: 64, color: AppColors.textTertiary),
        const SizedBox(height: 12),
        const Text("You're all caught up!",
          style: TextStyle(color: AppColors.textSecondary,
              fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        const Text('New activity will appear here',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
      ],
    ),
  );
}

class _NotifTile extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback    onTap;
  const _NotifTile({required this.notif, required this.onTap});

  IconData get _icon => switch (notif.type) {
    'new_video'  => Icons.play_circle_fill_rounded,
    'comment'    => Icons.comment_rounded,
    'reply'      => Icons.reply_rounded,
    'like'       => Icons.thumb_up_rounded,
    'subscribe'  => Icons.person_add_rounded,
    _            => Icons.info_rounded,
  };

  Color get _color => switch (notif.type) {
    'new_video'  => AppColors.accentOrange,
    'comment'    => const Color(0xFF3498DB),
    'reply'      => const Color(0xFF9B59B6),
    'like'       => AppColors.accentPink,
    'subscribe'  => const Color(0xFF2ECC71),
    _            => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      color: notif.read ? Colors.transparent : AppColors.accentOrange.withOpacity(0.04),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon badge
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color:        _color.withOpacity(0.12),
              shape:        BoxShape.circle,
            ),
            child: Icon(_icon, color: _color, size: 20),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notif.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:      notif.read ? AppColors.textSecondary : AppColors.textPrimary,
                    fontWeight: notif.read ? FontWeight.normal : FontWeight.w600,
                    fontSize:   13,
                  ),
                ),
                if (notif.body != null) ...[
                  const SizedBox(height: 2),
                  Text(notif.body!,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                ],
                const SizedBox(height: 4),
                Text(timeago.format(notif.createdAt),
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),

          // Unread indicator dot
          if (!notif.read)
            Container(
              width: 8, height: 8, margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient, shape: BoxShape.circle),
            ),
        ],
      ),
    ),
  );
}
