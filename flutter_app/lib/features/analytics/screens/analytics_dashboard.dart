import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/models/video_model.dart';

// ── Analytics Data Models ─────────────────────────────────────────────────────
class AnalyticsOverview {
  final int  totalVideos;
  final int  totalViews;
  final int  totalWatchSeconds;
  final int  totalLikes;
  final int  totalComments;
  final int  totalShares;
  final int  subscriberCount;

  const AnalyticsOverview({
    required this.totalVideos,
    required this.totalViews,
    required this.totalWatchSeconds,
    required this.totalLikes,
    required this.totalComments,
    required this.totalShares,
    required this.subscriberCount,
  });

  factory AnalyticsOverview.fromJson(Map<String, dynamic> j) => AnalyticsOverview(
    totalVideos:       j['total_videos']       as int? ?? 0,
    totalViews:        j['total_views']        as int? ?? 0,
    totalWatchSeconds: j['total_watch_seconds'] as int? ?? 0,
    totalLikes:        j['total_likes']        as int? ?? 0,
    totalComments:     j['total_comments']     as int? ?? 0,
    totalShares:       j['total_shares']       as int? ?? 0,
    subscriberCount:   j['subscriber_count']   as int? ?? 0,
  );

  String get watchTimeFormatted {
    final h = totalWatchSeconds ~/ 3600;
    if (h >= 1000) return '${(h / 1000).toStringAsFixed(1)}K hours';
    return '$h hours';
  }
}

class TimeseriesPoint {
  final String date;
  final int    views;
  final int    watchSeconds;
  final int    likes;

  const TimeseriesPoint({
    required this.date, required this.views,
    required this.watchSeconds, required this.likes,
  });

  factory TimeseriesPoint.fromJson(Map<String, dynamic> j) => TimeseriesPoint(
    date:         j['date'] as String,
    views:        j['views'] as int? ?? 0,
    watchSeconds: j['watch_seconds'] as int? ?? 0,
    likes:        j['likes'] as int? ?? 0,
  );
}

// ── Providers ─────────────────────────────────────────────────────────────────
// analyticsOverviewProvider, analyticsTimeseriesProvider, topVideosProvider
// are declared in auth_provider.dart (imported above).


// ── Analytics Dashboard Screen ────────────────────────────────────────────────
class AnalyticsDashboard extends ConsumerStatefulWidget {
  const AnalyticsDashboard({super.key});

  @override
  ConsumerState<AnalyticsDashboard> createState() => _AnalyticsDashboardState();
}

