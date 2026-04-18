import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/models/video_model.dart';

/// Renders a single video card. Supports two layouts:
///  - [horizontal] = false (default) → standard vertical card (thumbnail above info)
///  - [horizontal] = true  → compact side-by-side card (used in related videos)
class VideoCard extends StatefulWidget {
  final VideoModel video;
  final bool       horizontal;

  const VideoCard({super.key, required this.video, this.horizontal = false});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return widget.horizontal ? _buildHorizontal() : _buildVertical();
  }

  Widget _buildVertical() => MouseRegion(
    onEnter:  (_) => setState(() => _hovered = true),
    onExit:   (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: () => context.push('/video/${widget.video.id}'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin:   EdgeInsets.all(_hovered ? 4 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail ─────────────────────────────────────────────
            Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: _hovered
                        ? BorderRadius.circular(8)
                        : BorderRadius.zero,
                    boxShadow: _hovered
                        ? [const BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))]
                        : [],
                  ),
                  child: ClipRRect(
                    borderRadius: _hovered
                        ? BorderRadius.circular(8)
                        : BorderRadius.zero,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _ThumbnailImage(
                        url:    widget.video.thumbnailUrl,
                        blurOnHover: _hovered,
                      ),
                    ),
                  ),
                ),
                // Duration badge
                if (widget.video.formattedDuration.isNotEmpty)
                  Positioned(
                    bottom: 6, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.overlayDark,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.video.formattedDuration,
                        style: const TextStyle(color: Colors.white, fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                // Play overlay on hover
                if (_hovered)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.overlayDark,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white30),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                      ),
                    ),
                  ),
              ],
            ),

            // ── Info row ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Channel avatar
                  _ChannelAvatar(name: widget.video.channelName, size: 36),
                  const SizedBox(width: 10),
                  // Title + meta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium!.copyWith(
                            fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.video.channelName}  •  '
                          '${_formatCount(widget.video.viewCount)} views  •  '
                          '${timeago.format(widget.video.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // 3-dot menu
                  _VideoMenu(video: widget.video),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildHorizontal() => GestureDetector(
    onTap: () => context.push('/video/${widget.video.id}'),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 160, height: 90,
              child: Stack(
                children: [
                  _ThumbnailImage(url: widget.video.thumbnailUrl),
                  if (widget.video.formattedDuration.isNotEmpty)
                    Positioned(
                      bottom: 4, right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.overlayDark,
                            borderRadius: BorderRadius.circular(3)),
                        child: Text(widget.video.formattedDuration,
                            style: const TextStyle(color: Colors.white, fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600, fontSize: 12.5, height: 1.3)),
                const SizedBox(height: 4),
                Text(widget.video.channelName,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('${_formatCount(widget.video.viewCount)} views',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          _VideoMenu(video: widget.video),
        ],
      ),
    ),
  );

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Channel Avatar ────────────────────────────────────────────────────────────
class _ChannelAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _ChannelAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.avatarColors[
        name.isNotEmpty ? name.codeUnitAt(0) % AppColors.avatarColors.length : 0];
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color:      color,
            fontWeight: FontWeight.w700,
            fontSize:   size * 0.42,
          ),
        ),
      ),
    );
  }
}

// ── Thumbnail Image ───────────────────────────────────────────────────────────
class _ThumbnailImage extends StatelessWidget {
  final String? url;
  final bool    blurOnHover;
  const _ThumbnailImage({this.url, this.blurOnHover = false});

  @override
  Widget build(BuildContext context) {
    final child = url != null && url!.startsWith('http')
        ? CachedNetworkImage(
            imageUrl: url!,
            fit:      BoxFit.cover,
            placeholder: (_, __) => Container(color: AppColors.darkElevated),
            errorWidget:  (_, __, ___) => _placeholder(),
          )
        : _placeholder();

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity:  blurOnHover ? 0.7 : 1.0,
      child: child,
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.darkElevated,
    child: const Center(
      child: Icon(Icons.play_circle_outline_rounded,
          color: AppColors.textTertiary, size: 40),
    ),
  );
}

// ── 3-Dot Menu ────────────────────────────────────────────────────────────────
class _VideoMenu extends StatelessWidget {
  final VideoModel video;
  const _VideoMenu({required this.video});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    icon: const Icon(Icons.more_vert, color: AppColors.textTertiary, size: 20),
    color:            AppColors.darkCard,
    constraints:      const BoxConstraints(minWidth: 200),
    onSelected: (val) {
      final msg = switch (val) {
        'save'         => 'Added to Watch Later',
        'not_interest' => 'Got it, we\'ll show fewer like this',
        'report'       => 'Report submitted',
        'share'        => 'Link copied',
        _              => val,
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    },
    itemBuilder: (_) => [
      _menuItem('save',         Icons.bookmark_border_rounded, 'Save to Watch Later'),
      _menuItem('playlist',     Icons.playlist_add_rounded,    'Add to playlist'),
      _menuItem('share',        Icons.share_rounded,           'Share'),
      _menuItem('not_interest', Icons.do_disturb_alt_rounded,  'Not interested'),
      _menuItem('dont_channel', Icons.person_off_outlined,     'Don\'t recommend channel'),
      _menuItem('report',       Icons.flag_outlined,           'Report'),
    ],
  );

  PopupMenuItem<String> _menuItem(String val, IconData icon, String label) =>
      PopupMenuItem(
        value: val,
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          ],
        ),
      );
}
