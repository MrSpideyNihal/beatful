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
  const Profile({this.name = 'You', this.avatar = 0, this.loaded = false});

  final String name;
  final int avatar;
  final bool loaded;

  Profile copyWith({String? name, int? avatar, bool? loaded}) => Profile(
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    loaded: loaded ?? this.loaded,
  );
}

/// Trim, collapse runs of spaces, cap the length, and fall back to a default so
/// a seat badge is never blank.
String cleanName(String input, {String fallback = 'You'}) {
  final trimmed = input.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (trimmed.isEmpty) return fallback;
  return trimmed.length <= maxNameLength
      ? trimmed
      : trimmed.substring(0, maxNameLength);
}

class ProfileController extends Notifier<Profile> {
  static const _keyName = 'profile.name';
  static const _keyAvatar = 'profile.avatar';

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
    state = Profile(
      name: cleanName(prefs.getString(_keyName) ?? 'You'),
      avatar: (prefs.getInt(_keyAvatar) ?? 0).abs() % avatarCount(),
      loaded: true,
    );
  }

  Future<void> setName(String value) async {
    final name = cleanName(value);
    state = state.copyWith(name: name);
    (await _prefs())?.setString(_keyName, name);
  }

  Future<void> setAvatar(int id) async {
    final avatar = id.abs() % avatarCount();
    state = state.copyWith(avatar: avatar);
    (await _prefs())?.setInt(_keyAvatar, avatar);
  }
}

final profileProvider = NotifierProvider<ProfileController, Profile>(
  ProfileController.new,
);
