import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/video_model.dart';
import '../../../core/network/api_client.dart';


// ── Download State ──────────────────────────────────────────────────────────
enum DownloadStatus { pending, downloading, completed, failed, cancelled }

class DownloadTask {
  final VideoModel video;
  final double     progress;  // 0.0 – 1.0
  final DownloadStatus status;
  final String?    localPath;
  final String?    error;

  const DownloadTask({
    required this.video,
    this.progress  = 0,
    this.status    = DownloadStatus.pending,
    this.localPath,
    this.error,
  });

  bool get isDone    => status == DownloadStatus.completed;
  bool get isFailed  => status == DownloadStatus.failed;
  bool get isActive  => status == DownloadStatus.downloading;

  DownloadTask copyWith({double? progress, DownloadStatus? status,
      String? localPath, String? error}) => DownloadTask(
    video:     video,
    progress:  progress  ?? this.progress,
    status:    status    ?? this.status,
    localPath: localPath ?? this.localPath,
    error:     error     ?? this.error,
  );

  Map<String, dynamic> toJson() => {
    'videoId':   video.id,
    'title':     video.title,
    'localPath': localPath,
    'status':    status.name,
  };
}

// ── Download Manager ─────────────────────────────────────────────────────────
class DownloadManager extends StateNotifier<Map<String, DownloadTask>> {
  final ApiClient _api;
  final _dio       = Dio();
  final Map<String, CancelToken> _tokens = {};
  static const _indexKey = 'hub_downloads_index';

  DownloadManager(this._api) : super({}) {
    _loadIndex();
  }

  // ── Persist download index to SharedPreferences ─────────────────────────
  Future<void> _loadIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_indexKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      final map  = <String, DownloadTask>{};
      for (final item in list) {
        if (item['status'] == 'completed' && item['localPath'] != null) {
          final f = File(item['localPath'] as String);
          if (await f.exists()) {
            // TODO: rebuild VideoModel from stored data — for now we just track path
          }
        }
      }
      if (mounted) state = map;
    } catch (_) {}
  }

  Future<void> _saveIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final list  = state.values.where((t) => t.isDone).map((t) => t.toJson()).toList();
    await prefs.setString(_indexKey, jsonEncode(list));
  }

  // ── Start download ───────────────────────────────────────────────────────
  Future<void> download(VideoModel video) async {
    if (state.containsKey(video.id)) return; // already downloading or done

    state = {
      ...state,
      video.id: DownloadTask(video: video, status: DownloadStatus.pending),
    };

    try {
      // 1. Get stream URL
      final streamData  = await _api.getStreamUrl(video.id);
      final streamUrl   = streamData['streamUrl'] as String;
      final token       = _api.accessToken;

      // 2. Determine save path
      final dir  = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/hub_downloads/${video.id}.mp4';
      await Directory('${dir.path}/hub_downloads').create(recursive: true);

      final cancelToken = CancelToken();
      _tokens[video.id] = cancelToken;

      state = {
        ...state,
        video.id: state[video.id]!.copyWith(status: DownloadStatus.downloading),
      };

      // 3. Download
      await _dio.download(
        streamUrl,
        path,
        cancelToken: cancelToken,
        options: Options(headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        }),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final pct = received / total;
          if (mounted) {
            state = {
              ...state,
              video.id: state[video.id]!.copyWith(progress: pct),
            };
          }
        },
      );

      if (mounted) {
        state = {
          ...state,
          video.id: state[video.id]!.copyWith(
            status:    DownloadStatus.completed,
            progress:  1.0,
            localPath: path,
          ),
        };
        await _saveIndex();
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = {...state}..remove(video.id);
      } else {
        if (mounted) {
          state = {
            ...state,
            video.id: state[video.id]!.copyWith(
              status: DownloadStatus.failed,
              error:  e.message,
            ),
          };
        }
      }
    }
    _tokens.remove(video.id);
  }

  // ── Cancel download ───────────────────────────────────────────────────────
  void cancel(String videoId) {
    _tokens[videoId]?.cancel('User cancelled');
    state = {...state}..remove(videoId);
  }

  // ── Delete downloaded file ────────────────────────────────────────────────
  Future<void> delete(String videoId) async {
    final task = state[videoId];
    if (task?.localPath != null) {
      try { await File(task!.localPath!).delete(); } catch (_) {}
    }
    state = {...state}..remove(videoId);
    await _saveIndex();
  }

  List<DownloadTask> get completedDownloads =>
      state.values.where((t) => t.isDone).toList();

  List<DownloadTask> get activeDownloads =>
      state.values.where((t) => t.isActive).toList();
}

