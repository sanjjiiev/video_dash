import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/video_model.dart';

/// Full-featured controls overlay rendered on top of the video surface.
/// Completely custom-built — zero dependency on media_kit's built-in controls.
class PlayerControlsOverlay extends StatefulWidget {
  final bool       isPlaying;
  final bool       isFullscreen;
  final Duration   position;
  final Duration   duration;
  final Duration   buffered;
  final double     volume;
  final double     speed;
  final VideoModel? video;

  final VoidCallback       onPlay;
  final VoidCallback       onSkipBack;
  final VoidCallback       onSkipForward;
  final VoidCallback       onFullscreen;
  final VoidCallback       onOpenFile;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double>   onSpeedChange;
  final ValueChanged<double>   onVolumeChange;

  const PlayerControlsOverlay({
    super.key,
    required this.isPlaying,
    required this.isFullscreen,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.volume,
    required this.speed,
    this.video,
    required this.onPlay,
    required this.onSeek,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onFullscreen,
    required this.onSpeedChange,
    required this.onVolumeChange,
    required this.onOpenFile,
  });

  @override
  State<PlayerControlsOverlay> createState() => _PlayerControlsOverlayState();
}

class _PlayerControlsOverlayState extends State<PlayerControlsOverlay> {
  bool _showQualityPicker = false;
  bool _showSpeedPicker   = false;

  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  double get _progress =>
      widget.duration.inMilliseconds > 0
          ? widget.position.inMilliseconds / widget.duration.inMilliseconds
          : 0.0;

