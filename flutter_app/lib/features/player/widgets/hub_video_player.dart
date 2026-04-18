import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/video_model.dart';
import 'player_controls_overlay.dart';

/// The definitive media_kit-based video player for HUB 2.0.
///
/// Supports:
///  • HLS adaptive streaming (.m3u8) with AES-128 decryption
///  • Local file playback (.mp4, .mkv, .avi, .mov)
///  • Custom control overlay with:
///      - Play/Pause, Seek bar with buffer indicator
///      - Skip ±10 s (double-tap), swipe-to-seek
///      - Volume (swipe right), Brightness (swipe left)
///      - Long-press 2× speed
///      - Quality picker (rendition switching)
///      - Playback speed picker
///      - Subtitles/CC (if available)
///      - Picture-in-Picture stub
///  • Auto-rotate to landscape via gyroscope
///  • Wakelock (screen stays on during playback)
///  • Mini-player collapse on back navigation
class HubVideoPlayer extends StatefulWidget {
  /// Remote HLS URL or local file path
  final String?         url;
  final String?         accessToken;
  final VideoModel?     video;
  final bool            autoPlay;
  final bool            isFullscreen;
  final VoidCallback?   onFullscreenToggle;
  final VoidCallback?   onVideoEnd;

  const HubVideoPlayer({
    super.key,
    this.url,
    this.accessToken,
    this.video,
    this.autoPlay      = true,
    this.isFullscreen  = false,
    this.onFullscreenToggle,
    this.onVideoEnd,
  });

  @override
  State<HubVideoPlayer> createState() => HubVideoPlayerState();
}

