import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/video_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/network/api_client.dart';
import '../widgets/hub_video_player.dart';
import '../../home/widgets/video_card.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String  videoId;
  final String? localFilePath; // if set, plays offline without API calls
  const PlayerScreen({super.key, required this.videoId, this.localFilePath});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _isFullscreen    = false;
  bool _isLiked         = false;
  bool _isDisliked      = false;
  bool _isSaved         = false;
  bool _isSubscribed    = false;
  bool _showAllDesc     = false;
  bool _showComments    = false;
  final _commentCtrl = TextEditingController();
  final _scrollCtrl  = ScrollController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Offline / local file branch ──────────────────────────────────
    if (widget.localFilePath != null && widget.localFilePath!.isNotEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              HubVideoPlayer(
                url: widget.localFilePath,
              ),
              Positioned(
                top: 8, left: 8,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      );
    }


    final streamUrlAsync = ref.watch(streamUrlProvider(widget.videoId));
    final videoAsync     = ref.watch(videoDetailProvider(widget.videoId));
    final commentsAsync  = ref.watch(commentsProvider(widget.videoId));
    final auth           = ref.watch(authStateProvider).value;
    final token          = ref.read(apiClientProvider).accessToken;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: videoAsync.when(
        loading: () => _buildLoading(),
        error:   (e, _) => _buildError(e.toString()),
        data:    (video) {
          if (_isLiked != video.isLiked || _isDisliked != video.isDisliked) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() {
                _isLiked    = video.isLiked;
                _isDisliked = video.isDisliked;
                _isSaved    = video.isSaved;
              });
            });
          }

          return Column(
            children: [
              // ── Video Player ─────────────────────────────────────────
              streamUrlAsync.when(
                loading: () => AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(color: Colors.black,
                    child: const Center(child: CircularProgressIndicator(color: AppColors.accentOrange))),
                ),
                error: (e, _) => AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(color: Colors.black,
                    child: Center(child: Text(e.toString(), style: const TextStyle(color: Colors.white)))),
                ),
                data: (url) => HubVideoPlayer(
                  url:          url,
                  accessToken:  token,
                  video:        video,
                  isFullscreen: _isFullscreen,
                  onFullscreenToggle: () => setState(() => _isFullscreen = !_isFullscreen),
                ),
              ),

              // ── Scrollable content below player ──────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildVideoInfo(video),
                      _buildActionBar(video),
                      const Divider(height: 1, color: AppColors.darkDivider),
                      _buildChannelRow(video),
                      const Divider(height: 1, color: AppColors.darkDivider),
                      _buildDescription(video),
                      const Divider(height: 1, color: AppColors.darkDivider),
                      _buildCommentsSection(commentsAsync),
                      const Divider(height: 1, color: AppColors.darkDivider),
                      _buildRelatedVideos(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideoInfo(VideoModel video) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(video.title,
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.w700, fontSize: 17, height: 1.3),
        ).animate().fadeIn(),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '${_formatCount(video.viewCount)} views  •  ${timeago.format(video.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            // Live badge placeholder
            // Container(
            //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            //   decoration: BoxDecoration(color: AppColors.live, borderRadius: BorderRadius.circular(4)),
            //   child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            // ),
          ],
        ),
      ],
    ),
  );

  Widget _buildActionBar(VideoModel video) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Like
          _ActionChip(
            icon:     Icons.thumb_up_rounded,
            label:    _formatCount(video.likeCount),
            active:   _isLiked,
            onTap: () {
              setState(() {
                _isLiked    = !_isLiked;
                if (_isLiked) _isDisliked = false;
              });
              ref.read(apiClientProvider).likeVideo(video.id);
            },
          ),
          const SizedBox(width: 8),
          // Dislike
          _ActionChip(
            icon:     Icons.thumb_down_rounded,
            label:    _formatCount(video.dislikeCount),
            active:   _isDisliked,
            onTap: () {
              setState(() {
                _isDisliked = !_isDisliked;
                if (_isDisliked) _isLiked = false;
              });
              ref.read(apiClientProvider).dislikeVideo(video.id);
            },
          ),
          const SizedBox(width: 8),
          // Share
          _ActionChip(
            icon:  Icons.share_rounded,
            label: 'Share',
            onTap: () => Share.share(
              'Watch "${video.title}" on HUB 2.0!\nDelivered in AES-128 encrypted HLS.',
            ),
          ),
          const SizedBox(width: 8),
          // Save
          _ActionChip(
            icon:   Icons.bookmark_rounded,
            label:  _isSaved ? 'Saved' : 'Save',
            active: _isSaved,
            onTap: () => setState(() => _isSaved = !_isSaved),
          ),
          const SizedBox(width: 8),
          // Download
          _ActionChip(
            icon:  Icons.download_rounded,
            label: 'Download',
            onTap: () => _showSnack('Offline download coming in Phase 4'),
          ),
          const SizedBox(width: 8),
          // Clip
          _ActionChip(
            icon:  Icons.content_cut_rounded,
            label: 'Clip',
            onTap: () => _showSnack('Clip feature coming soon'),
          ),
        ],
      ),
    ),
  );

  Widget _buildChannelRow(VideoModel video) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        _ChannelAvatar(name: video.channelName, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(video.channelName,
                  style: Theme.of(context).textTheme.titleMedium),
              Text('${_formatCount(1240)} subscribers',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        // Subscribe button
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: _isSubscribed ? null : AppColors.brandGradient,
            color:    _isSubscribed ? AppColors.darkElevated : null,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() => _isSubscribed = !_isSubscribed);
                if (_isSubscribed) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Subscribed to ${video.channelName}!')),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  _isSubscribed ? 'Subscribed ✓' : 'Subscribe',
                  style: TextStyle(
                    color:      _isSubscribed ? AppColors.textSecondary : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize:   13,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildDescription(VideoModel video) => GestureDetector(
    onTap: () => setState(() => _showAllDesc = !_showAllDesc),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            video.description ?? 'No description',
            maxLines:  _showAllDesc ? null : 3,
            overflow:  _showAllDesc ? null : TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(height: 1.5),
          ),
          const SizedBox(height: 4),
          Text(
            _showAllDesc ? 'Show less' : 'Show more',
            style: const TextStyle(color: AppColors.accentOrange, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    ),
  );

  Widget _buildCommentsSection(AsyncValue<List<CommentModel>> commentsAsync) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Header tap to expand/collapse
      GestureDetector(
        onTap: () => setState(() => _showComments = !_showComments),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('Comments', style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(width: 8),
              commentsAsync.when(
                loading: () => const SizedBox.shrink(),
                error:   (_, __) => const SizedBox.shrink(),
                data:    (c) => Text('${c.length}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
              const Spacer(),
              Icon(
                _showComments ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),

      if (_showComments) ...[
        // Comment input
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              const _ChannelAvatar(name: 'Me', size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send_rounded, color: AppColors.accentOrange, size: 20),
                      onPressed: () async {
                        if (_commentCtrl.text.trim().isEmpty) return;
                        await ref.read(apiClientProvider).postComment(
                          widget.videoId, _commentCtrl.text.trim());
                        _commentCtrl.clear();
                        ref.invalidate(commentsProvider(widget.videoId));
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Comment list
        commentsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(color: AppColors.accentOrange)),
          ),
          error:   (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load comments', style: Theme.of(context).textTheme.bodySmall),
          ),
          data: (comments) => comments.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No comments yet. Be the first!',
                    style: Theme.of(context).textTheme.bodySmall),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: comments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 0),
                  itemBuilder: (_, i) => _CommentTile(comment: comments[i]),
                ),
        ),
      ],
    ],
  );

  Widget _buildRelatedVideos() {
    final relatedAsync = ref.watch(videoFeedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Up next', style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        ...relatedAsync.videos
            .where((v) => v.id != widget.videoId)
            .take(8)
            .map((v) => VideoCard(video: v, horizontal: true)),
      ],
    );
  }

  Widget _buildLoading() => Column(
    children: [
      AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(color: Colors.black,
          child: const Center(child: CircularProgressIndicator(color: AppColors.accentOrange))),
      ),
      const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.accentOrange))),
    ],
  );

  Widget _buildError(String e) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 48),
          const SizedBox(height: 16),
          Text(e, textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.invalidate(videoDetailProvider(widget.videoId)),
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final bool         active;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon, required this.label,
    this.active = false, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color:        active ? AppColors.accentOrange.withOpacity(0.15) : AppColors.darkElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? AppColors.accentOrange : AppColors.darkBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16,
              color: active ? AppColors.accentOrange : AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            color:      active ? AppColors.accentOrange : AppColors.textSecondary,
            fontSize:   12,
            fontWeight: FontWeight.w600,
          )),
        ],
      ),
    ),
  );
}

class _ChannelAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _ChannelAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.avatarColors[name.codeUnitAt(0) % AppColors.avatarColors.length];
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color:  color.withOpacity(0.2),
        shape:  BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(color: color, fontWeight: FontWeight.w700,
              fontSize: size * 0.4),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommentModel comment;
  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChannelAvatar(name: comment.authorName, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(comment.authorName,
                    style: const TextStyle(color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(width: 8),
                  Text(timeago.format(comment.createdAt),
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 3),
              Text(comment.text,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
              const SizedBox(height: 4),
              Row(
                children: [
                  GestureDetector(
                    child: const Icon(Icons.thumb_up_outlined,
                        size: 14, color: AppColors.textTertiary),
                  ),
                  const SizedBox(width: 4),
                  Text('${comment.likeCount}',
                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                  const SizedBox(width: 12),
                  const Text('Reply',
                      style: TextStyle(color: AppColors.textTertiary,
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
