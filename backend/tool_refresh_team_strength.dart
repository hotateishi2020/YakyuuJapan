import 'dart:convert';
import 'dart:io';

import 'app/TeamStrength.dart';

/// dart run tool_refresh_team_strength.dart [year] [npb|mlb]
Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  final org = args.length > 1 ? args[1] : null;
  if (org != null && org != 'npb' && org != 'mlb') {
    stderr.writeln('団体はnpbまたはmlbを指定してください');
    exit(2);
  }
  try {
    final result = await TeamStrength.refresh(year: year, org: org);
    print(jsonEncode(result));
    exit((result['errors'] as List).isEmpty ? 0 : 1);
  } catch (error) {
    stderr.writeln('戦力登録に失敗: $error');
    exit(1);
  }
}
