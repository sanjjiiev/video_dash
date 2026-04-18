import 'package:equatable/equatable.dart';

// ── User ──────────────────────────────────────────────────────────────────────
class UserModel extends Equatable {
  final String  id;
  final String  email;
  final String  role;
  final String? avatarUrl;
  final String? channelName;
  final int     subscriberCount;

  const UserModel({
    required this.id,
    required this.email,
    required this.role,
    this.avatarUrl,
    this.channelName,
    this.subscriberCount = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id:              json['id'] as String,
    email:           json['email'] as String,
    role:            json['role'] as String? ?? 'viewer',
    avatarUrl:       json['avatar_url'] as String?,
    channelName:     json['channel_name'] as String?,
    subscriberCount: json['subscriber_count'] as int? ?? 0,
  );

  String get displayName => channelName ?? email.split('@').first;

  @override
  List<Object?> get props => [id, email, role];
}

// ── Video ─────────────────────────────────────────────────────────────────────
class VideoModel extends Equatable {
  final String   id;
  final String   title;
  final String?  description;
  final String?  thumbnailUrl;
  final String   status;
  final double?  durationSeconds;
  final DateTime createdAt;
  final String   ownerEmail;
  final String?  ownerAvatarUrl;
  final int      viewCount;
  final int      likeCount;
  final int      dislikeCount;
  final bool     isLiked;
  final bool     isDisliked;
  final bool     isSaved;
  final List<RenditionModel> renditions;

  const VideoModel({
    required this.id,
    required this.title,
    this.description,
    this.thumbnailUrl,
    required this.status,
    this.durationSeconds,
    required this.createdAt,
    required this.ownerEmail,
    this.ownerAvatarUrl,
    this.viewCount      = 0,
    this.likeCount      = 0,
    this.dislikeCount   = 0,
    this.isLiked        = false,
    this.isDisliked     = false,
    this.isSaved        = false,
    this.renditions     = const [],
  });

  factory VideoModel.fromJson(Map<String, dynamic> json) => VideoModel(
    id:              json['id'] as String,
    title:           json['title'] as String,
    description:     json['description'] as String?,
    thumbnailUrl:    json['thumbnail_key'] as String?,
    status:          json['status'] as String? ?? 'pending',
    durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
    createdAt:       DateTime.parse(json['created_at'] as String),
    ownerEmail:      json['owner_email'] as String? ?? '',
    ownerAvatarUrl:  json['owner_avatar_url'] as String?,
    viewCount:       json['view_count']     as int? ?? 0,
    likeCount:       json['like_count']     as int? ?? 0,
    dislikeCount:    json['dislike_count']  as int? ?? 0,
    isLiked:         json['is_liked']       as bool? ?? false,
    isDisliked:      json['is_disliked']    as bool? ?? false,
    isSaved:         json['is_saved']       as bool? ?? false,
    renditions:      (json['renditions'] as List<dynamic>? ?? [])
        .map((r) => RenditionModel.fromJson(r as Map<String, dynamic>))
        .toList(),
  );

  String get channelName => ownerEmail.split('@').first;

