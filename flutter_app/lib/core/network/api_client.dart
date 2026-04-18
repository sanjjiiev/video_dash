import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _baseUrl     = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost/api/v1');
const String _accessKey   = 'hub_access_token';
const String _refreshKey  = 'hub_refresh_token';

// ── Shared Preferences singleton provider ─────────────────────────────────────
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in ProviderScope overrides');
});

// ── Dio instance provider ─────────────────────────────────────────────────────
final apiClientProvider = Provider<ApiClient>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ApiClient(prefs);
});

class ApiClient {
  late final Dio _dio;
  final SharedPreferences _prefs;

  ApiClient(this._prefs) {
    _dio = Dio(BaseOptions(
      baseUrl:         _baseUrl,
      connectTimeout:  const Duration(seconds: 10),
      receiveTimeout:  const Duration(seconds: 30),
      headers: {
        'Accept':       'application/json',
        'Content-Type': 'application/json',
      },
    ));

    _dio.interceptors.add(_AuthInterceptor(_prefs, _dio));
    _dio.interceptors.add(LogInterceptor(
      requestBody:  false,
      responseBody: false,
      logPrint: (o) => debugPrint('[API] $o'),
    ));
  }

  // ── Auth ───────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> login(String email, String password) async {
    final resp = await _dio.post('/auth/login', data: {'email': email, 'password': password});
    final data = resp.data as Map<String, dynamic>;
    await _saveTokens(data['accessToken'] as String);
    return data;
  }

  Future<Map<String, dynamic>> register(String email, String password) async {
    final resp = await _dio.post('/auth/register', data: {'email': email, 'password': password});
    return resp.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try { await _dio.post('/auth/logout'); } catch (_) {}
    await _prefs.remove(_accessKey);
  }

  Future<Map<String, dynamic>> getMe() async {
    final resp = await _dio.get('/auth/me');
    return resp.data as Map<String, dynamic>;
  }

  // ── Videos ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getVideos({int page = 1, int limit = 20, String? search}) async {
    final resp = await _dio.get('/videos', queryParameters: {
      'page': page, 'limit': limit,
      if (search != null) 'search': search,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getVideo(String id) async {
    final resp = await _dio.get('/videos/$id');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getStreamUrl(String videoId) async {
    final resp = await _dio.get('/videos/$videoId/stream');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> presignUpload({required String title, String? description}) async {
    final resp = await _dio.post('/videos/presign', data: {
      'title': title,
      if (description != null) 'description': description,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<void> confirmUpload(String videoId) async {
    await _dio.post('/videos/$videoId/confirm');
  }

  Future<void> likeVideo(String videoId) async {
    await _dio.post('/videos/$videoId/like');
  }

  Future<void> dislikeVideo(String videoId) async {
    await _dio.post('/videos/$videoId/dislike');
  }

  // ── Comments ─────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getComments(String videoId, {int page = 1}) async {
    final resp = await _dio.get('/videos/$videoId/comments', queryParameters: {'page': page});
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postComment(
    String videoId,
    String text, {
    String? parentId,
  }) async {
    final resp = await _dio.post('/videos/$videoId/comments', data: {
      'body': text,
      if (parentId != null) 'parent_id': parentId,
    });
    return resp.data as Map<String, dynamic>;
  }

  // ── Telemetry ─────────────────────────────────────────────────────────
  Future<void> reportWatchEvent(String videoId, int secondsWatched) async {
    try {
      await _dio.post('/analytics/record-watch',
          data: {'video_id': videoId, 'seconds_watched': secondsWatched});
    } catch (_) {} // fire and forget
  }

  // ── Subscriptions ─────────────────────────────────────────────────────
  Future<List<dynamic>> getSubscriptions() async {
    final resp = await _dio.get('/subscriptions');
    return (resp.data as Map<String, dynamic>)['subscriptions'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getSubscriptionFeed({int page = 1}) async {
    final resp = await _dio.get('/subscriptions/feed',
        queryParameters: {'page': page, 'limit': 20});
    return resp.data as Map<String, dynamic>;
  }

  Future<void> subscribe(String channelId, {bool notifyNew = true}) async {
    await _dio.post('/subscriptions/$channelId',
        data: {'notify_new': notifyNew});
  }

  Future<void> unsubscribe(String channelId) async {
    await _dio.delete('/subscriptions/$channelId');
  }

  Future<bool> getSubscriptionStatus(String channelId) async {
    try {
      final resp = await _dio.get('/subscriptions/status/$channelId');
      return (resp.data as Map<String, dynamic>)['subscribed'] as bool? ?? false;
    } catch (_) { return false; }
  }

  Future<void> toggleSubscriptionNotify(String channelId,
      {required bool notifyNew}) async {
    await _dio.patch('/subscriptions/$channelId',
        data: {'notify_new': notifyNew});
  }

  // ── Analytics ─────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getAnalyticsOverview() async {
    final resp = await _dio.get('/analytics/overview');
    return (resp.data as Map<String, dynamic>)['overview']
        as Map<String, dynamic>;
  }

  Future<List<dynamic>> getAnalyticsTimeseries({int days = 28}) async {
    final resp = await _dio.get('/analytics/timeseries',
        queryParameters: {'days': days});
    return (resp.data as Map<String, dynamic>)['timeseries'] as List<dynamic>;
  }

  Future<List<dynamic>> getTopVideos(
      {int days = 28, String metric = 'views', int limit = 10}) async {
    final resp = await _dio.get('/analytics/top-videos', queryParameters: {
      'days': days, 'metric': metric, 'limit': limit,
    });
    return (resp.data as Map<String, dynamic>)['top_videos'] as List<dynamic>;
  }

  // ── Channel / Owner videos ─────────────────────────────────────────────
  Future<Map<String, dynamic>> getChannelVideos(String ownerId,
      {int page = 1, int limit = 20}) async {
    final resp = await _dio.get('/videos', queryParameters: {
      'owner': ownerId, 'page': page, 'limit': limit,
    });
    return resp.data as Map<String, dynamic>;
  }

  // ── Playlists ──────────────────────────────────────────────────────────
  Future<List<dynamic>> getPlaylists() async {
    final resp = await _dio.get('/playlists');
    return (resp.data as Map<String, dynamic>)['playlists'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> createPlaylist(
      String title, {String visibility = 'private'}) async {
    final resp = await _dio.post('/playlists',
        data: {'title': title, 'visibility': visibility});
    return (resp.data as Map<String, dynamic>)['playlist']
        as Map<String, dynamic>;
  }

  Future<void> addToPlaylist(String playlistId, String videoId) async {
    await _dio.post('/playlists/$playlistId/items',
        data: {'video_id': videoId});
  }

  Future<void> removeFromPlaylist(String playlistId, String videoId) async {
    await _dio.delete('/playlists/$playlistId/items/$videoId');
  }

  // ── Watch Later ────────────────────────────────────────────────────────
  Future<List<dynamic>> getWatchLater() async {
    final resp = await _dio.get('/playlists/watch-later');
    return (resp.data as Map<String, dynamic>)['videos'] as List<dynamic>;
  }

  Future<void> saveWatchLater(String videoId) async {
    await _dio.post('/playlists/watch-later/$videoId');
  }

  Future<void> removeWatchLater(String videoId) async {
    await _dio.delete('/playlists/watch-later/$videoId');
  }

  // ── Notifications ──────────────────────────────────────────────────────
  Future<List<dynamic>> getNotifications() async {
    final resp = await _dio.get('/analytics/notifications');
    return (resp.data as Map<String, dynamic>)['notifications']
        as List<dynamic>;
  }

  Future<void> markNotificationRead(String id) async {
    try { await _dio.patch('/analytics/notifications/$id/read'); } catch (_) {}
  }

  Future<void> markAllNotificationsRead() async {
    try { await _dio.post('/analytics/notifications/read-all'); } catch (_) {}
  }

  Future<void> registerPushToken(
      {required String token, required String platform}) async {
    await _dio.post('/analytics/push-token',
        data: {'token': token, 'platform': platform});
  }

  // ── Token management ──────────────────────────────────────────────────
  Future<void> _saveTokens(String access) async {
    await _prefs.setString(_accessKey, access);
  }

  String? get accessToken => _prefs.getString(_accessKey);
  bool    get isLoggedIn  => accessToken != null;
}

// ── Auth interceptor — auto-attach token + refresh on 401 ─────────────────────
class _AuthInterceptor extends Interceptor {
  final SharedPreferences _prefs;
  final Dio               _dio;
  bool _isRefreshing = false;

  _AuthInterceptor(this._prefs, this._dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _prefs.getString(_accessKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        // Try to refresh via the /auth/refresh cookie endpoint
        final refreshDio = Dio(BaseOptions(baseUrl: _baseUrl));
        final resp = await refreshDio.post('/auth/refresh');
        final newToken = resp.data['accessToken'] as String;
        await _prefs.setString(_accessKey, newToken);

        // Retry the original request with the new token
        err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
        final retry = await _dio.fetch(err.requestOptions);
        handler.resolve(retry);
      } catch (_) {
        await _prefs.remove(_accessKey);
        handler.next(err);
      } finally {
        _isRefreshing = false;
      }
    } else {
      handler.next(err);
    }
  }
}

// silence flutter debugPrint import warning
void debugPrint(String? s, {int? wrapWidth}) {}
