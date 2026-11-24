/// Ground Assault level parsing (core engineer). Pure Dart. Format: README.md.
library;

import 'assault_types.dart';

const _terrainChars = {' ', '#', '=', '^'};
const _spawnChars = {'P', 'K', 'E', '*', 'S', 'L', 'R', 'g', 'r', 't', 'f', 'B'};

/// Parses [rows] (exactly [AssaultTuning.levelRows], all the same length) into
/// an [AssaultLevel]. Throws [ArgumentError] when the layout is invalid.
/// Spawns are returned in level order (left to right, then top to bottom) and
/// sit at the tile's bottom centre (x = col + 0.5, y = row + 1).
AssaultLevel parseAssaultLevel(String name, List<String> rows, {String theme = 'dusk'}) {
  if (rows.length != AssaultTuning.levelRows) {
    throw ArgumentError('Level "$name" must have exactly ${AssaultTuning.levelRows} rows, got ${rows.length}');
  }
  final width = rows.first.length;
  if (width == 0) throw ArgumentError('Level "$name" has empty rows');
  final tiles = <List<AssaultTile>>[];
  final found = <({int col, int row, String ch})>[];
  var starts = 0, exits = 0;
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    if (row.length != width) {
      throw ArgumentError('Level "$name" row $r has length ${row.length}, expected $width');
    }
    final out = <AssaultTile>[];
    for (var c = 0; c < width; c++) {
      final ch = row[c];
      switch (ch) {
        case '#':
          out.add(AssaultTile.solid);
        case '=':
          out.add(AssaultTile.platform);
        case '^':
          out.add(AssaultTile.spikes);
        default:
          if (!_terrainChars.contains(ch) && !_spawnChars.contains(ch)) {
            throw ArgumentError('Level "$name" has unknown character "$ch" at row $r, col $c');
          }
          out.add(AssaultTile.empty);
          if (_spawnChars.contains(ch)) {
            if (ch == 'P') starts++;
            if (ch == 'E') exits++;
            found.add((col: c, row: r, ch: ch));
          }
      }
    }
    tiles.add(List.unmodifiable(out));
  }
  if (starts != 1) throw ArgumentError('Level "$name" must have exactly one P (found $starts)');
  if (exits != 1) throw ArgumentError('Level "$name" must have exactly one E (found $exits)');
  found.sort((a, b) => a.col != b.col ? a.col.compareTo(b.col) : a.row.compareTo(b.row));
  return AssaultLevel(
    name: name,
    theme: theme,
    width: width,
    height: rows.length,
    tiles: List.unmodifiable(tiles),
    spawns: List.unmodifiable([for (final f in found) AssaultSpawn(f.ch, f.col + 0.5, f.row + 1.0)]),
  );
}
