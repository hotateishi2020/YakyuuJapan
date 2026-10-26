/// 打順の並びに沿って打席を配置する。回が変わっても列は進めず、
/// 9番から1番へ打順が戻ったときだけ右の列に折り返す。
/// 入力は選手ごと・打順ごとでもよいが、同じ打順内の打席順は保持する。
List<int> battingTurnColumns(List<({int order, int? inning})> plates) {
  final columns = List<int>.filled(plates.length, -1);
  final innings = plates.map((p) => p.inning).toSet().toList()
    ..sort((a, b) => a == null ? (b == null ? 0 : 1) : b == null ? -1 : a.compareTo(b));
  var column = 0;
  var lastOrder = 0;
  for (final inning in innings) {
    final queues = <int, List<int>>{};
    for (var i = 0; i < plates.length; i++) {
      final plate = plates[i];
      if (plate.inning != inning || plate.order < 1 || plate.order > 9) continue;
      queues.putIfAbsent(plate.order, () => []).add(i);
    }
    while (queues.isNotEmpty) {
      final next = lastOrder % 9 + 1;
      final orders = queues.keys.toList()
        ..sort((a, b) => ((a - next + 9) % 9).compareTo((b - next + 9) % 9));
      final order = orders.first;
      if (lastOrder > 0 && order <= lastOrder) column++;
      final queue = queues[order]!;
      columns[queue.removeAt(0)] = column;
      if (queue.isEmpty) queues.remove(order);
      lastOrder = order;
    }
  }
  return columns;
}
