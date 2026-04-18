import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/constants/app_colors.dart';

/// TikTok / YouTube Shorts style vertical swipe feed.
/// Each card is a full-screen video that plays automatically
/// as the user swipes up/down through the PageView.
class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key});

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  final _pageCtrl = PageController();
  int   _currentPage = 0;

  // Placeholder short clips (real data wired in Phase 4)
  static const _placeholders = [
    _ShortData(title: 'Amazing FFmpeg trick #1', channel: 'TechTips', likes: 12400, comments: 342),
    _ShortData(title: 'HLS streaming explained in 60s', channel: 'StreamDev', likes: 8900, comments: 201),
    _ShortData(title: 'Flutter media_kit showcase', channel: 'FlutterDev', likes: 22100, comments: 556),
    _ShortData(title: 'MinIO self-hosted setup', channel: 'DevOps101', likes: 5600, comments: 89),
    _ShortData(title: 'AES-128 encryption demo', channel: 'CryptoLearn', likes: 14300, comments: 278),
  ];

  @override
  void initState() {
    super.initState();
    // Shorts always start in full portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody:       true,
      body: Stack(
        children: [
          // ── Vertical pager ───────────────────────────────────────────
          PageView.builder(
            controller: _pageCtrl,
            scrollDirection: Axis.vertical,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _placeholders.length,
            itemBuilder: (_, i) => _ShortCard(
              data:      _placeholders[i],
              isActive:  i == _currentPage,
              index:     i,
            ),
          ),

          // ── Top bar (back + logo) ────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color:  Colors.black38,
                        shape:  BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Shorts',
                    style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w800, fontSize: 18)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color:  Colors.black38,
                        shape:  BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.search_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Page indicator dots ──────────────────────────────────────
          Positioned(
            right: 8,
            top:   0, bottom: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_placeholders.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  width:  i == _currentPage ? 6 : 4,
                  height: i == _currentPage ? 20 : 6,
                  decoration: BoxDecoration(
                    color:        i == _currentPage ? AppColors.accentOrange : Colors.white38,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Individual Short Card ──────────────────────────────────────────────────────
class _ShortCard extends StatefulWidget {
  final _ShortData data;
  final bool       isActive;
  final int        index;

  const _ShortCard({required this.data, required this.isActive, required this.index});

  @override
  State<_ShortCard> createState() => _ShortCardState();
}

class _ShortCardState extends State<_ShortCard> {
  late final Player         _player;
  late final VideoController _ctrl;
  bool _isLiked    = false;
  bool _isFollowing = false;

  // Gradient backgrounds used as video placeholders
  static const _gradients = [
    [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
    [Color(0xFF2d1b69), Color(0xFF11012e), Color(0xFFeff0f5)],
    [Color(0xFF0d0d0d), Color(0xFF1a1a1a), Color(0xFF2d2d2d)],
    [Color(0xFF003049), Color(0xFF0a1045), Color(0xFF000814)],
    [Color(0xFF1b0000), Color(0xFF3d0000), Color(0xFF590000)],
  ];

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024));
    _ctrl   = VideoController(_player);
    if (widget.isActive) _player.play();
  }

  @override
  void didUpdateWidget(_ShortCard old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _player.play();
    } else if (!widget.isActive && old.isActive) {
      _player.pause();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final gradColors = _gradients[widget.index % _gradients.length];

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background (gradient placeholder / real video) ───────────
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end:   Alignment.bottomRight,
              colors: gradColors,
            ),
          ),
          child: Center(
            child: Icon(Icons.play_circle_fill_rounded,
                color: Colors.white.withOpacity(0.2), size: 80),
          ),
        ),

        // ── Bottom info overlay ───────────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 72,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 80),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end:   Alignment.topCenter,
                colors: [Color(0xDD000000), Colors.transparent],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Channel row
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.brandGradient,
                      ),
                      child: Center(
                        child: Text(widget.data.channel[0],
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('@${widget.data.channel}',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => setState(() => _isFollowing = !_isFollowing),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color:        _isFollowing ? Colors.transparent : Colors.white,
                          border:       Border.all(color: Colors.white),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _isFollowing ? 'Following' : 'Follow',
                          style: TextStyle(
                            color:      _isFollowing ? Colors.white : Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize:   12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(widget.data.title,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 14, height: 1.3)),
                const SizedBox(height: 8),
                // Hashtags
                const Text('#shorts #streaming #hls',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ),

        // ── Right action column ───────────────────────────────────────
        Positioned(
          right: 8, bottom: 80,
          child: Column(
            children: [
              _ShortsAction(
                icon:  _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                label: _formatCount(widget.data.likes + (_isLiked ? 1 : 0)),
                color: _isLiked ? AppColors.accentPink : Colors.white,
                onTap: () => setState(() => _isLiked = !_isLiked),
              ),
              const SizedBox(height: 20),
              _ShortsAction(
                icon:  Icons.comment_rounded,
                label: _formatCount(widget.data.comments),
                onTap: () {},
              ),
              const SizedBox(height: 20),
              _ShortsAction(icon: Icons.share_rounded, label: 'Share', onTap: () {}),
              const SizedBox(height: 20),
              _ShortsAction(icon: Icons.bookmark_border_rounded, label: 'Save', onTap: () {}),
              const SizedBox(height: 20),
              // Rotating music disc
              _MusicDisc(channelName: widget.data.channel),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShortsAction extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  final Color        color;

  const _ShortsAction({
    required this.icon, required this.label, required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 32,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 8)]),
        const SizedBox(height: 3),
        Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 8)])),
      ],
    ),
  );
}

class _MusicDisc extends StatefulWidget {
  final String channelName;
  const _MusicDisc({required this.channelName});

  @override
  State<_MusicDisc> createState() => _MusicDiscState();
}

class _MusicDiscState extends State<_MusicDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _ctrl,
    child: Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.brandGradient,
        border: Border.all(color: Colors.black26, width: 3),
      ),
      child: Center(
        child: Container(
          width: 14, height: 14,
          decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
        ),
      ),
    ),
  );
}

class _ShortData {
  final String title;
  final String channel;
  final int    likes;
  final int    comments;
  const _ShortData({
    required this.title, required this.channel,
    required this.likes, required this.comments,
  });
}
