import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/NpbResearch.dart';
import 'app/CalendarResearch.dart';
import 'app/NpbResearchEvents.dart';
import 'app/NpbResearchPolicy.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final mode = args.firstOrNull ?? '--plan';
  if (mode == '--plan') {
    final now = DateTime.now().toUtc();
    final year = researchJst(now).year;
    final client = http.Client();
    try {
      final calendar = researchCalendar(
          await NpbResearch.source(client, 'https://npb.jp/event/$year/'),
          year);
      print(const JsonEncoder.withIndent('  ').convert({
        'jst_now':
            researchJst(now).toIso8601String().replaceFirst('Z', '+09:00'),
        'calendar': calendar,
        'due_topics': researchDue(now, calendar),
        'enabled': Platform.environment['NPB_RESEARCH_ENABLED'] == 'true',
        'key_configured':
            (Platform.environment['OPENAI_API_KEY'] ?? '').isNotEmpty,
        'model_configured':
            (Platform.environment['OPENAI_RESEARCH_MODEL'] ?? '').isNotEmpty,
      }));
    } finally {
      client.close();
    }
  } else if (mode == '--init') {
    await Postgres.withConnection((c) async {
      await NpbResearchEvents.ensure(c);
      await CalendarResearch.ensure(c);
    });
    print('NPB research tables initialized. No API request made.');
  } else if (mode == '--run') {
    print(jsonEncode(await NpbResearch.run()));
  } else {
    stderr.writeln(
        'Usage: dart run tool_npb_research.dart [--plan|--init|--run]');
    exitCode = 64;
  }
  // PostgreSQL retains pooled sockets; the one-shot CLI must release its process.
  await stdout.flush();
  await stderr.flush();
  exit(exitCode);
}
