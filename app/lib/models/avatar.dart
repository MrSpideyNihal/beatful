/// Preset avatars.
///
/// There are no avatar images in the bundle, so an avatar is an icon plus a
/// colour, drawn at any size. Each one has a name so the picker can label it and
/// a screen reader can read it out, which also keeps the choice from resting on
/// colour alone.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AvatarStyle {
  const AvatarStyle(this.name, this.icon, this.colour);

  final String name;
  final IconData icon;
  final Color colour;
}

const List<AvatarStyle> avatarStyles = [
  AvatarStyle('Sun', Icons.wb_sunny_rounded, Palette.amber),
  AvatarStyle('Leaf', Icons.eco_rounded, Palette.feltLight),
  AvatarStyle('Cat', Icons.pets_rounded, Palette.violet),
  AvatarStyle('Rocket', Icons.rocket_launch_rounded, Palette.blue),
  AvatarStyle('Star', Icons.star_rounded, Palette.amberDeep),
  AvatarStyle('Music', Icons.music_note_rounded, Palette.rose),
  AvatarStyle('Bike', Icons.pedal_bike_rounded, Palette.teal),
  AvatarStyle('Tea', Icons.local_cafe_rounded, Palette.coralDeep),
  AvatarStyle('Flower', Icons.local_florist_rounded, Palette.coral),
  AvatarStyle('Moon', Icons.nightlight_round, Palette.blueDeep),
  AvatarStyle('Boat', Icons.sailing_rounded, Palette.feltDark),
  AvatarStyle('Medal', Icons.military_tech_rounded, Palette.violet),
];

/// Any stored id is folded into range, so an old or hand edited value can never
/// crash the picker or a seat badge.
AvatarStyle avatarStyle(int id) => avatarStyles[id.abs() % avatarStyles.length];

int avatarCount() => avatarStyles.length;
