import 'app/SeasonAwards.dart';

Future<void> main(List<String> args) async {
  for (final year
      in args.isEmpty ? [DateTime.now().year] : args.map(int.parse)) {
    final result = await SeasonAwards.update(year);
    print(
        '$year: ${(result['pages'] as Map).length} pages, errors: ${result['errors']}');
  }
}
