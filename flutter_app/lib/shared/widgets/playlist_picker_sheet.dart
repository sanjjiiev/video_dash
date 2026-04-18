import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';

/// Bottom sheet that lets the user add a video to one of their playlists,
/// or quickly save to Watch Later — shown from the VideoCard 3-dot menu
/// or the PlayerScreen action bar.
///
/// Usage:
///   PlaylistPickerSheet.show(context, videoId: video.id);
class PlaylistPickerSheet extends ConsumerStatefulWidget {
  final String videoId;
  const PlaylistPickerSheet({super.key, required this.videoId});

  static Future<void> show(BuildContext context, {required String videoId}) {
    return showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder:            (ctx) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child:  PlaylistPickerSheet(videoId: videoId),
      ),
    );
  }

  @override
  ConsumerState<PlaylistPickerSheet> createState() => _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends ConsumerState<PlaylistPickerSheet> {
  List<Map<String, dynamic>> _playlists = [];
  Set<String>  _added         = {};
  bool         _loading        = true;
  bool         _watchLaterSaved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api      = ref.read(apiClientProvider);
      final raw      = await api.getPlaylists();
      setState(() {
        _playlists = raw.cast<Map<String, dynamic>>();
        _loading   = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _togglePlaylist(String playlistId, bool isAdded) async {
    final api = ref.read(apiClientProvider);
    setState(() {
      if (isAdded) _added.remove(playlistId);
      else         _added.add(playlistId);
    });
    try {
      if (isAdded) {
        await api.removeFromPlaylist(playlistId, widget.videoId);
      } else {
        await api.addToPlaylist(playlistId, widget.videoId);
      }
    } catch (e) {
      // Revert optimistic update
      setState(() {
        if (isAdded) _added.add(playlistId);
        else         _added.remove(playlistId);
      });
    }
  }

  Future<void> _toggleWatchLater() async {
    final api     = ref.read(apiClientProvider);
    final newState = !_watchLaterSaved;
    setState(() => _watchLaterSaved = newState);
    try {
      if (newState) {
        await api.saveWatchLater(widget.videoId);
      } else {
        await api.removeWatchLater(widget.videoId);
      }
    } catch (_) {
      setState(() => _watchLaterSaved = !newState);
    }
  }

  Future<void> _createPlaylist() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        title: const Text('New playlist',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText:  'Playlist name',
            hintStyle: TextStyle(color: AppColors.textTertiary),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Create', style: TextStyle(color: AppColors.accentOrange)),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      try {
        final api   = ref.read(apiClientProvider);
        final p     = await api.createPlaylist(name);
        final newId = p['id'] as String;
        await api.addToPlaylist(newId, widget.videoId);
        setState(() {
          _playlists.add(p);
          _added.add(newId);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create playlist: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.70),
      decoration: const BoxDecoration(
        color:        AppColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ───────────────────────────────────────────────────
          Container(
            width: 36, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
                color: AppColors.darkDivider, borderRadius: BorderRadius.circular(2)),
          ),

          // ── Header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Save video',
                    style: TextStyle(color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.darkDivider),

          // ── Watch Later ───────────────────────────────────────────────
          _PickerRow(
            icon:     Icons.watch_later_rounded,
            label:    'Watch Later',
            checked:  _watchLaterSaved,
            color:    const Color(0xFF3498DB),
            onToggle: _toggleWatchLater,
          ).animate().fadeIn(duration: 200.ms),

          const Divider(height: 1, color: AppColors.darkDivider),

          // ── Playlists ─────────────────────────────────────────────────
          Flexible(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: AppColors.accentOrange),
                    ))
                : ListView(
                    shrinkWrap: true,
                    children: [
                      ..._playlists.asMap().entries.map((e) {
                        final p       = e.value;
                        final pid     = p['id'] as String;
                        final isAdded = _added.contains(pid);
                        return _PickerRow(
                          icon:     Icons.playlist_play_rounded,
                          label:    p['title'] as String? ?? 'Playlist',
                          sublabel: '${p['item_count'] ?? 0} videos',
                          checked:  isAdded,
                          color:    AppColors.accentOrange,
                          onToggle: () => _togglePlaylist(pid, isAdded),
                        ).animate().fadeIn(delay: (e.key * 40).ms).slideX(begin: 0.05);
                      }),

                      // ── Create new playlist ──────────────────────────
                      InkWell(
                        onTap: _createPlaylist,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color:        AppColors.darkElevated,
                                  borderRadius: BorderRadius.circular(8),
                                  border:       Border.all(color: AppColors.accentOrange,
                                      style: BorderStyle.solid),
                                ),
                                child: const Icon(Icons.add_rounded,
                                    color: AppColors.accentOrange, size: 22),
                              ),
                              const SizedBox(width: 14),
                              const Text('New playlist',
                                style: TextStyle(color: AppColors.accentOrange,
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          // ── Done button ──────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width:  double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:  AppColors.accentOrange,
                    foregroundColor:  Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable checkbox row ─────────────────────────────────────────────────────
class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String?  sublabel;
  final bool     checked;
  final Color    color;
  final VoidCallback onToggle;

  const _PickerRow({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.checked,
    required this.color,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onToggle,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color:        color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                  style: const TextStyle(color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600, fontSize: 14)),
                if (sublabel != null)
                  Text(sublabel!,
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24, height: 24,
            decoration: BoxDecoration(
              color:        checked ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border:       Border.all(
                color: checked ? color : AppColors.darkDivider,
                width: 2,
              ),
            ),
            child: checked
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                : null,
          ),
        ],
      ),
    ),
  );
}
