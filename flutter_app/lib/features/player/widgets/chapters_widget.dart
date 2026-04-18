import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Model for a single video chapter
class ChapterModel {
  final String id;
  final String title;
  final double startSeconds;
  final int    position;

  const ChapterModel({
    required this.id,
    required this.title,
    required this.startSeconds,
    required this.position,
  });

  factory ChapterModel.fromJson(Map<String, dynamic> j) => ChapterModel(
    id:           j['id'] as String,
    title:        j['title'] as String,
    startSeconds: (j['start_seconds'] as num).toDouble(),
    position:     j['position'] as int,
  );
}

/// Chapters widget with two display modes:
///
/// 1. [ChaptersSeekBar] — overlays chapter markers on the player's seek bar
/// 2. [ChaptersPanel]   — expandable list panel below the player
class ChaptersSeekBar extends StatelessWidget {
  final List<ChapterModel> chapters;
  final Duration           duration;
  final Duration           position;
  final ValueChanged<Duration> onSeek;

  const ChaptersSeekBar({
    super.key,
    required this.chapters,
    required this.duration,
    required this.position,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    if (chapters.isEmpty || duration.inSeconds == 0) return const SizedBox.shrink();

    return SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // ── Chapter tick marks ───────────────────────────────────
              ...chapters.skip(1).map((chapter) {
                final pct = (chapter.startSeconds / duration.inSeconds).clamp(0.0, 1.0);
                return Positioned(
                  left: w * pct - 1,
                  child: GestureDetector(
                    onTap: () => onSeek(Duration(seconds: chapter.startSeconds.round())),
                    child: Tooltip(
                      message:        chapter.title,
                      preferBelow:    false,
                      textStyle:      const TextStyle(color: Colors.white, fontSize: 11),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Container(
                        width:  2.5,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white70,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                );
              }),

              // ── Current chapter label ─────────────────────────────────
              _CurrentChapterLabel(
                chapters: chapters,
                position: position,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CurrentChapterLabel extends StatelessWidget {
  final List<ChapterModel> chapters;
  final Duration           position;

  const _CurrentChapterLabel({required this.chapters, required this.position});

  ChapterModel? get _current {
    final secs = position.inSeconds.toDouble();
    ChapterModel? result;
    for (final c in chapters) {
      if (c.startSeconds <= secs) result = c;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _current;
    if (chapter == null) return const SizedBox.shrink();

    return Positioned(
      top: 0, left: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          chapter.title,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Expandable chapters list panel — shown below the video player
class ChaptersPanel extends StatefulWidget {
  final List<ChapterModel> chapters;
  final Duration           duration;
  final Duration           currentPosition;
  final ValueChanged<Duration> onSeek;

  const ChaptersPanel({
    super.key,
    required this.chapters,
    required this.duration,
    required this.currentPosition,
    required this.onSeek,
  });

  @override
  State<ChaptersPanel> createState() => _ChaptersPanelState();
}

class _ChaptersPanelState extends State<ChaptersPanel> {
  bool _expanded = false;

  int get _currentIndex {
    final secs = widget.currentPosition.inSeconds.toDouble();
    int result = 0;
    for (int i = 0; i < widget.chapters.length; i++) {
      if (widget.chapters[i].startSeconds <= secs) result = i;
    }
    return result;
  }

  String _fmt(double secs) {
    final d = Duration(seconds: secs.round());
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chapters.isEmpty) return const SizedBox.shrink();

    final current = widget.chapters[_currentIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.menu_book_rounded, size: 18, color: AppColors.accentOrange),
                const SizedBox(width: 8),
                const Text('Chapters',
                  style: TextStyle(color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(width: 8),
                // Current chapter name
                Expanded(
                  child: Text(
                    '· ${current.title}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.accentOrange,
                        fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary, size: 20),
              ],
            ),
          ),
        ),

        // ── Chapter list (animated expand) ───────────────────────────
        AnimatedCrossFade(
          duration:   const Duration(milliseconds: 200),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: ListView.builder(
            shrinkWrap: true,
            physics:    const NeverScrollableScrollPhysics(),
            itemCount:  widget.chapters.length,
            itemBuilder: (_, i) {
              final chapter   = widget.chapters[i];
              final isActive  = i == _currentIndex;
              final nextStart = i + 1 < widget.chapters.length
                  ? widget.chapters[i + 1].startSeconds
                  : widget.duration.inSeconds.toDouble();
              final chapterDuration = nextStart - chapter.startSeconds;

              // Progress within this chapter
              double chapterProgress = 0;
              if (isActive && chapterDuration > 0) {
                chapterProgress = (widget.currentPosition.inSeconds.toDouble() -
                    chapter.startSeconds).clamp(0, chapterDuration) / chapterDuration;
              } else if (i < _currentIndex) {
                chapterProgress = 1;
              }

              return InkWell(
                onTap: () {
                  widget.onSeek(Duration(seconds: chapter.startSeconds.round()));
                  setState(() => _expanded = false);
                },
                child: Container(
                  color: isActive ? AppColors.accentOrange.withOpacity(0.05) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      // Chapter number
                      SizedBox(
                        width: 24,
                        child: Text('${i + 1}',
                          style: TextStyle(
                            color: isActive ? AppColors.accentOrange : AppColors.textTertiary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Mini progress bar for this chapter
                      SizedBox(
                        width: 4,
                        height: 40,
                        child: Column(
                          children: [
                            Expanded(
                              flex: (chapterProgress * 100).round(),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: AppColors.brandGradient,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: ((1 - chapterProgress) * 100).round().clamp(0, 100),
                              child: Container(
                                color: AppColors.darkDivider,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(chapter.title,
                              style: TextStyle(
                                color:      isActive ? AppColors.accentOrange : AppColors.textPrimary,
                                fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                                fontSize:   13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(_fmt(chapter.startSeconds),
                              style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                          ],
                        ),
                      ),
                      // Duration of this chapter
                      Text(_fmt(chapterDuration),
                        style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const Divider(height: 1, color: AppColors.darkDivider),
      ],
    );
  }
}