  double get _bufferProgress =>
      widget.duration.inMilliseconds > 0
          ? widget.buffered.inMilliseconds / widget.duration.inMilliseconds
          : 0.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Top gradient + title ─────────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            height: 120,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end:   Alignment.bottomCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    ),
                    Expanded(
                      child: Text(
                        widget.video?.title ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 14,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // More options
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: AppColors.darkCard,
                      onSelected: (v) {
                        if (v == 'open_file') widget.onOpenFile();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'open_file',
                            child: Row(children: [
                              Icon(Icons.folder_open, color: AppColors.textSecondary, size: 18),
                              SizedBox(width: 10),
                              Text('Open local file', style: TextStyle(color: AppColors.textPrimary)),
                            ])),
                        const PopupMenuItem(value: 'subtitle',
                            child: Row(children: [
                              Icon(Icons.subtitles, color: AppColors.textSecondary, size: 18),
                              SizedBox(width: 10),
                              Text('Subtitles / CC', style: TextStyle(color: AppColors.textPrimary)),
                            ])),
                        const PopupMenuItem(value: 'loop',
                            child: Row(children: [
                              Icon(Icons.loop, color: AppColors.textSecondary, size: 18),
                              SizedBox(width: 10),
                              Text('Loop video', style: TextStyle(color: AppColors.textPrimary)),
                            ])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Centre play/pause + skip ─────────────────────────────────────
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CircleButton(
                icon: Icons.replay_10_rounded,
                size: 30,
                onTap: widget.onSkipBack,
              ),
              const SizedBox(width: 24),
              _CircleButton(
                icon: widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 44,
                onTap: widget.onPlay,
                filled: true,
              ),
              const SizedBox(width: 24),
              _CircleButton(
                icon: Icons.forward_10_rounded,
                size: 30,
                onTap: widget.onSkipForward,
              ),
            ],
          ),
        ),

        // ── Bottom gradient + progress bar ───────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 60, 12, 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end:   Alignment.topCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Seek bar ──────────────────────────────────────────
                  _SeekBar(
                    progress:       _progress,
                    bufferProgress: _bufferProgress,
                    onSeek: (pct) {
                      final ms = (pct * widget.duration.inMilliseconds).round();
                      widget.onSeek(Duration(milliseconds: ms));
                    },
                  ),
                  const SizedBox(height: 6),

                  // ── Time + controls row ───────────────────────────────
                  Row(
                    children: [
                      Text(
                        '${_fmt(widget.position)} / ${_fmt(widget.duration)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const Spacer(),

                      // Speed button
                      _ControlButton(
                        label: '${widget.speed == 1.0 ? "1" : widget.speed}×',
                        onTap: () => setState(() => _showSpeedPicker = !_showSpeedPicker),
                      ),
                      const SizedBox(width: 8),

                      // Quality button
                      _ControlButton(
                        label: 'HD',
                        onTap: () => setState(() => _showQualityPicker = !_showQualityPicker),
                      ),
                      const SizedBox(width: 8),

                      // Volume
                      IconButton(
                        onPressed: () => widget.onVolumeChange(widget.volume > 0 ? 0 : 1),
                        icon: Icon(
                          widget.volume > 0.5 ? Icons.volume_up
                              : widget.volume > 0 ? Icons.volume_down
                              : Icons.volume_off,
                          color: Colors.white, size: 20,
                        ),
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),

                      // Fullscreen
                      IconButton(
                        onPressed: widget.onFullscreen,
                        icon: Icon(
                          widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                          color: Colors.white, size: 22,
                        ),
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Speed picker ─────────────────────────────────────────────────
        if (_showSpeedPicker)
          Positioned(
            bottom: 80, right: 12,
            child: _Picker<double>(
              title:    'Playback speed',
              items:    _speeds,
              selected: widget.speed,
              label:    (s) => '${s == 1.0 ? "Normal" : "${s}×"}',
              onSelect: (s) {
                widget.onSpeedChange(s);
                setState(() => _showSpeedPicker = false);
              },
              onDismiss: () => setState(() => _showSpeedPicker = false),
            ),
          ),

        // ── Quality picker ────────────────────────────────────────────────
        if (_showQualityPicker && (widget.video?.renditions ?? []).isNotEmpty)
          Positioned(
            bottom: 80, right: 12,
            child: _Picker<RenditionModel>(
              title:    'Quality',
              items:    widget.video!.renditions,
              selected: null,
              label:    (r) => r.name,
              onSelect: (r) {
                setState(() => _showQualityPicker = false);
                // Caller handles actual quality switch via player.switchQuality()
              },
              onDismiss: () => setState(() => _showQualityPicker = false),
            ),
          ),
      ],
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SeekBar extends StatefulWidget {
  final double  progress;
  final double  bufferProgress;
  final void Function(double) onSeek;
  const _SeekBar({required this.progress, required this.bufferProgress, required this.onSeek});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  bool _dragging = false;
  double _dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final value = _dragging ? _dragValue : widget.progress;

    return GestureDetector(
      onHorizontalDragStart: (d) {
        final box = context.findRenderObject() as RenderBox;
        setState(() {
          _dragging = true;
          _dragValue = (d.localPosition.dx / box.size.width).clamp(0, 1);
        });
      },
      onHorizontalDragUpdate: (d) {
        final box = context.findRenderObject() as RenderBox;
        setState(() => _dragValue = (d.localPosition.dx / box.size.width).clamp(0, 1));
      },
      onHorizontalDragEnd: (_) {
        widget.onSeek(_dragValue);
        setState(() => _dragging = false);
      },
      child: SizedBox(
        height: 20,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Buffer track
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                widthFactor: widget.bufferProgress,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Played track
            Container(
              height: _dragging ? 5 : 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: (value * 1000).round(),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Expanded(flex: ((1 - value) * 1000).round(), child: const SizedBox()),
                ],
              ),
            ),
            // Thumb
            Positioned(
              left: value * (MediaQuery.of(context).size.width - 24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width:  _dragging ? 16 : 12,
                height: _dragging ? 16 : 12,
                decoration: const BoxDecoration(
                  color: AppColors.accentOrange,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData     icon;
  final double       size;
  final VoidCallback onTap;
  final bool         filled;

  const _CircleButton({
    required this.icon, required this.size, required this.onTap, this.filled = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width:  filled ? size + 20 : size + 8,
      height: filled ? size + 20 : size + 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? AppColors.overlayDark : Colors.transparent,
        border: filled ? Border.all(color: Colors.white24) : null,
      ),
      child: Icon(icon, color: Colors.white, size: size),
    ),
  );
}

class _ControlButton extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  const _ControlButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white54),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
    ),
  );
}

class _Picker<T> extends StatelessWidget {
  final String        title;
  final List<T>       items;
  final T?            selected;
  final String Function(T) label;
  final void Function(T)   onSelect;
  final VoidCallback       onDismiss;

  const _Picker({
    required this.title, required this.items, required this.selected,
    required this.label, required this.onSelect, required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(title, style: const TextStyle(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                GestureDetector(onTap: onDismiss,
                  child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.darkDivider),
          ...items.map((item) => InkWell(
            onTap: () => onSelect(item),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: item == selected ? AppColors.accentOrange.withOpacity(0.1) : null,
              child: Row(
                children: [
                  Text(label(item),
                    style: TextStyle(
                      color: item == selected ? AppColors.accentOrange : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: item == selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (item == selected) ...[
                    const Spacer(),
                    const Icon(Icons.check, size: 14, color: AppColors.accentOrange),
                  ],
                ],
              ),
            ),
          )),
          const SizedBox(height: 4),
        ],
      ),
    ),
  );
}
