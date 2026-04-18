import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

// ── Notification Model ────────────────────────────────────────────────────────
class AppNotification {
  final String id;
  final String type; // 'new_video' | 'comment' | 'reply' | 'like' | 'system'
  final String title;
  final String? body;
  final String? imageUrl;
  final String? actionUrl;
  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.imageUrl,
    this.actionUrl,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'system',
        title: j['title'] as String? ?? '',
        body: j['body'] as String?,
        imageUrl: j['image_url'] as String?,
        actionUrl: j['action_url'] as String?,
        read: j['read'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        imageUrl: imageUrl,
        actionUrl: actionUrl,
        read: read ?? this.read,
        createdAt: createdAt,
      );
}

// ── Notification State ────────────────────────────────────────────────────────
class NotificationState {
  final List<AppNotification> notifications;
  final bool loading;
  final int unreadCount;

  const NotificationState({
    this.notifications = const [],
    this.loading = false,
    this.unreadCount = 0,
  });

  NotificationState copyWith({
    List<AppNotification>? notifications,
    bool? loading,
    int? unreadCount,
  }) =>
      NotificationState(
        notifications: notifications ?? this.notifications,
        loading: loading ?? this.loading,
        unreadCount: unreadCount ?? this.unreadCount,
      );
}

// ── Notification Service (StateNotifier) ─────────────────────────────────────
class NotificationService extends StateNotifier<NotificationState> {
  final ApiClient _api;
  Timer? _pollTimer;
  static const _pollInterval = Duration(minutes: 1);

  NotificationService(this._api) : super(const NotificationState()) {
    _init();
  }

  Future<void> _init() async {
    await fetch();
    // Poll every minute for now; replace with FCM push in Phase 5
    _pollTimer = Timer.periodic(_pollInterval, (_) => fetch());
  }

  /// Fetch notifications from API and merge with local state
  Future<void> fetch() async {
    if (!_api.isLoggedIn) return;
    try {
      state = state.copyWith(loading: true);
      final data = await _api.getNotifications();

      if (!mounted) return; // Protect against state updates if disposed

      final notifs = data
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      final unread = notifs.where((n) => !n.read).length;
      state = state.copyWith(
        notifications: notifs,
        loading: false,
        unreadCount: unread,
      );
    } catch (e) {
      debugPrint('[Notifications] fetch error: $e');
      if (!mounted) return;
      state = state.copyWith(loading: false);
    }
  }

  /// Mark a single notification as read (optimistic + API)
  void markRead(String notifId) {
    // Prevent decrementing count if it's already read
    final isUnread = state.notifications.any((n) => n.id == notifId && !n.read);
    if (!isUnread) return;

    state = state.copyWith(
      notifications: state.notifications
          .map((n) => n.id == notifId ? n.copyWith(read: true) : n)
          .toList(),
      unreadCount: (state.unreadCount - 1).clamp(0, state.notifications.length),
    );
    _api.markNotificationRead(notifId).catchError((Object error) {});
  }

  /// Mark all as read
  void markAllRead() {
    state = state.copyWith(
      notifications:
          state.notifications.map((n) => n.copyWith(read: true)).toList(),
      unreadCount: 0,
    );
    _api.markAllNotificationsRead().catchError((Object error) {});
  }

  /// Register device FCM push token with the backend
  Future<void> registerPushToken(String token, String platform) async {
    try {
      await _api.registerPushToken(token: token, platform: platform);
    } catch (e) {
      debugPrint('[Notifications] push token registration failed: $e');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final notificationServiceProvider =
    StateNotifierProvider<NotificationService, NotificationState>(
  (ref) => NotificationService(ref.watch(apiClientProvider)),
);

// Convenience unread-count provider for the badge
final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationServiceProvider).unreadCount;
});
