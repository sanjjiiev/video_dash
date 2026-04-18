import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../models/video_model.dart';
import '../../features/analytics/screens/analytics_dashboard.dart';


// ── Auth State ────────────────────────────────────────────────────────────────
class AuthState {
  final UserModel? user;
  final bool       isLoading;
  final String?    error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isLoggedIn => user != null;

  AuthState copyWith({UserModel? user, bool? isLoading, String? error, bool clearError = false}) =>
    AuthState(
      user:      user       ?? this.user,
      isLoading: isLoading  ?? this.isLoading,
      error:     clearError ? null : (error ?? this.error),
    );
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AsyncValue<AuthState>> {
  final ApiClient _api;

  AuthNotifier(this._api) : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    if (_api.isLoggedIn) {
      try {
        final data = await _api.getMe();
        final user = UserModel.fromJson(data);
        state = AsyncValue.data(AuthState(user: user));
      } catch (_) {
        state = AsyncValue.data(const AuthState());
      }
    } else {
      state = AsyncValue.data(const AuthState());
    }
  }

  Future<void> login(String email, String password) async {
    state = AsyncValue.data(state.value!.copyWith(isLoading: true, clearError: true));
    try {
      final data = await _api.login(email, password);
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      state = AsyncValue.data(AuthState(user: user));
    } catch (e) {
      state = AsyncValue.data(
        state.value!.copyWith(isLoading: false, error: _parseError(e)),
      );
    }
  }

  Future<void> register(String email, String password) async {
    state = AsyncValue.data(state.value!.copyWith(isLoading: true, clearError: true));
    try {
      await _api.register(email, password);
      await login(email, password);
    } catch (e) {
      state = AsyncValue.data(
        state.value!.copyWith(isLoading: false, error: _parseError(e)),
      );
    }
  }

  Future<void> logout() async {
    await _api.logout();
    state = AsyncValue.data(const AuthState());
  }