  String get formattedDuration {
    if (durationSeconds == null) return '';
    final d = Duration(seconds: durationSeconds!.round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  VideoModel copyWith({
    bool? isLiked,
    bool? isDisliked,
    bool? isSaved,
    int?  likeCount,
    int?  dislikeCount,
  }) => VideoModel(
    id:              id,
    title:           title,
    description:     description,
    thumbnailUrl:    thumbnailUrl,
    status:          status,
    durationSeconds: durationSeconds,
    createdAt:       createdAt,
    ownerEmail:      ownerEmail,
    ownerAvatarUrl:  ownerAvatarUrl,
    viewCount:       viewCount,
    likeCount:       likeCount        ?? this.likeCount,
    dislikeCount:    dislikeCount     ?? this.dislikeCount,
    isLiked:         isLiked          ?? this.isLiked,
    isDisliked:      isDisliked       ?? this.isDisliked,
    isSaved:         isSaved          ?? this.isSaved,
    renditions:      renditions,
  );

  @override
  List<Object?> get props => [id, status, isLiked, isDisliked, isSaved];
}

class RenditionModel {
  final String name;
  final int?   bitrateK;

  const RenditionModel({required this.name, this.bitrateK});

  factory RenditionModel.fromJson(Map<String, dynamic> json) => RenditionModel(
    name:     json['name'] as String,
    bitrateK: json['bitrate_k'] as int?,
  );
}

// ── Comment ───────────────────────────────────────────────────────────────────
class CommentModel extends Equatable {
  final String   id;
  final String   text;
  final String   authorEmail;
  final String?  authorAvatarUrl;
  final DateTime createdAt;
  final int      likeCount;
  final bool     isLiked;

  const CommentModel({
    required this.id,
    required this.text,
    required this.authorEmail,
    this.authorAvatarUrl,
    required this.createdAt,
    this.likeCount = 0,
    this.isLiked   = false,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) => CommentModel(
    id:              json['id'] as String,
    text:            json['text'] as String,
    authorEmail:     json['author_email'] as String? ?? '',
    authorAvatarUrl: json['author_avatar_url'] as String?,
    createdAt:       DateTime.parse(json['created_at'] as String),
    likeCount:       json['like_count'] as int? ?? 0,
    isLiked:         json['is_liked']   as bool? ?? false,
  );

  String get authorName => authorEmail.split('@').first;

  @override
  List<Object?> get props => [id];
}

// ── Subscription ──────────────────────────────────────────────────────────────
class SubscriptionModel extends Equatable {
  final String   channelId;
  final String   channelName;
  final String?  avatarUrl;
  final int      subscriberCount;
  final bool     notifyNew;
  final DateTime subscribedAt;
  final bool     hasNewContent;

  const SubscriptionModel({
    required this.channelId,
    required this.channelName,
    this.avatarUrl,
    this.subscriberCount = 0,
    this.notifyNew       = true,
    required this.subscribedAt,
    this.hasNewContent   = false,
  });

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) =>
    SubscriptionModel(
      channelId:       json['id'] as String,
      channelName:     (json['channel_name'] as String?) ??
                       (json['email'] as String? ?? '').split('@').first,
      avatarUrl:       json['avatar_url'] as String?,
      subscriberCount: json['subscriber_count'] as int? ?? 0,
      notifyNew:       json['notify_new'] as bool? ?? true,
      subscribedAt:    DateTime.parse(
                         json['subscribed_at'] as String? ??
                         DateTime.now().toIso8601String()),
      hasNewContent:   json['has_new_content'] as bool? ?? false,
    );

  String get displayName => channelName;

  @override
  List<Object?> get props => [channelId];
}

// ── Channel Video Stats ───────────────────────────────────────────────────────
/// Summary row returned by GET /analytics/top-videos
class ChannelVideoStats extends Equatable {
  final String  videoId;
  final String  title;
  final String? thumbnailKey;
  final int     views;
  final int     likes;
  final int     avgCompletionPct;
  final int     watchSeconds;

  const ChannelVideoStats({
    required this.videoId,
    required this.title,
    this.thumbnailKey,
    this.views            = 0,
    this.likes            = 0,
    this.avgCompletionPct = 0,
    this.watchSeconds     = 0,
  });

  factory ChannelVideoStats.fromJson(Map<String, dynamic> json) =>
    ChannelVideoStats(
      videoId:          json['id'] as String,
      title:            json['title'] as String,
      thumbnailKey:     json['thumbnail_key'] as String?,
      views:            (json['views'] as num?)?.toInt() ?? 0,
      likes:            (json['likes'] as num?)?.toInt() ?? 0,
      avgCompletionPct: json['avg_completion_pct'] as int? ?? 0,
      watchSeconds:     (json['watch_seconds'] as num?)?.toInt() ?? 0,
    );

  @override
  List<Object?> get props => [videoId];
}