class _AnalyticsDashboardState extends ConsumerState<AnalyticsDashboard>
    with SingleTickerProviderStateMixin {

  late TabController _tabCtrl;
  int   _selectedDays  = 28;
  String _selectedMetric = 'views';

  // Sample data until backend is wired
  final List<TimeseriesPoint> _sampleData = List.generate(28, (i) {
    final rng = math.Random(i);
    return TimeseriesPoint(
      date:         DateTime.now().subtract(Duration(days: 27 - i)).toIso8601String().substring(0, 10),
      views:        50 + rng.nextInt(950),
      watchSeconds: 300 + rng.nextInt(3600),
      likes:        2 + rng.nextInt(80),
    );
  });

  // Sample top videos
  final _topVideos = [
    {'title': 'Getting started with HLS streaming', 'views': 12400, 'likes': 840, 'completion': 72},
    {'title': 'AES-128 encryption explained',        'views': 8900,  'likes': 620, 'completion': 65},
    {'title': 'FFmpeg transcoding deep dive',         'views': 6700,  'likes': 410, 'completion': 58},
    {'title': 'MinIO vs AWS S3',                      'views': 4200,  'likes': 380, 'completion': 81},
    {'title': 'Flutter media_kit tutorial',            'views': 3100,  'likes': 290, 'completion': 69},
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor:  AppColors.darkBg,
        surfaceTintColor: Colors.transparent,
        title: ShaderMask(
          shaderCallback: (b) => AppColors.brandGradient.createShader(b),
          child: const Text('Channel Analytics',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        actions: [
          // Period selector
          PopupMenuButton<int>(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_selectedDays days',
                  style: const TextStyle(color: AppColors.accentOrange,
                      fontWeight: FontWeight.w600, fontSize: 13)),
                const Icon(Icons.expand_more, color: AppColors.accentOrange, size: 18),
              ],
            ),
            color: AppColors.darkCard,
            onSelected: (d) => setState(() => _selectedDays = d),
            itemBuilder: (_) => [7, 28, 90, 365].map((d) =>
              PopupMenuItem(
                value: d,
                child: Text('Last $d days',
                  style: TextStyle(
                    color: d == _selectedDays ? AppColors.accentOrange : AppColors.textPrimary,
                    fontWeight: d == _selectedDays ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
            ).toList(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.accentOrange,
          indicatorWeight: 2,
          labelColor: AppColors.accentOrange,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Videos'), Tab(text: 'Audience')],
        ),
      ),

      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildOverviewTab(),
          _buildVideosTab(),
          _buildAudienceTab(),
        ],
      ),
    );
  }

  // ── Overview Tab ──────────────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    final overviewAsync = ref.watch(analyticsOverviewProvider);
    final seriesAsync   = ref.watch(analyticsTimeseriesProvider(_selectedDays));
    final liveData = seriesAsync.valueOrNull
        ?.map((e) => TimeseriesPoint.fromJson(e as Map<String, dynamic>))
        .toList() ?? _sampleData;
    final ov = overviewAsync.valueOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap:     true,
            physics:        const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.7,
            mainAxisSpacing:  12,
            crossAxisSpacing: 12,
            children: [
              _StatCard(
                label: 'Total Views',
                value: ov == null ? '...' : _formatCount(ov.totalViews),
                change: '+12%', icon: Icons.visibility_rounded,
                gradient: AppColors.brandGradient),
              _StatCard(
                label: 'Watch Time',
                value: ov == null ? '...' : ov.watchTimeFormatted,
                change: '+8%', icon: Icons.timer_rounded,
                gradient: const LinearGradient(colors: [Color(0xFF3498DB), Color(0xFF2980B9)])),
              _StatCard(
                label: 'Subscribers',
                value: ov == null ? '...' : _formatCount(ov.subscriberCount),
                change: '+34', icon: Icons.people_rounded,
                gradient: const LinearGradient(colors: [Color(0xFF2ECC71), Color(0xFF27AE60)])),
              _StatCard(
                label: 'Likes',
                value: ov == null ? '...' : _formatCount(ov.totalLikes),
                change: '+6%', icon: Icons.thumb_up_rounded,
                gradient: const LinearGradient(colors: [Color(0xFF9B59B6), Color(0xFF8E44AD)])),
            ],
          ).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 24),

          _MetricToggle(
            selected: _selectedMetric,
            onSelect: (m) => setState(() => _selectedMetric = m),
          ),
          const SizedBox(height: 16),

          _LineChart(
            data:   liveData,
            metric: _selectedMetric,
          ).animate().fadeIn(delay: 150.ms),

          const SizedBox(height: 24),

          const Text('Engagement', style: TextStyle(color: AppColors.textPrimary,
              fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          _EngagementBar(
            label: 'Like rate',
            value: (ov != null && ov.totalViews > 0)
                ? (ov.totalLikes / ov.totalViews).clamp(0.0, 1.0)
                : 0.094,
            color: AppColors.accentOrange),
          _EngagementBar(
            label: 'Comment rate',
            value: (ov != null && ov.totalViews > 0)
                ? (ov.totalComments / ov.totalViews).clamp(0.0, 1.0)
                : 0.034,
            color: AppColors.accentPink),
          _EngagementBar(label: 'Share rate', value: 0.012,
              color: const Color(0xFF3498DB)),
          _EngagementBar(label: 'Save rate',  value: 0.061,
              color: const Color(0xFF2ECC71)),
        ],
      ),
    );
  }

  // ── Videos Tab ────────────────────────────────────────────────────────────
  Widget _buildVideosTab() {
    final topAsync = ref.watch(topVideosProvider(_selectedMetric));
    return topAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accentOrange)),
      error: (_, __) => _videosTabFallback(),
      data: (videos) => videos.isEmpty
          ? _videosTabFallback()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  const Text('Top Videos', style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 15)),
                  const Spacer(),
                  _MetricChip(label: 'Views',
                      selected: _selectedMetric == 'views',
                      onTap: () => setState(() => _selectedMetric = 'views')),
                  const SizedBox(width: 6),
                  _MetricChip(label: 'Likes',
                      selected: _selectedMetric == 'likes',
                      onTap: () => setState(() => _selectedMetric = 'likes')),
                ]),
                const SizedBox(height: 12),
                ...videos.asMap().entries.map((e) => _TopVideoRow(
                  rank: e.key + 1,
                  data: {
                    'title':      e.value.title,
                    'views':      e.value.views,
                    'likes':      e.value.likes,
                    'completion': e.value.avgCompletionPct,
                  },
                  metric: _selectedMetric,
                )).toList().animate(interval: 60.ms).fadeIn().slideX(begin: 0.1),
              ],
            ),
    );
  }

  Widget _videosTabFallback() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Row(children: [
        const Text('Top Videos', style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700, fontSize: 15)),
        const Spacer(),
        _MetricChip(label: 'Views',
            selected: _selectedMetric == 'views',
            onTap: () => setState(() => _selectedMetric = 'views')),
        const SizedBox(width: 6),
        _MetricChip(label: 'Likes',
            selected: _selectedMetric == 'likes',
            onTap: () => setState(() => _selectedMetric = 'likes')),
      ]),
      const SizedBox(height: 12),
      ..._topVideos.asMap().entries.map((e) => _TopVideoRow(
        rank: e.key + 1,
        data: e.value,
        metric: _selectedMetric,
      )).toList().animate(interval: 60.ms).fadeIn().slideX(begin: 0.1),
    ],
  );


  // ── Audience Tab ──────────────────────────────────────────────────────────
  Widget _buildAudienceTab() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Subscriber Growth'),
        const SizedBox(height: 8),
        _LineChart(data: _sampleData, metric: 'views', color: const Color(0xFF2ECC71)),
        const SizedBox(height: 24),

        _SectionHeader('Device Breakdown'),
        const SizedBox(height: 12),
        _DonutChart(
          segments: const [
            _DonutSegment('Android', 0.45, AppColors.accentOrange),
            _DonutSegment('iOS',     0.30, AppColors.accentPink),
            _DonutSegment('Web',     0.18, Color(0xFF3498DB)),
            _DonutSegment('Desktop', 0.07, Color(0xFF2ECC71)),
          ],
        ),
        const SizedBox(height: 24),

        _SectionHeader('Watch Time by Hour'),
        const SizedBox(height: 8),
        _HourlyBar(data: List.generate(24, (i) => (math.sin(i / 4) + 1).clamp(0.05, 1.0))),
      ],
    ),
  );
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) => Text(label,
    style: const TextStyle(color: AppColors.textPrimary,
        fontWeight: FontWeight.w700, fontSize: 15));
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String change;
  final IconData icon;
  final LinearGradient gradient;
  const _StatCard({required this.label, required this.value,
      required this.change, required this.icon, required this.gradient});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color:        AppColors.darkCard,
      borderRadius: BorderRadius.circular(14),
      border:       Border.all(color: AppColors.darkBorder),
    ),
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ShaderMask(
              shaderCallback: (b) => gradient.createShader(b),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color:        AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(change,
                style: const TextStyle(color: AppColors.success,
                    fontWeight: FontWeight.w700, fontSize: 10)),
            ),
          ],
        ),
        const Spacer(),
        Text(value,
          style: const TextStyle(color: AppColors.textPrimary,
              fontWeight: FontWeight.w800, fontSize: 20)),
        Text(label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    ),
  );
}

