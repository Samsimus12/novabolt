// Static checks on lib/audio/audio_manager.dart. The track lists are private
// consts, so we parse the source. Files only: no audio plugin is touched.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, List<String>> _lists() {
  final src = File('lib/audio/audio_manager.dart').readAsStringSync();
  final re = RegExp(r'static const (_\w+Tracks) = \[(.*?)\];', dotAll: true);
  final out = <String, List<String>>{};
  for (final m in re.allMatches(src)) {
    out[m.group(1)!] = RegExp(r"'([^']+)'")
        .allMatches(m.group(2)!)
        .map((t) => t.group(1)!)
        .toList();
  }
  return out;
}

void main() {
  final lists = _lists();

  test('all four playlists are found', () {
    expect(lists.keys,
        containsAll(['_menuTracks', '_gameTracks', '_arcadeTracks', '_bossTracks']));
    for (final e in lists.entries) {
      expect(e.value, isNotEmpty, reason: e.key);
    }
  });

  test('every listed track exists in assets/music/ and has no duplicates', () {
    final seen = <String>{};
    for (final e in lists.entries) {
      for (final t in e.value) {
        expect(t, startsWith('music/'), reason: '${e.key}: $t');
        final f = File('assets/$t');
        expect(f.existsSync(), isTrue, reason: 'missing ${f.path}');
        expect(f.lengthSync(), greaterThan(10000),
            reason: '${f.path} looks empty/truncated');
        expect(seen.add(t), isTrue, reason: '$t is in more than one list/twice');
      }
    }
  });

  test('assets/music/ is declared in pubspec and has no unused files', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^\s*-\s*assets/music/\s*$', multiLine: true).hasMatch(pub),
        isTrue,
        reason: 'pubspec must declare assets/music/');
    final used = lists.values.expand((l) => l).toSet();
    final onDisk = Directory('assets/music')
        .listSync()
        .whereType<File>()
        .map((f) => 'music/${f.uri.pathSegments.last}')
        .where((p) => !p.contains('.DS_Store'))
        .toSet();
    expect(onDisk.difference(used), isEmpty,
        reason: 'files in assets/music not in any playlist');
  });

  test('every list a random pick is made from has 2+ tracks (menu may have 1)',
      () {
    for (final k in ['_gameTracks', '_arcadeTracks', '_bossTracks']) {
      expect(lists[k]!.length, greaterThanOrEqualTo(2),
          reason: '$k needs 2+ so "never repeat" is possible');
    }
  });

  test('playArcade uses the arcade list via the no-repeat _pick', () {
    final src = File('lib/audio/audio_manager.dart').readAsStringSync();
    expect(src, contains('_pick(_arcadeTracks)'));
    expect(src, contains('where((t) => t != _lastTrack)'));
    expect(src, contains('_lastTrack = t'));
  });
}
