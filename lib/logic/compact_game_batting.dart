/// 試合の表示用。安打数は取得元の合計安打を使い、HRを重複加算しない。
String compactGameBatting(Map<String, dynamic> line) {
  int number(String key) => int.tryParse('${line[key]}') ?? 0;
  if (line['int_batting'] != null && line['int_hit1'] != null) {
    return '${number('int_batting')}打数${number('int_hit1')}安打'
        '${number('int_homerun') > 0 ? '${number('int_homerun')}HR' : ''}'
        '${number('int_steal_base') > 0 ? '${number('int_steal_base')}盗塁' : ''}';
  }
  final text = '${line['txt_batting'] ?? ''}';
  final base = RegExp(r'(\d+)打数(\d+|無)安打').firstMatch(text);
  if (base == null) return '';
  final hr = RegExp(r'\d+HR').firstMatch(text)?.group(0) ?? '';
  final steal = RegExp(r'\d+盗塁').firstMatch(text)?.group(0) ?? '';
  return '${base[1]}打数${base[2] == '無' ? '0' : base[2]}安打$hr$steal';
}
