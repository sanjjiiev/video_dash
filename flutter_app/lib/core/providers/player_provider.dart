import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

/// Global player state shared across the entire app.
/// Enables:
///  - Mini player at the bottom of any screen when navigating away from player
///  - Persistent playback session state (video ID, position, playing state)
///  - The MiniPlayer widget reads from / writes to this provider

class PlayerState {
  final String?  videoId;
  final String?  videoTitle;
  final String?  channelName;
  final String?  thumbnailUrl;
  final String?  streamUrl;
  final String?  accessToken;
  final bool     isPlaying;
  final bool     isVisible;   // is the mini player visible?
  final Duration position;
  final Duration duration;

  const PlayerState({
    this.videoId,
    this.videoTitle,
    this.channelName,
    this.thumbnailUrl,
    this.streamUrl,
    this.accessToken,
    this.isPlaying   = false,
    this.isVisible   = false,
    this.position    = Duration.zero,
    this.duration    = Duration.zero,
  });

  bool get hasVideo => videoId != null;

  PlayerState copyWith({
    String?   videoId,
    String?   videoTitle,
    String?   channelName,
    String?   thumbnailUrl,
    String?   streamUrl,
    String?   accessToken,
    bool?     isPlaying,
    bool?     isVisible,
    Duration? position,
    Duration? duration,
  }) => PlayerState(
    videoId:      videoId      ?? this.videoId,
    videoTitle:   videoTitle   ?? this.videoTitle,
    channelName:  channelName  ?? this.channelName,
    thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    streamUrl:    streamUrl    ?? this.streamUrl,
    accessToken:  accessToken  ?? this.accessToken,
    isPlaying:    isPlaying    ?? this.isPlaying,
    isVisible:    isVisible    ?? this.isVisible,
    position:     position     ?? this.position,
    duration:     duration     ?? this.duration,
  );
}

class GlobalPlayerNotifier extends StateNotifier<PlayerState> {
  late final Player _player;

  GlobalPlayerNotifier() : super(const PlayerState()) {
    _player = Player(
      configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
    );
    _player.stream.playing.listen((v)   => state = state.copyWith(isPlaying: v));
    _player.stream.position.listen((v)  => state = state.copyWith(position: v));
    _player.stream.duration.listen((v)  => state = state.copyWith(duration: v));
  }

  Player get player => _player;

  /// Load a new video into the global player (used when transitioning to mini player)
  void load({
    required String videoId,
    required String title,
    String? channelName,
    String? thumbnailUrl,
    required String streamUrl,
    String? accessToken,
    Duration startPosition = Duration.zero,
  }) {
    state = PlayerState(
      videoId:      videoId,
      videoTitle:   title,
      channelName:  channelName,
      thumbnailUrl: thumbnailUrl,
      streamUrl:    streamUrl,
      accessToken:  accessToken,
      isPlaying:    true,
      isVisible:    true,
    );

    _player.open(
      Media(streamUrl, httpHeaders: {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      }),
      play: true,
    );

    if (startPosition > Duration.zero) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _player.seek(startPosition);
      });
    }
  }

  void play()  => _player.play();
  void pause() => _player.pause();
  void toggle() => state.isPlaying ? _player.pause() : _player.play();

  void seekTo(Duration pos) => _player.seek(pos);

  void showMiniPlayer()  => state = state.copyWith(isVisible: true);
  void hideMiniPlayer()  => state = state.copyWith(isVisible: false);

  void dismiss() {
    _player.stop();
    state = const PlayerState();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

final globalPlayerProvider =
    StateNotifierProvider<GlobalPlayerNotifier, PlayerState>(
  (ref) => GlobalPlayerNotifier(),
);
