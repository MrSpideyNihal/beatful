/// Room codes, kept in step with the server on purpose.
///
/// The alphabet leaves out O, 0, I, 1 and L, so no glyph a player might misread
/// ever appears in a code. That means an ambiguous character is always a typo and
/// never needs guessing at, which is why this file can reject it outright instead
/// of trying to correct it.
library;

const String roomCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const int roomCodeLength = 6;

const String roomLinkScheme = 'beatful';

/// Uppercases and drops spaces, dashes and anything else people type out of
/// habit, so "abc-def" and "ABC DEF" both reach the server as ABCDEF.
String normaliseRoomCode(String? input) {
  if (input == null) return '';
  return input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
}

bool isValidRoomCode(String code) {
  if (code.length != roomCodeLength) return false;
  for (final unit in code.codeUnits) {
    if (!roomCodeAlphabet.codeUnits.contains(unit)) return false;
  }
  return true;
}

/// The characters in a code that could not possibly belong to one. Used to tell a
/// player exactly which letter to look at again rather than just refusing.
String confusedCharacters(String code) {
  final found = <String>[];
  for (final char in code.split('')) {
    if (!roomCodeAlphabet.contains(char) && !found.contains(char)) {
      found.add(char);
    }
  }
  return found.join(', ');
}

String roomLinkFor(String code) => '$roomLinkScheme://join/$code';

/// Pulls a code out of beatful://join/ABCDEF, and out of an https link ending in
/// the same path, so a code shared either way still opens the room. Returns null
/// when there is no usable code, which the caller shows as a normal join screen.
String? roomCodeFromLink(Uri? uri) {
  if (uri == null) return null;
  final segments = [
    for (final segment in uri.pathSegments)
      if (segment.isNotEmpty) segment,
  ];
  // beatful://join/ABCDEF parses with join as the host on some platforms and as
  // the first path segment on others, so both shapes are accepted.
  final candidates = <String>[
    if (segments.isNotEmpty) segments.last,
    if (uri.host.isNotEmpty) uri.host,
    ?uri.queryParameters['code'],
  ];
  for (final candidate in candidates) {
    final code = normaliseRoomCode(candidate);
    if (isValidRoomCode(code)) return code;
  }
  return null;
}
