/// The one way this app talks to the server.
///
/// Nothing else in the app opens a socket. Every call here returns either parsed
/// JSON or an ApiFailure carrying a code the UI can switch on and a sentence a
/// player can read. Network faults are retried with a short backoff, and the
/// first minute after a cold start is reported as "connecting" rather than as an
/// error, because a free tier host takes that long to wake.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Set at build time: flutter build apk --dart-define=BEATFUL_API=https://...
/// The default is the deployed service. No secret ever lives in the client.
const String apiBase = String.fromEnvironment(
  'BEATFUL_API',
  defaultValue: 'https://beatful-api.onrender.com',
);

/// How long a sleeping host is given to wake up before its silence counts as a
/// real failure.
const Duration coldStartWindow = Duration(seconds: 75);

@immutable
class ApiFailure implements Exception {
  const ApiFailure(this.code, this.message, {this.status, this.waking = false});

  final String code;
  final String message;
  final int? status;

  /// True while the server may simply be waking up. The UI shows this as
  /// progress, not as a failure.
  final bool waking;

  bool get isNetwork => status == null;

  bool get isAuth => code == 'UNAUTHORIZED' || code == 'TOKEN_INVALID';

  @override
  String toString() => 'ApiFailure($code, $message)';
}

class Api {
  Api({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Guest session token. Set by the identity layer after /user/init.
  String? token;

  /// When the app first tried to reach the server, and whether it ever managed
  /// to. Together these decide whether silence means "waking" or "broken".
  DateTime? _firstTry;
  bool _reached = false;

  bool get everReached => _reached;

  void close() => _client.close();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$apiBase$path').replace(queryParameters: query);

  Map<String, String> _headers({bool json = false}) => {
    if (json) 'content-type': 'application/json',
    'accept': 'application/json',
    if (token != null) 'authorization': 'Bearer $token',
  };

  /// One request, with retries for the faults that are worth retrying.
  ///
  /// A 4xx is never retried: the server has decided. A dropped connection, a
  /// timeout, a 5xx or a 503 from a waking host is retried with a short backoff.
  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
    int retries = 2,
  }) async {
    _firstTry ??= DateTime.now();
    var attempt = 0;

    while (true) {
      attempt += 1;
      try {
        final request = http.Request(method, _uri(path, query))
          ..headers.addAll(_headers(json: body != null));
        if (body != null) request.body = jsonEncode(body);

        final streamed = await _client.send(request).timeout(timeout);
        final response = await http.Response.fromStream(
          streamed,
        ).timeout(timeout);
        _reached = true;

        final decoded = _decode(response);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return decoded;
        }
        final failure = _failureFrom(response, decoded);
        // A server that is starting up can answer 503 for a few seconds.
        if (response.statusCode >= 500 && attempt <= retries) {
          await Future<void>.delayed(_backoff(attempt));
          continue;
        }
        throw failure;
      } on ApiFailure {
        rethrow;
      } catch (error) {
        if (attempt <= retries) {
          await Future<void>.delayed(_backoff(attempt));
          continue;
        }
        throw _networkFailure(error);
      }
    }
  }

  Duration _backoff(int attempt) =>
      Duration(milliseconds: 300 * attempt * attempt);

  Map<String, Object?> _decode(http.Response response) {
    if (response.body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, Object?> ? decoded : {'data': decoded};
    } catch (_) {
      return const {};
    }
  }

  ApiFailure _failureFrom(http.Response response, Map<String, Object?> body) {
    final code = body['error'] is String
        ? body['error'] as String
        : 'SERVER_ERROR';
    final message = body['message'] is String
        ? body['message'] as String
        : 'The server could not do that.';
    return ApiFailure(code, message, status: response.statusCode);
  }

  /// No answer at all. Inside the cold start window this is reported as waking,
  /// so the first screen a player sees says connecting instead of failed.
  ApiFailure _networkFailure(Object error) {
    final since = DateTime.now().difference(_firstTry ?? DateTime.now());
    final waking = !_reached && since < coldStartWindow;
    if (waking) {
      return const ApiFailure(
        'WAKING',
        'Connecting to the game server. This can take up to a minute the first '
            'time.',
        waking: true,
      );
    }
    if (error is TimeoutException) {
      return const ApiFailure('TIMEOUT', 'The server took too long to answer.');
    }
    // A dropped connection, a refused port, a DNS miss: http wraps all of them
    // in ClientException, including the socket faults, so this covers the lot
    // without importing dart:io, which would stop the app compiling for web.
    if (error is http.ClientException) {
      return const ApiFailure(
        'OFFLINE',
        'No connection. Check your internet and try again.',
      );
    }
    debugPrint('api fault: $error');
    return const ApiFailure('OFFLINE', 'Could not reach the game server.');
  }

  /* ------------------------------------------------------------------ meta */

  Future<Map<String, Object?>> meta() => _send('GET', '/meta');

  Future<Map<String, Object?>> health() =>
      _send('GET', '/health', timeout: const Duration(seconds: 12));

  /* -------------------------------------------------------------- identity */

  /// Called on every cold start with the guest id stored on the device. The
  /// server returns the same account for the same id, so this never duplicates.
  Future<Map<String, Object?>> userInit({
    required String guestId,
    String? displayName,
    int? avatarId,
  }) => _send(
    'POST',
    '/user/init',
    body: {
      'guestId': guestId,
      'displayName': ?displayName,
      'avatarId': ?avatarId,
    },
    // The wake up call. Long timeout, more tries, because this is the request
    // that pays the cold start cost for the whole session.
    timeout: coldStartWindow,
    retries: 3,
  );

  Future<Map<String, Object?>> me() => _send('GET', '/user/me');

  Future<Map<String, Object?>> setName(String displayName) =>
      _send('PATCH', '/user/name', body: {'displayName': displayName});

  Future<Map<String, Object?>> setAvatar(int avatarId) =>
      _send('PATCH', '/user/avatar', body: {'avatarId': avatarId});

  Future<Map<String, Object?>> transactions() =>
      _send('GET', '/user/transactions');

  /* ----------------------------------------------------------------- rooms */

  Future<Map<String, Object?>> createRoom(Map<String, Object?> settings) =>
      _send('POST', '/room/create', body: {'settings': settings});

  Future<Map<String, Object?>> joinRoom(String code) =>
      _send('POST', '/room/join', body: {'code': code});

  Future<Map<String, Object?>> lookupRoom(String code) =>
      _send('GET', '/room/lookup', query: {'code': code});

  Future<Map<String, Object?>> roomSnapshot(String roomId) =>
      _send('GET', '/room/$roomId');

  /// The long poll. Held open by the server for its poll window, so the timeout
  /// here is deliberately longer than that window and it is never retried: the
  /// caller loops instead.
  Future<Map<String, Object?>> pollRoom(String roomId, int since) => _send(
    'GET',
    '/room/$roomId/state',
    query: {'since': '$since'},
    timeout: const Duration(seconds: 40),
    retries: 0,
  );

  Future<Map<String, Object?>> play(String roomId, String card) =>
      _send('POST', '/room/$roomId/play', body: {'card': card}, retries: 1);

  Future<Map<String, Object?>> pass(String roomId) =>
      _send('POST', '/room/$roomId/pass', body: const {}, retries: 1);

  Future<Map<String, Object?>> startGame(String roomId) =>
      _send('POST', '/room/$roomId/start', body: const {});

  Future<Map<String, Object?>> updateSettings(
    String roomId,
    Map<String, Object?> patch,
  ) => _send('POST', '/room/$roomId/settings', body: {'settings': patch});

  Future<Map<String, Object?>> setReady(String roomId, bool ready) =>
      _send('POST', '/room/$roomId/ready', body: {'ready': ready});

  Future<Map<String, Object?>> kick(String roomId, String userId) =>
      _send('POST', '/room/$roomId/kick', body: {'userId': userId});

  Future<Map<String, Object?>> setLocked(String roomId, bool locked) =>
      _send('POST', '/room/$roomId/lock', body: {'locked': locked});

  Future<Map<String, Object?>> addBot(String roomId, String difficulty) =>
      _send('POST', '/room/$roomId/bot', body: {'difficulty': difficulty});

  Future<Map<String, Object?>> botTakeover(String roomId, int seatIndex) =>
      _send('POST', '/room/$roomId/bot-takeover', body: {'seatIndex': seatIndex});

  Future<Map<String, Object?>> leaveRoom(String roomId) =>
      _send('POST', '/room/$roomId/leave', body: const {});

  /* --------------------------------------------------------------- economy */

  Future<Map<String, Object?>> shopItems() => _send('GET', '/shop/items');

  Future<Map<String, Object?>> purchase(String itemId) =>
      _send('POST', '/shop/purchase', body: {'itemId': itemId});

  Future<Map<String, Object?>> equip(String itemId) =>
      _send('POST', '/shop/equip', body: {'itemId': itemId});

  Future<Map<String, Object?>> adsStatus() => _send('GET', '/ads/status');

  Future<Map<String, Object?>> claimAdReward() =>
      _send('POST', '/ads/reward', body: const {});
}

final apiProvider = Provider<Api>((ref) {
  final api = Api();
  ref.onDispose(api.close);
  return api;
});
