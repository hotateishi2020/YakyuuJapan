import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/retained_tab_body.dart';

void main() {
  testWidgets('訪問したタブだけを初期化し、戻っても再取得せず状態を保持する', (tester) async {
    final loads = <String>[];
    Future<void> show(String tab,
        {int year = 2026, String label = '初期'}) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RetainedTabBody(
        key: ValueKey(year),
        selected: tab,
        builder: (_) => _Probe(tab: tab, label: label, onLoad: loads.add),
      ))));
    }

    await show('NPB');
    expect(loads, ['NPB']);
    await tester.tap(find.text('初期:0'));
    await tester.pump();
    await show('MLB');
    expect(loads, ['NPB', 'MLB']);
    expect(find.text('初期:1'), findsNothing);
    await show('NPB', label: '更新');
    expect(find.text('更新:1'), findsOneWidget);
    expect(loads, ['NPB', 'MLB']);
    await show('NPB', year: 2025);
    expect(find.text('初期:0'), findsOneWidget);
    expect(loads, ['NPB', 'MLB', 'NPB']);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.tab, required this.label, required this.onLoad});
  final String tab, label;
  final void Function(String) onLoad;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int count = 0;
  @override
  void initState() {
    super.initState();
    widget.onLoad(widget.tab);
  }

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => count++),
        child: Text('${widget.label}:$count'),
      );
}