class _MetricToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _MetricToggle({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Row(
    children: ['views', 'watch_seconds', 'likes'].map((m) {
      final label = m == 'watch_seconds' ? 'Watch time' : m[0].toUpperCase() + m.substring(1);
      final isSelected = m == selected;
      return GestureDetector(
        onTap: () => onSelect(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:        isSelected ? AppColors.accentOrange.withOpacity(0.15) : AppColors.darkElevated,
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(color: isSelected ? AppColors.accentOrange : AppColors.darkBorder),
          ),
          child: Text(label,
            style: TextStyle(
              color:      isSelected ? AppColors.accentOrange : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
              fontSize:   12,
            ),
          ),
        ),
      );
    }).toList(),
  );
}

class _MetricChip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  const _MetricChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        selected ? AppColors.accentOrange.withOpacity(0.15) : AppColors.darkElevated,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: selected ? AppColors.accentOrange : AppColors.darkBorder),
      ),
      child: Text(label, style: TextStyle(
        color:      selected ? AppColors.accentOrange : AppColors.textSecondary,
        fontSize:   11, fontWeight: FontWeight.w600)),
    ),
  );
}

// ── Line Chart ────────────────────────────────────────────────────────────────
class _LineChart extends StatelessWidget {
  final List<TimeseriesPoint> data;
  final String                metric;
  final Color                 color;

  const _LineChart({
    required this.data,
    required this.metric,
    this.color = AppColors.accentOrange,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color:        AppColors.darkCard,
      borderRadius: BorderRadius.circular(14),
      border:       Border.all(color: AppColors.darkBorder),
    ),
    child: CustomPaint(
      painter: _LineChartPainter(data: data, metric: metric, color: color),
    ),
  );
}

