import 'dart:io';

/// Compatibility entry point. All MLB categories now share the audited updater;
/// the old eight-category update must not erase verified play-level records.
Future<void> main(List<String> args) async {
  final year = args.isEmpty ? '${DateTime.now().year}' : args.first;
  final options = args.skip(1).toList();
  final cache = options.contains('--cache')
      ? <String>[]
      : ['--cache', Directory.systemTemp.createTempSync('koko-mlb-streaks-$year-').path];
  final process = await Process.start('python3',
      ['tool_refresh_mlb_streaks.py', year, ...options, ...cache],
      mode: ProcessStartMode.inheritStdio);
  exit(await process.exitCode);
}