class HubVideoPlayerState extends State<HubVideoPlayer>
    with WidgetsBindingObserver {

  late final Player        _player;
  late final VideoController _controller;

  // ── Overlay state ─────────────────────────────────────────────────────────
  bool   _showControls   = true;
  bool   _isBuffering    = false;
  bool   _isPlaying      = false;
  bool   _isFullscreen   = false;
  double _volume         = 1.0;
  double _playbackSpeed  = 1.0;
  Duration _position     = Duration.zero;
  Duration _duration     = Duration.zero;
  Duration _buffered     = Duration.zero;

  // ── Gesture state ─────────────────────────────────────────────────────────
  double _dragStartX     = 0;
  double _dragStartY     = 0;
  bool   _isDraggingSeek = false;
  bool   _isDraggingVolume = false;
  bool   _isDraggingBright = false;
  double _seekTarget     = 0;
  double _brightnessLevel = 0.5;

  // ── Double-tap seek feedback ───────────────────────────────────────────────
  bool   _showLeftSeek   = false;
  bool   _showRightSeek  = false;

  // ── Long-press 2× speed ───────────────────────────────────────────────────
  bool   _is2xSpeed      = false;

  // ── Auto-hide timer ───────────────────────────────────────────────────────
  Timer? _hideTimer;

  // ── Gyroscope ─────────────────────────────────────────────────────────────
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  static const double _rotateThreshold = 2.5; // rad/s

  // ── Stream subscriptions ──────────────────────────────────────────────────
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isFullscreen = widget.isFullscreen;
    _initPlayer();
    _initGyroscope();
    WakelockPlus.enable();
  }

  // ── Player init ────────────────────────────────────────────────────────────
  void _initPlayer() {
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024, // 32 MB buffer
        logLevel:   MPVLogLevel.warn,
      ),
    );

    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    // ── Subscribe to player streams ──────────────────────────────────────
    _subs.addAll([
      _player.stream.playing.listen((v)       => setState(() => _isPlaying  = v)),
      _player.stream.buffering.listen((v)     => setState(() => _isBuffering = v)),
      _player.stream.position.listen((v)      => setState(() => _position    = v)),
      _player.stream.duration.listen((v)      => setState(() => _duration    = v)),
      _player.stream.buffer.listen((v)        => setState(() => _buffered    = v)),
      _player.stream.volume.listen((v)        => setState(() => _volume      = v / 100.0)),
      _player.stream.completed.listen((done)  { if (done) widget.onVideoEnd?.call(); }),
    ]);

    if (widget.url != null) _loadMedia(widget.url!);
  }

  void _loadMedia(String url) {
    final isLocal = !url.startsWith('http');
    final media = Media(
      url,
      httpHeaders: isLocal ? null : {
        if (widget.accessToken != null)
          'Authorization': 'Bearer ${widget.accessToken}',
        'User-Agent': 'HUBStreamingApp/1.0',
      },
    );
    _player.open(media, play: widget.autoPlay);
  }

  // ── Local file picker ──────────────────────────────────────────────────────
  Future<void> openLocalFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      _loadMedia(result.files.single.path!);
    }
  }

  // ── Gyroscope auto-rotate ─────────────────────────────────────────────────
  void _initGyroscope() {
    _gyroSub = gyroscopeEventStream().listen((event) {
      if (event.z.abs() > _rotateThreshold) {
        final toLandscape = event.z < -_rotateThreshold;
        _setFullscreen(toLandscape);
      }
    });
  }

  Future<void> _setFullscreen(bool fullscreen) async {
    if (_isFullscreen == fullscreen) return;
    setState(() => _isFullscreen = fullscreen);

    if (fullscreen) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    widget.onFullscreenToggle?.call();
  }

  // ── Controls visibility ───────────────────────────────────────────────────
  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    _startHideTimer();
  }

  // ── Playback controls ─────────────────────────────────────────────────────
  void _togglePlay() {
    _isPlaying ? _player.pause() : _player.play();
    _showControlsTemporarily();
  }

  void _seekTo(Duration pos) {
    _player.seek(pos.clamp(Duration.zero, _duration));
  }

  void _skipForward()  => _seekTo(_position + const Duration(seconds: 10));
  void _skipBackward() => _seekTo(_position - const Duration(seconds: 10));

  void _setSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _player.setRate(speed);
  }

  void _setVolume(double v) {
    setState(() => _volume = v.clamp(0.0, 1.0));
    _player.setVolume(_volume * 100);
  }

  // ── Quality switching ─────────────────────────────────────────────────────
  /// Switch to a specific rendition sub-playlist URL.
  /// Saves position and reloads at the same timestamp.
  Future<void> switchQuality(String playlistUrl) async {
    final pos = _position;
    await _player.open(
      Media(playlistUrl, httpHeaders: {
        if (widget.accessToken != null)
          'Authorization': 'Bearer ${widget.accessToken}',
      }),
      play: true,
    );
    await Future.delayed(const Duration(milliseconds: 800));
    _seekTo(pos);
  }

  // ── Long-press → 2× speed ────────────────────────────────────────────────
  void _onLongPressStart(_) {
    setState(() => _is2xSpeed = true);
    _player.setRate(2.0);
    HapticFeedback.mediumImpact();
  }

  void _onLongPressEnd(_) {
    setState(() => _is2xSpeed = false);
    _player.setRate(_playbackSpeed);
  }

  // ── Horizontal swipe → seek ───────────────────────────────────────────────
  void _onHorizontalDragStart(DragStartDetails d) {
    _dragStartX  = d.localPosition.dx;
    _seekTarget  = _position.inMilliseconds.toDouble();
    setState(() => _isDraggingSeek = true);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    final delta = d.localPosition.dx - _dragStartX;
    final ms    = (delta / MediaQuery.of(context).size.width) * _duration.inMilliseconds * 0.5;
    setState(() {
      _seekTarget = (_seekTarget + ms).clamp(0, _duration.inMilliseconds.toDouble());
    });
  }

  void _onHorizontalDragEnd(_) {
    _seekTo(Duration(milliseconds: _seekTarget.round()));
    setState(() => _isDraggingSeek = false);
  }

  // ── Vertical swipe → volume / brightness ─────────────────────────────────
  void _onVerticalDragStart(DragStartDetails d) {
    _dragStartY = d.localPosition.dy;
    final halfWidth = MediaQuery.of(context).size.width / 2;
    if (d.localPosition.dx < halfWidth) {
      setState(() => _isDraggingBright = true);
    } else {
      setState(() => _isDraggingVolume = true);
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    final delta = (_dragStartY - d.localPosition.dy) / MediaQuery.of(context).size.height;
    if (_isDraggingVolume) {
      _setVolume(_volume + delta * 0.5);
    } else {
      setState(() => _brightnessLevel = (_brightnessLevel + delta * 0.5).clamp(0, 1));
    }
    _dragStartY = d.localPosition.dy;
  }

  void _onVerticalDragEnd(_) {
    setState(() { _isDraggingBright = false; _isDraggingVolume = false; });
  }

  // ── Double-tap → skip ────────────────────────────────────────────────────
  void _onDoubleTapLeft() {
    _skipBackward();
    setState(() => _showLeftSeek = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showLeftSeek = false);
    });
  }

  void _onDoubleTapRight() {
    _skipForward();
    setState(() => _showRightSeek = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showRightSeek = false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused)   _player.pause();
    if (state == AppLifecycleState.resumed && _isPlaying) _player.play();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _gyroSub?.cancel();
    for (final s in _subs) { s.cancel(); }
    _player.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _isFullscreen
          ? MediaQuery.of(context).size.aspectRatio
          : 16 / 9,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Video surface ──────────────────────────────────────────────
          Container(
            color: Colors.black,
            child: Video(
              controller:     _controller,
              controls:       NoVideoControls,
              wakelock:       true,
              fill:           Colors.black,
            ),
          ),

          // ── Gesture detector layer ─────────────────────────────────────
          GestureDetector(
            onTap:              _toggleControls,
            onLongPressStart:   _onLongPressStart,
            onLongPressEnd:     _onLongPressEnd,
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            onVerticalDragStart: _onVerticalDragStart,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd:   _onVerticalDragEnd,
            child: Container(color: Colors.transparent),
          ),

          // ── Left double-tap zone ───────────────────────────────────────
          Positioned(
            left: 0, top: 0, bottom: 0,
            width: MediaQuery.of(context).size.width * 0.35,
            child: GestureDetector(
              onDoubleTap: _onDoubleTapLeft,
              child: Container(color: Colors.transparent),
            ),
          ),

          // ── Right double-tap zone ──────────────────────────────────────
          Positioned(
            right: 0, top: 0, bottom: 0,
            width: MediaQuery.of(context).size.width * 0.35,
            child: GestureDetector(
              onDoubleTap: _onDoubleTapRight,
              child: Container(color: Colors.transparent),
            ),
          ),

          // ── Double-tap seek animation ─────────────────────────────────
          if (_showLeftSeek)
            Positioned(left: 20, child: _SeekRipple(isForward: false)),
          if (_showRightSeek)
            Positioned(right: 20, child: _SeekRipple(isForward: true)),

          // ── 2× speed badge ────────────────────────────────────────────
          if (_is2xSpeed)
            Positioned(
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.overlayDark,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fast_forward, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('2× speed', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ),

          // ── Seek drag indicator ───────────────────────────────────────
          if (_isDraggingSeek)
            _DragSeekIndicator(
              currentMs:  _seekTarget,
              totalMs:    _duration.inMilliseconds.toDouble(),
            ),

          // ── Volume indicator ──────────────────────────────────────────
          if (_isDraggingVolume)
            _VolumeIndicator(volume: _volume),

          // ── Brightness indicator ──────────────────────────────────────
          if (_isDraggingBright)
            _BrightnessIndicator(brightness: _brightnessLevel),

          // ── Buffering spinner ─────────────────────────────────────────
          if (_isBuffering && !_isDraggingSeek)
            const _BufferingIndicator(),

          // ── Controls overlay ──────────────────────────────────────────
          AnimatedOpacity(
            opacity:  _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: PlayerControlsOverlay(
                isPlaying:     _isPlaying,
                isFullscreen:  _isFullscreen,
                position:      _position,
                duration:      _duration,
                buffered:      _buffered,
                volume:        _volume,
                speed:         _playbackSpeed,
                video:         widget.video,
                onPlay:        _togglePlay,
                onSeek:        _seekTo,
                onSkipBack:    _skipBackward,
                onSkipForward: _skipForward,
                onFullscreen:  () => _setFullscreen(!_isFullscreen),
                onSpeedChange: _setSpeed,
                onVolumeChange:_setVolume,
                onOpenFile:    openLocalFile,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Internal widgets ──────────────────────────────────────────────────────────

class _BufferingIndicator extends StatelessWidget {
  const _BufferingIndicator();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 48, height: 48,
    child: CircularProgressIndicator(
      color: AppColors.accentOrange,
      strokeWidth: 3,
    ),
  );
}

class _SeekRipple extends StatefulWidget {
  final bool isForward;
  const _SeekRipple({required this.isForward});

  @override
  State<_SeekRipple> createState() => _SeekRippleState();
}

class _SeekRippleState extends State<_SeekRipple>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  late Animation<double>   _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _scale   = Tween(begin: 0.6, end: 1.2).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Opacity(
      opacity: _opacity.value,
      child: Transform.scale(
        scale: _scale.value,
        child: Container(
          width: 90, height: 90,
          decoration: const BoxDecoration(
            color: AppColors.overlayLight,
            shape: BoxShape.circle,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isForward ? Icons.fast_forward : Icons.fast_rewind,
                color: Colors.white, size: 28,
              ),
              const SizedBox(height: 2),
              const Text('+10s', style: TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DragSeekIndicator extends StatelessWidget {
  final double currentMs;
  final double totalMs;
  const _DragSeekIndicator({required this.currentMs, required this.totalMs});

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.overlayDark,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '${_fmt(currentMs.round())} / ${_fmt(totalMs.round())}',
      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
    ),
  );
}

class _VolumeIndicator extends StatelessWidget {
  final double volume;
  const _VolumeIndicator({required this.volume});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.overlayDark,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(volume > 0.5 ? Icons.volume_up : (volume > 0 ? Icons.volume_down : Icons.volume_off),
             color: Colors.white, size: 28),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: RotatedBox(
            quarterTurns: -1,
            child: LinearProgressIndicator(
              value: volume,
              backgroundColor: Colors.white24,
              color: AppColors.accentOrange,
            ),
          ),
        ),
      ],
    ),
  );
}

class _BrightnessIndicator extends StatelessWidget {
  final double brightness;
  const _BrightnessIndicator({required this.brightness});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.overlayDark,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.brightness_6, color: Colors.white, size: 28),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: RotatedBox(
            quarterTurns: -1,
            child: LinearProgressIndicator(
              value: brightness,
              backgroundColor: Colors.white24,
              color: Colors.yellow,
            ),
          ),
        ),
      ],
    ),
  );
}
