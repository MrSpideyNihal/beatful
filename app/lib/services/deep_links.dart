/// Deep links: beatful://join/ABC123.
///
/// A link has one job, which is to put somebody in a room. That means the code
/// has to survive a cold start, where the link arrives before there is an account
/// to join with, so an incoming code is held until the identity is ready and then
/// used once.
///
/// Nothing here decides whether the room can be joined. The code goes to the
/// server and the server answers, same as a typed code.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/room_code.dart';

/// A room code that arrived from outside the app and has not been acted on yet.
@immutable
class PendingLink {
  const PendingLink({required this.code, required this.at});

  final String code;

  /// Only used to tell two arrivals of the same code apart, so tapping the same
  /// link twice opens the room twice.
  final int at;

  @override
  bool operator ==(Object other) =>
      other is PendingLink && other.code == code && other.at == at;

  @override
  int get hashCode => Object.hash(code, at);
}

class DeepLinks extends Notifier<PendingLink?> {
  StreamSubscription<Uri>? _sub;
  int _counter = 0;

  @override
  PendingLink? build() {
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    unawaited(_listen());
    return null;
  }

  Future<void> _listen() async {
    final links = AppLinks();
    try {
      // The link that launched the app, if it was launched by one.
      offer(await links.getInitialLink());
    } catch (error) {
      // A platform without link support is not a problem worth telling anybody
      // about: typing the code still works.
      debugPrint('initial link unavailable: $error');
    }
    try {
      _sub = links.uriLinkStream.listen(
        offer,
        onError: (Object error) => debugPrint('link stream fault: $error'),
      );
    } catch (error) {
      debugPrint('link stream unavailable: $error');
    }
  }

  /// Takes a link and keeps the code in it, if there is one. Also the way tests
  /// and the paste box feed a link in without a platform channel.
  void offer(Uri? uri) {
    final code = roomCodeFromLink(uri);
    if (code == null) return;
    _counter += 1;
    state = PendingLink(code: code, at: _counter);
  }

  /// Called once the code has been acted on, so a rebuild does not join again.
  void taken() => state = null;
}

final deepLinkProvider = NotifierProvider<DeepLinks, PendingLink?>(
  DeepLinks.new,
);