class _LineChartPainter extends CustomPainter {
  final List<TimeseriesPoint> data;
  final String                metric;
  final Color                 color;

  _LineChartPainter({required this.data, required this.metric, required this.color});

  List<int> get _values => data.map((d) => switch (metric) {
    'watch_seconds' => d.watchSeconds,
    'likes'         => d.likes,
    _               => d.views,
  }).toList();

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final values = _values;
    final maxVal = values.reduce(math.max).toDouble();
    if (maxVal == 0) return;

    final w = size.width;
    final h = size.height;
    final dx = w / (values.length - 1);

    // ── Grid lines ──────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = AppColors.darkDivider
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = h * i / 4;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // ── Fill gradient ────────────────────────────────────────────────
    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = h - (values[i] / maxVal) * h;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(fillPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end:   Alignment.bottomCenter,
        colors: [color.withOpacity(0.3), color.withOpacity(0)],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // ── Line ─────────────────────────────────────────────────────────
    canvas.drawPath(path, Paint()
      ..color       = color
      ..strokeWidth = 2.5
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round);

    // ── Data points (last one highlighted) ───────────────────────────
    for (int i = values.length - 1; i >= values.length - 1; i--) {
      final x = i * dx;
      final y = h - (values[i] / maxVal) * h;
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.data != data || old.metric != metric;
}

// ── Donut Chart ───────────────────────────────────────────────────────────────
class _DonutSegment {
  final String label;
  final double value;
  final Color  color;
  const _DonutSegment(this.label, this.value, this.color);
}

class _DonutChart extends StatelessWidget {
  final List<_DonutSegment> segments;
  const _DonutChart({required this.segments});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 140, height: 140,
        child: CustomPaint(painter: _DonutPainter(segments: segments)),
      ),
      const SizedBox(width: 24),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: segments.map((s) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(s.label,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
                Text('${(s.value * 100).round()}%',
                    style: const TextStyle(color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ),
          )).toList(),
        ),
      ),
    ],
  );
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  _DonutPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final stroke = radius * 0.42;
    var startAngle = -math.pi / 2;

    for (final seg in segments) {
      final sweep = seg.value * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - stroke / 2),
        startAngle, sweep, false,
        Paint()
          ..color       = seg.color
          ..strokeWidth = stroke
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.butt,
      );
      startAngle += sweep;
    }

    // Spacer gaps
    startAngle = -math.pi / 2;
    for (final seg in segments) {
      final sweep = seg.value * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - stroke / 2),
        startAngle + sweep - 0.02, 0.04, false,
        Paint()
          ..color       = AppColors.darkBg
          ..strokeWidth = stroke + 4
          ..style       = PaintingStyle.stroke,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => false;
}

class _EngagementBar extends StatelessWidget {
  final String label;
  final double value;  // 0.0 – 1.0
  final Color  color;
  const _EngagementBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            Text('${(value * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value:           value,
            backgroundColor: AppColors.darkDivider,
            color:           color,
            minHeight:       8,
          ),
        ),
      ],
    ),
  );
}

class _TopVideoRow extends StatelessWidget {
  final int                 rank;
  final Map<String, Object> data;
  final String              metric;
  const _TopVideoRow({required this.rank, required this.data, required this.metric});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.darkCard,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.darkBorder),
    ),
    child: Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            gradient:     rank <= 3 ? AppColors.brandGradient : null,
            color:        rank > 3  ? AppColors.darkElevated  : null,
            shape:        BoxShape.circle,
          ),
          child: Center(child: Text('$rank',
            style: TextStyle(
              color:      rank <= 3 ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize:   12,
            ),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data['title'] as String,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              Row(
                children: [
                  _mini(Icons.visibility_outlined, '${data["views"]}'),
                  const SizedBox(width: 12),
                  _mini(Icons.thumb_up_outlined,   '${data["likes"]}'),
                  const SizedBox(width: 12),
                  _mini(Icons.trending_up_rounded, '${data["completion"]}% done'),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _mini(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: AppColors.textTertiary),
      const SizedBox(width: 3),
      Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
    ],
  );
}

class _HourlyBar extends StatelessWidget {
  final List<double> data;
  const _HourlyBar({required this.data});

  @override
  Widget build(BuildContext context) => Container(
    height: 80,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(data.length, (i) {
        final isPeak = data[i] == data.reduce(math.max);
        return Expanded(
          child: Tooltip(
            message: '${i}:00',
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              height: 70 * data[i],
              decoration: BoxDecoration(
                gradient: isPeak ? AppColors.brandGradient : null,
                color:    isPeak ? null : AppColors.darkElevated,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ),
        );
      }),
    ),
  );
}
