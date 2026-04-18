import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/models/video_model.dart';
import '../../home/widgets/video_card.dart';


class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider).value;
    final user = auth?.user;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 220,
            pinned:         true,
            backgroundColor: AppColors.darkBg,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                children: [
                  // Banner gradient
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end:   Alignment.bottomRight,
                        colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
                      ),
                    ),
                  ),
                  // Avatar + name
                  Positioned(
                    bottom: 50, left: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.brandGradient,
                            border: Border.all(color: AppColors.darkBg, width: 3),
                          ),
                          child: Center(
                            child: Text(
                              (user?.displayName ?? 'U')[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.w800, fontSize: 30),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(user?.displayName ?? 'Anonymous',
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w700, fontSize: 20)),
                        const SizedBox(height: 2),
                        Text(user?.email ?? '',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
                onPressed: () => _showSettingsSheet(context),
              ),
            ],
          ),

          // Stats row
          SliverToBoxAdapter(
            child: Builder(builder: (context) {
              final overviewAsync = ref.watch(analyticsOverviewProvider);
              final ov = overviewAsync.valueOrNull;
              final videosAsync = user == null
                  ? null
                  : ref.watch(channelVideosProvider(user.id));
              final videoCount = videosAsync?.valueOrNull?.length ?? 0;

              return Container(
                color: AppColors.darkSurface,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatItem(
                        value: ov == null ? '0' : '$videoCount',
                        label: 'Videos'),
                    _Divider(),
                    _StatItem(
                        value: ov == null ? '0'
                            : _fmt(ov.subscriberCount),
                        label: 'Subscribers'),
                    _Divider(),
                    _StatItem(
                        value: ov == null ? '0'
                            : _fmt(ov.totalViews),
                        label: 'Views'),
                    _Divider(),
                    _StatItem(
                        value: ov == null ? '0'
                            : _fmt(ov.totalLikes),
                        label: 'Likes'),
                  ],
                ),
              );
            }),
          ),


          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabCtrl,
                isScrollable: false,
                indicatorColor: AppColors.accentOrange,
                indicatorWeight: 2,
                labelColor: AppColors.accentOrange,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: const [
                  Tab(text: 'Videos'),
                  Tab(text: 'Playlists'),
                  Tab(text: 'History'),
                  Tab(text: 'Saved'),
                ],
              ),
            ),
          ),
        ],

        body: TabBarView(
          controller: _tabCtrl,
          children: [
            // ── Videos tab: real channel videos ──────────────────────
            if (user == null)
              const _EmptyTab(
                icon: Icons.videocam_outlined,
                label: 'No videos yet',
                sub: 'Upload your first video to get started')
            else
              Consumer(builder: (context, ref, _) {
                final videosAsync = ref.watch(channelVideosProvider(user.id));
                return videosAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentOrange)),
                  error: (_, __) => const _EmptyTab(
                    icon: Icons.videocam_outlined,
                    label: 'Could not load videos',
                    sub: 'Pull to refresh'),
                  data: (videos) => videos.isEmpty
                      ? const _EmptyTab(
                          icon: Icons.videocam_outlined,
                          label: 'No videos yet',
                          sub: 'Upload your first video to get started')
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: videos.length,
                          itemBuilder: (_, i) =>
                              VideoCard(video: videos[i])
                                  .animate()
                                  .fadeIn(delay: (i * 40).ms)
                                  .slideY(begin: 0.05),
                        ),
                );
              }),
            _EmptyTab(icon: Icons.playlist_play_rounded, label: 'No playlists',
                sub: 'Create a playlist to organize your videos'),
            _EmptyTab(icon: Icons.history_rounded, label: 'No watch history',
                sub: 'Videos you watch will appear here'),
            _EmptyTab(icon: Icons.bookmark_border_rounded, label: 'No saved videos',
                sub: 'Bookmark videos to watch later'),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.darkBorder,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          const Text('Settings', style: TextStyle(color: AppColors.textPrimary,
              fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 16),
          _SettingsTile(icon: Icons.person_outline, label: 'Edit profile',
              onTap: () {}),
          _SettingsTile(icon: Icons.dark_mode_outlined, label: 'Dark mode',
              trailing: Switch(
                value: true,
                onChanged: (_) {},
                activeColor: AppColors.accentOrange,
              )),
          _SettingsTile(icon: Icons.notifications_outlined, label: 'Notifications',
              onTap: () {}),
          _SettingsTile(icon: Icons.lock_outline, label: 'Privacy & Security',
              onTap: () {}),
          _SettingsTile(icon: Icons.help_outline, label: 'Help & Feedback',
              onTap: () {}),
          const Divider(color: AppColors.darkDivider),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppColors.error),
            title: const Text('Sign out', style: TextStyle(color: AppColors.error,
                fontWeight: FontWeight.w600)),
            onTap: () async {
              Navigator.pop(ctx);
              await ref.read(authStateProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: const TextStyle(color: AppColors.textPrimary,
          fontWeight: FontWeight.w700, fontSize: 18)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
    ],
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 30, color: AppColors.darkDivider);
}

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   sub;
  const _EmptyTab({required this.icon, required this.label, required this.sub});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: AppColors.textTertiary),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: AppColors.textSecondary,
            fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        Text(sub, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
            textAlign: TextAlign.center),
      ],
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData   icon;
  final String     label;
  final VoidCallback? onTap;
  final Widget?    trailing;
  const _SettingsTile({required this.icon, required this.label, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppColors.textSecondary, size: 20),
    title: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
    trailing: trailing ?? (onTap != null
        ? const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18)
        : null),
    onTap: onTap,
  );
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(_, __, ___) => Container(
    color: AppColors.darkBg,
    child: tabBar,
  );

  @override
  bool shouldRebuild(_TabBarDelegate old) => false;
}
