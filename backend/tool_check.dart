import 'dart:io';

import 'app/Achieve.dart';
import 'app/PlayLabel.dart';

void main() {
  final terachi = plateFeatsFromLine(atBats: 4, hits: 3, walks: 0, hbp: 0, sacrifices: 0, errors: 0);
  final yamano = plateFeatsFromLine(atBats: 2, hits: 2, walks: 0, hbp: 0, sacrifices: 0, errors: 0);
  final kondo = plateFeatsFromLine(atBats: 3, hits: 3, walks: 1, hbp: 0, sacrifices: 0, errors: 0);
  final sac = plateFeatsFromLine(atBats: 2, hits: 2, walks: 0, hbp: 0, sacrifices: 1, errors: 0);
  final errorReach = plateFeatsFromLine(atBats: 2, hits: 1, walks: 0, hbp: 0, sacrifices: 0, errors: 1);
  print('terachi [$terachi]');
  print('yamano [$yamano]');
  print('kondo [$kondo]');
  print('sac [$sac]');
  print('error [$errorReach]');
  final sato = playsWithHomerNumbers(
    playsFilledFromLine('', singles: 1, doubles: 0, triples: 0, homers: 1),
    '18',
  );
  print('sato [$sato]');
  final already = playsFilledFromLine('中安|single 18号ソロホームラン|hr', singles: 1, doubles: 0, triples: 0, homers: 1);
  print('already [$already]');
  final alreadyParts = already.split(' ');
  if (terachi.isNotEmpty || sac.isNotEmpty || !yamano.contains('全打席安打') || kondo != '全打席出塁|allreach' || !sato.contains('18号ホームラン|hr') || !sato.contains('安|single') || alreadyParts.length != 2) {
    stderr.writeln('unexpected');
    exit(1);
  }
  exit(0);
}
