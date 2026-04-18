import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';

// ── Comment Model ─────────────────────────────────────────────────────────────
class CommentModel {
  final String  id;
  final String  body;
  final int     likeCount;
  final int     replyCount;
  final bool    pinned;
  final String  authorId;
  final String  authorName;
  final String? authorAvatar;
  final DateTime createdAt;
  bool liked;

  CommentModel({
    required this.id,
    required this.body,
    required this.likeCount,
    required this.replyCount,
    required this.pinned,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    required this.createdAt,
    this.liked = false,
  });

  factory CommentModel.fromJson(Map<String, dynamic> j) => CommentModel(
    id:           j['id'] as String,
    body:         j['body'] as String,
    likeCount:    j['like_count']  as int? ?? 0,
    replyCount:   j['reply_count'] as int? ?? 0,
    pinned:       j['pinned']      as bool? ?? false,
    authorId:     j['author_id']   as String? ?? '',
    authorName:   j['author_name'] as String? ?? j['author_email'] as String? ?? 'Unknown',
    authorAvatar: j['author_avatar'] as String?,
    createdAt:    DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

// ── Comments Provider ─────────────────────────────────────────────────────────
final commentsProvider = StateNotifierProvider.family<CommentsNotifier,
    AsyncValue<List<CommentModel>>, String>(
  (ref, videoId) => CommentsNotifier(videoId, ref.watch(apiClientProvider)),
);

class CommentsNotifier extends StateNotifier<AsyncValue<List<CommentModel>>> {
  final String    _videoId;
  final ApiClient _api;
  int _page = 1;
  bool _hasMore = true;

  CommentsNotifier(this._videoId, this._api)
      : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch({bool reset = false}) async {
    if (reset) {
      _page    = 1;
      _hasMore = true;
      state    = const AsyncValue.loading();
    }
    try {
      final data = await _api.getComments(_videoId, page: _page);
      final list = (data['comments'] as List)
          .map((j) => CommentModel.fromJson(j as Map<String, dynamic>))
          .toList();
      final total = data['total'] as int? ?? 0;

      final existing = reset ? <CommentModel>[] : (state.valueOrNull ?? []);
      final merged   = [...existing, ...list];
      _hasMore       = merged.length < total;
      _page++;
      state          = AsyncValue.data(merged);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> post(String body) async {
    final data = await _api.postComment(_videoId, body);
    final newComment = CommentModel.fromJson(data['comment'] as Map<String, dynamic>);
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([newComment, ...current]);
  }

  void toggleLike(String commentId) {
    final current = [...(state.valueOrNull ?? [])];
    final idx     = current.indexWhere((c) => c.id == commentId);
    if (idx == -1) return;
    final c    = current[idx];
    c.liked    = !c.liked;
    current[idx] = CommentModel(
      id:           c.id,
      body:         c.body,
      likeCount:    c.liked ? c.likeCount + 1 : c.likeCount - 1,
      replyCount:   c.replyCount,
      pinned:       c.pinned,
      authorId:     c.authorId,
      authorName:   c.authorName,
      authorAvatar: c.authorAvatar,
      createdAt:    c.createdAt,
      liked:        c.liked,
    );
    state = AsyncValue.data(current);
  }

  bool get hasMore => _hasMore;
}

// ── Comments Section Widget ───────────────────────────────────────────────────
class CommentsSection extends ConsumerStatefulWidget {
  final String videoId;
  final int    totalComments;

  const CommentsSection({
    super.key,
    required this.videoId,
    required this.totalComments,
  });

  @override
  ConsumerState<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<CommentsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row (tap to expand) ───────────────────────────────────
        GestureDetector(
          onTap: () {
            setState(() => _expanded = !_expanded);
            // Trigger bottom sheet
            if (!_expanded) return;
            _showCommentsSheet(context);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color:        AppColors.darkCard,
                borderRadius: BorderRadius.circular(12),
                border:       Border.all(color: AppColors.darkBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.comment_rounded,
                      color: AppColors.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text('Comments',
                    style: const TextStyle(color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(width: 6),
                  Text('${widget.totalComments}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const Spacer(),
                  const Icon(Icons.expand_more_rounded,
                      color: AppColors.textSecondary, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showCommentsSheet(BuildContext context) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder:            (_) => ProviderScope(
        parent: ref,
        child:  _CommentsSheet(videoId: widget.videoId),
      ),
    );
  }
}

// ── Full Comments Bottom Sheet ────────────────────────────────────────────────
class _CommentsSheet extends ConsumerStatefulWidget {
  final String videoId;
  const _CommentsSheet({required this.videoId});

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _ctrl   = TextEditingController();
  final _focus  = FocusNode();
  bool  _posting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    try {
      await ref.read(commentsProvider(widget.videoId).notifier).post(text);
      _ctrl.clear();
      _focus.unfocus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post: $e')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.videoId));
    final notifier      = ref.read(commentsProvider(widget.videoId).notifier);
    final authState     = ref.watch(authStateProvider);
    final isLoggedIn    = authState.value?.isLoggedIn ?? false;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize:     0.4,
      maxChildSize:     0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color:        AppColors.darkSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Handle ─────────────────────────────────────────────────
            Container(
              width: 36, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: AppColors.darkDivider, borderRadius: BorderRadius.circular(2)),
            ),

            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Comments', style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800, fontSize: 16)),
                  const Spacer(),
                  // Sort popup
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.sort_rounded,
                        color: AppColors.textSecondary, size: 20),
                    color: AppColors.darkCard,
                    onSelected: (_) => notifier.fetch(reset: true),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'newest', child:
                          Text('Newest first', style: TextStyle(color: AppColors.textPrimary))),
                      const PopupMenuItem(value: 'top', child:
                          Text('Top comments', style: TextStyle(color: AppColors.textPrimary))),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.darkDivider),

            // ── List ────────────────────────────────────────────────────
            Expanded(
              child: commentsAsync.when(
                loading: () => const Center(child:
                    CircularProgressIndicator(color: AppColors.accentOrange)),
                error:   (e, _) => Center(child: Text('Error: $e',
                    style: const TextStyle(color: AppColors.error))),
                data:    (comments) => comments.isEmpty
                    ? const Center(child: Text('No comments yet — be the first! 🎉',
                        style: TextStyle(color: AppColors.textSecondary)))
                    : RefreshIndicator(
                        color:    AppColors.accentOrange,
                        onRefresh: () => notifier.fetch(reset: true),
                        child: ListView.builder(
                          controller: ctrl,
                          itemCount:  comments.length +
                              (notifier.hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == comments.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: notifier.fetch,
                                  child: const Text('Load more',
                                      style: TextStyle(color: AppColors.accentOrange)),
                                ),
                              );
                            }
                            return _CommentTile(
                              comment: comments[i],
                              onLike:  () => notifier.toggleLike(comments[i].id),
                            ).animate().fadeIn(delay: (i * 20).ms);
                          },
                        ),
                      ),
              ),
            ),

            // ── Input box ───────────────────────────────────────────────
            if (isLoggedIn)
              SafeArea(
                child: Container(
                  padding: EdgeInsets.only(
                    left: 12, right: 8, top: 8,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.darkCard,
                    border: Border(top: BorderSide(color: AppColors.darkDivider)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller:  _ctrl,
                          focusNode:   _focus,
                          maxLines:    3,
                          minLines:    1,
                          style:       const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            hintText:  'Add a comment…',
                            hintStyle: const TextStyle(color: AppColors.textTertiary),
                            filled:    true,
                            fillColor: AppColors.darkElevated,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide:   BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _posting
                          ? const SizedBox(width: 36, height: 36,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.accentOrange))
                          : IconButton(
                              onPressed: _post,
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.accentOrange,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 18),
                            ),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                color: AppColors.darkCard,
                child: Text('Sign in to comment',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Individual Comment Tile ───────────────────────────────────────────────────
class _CommentTile extends StatelessWidget {
  final CommentModel comment;
  final VoidCallback onLike;
  const _CommentTile({required this.comment, required this.onLike});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        CircleAvatar(
          radius:          18,
          backgroundColor: AppColors.accentOrange.withOpacity(0.15),
          child: Text(
            comment.authorName.isNotEmpty ? comment.authorName[0].toUpperCase() : '?',
            style: const TextStyle(color: AppColors.accentOrange,
                fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author + time
              Row(
                children: [
                  if (comment.pinned)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.push_pin_rounded,
                          size: 12, color: AppColors.accentOrange),
                    ),
                  Text(comment.authorName,
                    style: const TextStyle(color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(timeago.format(comment.createdAt),
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 4),

              // Body
              Text(comment.body,
                style: const TextStyle(color: AppColors.textSecondary,
                    fontSize: 13, height: 1.4)),
              const SizedBox(height: 6),

              // Actions
              Row(
                children: [
                  GestureDetector(
                    onTap: onLike,
                    child: Row(
                      children: [
                        Icon(
                          comment.liked
                              ? Icons.thumb_up_rounded
                              : Icons.thumb_up_outlined,
                          size:  16,
                          color: comment.liked
                              ? AppColors.accentOrange
                              : AppColors.textTertiary,
                        ),
                        if (comment.likeCount > 0) ...[
                          const SizedBox(width: 4),
                          Text('${comment.likeCount}',
                            style: TextStyle(
                              color:    comment.liked
                                  ? AppColors.accentOrange
                                  : AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (comment.replyCount > 0)
                    Text('${comment.replyCount} replies',
                      style: const TextStyle(
                        color:      AppColors.accentOrange,
                        fontSize:   12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
