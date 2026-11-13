import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import '../downloads/downloads.dart';

class LiveReports {
  /// Audio progress, in source milliseconds, between periodic reports.
  /// Playback uses the same cadence for durable personal-record uploads.
  static const progressIntervalMs = 10000;

  LiveReports(
    this.policy, {
    JellyfinClient Function(JellyfinSession)? clientFactory,
  }) : _clientFactory =
           clientFactory ??
           ((session) => JellyfinClient(
             session.scope.server,
             deviceId: 'bookfin-playback',
           )) {
    policy.addListener(_networkChanged);
  }
  final MediaPolicy policy;
  final JellyfinClient Function(JellyfinSession) _clientFactory;
  final _clients = <Object, JellyfinClient>{};
  Future<void> _pending = Future.value();
  _LiveSession? _live;
  JellyfinSession? _account;
  int _generation = 0;
  int _sequence = 0;
  bool _closed = false;
  DateTime? _retryAfter;
  bool get _allowed =>
      _account?.needsSignIn != true &&
      (policy.network == MediaNetwork.wifi ||
          policy.network == MediaNetwork.mobile);

  void _networkChanged() {
    _retryAfter = null;
    if (_allowed) return;
    _generation++;
    _live = null;
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }

  void observe(
    JellyfinSession session,
    SourceFile file,
    int milliseconds, {
    required bool playing,
    required double speed,
    bool completed = false,
  }) {
    if (_closed) return;
    if (_account?.credentialIdentity != session.credentialIdentity) {
      _account?.credentialChanges.removeListener(_networkChanged);
      _account = session;
      session.credentialChanges.addListener(_networkChanged);
    }
    if (!_allowed) {
      _networkChanged();
      return;
    }
    if (_retryAfter != null && DateTime.now().isBefore(_retryAfter!)) return;
    if (_live != null &&
        (_live!.account.scope.key != session.scope.key ||
            _live!.file.key != file.key ||
            _live!.account.credentialIdentity != session.credentialIdentity)) {
      stop();
    }
    if (_live == null) {
      if (!playing || completed) return;
      _live = _LiveSession(
        session,
        file,
        '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
        milliseconds,
        playing,
        speed,
      );
      _send('start', _live!);
      return;
    }
    final live = _live!;
    final shouldReport =
        (milliseconds - live.lastReportedMs).abs() >= progressIntervalMs ||
        live.playing != playing ||
        live.speed != speed;
    live.milliseconds = milliseconds;
    live.playing = playing;
    live.speed = speed;
    if (completed) {
      stop();
    } else if (shouldReport) {
      _send('progress', live);
    }
  }

  void _send(String event, _LiveSession live) {
    final generation = _generation;
    final clientKey = live.account.credentialIdentity;
    final client = _clients.putIfAbsent(
      clientKey,
      () => _clientFactory(live.account),
    );
    final body = <String, dynamic>{
      'ItemId': live.file.itemId,
      'MediaSourceId': live.file.mediaSourceId,
      'PlaySessionId': live.id,
      'PositionTicks': live.milliseconds * 10000,
      'IsPaused': !live.playing,
      'IsMuted': false,
      'CanSeek': true,
      'PlayMethod': 'DirectPlay',
    };
    live.lastReportedMs = live.milliseconds;
    _pending = _pending.then((_) async {
      if (_closed || generation != _generation || !_allowed || live.failed) {
        return;
      }
      if (event == 'stop') {
        if (!live.started) return;
      } else if (live.retired) {
        return;
      }
      if (event == 'start') live.started = true;
      try {
        await client.reportPlayback(live.account, event, body);
      } catch (error) {
        if (error is CatalogFailure &&
            error.kind == CatalogFailureKind.unauthorized) {
          live.account.rejectCredential();
        }
        live.failed = true;
        if (generation == _generation && _live?.id == live.id) {
          _live = null;
          _retryAfter = DateTime.now().add(const Duration(seconds: 30));
        }
      }
    });
  }

  void stop() {
    final live = _live;
    _live = null;
    if (live != null) {
      live.retired = true;
      if (_allowed && !_closed) _send('stop', live);
    }
  }

  Future<void> get idle => _pending;
  void close() {
    if (_closed) return;
    _closed = true;
    _live = null;
    _generation++;
    _account?.credentialChanges.removeListener(_networkChanged);
    policy.removeListener(_networkChanged);
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }
}

class _LiveSession {
  _LiveSession(
    this.account,
    this.file,
    this.id,
    this.milliseconds,
    this.playing,
    this.speed,
  ) : lastReportedMs = milliseconds;
  final JellyfinSession account;
  final SourceFile file;
  final String id;
  int milliseconds;
  int lastReportedMs;
  bool playing;
  double speed;
  bool retired = false;
  bool failed = false;
  bool started = false;
}
