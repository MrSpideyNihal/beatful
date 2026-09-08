/// The player's display name and avatar.
///
/// Stored locally so a first time player is never asked to sign up. The guest id
/// that ties this to a server account is handled separately by the identity
/// layer; this is only what other players see.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/avatar.dart';

const int maxNameLength = 14;

@immutable
class Profile {
  const Profile({
    this.name = 'Player',
    this.avatar = 0,
    this.loaded = false,
    this.hasCustomName = false,
  });

  final String name;
  final int avatar;
  final bool loaded;
  final bool hasCustomName;

  Profile copyWith({
    String? name,
    int? avatar,
    bool? loaded,
    bool? hasCustomName,
  }) => Profile(
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    loaded: loaded ?? this.loaded,
    hasCustomName: hasCustomName ?? this.hasCustomName,
  );
}

/// Trim, collapse runs of spaces, cap the length, and fall back to a default so
/// a seat badge is never blank or generically 'You'.
String cleanName(String input, {String fallback = 'Player'}) {
  final trimmed = input.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (trimmed.isEmpty) return fallback;
  return trimmed.length <= maxNameLength
      ? trimmed
      : trimmed.substring(0, maxNameLength);
}

class ProfileController extends Notifier<Profile> {
  static const _keyName = 'profile.name';
  static const _keyAvatar = 'profile.avatar';
  static const _keyHasCustomName = 'profile.has_custom_name';

  @override
  Profile build() {
    Future.microtask(_load);
    return const Profile();
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint('profile unavailable: $error');
      return null;
    }
  }

  Future<void> _load() async {
    final prefs = await _prefs();
    if (prefs == null) {
      state = state.copyWith(loaded: true);
      return;
    }
    final storedName = prefs.getString(_keyName);
    final hasCustom = prefs.getBool(_keyHasCustomName) ??
        (storedName != null &&
            storedName.trim().isNotEmpty &&
            storedName.trim().toLowerCase() != 'you');

    state = Profile(
      name: cleanName(storedName ?? 'Player'),
      avatar: (prefs.getInt(_keyAvatar) ?? 0).abs() % avatarCount(),
      loaded: true,
      hasCustomName: hasCustom,
    );
  }

  Future<void> setName(String value) async {
    final name = cleanName(value);
    state = state.copyWith(name: name, hasCustomName: true);
    final prefs = await _prefs();
    await prefs?.setString(_keyName, name);
    await prefs?.setBool(_keyHasCustomName, true);
  }

  Future<void> setAvatar(int id) async {
    final avatar = id.abs() % avatarCount();
    state = state.copyWith(avatar: avatar);
    (await _prefs())?.setInt(_keyAvatar, avatar);
  }

  Future<void> setHasCustomName(bool value) async {
    state = state.copyWith(hasCustomName: value);
    (await _prefs())?.setBool(_keyHasCustomName, value);
  }
}

final profileProvider = NotifierProvider<ProfileController, Profile>(
  ProfileController.new,
);
