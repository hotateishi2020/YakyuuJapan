import 'dart:io';

import 'app/HistoricalBaseballImporter.dart';

Future<void> main(List<String> args) async {
  try {
    final options = BackfillOptions.parse(args);
    if (options.help) {
      stdout.writeln(BackfillOptions.usage);
      await _terminate(0);
    }
    stdout.writeln(
      'Historical backfill: org=${options.org} '
      '${options.fromYear}-${options.toYear} resume=${options.resume}',
    );
    await HistoricalBaseballImporter().importRange(
      org: options.org,
      fromYear: options.fromYear,
      toYear: options.toYear,
      resume: options.resume,
      progress: stdout.writeln,
    );
    stdout.writeln('Historical backfill complete.');
    await _terminate(0);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(BackfillOptions.usage);
    await _terminate(64);
  } catch (error, stackTrace) {
    stderr.writeln('Historical backfill failed: $error');
    stderr.writeln(stackTrace);
    await _terminate(1);
  }
}

Future<Never> _terminate(int code) async {
  await stdout.flush();
  await stderr.flush();
  exit(code);
}

class BackfillOptions {
  const BackfillOptions({
    required this.org,
    required this.fromYear,
    required this.toYear,
    required this.resume,
    this.help = false,
  });

  final String org;
  final int fromYear;
  final int toYear;
  final bool resume;
  final bool help;

  static const usage = '''
Usage:
  dart run tool_history_backfill.dart --org=npb|mlb|all --from=YEAR --to=YEAR [--resume]

Options:
  --org       Data source to import (required)
  --from      First season, inclusive (required)
  --to        Last season, inclusive (required)
  --resume    Skip datasets with a completed checkpoint
  --help      Show this help

The importer supports NPB from 1936, MLB NL from 1876, and MLB AL from 1901.
Pre-1950 one-league NPB seasons use app league 1 for compatibility.
''';

  static BackfillOptions parse(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      return const BackfillOptions(
        org: 'all',
        fromYear: 0,
        toYear: 0,
        resume: false,
        help: true,
      );
    }
    final values = <String, String>{};
    var resume = false;
    for (final argument in args) {
      if (argument == '--resume') {
        resume = true;
        continue;
      }
      final match = RegExp(r'^--(org|from|to)=(.+)$').firstMatch(argument);
      if (match == null) {
        throw FormatException('Unknown option: $argument');
      }
      values[match.group(1)!] = match.group(2)!;
    }
    final org = values['org']?.trim().toLowerCase();
    final from = int.tryParse(values['from'] ?? '');
    final to = int.tryParse(values['to'] ?? '');
    if (org == null || !const {'npb', 'mlb', 'all'}.contains(org)) {
      throw const FormatException('--org=npb|mlb|all is required');
    }
    if (from == null || to == null) {
      throw const FormatException('--from and --to must be integer years');
    }
    if (from > to) {
      throw const FormatException('--from must not be later than --to');
    }
    final current = DateTime.now().year;
    if (from < 1876 || to > current) {
      throw FormatException('Years must be between 1876 and $current');
    }
    if (org == 'npb' && from < 1936) {
      throw const FormatException('NPB historical pages begin in 1936');
    }
    return BackfillOptions(
      org: org,
      fromYear: from,
      toYear: to,
      resume: resume,
    );
  }
}
