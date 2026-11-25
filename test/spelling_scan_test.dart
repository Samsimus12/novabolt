// US-spelling guard: fails if a user-facing string in lib/ (or a platform
// permission/label string) uses a UK spelling. Run:
//   flutter test test/spelling_scan_test.dart
//
// How it works: every single-line Dart string literal in lib/ that reads like
// text (has a space, or starts with a capital) is checked against the UK
// spellings below. Identifiers, persisted keys, asset paths and enum names are
// not text, so they are never looked at; if a text literal legitimately needs
// a UK word, add the exact literal to [_allowLiterals] or the file to
// [_allowFiles] with a reason.
//
// NOTE: the UK words are written split in two ('colo' r'ur') on purpose, so a
// find-and-replace spelling pass over the repo cannot rewrite this list and
// silently turn the guard into its opposite.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Exact string literals allowed to keep a UK word (persisted values, names).
const _allowLiterals = <String>{
  // 'some persisted value',
};

/// Whole files exempt from the scan, with the reason.
const _allowFiles = <String>{
  // 'lib/some/file.dart', // reason
};

/// Words that match a stem below but are valid US spellings.
const _ignore = {'ensure', 'ensures', 'ensured', 'mom', 'mum', 'toward', 'towards'};

final _uk = RegExp(
  r'\b(' +
      [
        r'colo' r'urs?|colo' r'ured|colo' r'urful|colo' r'urless',
        r'favo' r'urites?|favo' r'urs?',
        r'armo' r'ur\w*',
        r'cent' r'res?|cent' r'red',
        r'met' r'res?',
        r'defe' r'nce',
        r'lice' r'nce',
        r'gr' r'eys?',
        r'organi' r's(e|ed|es|ing|ation|ations)',
        r'recogni' r's(e|ed|es|ing|ation)',
        r'reali' r's(e|ed|es|ing|ation)',
        r'minimi' r's(e|ed|es|ing)',
        r'maximi' r's(e|ed|es|ing)',
        r'customi' r's(e|ed|es|ing|ation)',
        r'personali' r's(e|ed|es|ing|ation)',
        r'speciali' r's(e|ed|es|ing|ation)',
        r'stabili' r's(e|ed|es|ing|ation)',
        r'neutrali' r's(e|ed|es|ing|ation)',
        r'summari' r's(e|ed|es|ing)',
        r'initiali' r's(e|ed|es|ing|ation)',
        r'synchroni' r's(e|ed|es|ing|ation)',
        r'utili' r's(e|ed|es|ing|ation)',
        r'analy' r's(e|ed|es|ing)',
        r'behavi' r'ours?',
        r'hono' r'ur\w*',
        r'neighbo' r'ur\w*',
        r'labo' r'ur\w*',
        r'flavo' r'ur\w*',
        r'humo' r'ur\w*',
        r'rumo' r'ur\w*',
        r'vigo' r'ur\w*',
        r'rigo' r'ur\w*',
        r'thea' r'tre',
        r'fi' r'bre',
        r'li' r'tre',
        r'cali' r'bre',
        r'sa' r'bre',
        r'manoeu' r'vre\w*',
        r'catal' r'ogue',
        r'dial' r'ogue',
        r'progra' r'mme',
        r'ty' r're',
        r'che' r'que',
        r'jewel' r'lery',
        r'trave' r'll\w+',
        r'cance' r'll\w+',
        r'mode' r'll\w+',
        r'label' r'l\w+',
        r'fue' r'll\w+',
        r'signa' r'll\w+',
        r'leve' r'll\w+',
        r'prac' r'tise\w*',
        r'age' r'ing',
        r'whi' r'lst',
        r'lear' r'nt',
        r'sp' r'elt',
        r'bur' r'nt',
        r'drea' r'mt',
        r'judge' r'ment',
        r'arte' r'facts?',
        r'alumin' r'ium',
        r'sul' r'phur',
        r'mou' r'ld',
        r'plo' r'ugh',
        r'sto' r'rey',
        r'ke' r'rb',
        r'pyja' r'mas',
        r'scep' r'tic\w*',
        r'enr' r'ol',
        r'ful' r'fil',
        r'skil' r'ful',
        r'insta' r'lment',
      ].join('|') +
      r')\b',
  caseSensitive: false,
);

// A Dart single- or double-quoted literal on one line.
final _lit = RegExp(r'''(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")''');

bool _looksLikeText(String s) => s.contains(' ') || RegExp(r'^[A-Z][a-z]+').hasMatch(s);

List<String> scanDart(String path, List<String> lines) {
  final hits = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i].trimLeft();
    if (t.startsWith('//') || t.startsWith('import ') || t.startsWith('export ') || t.startsWith('part ')) continue;
    final code = lines[i].replaceFirst(RegExp(r'\s//.*$'), '');
    for (final m in _lit.allMatches(code)) {
      final s = m.group(1) ?? m.group(2) ?? '';
      if (!_looksLikeText(s) || _allowLiterals.contains(s)) continue;
      if (s.contains('/') && !s.contains(' ')) continue; // an asset path
      for (final w in _uk.allMatches(s)) {
        final word = w.group(0)!;
        if (_ignore.contains(word.toLowerCase())) continue;
        hits.add('$path:${i + 1}  "$word"  in  "$s"');
      }
    }
  }
  return hits;
}

void main() {
  test('the scanner itself recognises UK spellings and leaves US ones alone', () {
    final uk = scanDart('x.dart', ['final a = "Your ' 'colo' 'ur is great";', "final b = 'Ablative arm" "our';"]);
    expect(uk, hasLength(2));
    final us = scanDart('x.dart', ['final a = "Your color is great";', "final b = 'Ablative armor';", "final c = 'colo' 'ur_key';"]);
    expect(us, isEmpty, reason: 'US words and identifier-like keys are not flagged: $us');
    expect(scanDart('x.dart', ['// a comment about colo' 'ur']), isEmpty);
  });

  test('no UK spellings in user-facing strings under lib/', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (_allowFiles.contains(f.path)) continue;
      hits.addAll(scanDart(f.path, f.readAsLinesSync()));
    }
    expect(hits, isEmpty, reason: 'UK spellings found:\n${hits.join('\n')}');
  });

  test('no UK spellings in platform strings (Info.plist, Android manifest/strings, pubspec description)', () {
    final hits = <String>[];
    final files = [
      File('ios/Runner/Info.plist'),
      File('android/app/src/main/AndroidManifest.xml'),
      File('pubspec.yaml'),
      ...Directory('android/app/src/main/res')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('strings.xml')),
    ];
    for (final f in files) {
      if (!f.existsSync()) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // Only prose: skip keys/identifiers/URLs/comments.
        final l = lines[i].trim();
        if (l.startsWith('#') || l.startsWith('<!--')) continue;
        final text = l.replaceAll(RegExp(r'<[^>]+>'), ' ');
        if (!text.contains(' ')) continue;
        for (final w in _uk.allMatches(text)) {
          final word = w.group(0)!;
          if (_ignore.contains(word.toLowerCase())) continue;
          hits.add('${f.path}:${i + 1}  "$word"  in  "$l"');
        }
      }
    }
    expect(hits, isEmpty, reason: 'UK spellings found:\n${hits.join('\n')}');
  });
}
