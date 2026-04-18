import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../home/widgets/video_card.dart';
import '../../home/widgets/shorts_row.dart';

// ── Category tabs ─────────────────────────────────────────────────────────────
const _categories = [
  'All', 'Music', 'Gaming', 'Sports', 'News', 'Live', 'Films',
  'Tech', 'Science', 'Comedy', 'Education', 'Podcasts',
];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int    _selectedCategory = 0;
  final  _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(videoFeedProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(videoFeedProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: NestedScrollView(
        controller: _scrollCtrl,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // ── Top App Bar ────────────────────────────────────────────────
          SliverAppBar(
            floating: true,
            snap:     true,
            pinned:   false,
            backgroundColor: AppColors.darkBg,
            surfaceTintColor: Colors.transparent,
            title: ShaderMask(
              shaderCallback: (bounds) =>
                  AppColors.brandGradient.createShader(bounds),
              child: const Text('HUB',
                style: TextStyle(
                  color:      Colors.white,
                  fontSize:   26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.cast_rounded, color: AppColors.textSecondary),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
                onPressed: () => _showNotificationsSheet(context),
              ),
              IconButton(
                icon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                onPressed: () => context.push('/search'),
              ),
              const SizedBox(width: 4),
            ],
          ),

          // ── Category chips ──────────────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _CategoryBarDelegate(
              child: _CategoryBar(
                categories: _categories,
                selected:   _selectedCategory,
                onSelect:   (i) {
                  setState(() => _selectedCategory = i);
                  ref.read(videoFeedProvider.notifier).refresh();
                },
              ),
            ),
          ),
        ],

        body: RefreshIndicator(
          color:            AppColors.accentOrange,
          backgroundColor:  AppColors.darkCard,
          onRefresh:        () => ref.read(videoFeedProvider.notifier).refresh(),
          child: feedState.isLoading
              ? _buildSkeleton()
              : feedState.error != null && feedState.videos.isEmpty
                  ? _buildError(feedState.error!)
                  : CustomScrollView(
                      slivers: [
                        // ── Shorts row ─────────────────────────────────
                        const SliverToBoxAdapter(child: ShortsRow()),

                        // ── Video grid ─────────────────────────────────
                        SliverList.builder(
                          itemCount:   feedState.videos.length + (feedState.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == feedState.videos.length) {
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: CircularProgressIndicator(
                                    color: AppColors.accentOrange)),
                              );
                            }
                            return VideoCard(video: feedState.videos[i])
                                .animate()
                                .fadeIn(duration: 300.ms, delay: (i * 40).ms)
                                .slideY(begin: 0.05, curve: Curves.easeOut);
                          },
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() => ListView.builder(
    itemCount: 6,
    itemBuilder: (_, __) => Shimmer.fromColors(
      baseColor:      AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: const _VideoCardSkeleton(),
    ),
  );

  Widget _buildError(String error) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.textTertiary),
        const SizedBox(height: 16),
        const Text('Could not load videos', style: TextStyle(
            color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(error, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => ref.read(videoFeedProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ),
  );

  void _showNotificationsSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.darkBorder,
                  borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Notifications', style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
          ),
          const Divider(height: 1, color: AppColors.darkDivider),
          Expanded(
            child: ListView(
              children: const [
                _NotifTile(icon: Icons.notifications_active, title: 'New video from TechChannel',
                    sub: '2 minutes ago'),
                _NotifTile(icon: Icons.thumb_up_rounded, title: 'Someone liked your comment',
                    sub: '1 hour ago'),
                _NotifTile(icon: Icons.person_add, title: 'New subscriber',
                    sub: '3 hours ago'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   sub;
  const _NotifTile({required this.icon, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: AppColors.accentOrange, size: 20),
    ),
    title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
    subtitle: Text(sub, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
  );
}

// ── Category Bar ─────────────────────────────────────────────────────────────
class _CategoryBar extends StatelessWidget {
  final List<String>  categories;
  final int           selected;
  final ValueChanged<int> onSelect;

  const _CategoryBar({required this.categories, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    color: AppColors.darkBg,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: categories.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          child: FilterChip(
            selected:     i == selected,
            label:        Text(categories[i]),
            onSelected:   (_) => onSelect(i),
            selectedColor: AppColors.accentOrange.withOpacity(0.2),
            checkmarkColor: AppColors.accentOrange,
            labelStyle: TextStyle(
              color:      i == selected ? AppColors.accentOrange : AppColors.textSecondary,
              fontWeight: i == selected ? FontWeight.w700 : FontWeight.normal,
            ),
            backgroundColor: AppColors.darkElevated,
            side: BorderSide(
              color: i == selected ? AppColors.accentOrange : AppColors.darkBorder,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            showCheckmark: false,
          ),
        ),
      ),
    ),
  );
}

class _CategoryBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  const _CategoryBarDelegate({required this.child});

  @override double get minExtent => 48;
  @override double get maxExtent => 48;

  @override
  Widget build(_, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_CategoryBarDelegate old) => old.child != child;
}

// ── Video Card Skeleton ───────────────────────────────────────────────────────
class _VideoCardSkeleton extends StatelessWidget {
  const _VideoCardSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 200, width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 38, height: 38,
                decoration: const BoxDecoration(color: AppColors.shimmerBase, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 220, height: 14, color: AppColors.shimmerBase),
                const SizedBox(height: 6),
                Container(width: 140, height: 11, color: AppColors.shimmerBase),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}
