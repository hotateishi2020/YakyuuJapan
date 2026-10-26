import 'dart:io';
import 'package:html/parser.dart';
import 'package:test/test.dart';
import '../app/GameBench.dart';
void main() {
  test('extracts game-day bench names by team and role from real markup', () {
    final rows = parseGameBench(parse(File('test/fixtures/game_bench.html').readAsStringSync()), 5, 6);
    expect(rows, isNotEmpty);
    expect(rows.where((r)=>r['id_team']==5 && r['name']=='岩崎 優').single['pitcher'], isTrue);
    expect(rows.where((r)=>r['id_team']==5 && r['name']=='梅野 隆太郎').single['pitcher'], isFalse);
    expect(rows.any((r)=>r['id_team']==6), isTrue);
    expect(rows.map((r)=>'${r['id_team']}:${r['name']}').toSet().length, rows.length);
  });
  test('never substitutes full club roster for missing bench', () {
    expect(parseGameBench(parse('<a href="/npb/player/1/top">選手</a>'),1,2),isEmpty);
  });
}