  String _parseError(dynamic e) {
    if (e is Exception) return e.toString().replaceFirst('Exception: ', '');
    return 'An unexpected error occurred';
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AsyncValue<AuthState>>(
  (ref) => AuthNotifier(ref.watch(apiClientProvider)),
);

// ── Video Feed Provider ───────────────────────────────────────────────────────
class VideoFeedState {
  final List<VideoModel> videos;
  final bool             isLoading;
  final bool             isLoadingMore;
  final bool             hasMore;
  final int              currentPage;
  final String?          error;

  const VideoFeedState({
    this.videos        = const [],
    this.isLoading     = false,
    this.isLoadingMore = false,
    this.hasMore       = true,
    this.currentPage   = 1,
    this.error,
  });

  VideoFeedState copyWith({
    List<VideoModel>? videos,
    bool? isLoading, bool? isLoadingMore, bool? hasMore,
    int? currentPage, String? error, bool clearError = false,
  }) => VideoFeedState(
    videos:        videos        ?? this.videos,
    isLoading:     isLoading     ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore:       hasMore       ?? this.hasMore,
    currentPage:   currentPage   ?? this.currentPage,
    error:         clearError ? null : (error ?? this.error),
  );
}

class VideoFeedNotifier extends StateNotifier<VideoFeedState> {
  final ApiClient _api;

  VideoFeedNotifier(this._api) : super(const VideoFeedState()) {
    load();
  }

  Future<void> load({String? search}) async {
    state = state.copyWith(isLoading: true, clearError: true, videos: [], currentPage: 1, hasMore: true);
    try {
      final data = await _api.getVideos(page: 1, search: search);
      final videos = (data['videos'] as List)
          .map((v) => VideoModel.fromJson(v as Map<String, dynamic>))
          .toList();
      final pagination = data['pagination'] as Map<String, dynamic>;
      state = state.copyWith(
        isLoading:   false,
        videos:      videos,
        hasMore:     (pagination['page'] as int) < (pagination['totalPages'] as int),
        currentPage: 2,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final data = await _api.getVideos(page: state.currentPage);
      final newVideos = (data['videos'] as List)
          .map((v) => VideoModel.fromJson(v as Map<String, dynamic>))
          .toList();
      final pagination = data['pagination'] as Map<String, dynamic>;
      state = state.copyWith(
        isLoadingMore: false,
        videos:        [...state.videos, ...newVideos],
        hasMore:       state.currentPage <= (pagination['totalPages'] as int),
        currentPage:   state.currentPage + 1,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() => load();
}

final videoFeedProvider = StateNotifierProvider<VideoFeedNotifier, VideoFeedState>(
  (ref) => VideoFeedNotifier(ref.watch(apiClientProvider)),
);

// ── Single Video Detail Provider ──────────────────────────────────────────────
final videoDetailProvider = FutureProvider.family<VideoModel, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getVideo(id);
  return VideoModel.fromJson(data);
});

// ── Stream URL Provider ───────────────────────────────────────────────────────
final streamUrlProvider = FutureProvider.family<String, String>((ref, videoId) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getStreamUrl(videoId);
  return data['streamUrl'] as String;
});

// ── Comments Provider ─────────────────────────────────────────────────────────
final commentsProvider = FutureProvider.family<List<CommentModel>, String>((ref, videoId) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.getComments(videoId);
  return (data['comments'] as List? ?? [])
      .map((c) => CommentModel.fromJson(c as Map<String, dynamic>))
      .toList();
});

// ── Search Provider ───────────────────────────────────────────────────────────
final searchProvider = StateNotifierProvider<SearchNotifier, VideoFeedState>(
  (ref) => SearchNotifier(ref.watch(apiClientProvider)),
);

class SearchNotifier extends StateNotifier<VideoFeedState> {
  final ApiClient _api;
  SearchNotifier(this._api) : super(const VideoFeedState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const VideoFeedState();
      return;
    }
    state = state.copyWith(isLoading: true, videos: []);
    try {
      final data = await _api.getVideos(search: query.trim());
      final videos = (data['videos'] as List)
          .map((v) => VideoModel.fromJson(v as Map<String, dynamic>))
          .toList();
      state = state.copyWith(isLoading: false, videos: videos);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clear() => state = const VideoFeedState();
}

// ── Subscriptions Provider ──────────────────────────────────────────────────
class SubscriptionsNotifier
    extends StateNotifier<AsyncValue<List<SubscriptionModel>>> {
  final ApiClient _api;
  SubscriptionsNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final raw  = await _api.getSubscriptions();
      final list = raw
          .map((e) => SubscriptionModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> subscribe(String channelId) async {
    try {
      await _api.subscribe(channelId);
      await load();
    } catch (_) {}
  }

  Future<void> unsubscribe(String channelId) async {
    // Optimistic removal
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
        current.where((s) => s.channelId != channelId).toList());
    try {
      await _api.unsubscribe(channelId);
    } catch (_) {
      await load(); // rollback on failure
    }
  }

  Future<void> toggleNotify(String channelId,
      {required bool notifyNew}) async {
    try {
      await _api.toggleSubscriptionNotify(channelId, notifyNew: notifyNew);
      await load();
    } catch (_) {}
  }
}

final subscriptionsProvider = StateNotifierProvider<
    SubscriptionsNotifier,
    AsyncValue<List<SubscriptionModel>>>(
  (ref) => SubscriptionsNotifier(ref.watch(apiClientProvider)),
);

// ── Channel Videos Provider ───────────────────────────────────────────────
/// Loads videos owned by a specific user (their channel). Used by ProfileScreen.
final channelVideosProvider =
    FutureProvider.family<List<VideoModel>, String>((ref, ownerId) async {
  final api  = ref.watch(apiClientProvider);
  final data = await api.getChannelVideos(ownerId);
  return ((data['videos'] ?? []) as List)
      .map((v) => VideoModel.fromJson(v as Map<String, dynamic>))
      .toList();
});

// ── Analytics Timeseries Provider ─────────────────────────────────────────
final analyticsOverviewProvider =
    FutureProvider<AnalyticsOverview>((ref) async {
  final d = await ref.watch(apiClientProvider).getAnalyticsOverview();
  return AnalyticsOverview.fromJson(d);
});

final analyticsTimeseriesProvider =
    FutureProvider.family<List<dynamic>, int>((ref, days) async {
  return ref.watch(apiClientProvider).getAnalyticsTimeseries(days: days);
});

final topVideosProvider =
    FutureProvider.family<List<ChannelVideoStats>, String>((ref, metric) async {
  final raw = await ref.watch(apiClientProvider).getTopVideos(
        metric: metric, days: 28, limit: 10);
  return raw
      .map((v) => ChannelVideoStats.fromJson(v as Map<String, dynamic>))
      .toList();
});

