import 'app/SeasonAwards.dart';

Future<void> main(List<String> args) async {
  final seriesOnly = args.contains('--series-only');
  final years = args.where((arg) => arg != '--series-only').toList();
  for (final year
      in years.isEmpty ? [DateTime.now().year] : years.map(int.parse)) {
    final result = await SeasonAwards.update(year, seriesOnly: seriesOnly);
    print(
        '$year: ${(result['pages'] as Map).length} pages, errors: ${result['errors']}');
  }
}
