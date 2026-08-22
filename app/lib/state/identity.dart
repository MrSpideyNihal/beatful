/// Guest identity and the coin balance that hangs off it.
///
/// The device makes a UUID once and keeps it in secure storage. Every cold start
/// posts that id to /user/init, which returns the same account and a fresh token.
/// Nothing here blocks solo play: if the server never answers, the app still runs
/// offline and only the online parts report that they are unavailable.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/account.dart';
import '../services/api.dart';
import 'profile.dart';

const String _guestKey = 'beatful.guestId';

enum LinkStatus {
  /// Nothing tried yet.
  idle,

  /// A request is in flight, or the free tier host is still waking up.
  connecting,

  /// Signed in as a guest, online features available.
  ready,

  /// Tried and could not reach the server. Solo play is unaffected.
  offline,
}

@immutable
class Identity {
  const Identity({
    this.status = LinkStatus.idle,
    this.account,
    this.guestId,
    this.message,
    this.waking = false,
  });

  final LinkStatus status;
  final Account? account;
  final String? guestId;

  /// Why the last attempt failed, in words a player can read.
  final String? message;

  /// True while silence is still explained by a sleeping server.
  final bool waking;

  bool get isReady => status == LinkStatus.ready && account != null;

  int get coins => account?.coins ?? 0;

  Identity copyWith({
    LinkStatus? status,
    Account? account,
    String? guestId,
    String? message,
    bool clearMessage = false,
    bool? waking,
  }) => Identity(
    status: status ?? this.status,
    account: account ?? this.account,
    guestId: guestId ?? this.guestId,
    message: clearMessage ? null : (message ?? this.message),
    waking: waking ?? this.waking,
  );
}

/// Reads and writes the one persistent secret this app has: the guest id.
///
/// Secure storage is the primary home. Some devices refuse it, so a plain
/// preference is the fallback rather than losing the account on every launch.
class GuestIdStore {
  const GuestIdStore();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String> loadOrCreate() async {
    final existing = await _read();
    if (existing != null && existing.length >= 8) return existing;
    final fresh = const Uuid().v4();
    await _write(fresh);
    return fresh;
  }

  Future<String?> _read() async {
    try {
      final value = await _secure.read(key: _guestKey);
      if (value != null && value.isNotEmpty) return value;
    } catch (error) {
      debugPrint('secure storage read failed: $error');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_guestKey);
    } catch (error) {
      debugPrint('guest id fallback read failed: $error');
      return null;
    }
  }

  Future<void> _write(String value) async {
    var stored = false;
    try {
      await _secure.write(key: _guestKey, value: value);
      stored = true;
    } catch (error) {
      debugPrint('secure storage write failed: $error');
    }
    if (stored) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_guestKey, value);
    } catch (error) {
      debugPrint('guest id fallback write failed: $error');
    }
  }
}

class IdentityController extends Notifier<Identity> {
  Future<void>? _inFlight;

  @override
  Identity build() {
    // Kicked off in the background: the home screen is usable immediately and
    // shows a quiet connecting chip while this runs.
    Future.microtask(connect);
    return const Identity(status: LinkStatus.connecting, waking: true);
  }

  Api get _api => ref.read(apiProvider);

  /// Signs in, or retries after a failure. Concurrent calls share one request.
  Future<void> connect() {
    return _inFlight ??= _connect().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _connect() async {
    state = state.copyWith(
      status: LinkStatus.connecting,
      clearMessage: true,
      waking: !_api.everReached,
    );
    try {
      final guestId = await const GuestIdStore().loadOrCreate();
      final profile = ref.read(profileProvider);
      final response = await _api.userInit(
        guestId: guestId,
        // Only sent as a starting point. The server keeps whatever name the
        // account already has, so a rename is never undone by a relaunch.
        displayName: profile.loaded ? profile.name : null,
        avatarId: profile.loaded ? profile.avatar : null,
      );
      final token = response['token'];
      if (token is! String || token.isEmpty) {
        throw const ApiFailure('SERVER_ERROR', 'The server did not sign us in.');
      }
      _api.token = token;
      final account = Account.fromJson(
        response['user'] is Map
            ? Map<String, Object?>.from(response['user'] as Map)
            : const {},
      );
      state = Identity(
        status: LinkStatus.ready,
        account: account,
        guestId: guestId,
      );
      // First launch adopts the name the server suggested; after that the local
      // name wins and is pushed up instead.
      await _reconcileProfile(account, isNew: response['isNewUser'] == true);
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: failure.waking ? LinkStatus.connecting : LinkStatus.offline,
        message: failure.message,
        waking: failure.waking,
      );
    } catch (error) {
      debugPrint('sign in failed: $error');
      state = state.copyWith(
        status: LinkStatus.offline,
        message: 'Could not reach the game server. You can still play offline.',
        waking: false,
      );
    }
  }

  Future<void> _reconcileProfile(Account account, {required bool isNew}) async {
    final profile = ref.read(profileProvider);
    if (isNew && !profile.loaded) {
      await ref.read(profileProvider.notifier).setName(account.displayName);
      return;
    }
    if (profile.loaded && profile.name != account.displayName) {
      await pushName(profile.name);
    }
    if (profile.loaded && profile.avatar != account.avatarId) {
      await pushAvatar(profile.avatar);
    }
  }

  /// Replaces the local copy from any response that carries a user object, which
  /// is how a coin balance stays honest without polling for it.
  void adopt(Object? userJson) {
    if (userJson is! Map) return;
    state = state.copyWith(
      account: Account.fromJson(Map<String, Object?>.from(userJson)),
      status: LinkStatus.ready,
      clearMessage: true,
      waking: false,
    );
  }

  /// Sends the display name up. Failure is not surfaced: the local name has
  /// already changed and the next launch retries.
  Future<void> pushName(String name) async {
    if (!state.isReady) return;
    try {
      adopt((await _api.setName(name))['user']);
    } on ApiFailure catch (failure) {
      debugPrint('name sync deferred: ${failure.code}');
    }
  }

  Future<void> pushAvatar(int avatarId) async {
    if (!state.isReady) return;
    try {
      adopt((await _api.setAvatar(avatarId))['user']);
    } on ApiFailure catch (failure) {
      debugPrint('avatar sync deferred: ${failure.code}');
    }
  }

  /// Award coins locally (e.g. winning a solo match or offline reward).
  void awardCoins(int amount) {
    if (amount <= 0) return;
    final current = state.account;
    if (current != null) {
      state = state.copyWith(
        account: current.copyWith(coins: current.coins + amount),
      );
    }
  }

  /// Pulls a fresh balance, used when returning to Home from a match.
  Future<void> refresh() async {
    if (!state.isReady) return;
    try {
      adopt((await _api.me())['user']);
    } on ApiFailure catch (failure) {
      debugPrint('balance refresh deferred: ${failure.code}');
    }
  }
}

final identityProvider = NotifierProvider<IdentityController, Identity>(
  IdentityController.new,
);

/// The coin balance on its own, so a coin pill rebuilds without watching the
/// whole identity object.
final coinsProvider = Provider<int>(
  (ref) => ref.watch(identityProvider).coins,
);
