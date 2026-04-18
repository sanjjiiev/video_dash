import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/models/video_model.dart';
import '../../home/widgets/video_card.dart';


class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(videoFeedProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor:  AppColors.darkBg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Subscriptions'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.accentOrange,
          labelColor: AppColors.accentOrange,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [Tab(text: 'Feed'), Tab(text: 'Channels')],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // ── Subscription feed ──────────────────────────────────────
          feedState.isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accentOrange))
              : feedState.videos.isEmpty
                  ? _buildEmptyFeed()
                  : RefreshIndicator(
                      color: AppColors.accentOrange,
                      onRefresh: () => ref.read(videoFeedProvider.notifier).refresh(),
                      child: ListView.builder(
                        itemCount: feedState.videos.length,
                        itemBuilder: (_, i) => VideoCard(video: feedState.videos[i])
                            .animate()
                            .fadeIn(delay: (i * 40).ms)
                            .slideY(begin: 0.05),
                      ),
                    ),

          // ── Channels list ──────────────────────────────────────────
          _buildChannelsList(),
        ],
      ),
    );
  }

  Widget _buildEmptyFeed() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            shape:    BoxShape.circle,
          ),
          child: const Icon(Icons.subscriptions_outlined, color: Colors.white, size: 36),
        ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
        const SizedBox(height: 20),
        const Text("You haven't subscribed to any channels yet",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary,
              fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        const Text('Go to any channel page and hit Subscribe',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
      ],
    ),
  );

  Widget _buildChannelsList() {
    final subsAsync = ref.watch(subscriptionsProvider);
    return subsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accentOrange)),
      error:   (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(e.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () =>
                  ref.read(subscriptionsProvider.notifier).load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (subs) => subs.isEmpty
          ? _buildEmptyFeed()
          : RefreshIndicator(
              color: AppColors.accentOrange,
              onRefresh: () =>
                  ref.read(subscriptionsProvider.notifier).load(),
              child: ListView.builder(
                padding:   const EdgeInsets.all(12),
                itemCount: subs.length,
                itemBuilder: (_, i) => _ChannelTile(
                  channel:     subs[i],
                  onUnsubscribe: () => ref
                      .read(subscriptionsProvider.notifier)
                      .unsubscribe(subs[i].channelId),
                  onToggleNotify: (v) => ref
                      .read(subscriptionsProvider.notifier)
                      .toggleNotify(subs[i].channelId, notifyNew: v),
                ).animate().fadeIn(delay: (i * 60).ms).slideX(begin: 0.05),
              ),
            ),
    );
  }
} // end _SubscriptionsScreenState

class _ChannelTile extends StatefulWidget {
  final SubscriptionModel  channel;
  final VoidCallback       onUnsubscribe;
  final ValueChanged<bool> onToggleNotify;

  const _ChannelTile({
    super.key,
    required this.channel,
    required this.onUnsubscribe,
    required this.onToggleNotify,
  });

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  late bool _notifyOn;

  @override
  void initState() {
    super.initState();
    _notifyOn = widget.channel.notifyNew;
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Color get _avatarColor {
    final colors = AppColors.avatarColors;
    return colors[widget.channel.channelName.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) => Container(
    margin:  const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color:        AppColors.darkCard,
      borderRadius: BorderRadius.circular(14),
      border:       Border.all(color: AppColors.darkBorder),
    ),
    child: Row(
      children: [
        // Avatar with new-content dot
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color:  _avatarColor.withOpacity(0.2),
                shape:  BoxShape.circle,
                border: Border.all(color: _avatarColor.withOpacity(0.5), width: 2),
              ),
              child: Center(
                child: Text(
                  widget.channel.channelName.isNotEmpty
                      ? widget.channel.channelName[0].toUpperCase()
                      : '?',
                  style: TextStyle(color: _avatarColor,
                      fontWeight: FontWeight.w800, fontSize: 20)),
              ),
            ),
            if (widget.channel.hasNewContent)
              Positioned(
                top: -2, right: -2,
                child: Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    shape:    BoxShape.circle,
                    border:   Border.all(color: AppColors.darkBg, width: 2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),

        // Name + subs
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.channel.channelName,
                style: const TextStyle(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700, fontSize: 14)),
              Text('${_fmt(widget.channel.subscriberCount)} subscribers',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),

        // Notification bell toggle
        GestureDetector(
          onTap: () {
            setState(() => _notifyOn = !_notifyOn);
            widget.onToggleNotify(_notifyOn);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color:        AppColors.darkElevated,
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: AppColors.darkBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _notifyOn
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_outlined,
                  color: _notifyOn ? AppColors.accentOrange : AppColors.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(_notifyOn ? 'All' : 'Off',
                  style: TextStyle(
                    color:      _notifyOn ? AppColors.accentOrange : AppColors.textSecondary,
                    fontSize:   11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Unsubscribe
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textTertiary,
            padding:   const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
          ),
          onPressed: () => _showUnsubscribeDialog(context),
          child: const Text('Unsubscribe', style: TextStyle(fontSize: 11)),
        ),
      ],
    ),
  );

  void _showUnsubscribeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: Text('Unsubscribe from ${widget.channel.channelName}?',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onUnsubscribe();
            },
            child: const Text('Unsubscribe', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