final downloadManagerProvider =
    StateNotifierProvider<DownloadManager, Map<String, DownloadTask>>(
  (ref) => DownloadManager(ref.watch(apiClientProvider)),
);

// ── Downloads Screen ─────────────────────────────────────────────────────────
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final manager   = ref.read(downloadManagerProvider.notifier);
    final tasks     = downloads.values.toList();

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor:  AppColors.darkBg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Downloads'),
        actions: [
          if (tasks.any((t) => t.isDone))
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.error),
              tooltip: 'Delete all',
              onPressed: () => _confirmDeleteAll(context, manager, tasks),
            ),
        ],
      ),
      body: tasks.isEmpty
          ? _buildEmpty(context)
          : ListView.builder(
              itemCount:   tasks.length,
              padding:     const EdgeInsets.all(12),
              itemBuilder: (_, i) => _DownloadTile(
                task:    tasks[i],
                onDelete: () => manager.delete(tasks[i].video.id),
                onCancel: () => manager.cancel(tasks[i].video.id),
              ),
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.download_for_offline_outlined, size: 72, color: AppColors.textTertiary),
        const SizedBox(height: 16),
        const Text('No downloads yet',
          style: TextStyle(color: AppColors.textSecondary,
              fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Tap the download icon on any video to save it offline',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
      ],
    ),
  );

  void _confirmDeleteAll(
      BuildContext ctx, DownloadManager manager, List<DownloadTask> tasks) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('Delete all downloads?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('This will permanently delete all downloaded videos from your device.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              for (final t in tasks) { manager.delete(t.video.id); }
            },
            child: const Text('Delete all', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  const _DownloadTile({required this.task, required this.onDelete, required this.onCancel});

  String get _sizeStr {
    if (task.localPath == null) return '';
    try {
      final bytes = File(task.localPath!).lengthSync();
      if (bytes < 1024 * 1024)       return '${(bytes / 1024).toStringAsFixed(0)} KB';
      if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) => Card(
    color:  AppColors.darkCard,
    margin: const EdgeInsets.only(bottom: 8),
    child:  Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color:        _statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_statusIcon, color: _statusColor, size: 24),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.video.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),

                if (task.isActive) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value:           task.progress,
                      backgroundColor: AppColors.darkDivider,
                      color:           AppColors.accentOrange,
                      minHeight:       4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('${(task.progress * 100).round()}%',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ] else ...[
                  Text(
                    task.isDone
                        ? 'Downloaded · $_sizeStr'
                        : task.isFailed
                            ? 'Failed: ${task.error ?? "Unknown error"}'
                            : task.status.name,
                    style: TextStyle(color: _statusColor, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),

          // Action button
          if (task.isActive)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: AppColors.error),
              onPressed: onCancel,
            )
          else if (task.isDone) ...[
            // Play offline
            IconButton(
              icon: const Icon(Icons.play_circle_rounded,
                  color: AppColors.accentOrange),
              tooltip: 'Play offline',
              onPressed: () => context.push(
                '/video/local',
                extra: {'filePath': task.localPath},
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.textTertiary),
              onPressed: onDelete,
            ),
          ]
          else if (task.isFailed)
            const Icon(Icons.error_outline, color: AppColors.error, size: 20),
        ],
      ),
    ),
  );

  Color get _statusColor => switch (task.status) {
    DownloadStatus.completed   => AppColors.success,
    DownloadStatus.downloading => AppColors.accentOrange,
    DownloadStatus.failed      => AppColors.error,
    _                          => AppColors.textSecondary,
  };

  IconData get _statusIcon => switch (task.status) {
    DownloadStatus.completed   => Icons.check_circle_rounded,
    DownloadStatus.downloading => Icons.download_rounded,
    DownloadStatus.failed      => Icons.error_rounded,
    _                          => Icons.hourglass_top_rounded,
  };
}
