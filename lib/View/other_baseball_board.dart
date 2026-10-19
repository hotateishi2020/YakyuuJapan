import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/baseball_loading.dart';

class OtherBaseballBoard extends StatelessWidget {
  const OtherBaseballBoard({super.key, required this.year});
  final int year;
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(
            labelColor: Colors.black,
            tabs: [Tab(text: '高校野球'), Tab(text: '国際シリーズ')]),
        Expanded(
            child: TabBarView(children: [
          AutumnKyushuBracket(year: year),
          const Center(child: Text('国際シリーズの大会情報はまだ登録されていません。')),
        ])),
      ]));
}

class AutumnKyushuBracket extends StatefulWidget {
  const AutumnKyushuBracket({super.key, required this.year});
  final int year;
  @override
  State<AutumnKyushuBracket> createState() => _AutumnKyushuBracketState();
}

class _AutumnKyushuBracketState extends State<AutumnKyushuBracket> {
  late final Future<Map<String, dynamic>> data = rootBundle
      .loadString('backend/assets/data/autumn_kyushu_2026.json')
      .then((s) => jsonDecode(s) as Map<String, dynamic>);
  @override
  Widget build(BuildContext context) => widget.year != 2026
      ? Center(child: Text('${widget.year}年の秋季九州大会は未収録です。2026年を選択してください。'))
      : FutureBuilder<Map<String, dynamic>>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return const Center(child: Text('組合せを取得できませんでした'));
            if (!snapshot.hasData)
              return const Center(child: BaseballLoading());
            final info = snapshot.data!;
            final matches =
                (info['matches'] as List).cast<Map<String, dynamic>>();
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                          '${info['title']}\n${info['venue']}　${info['checked_at']}確認',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      child: SingleChildScrollView(
                          child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: 880,
                                height: 840,
                                child: CustomPaint(
                                    painter: _BracketLines(),
                                    child: Stack(children: [
                                      for (var round = 0;
                                          round < 4;
                                          round++) ...[
                                        Positioned(
                                            left: round * 220,
                                            top: 0,
                                            width: 200,
                                            child: Text(
                                                [
                                                  '1回戦',
                                                  '準々決勝',
                                                  '準決勝',
                                                  '決勝'
                                                ][round],
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold))),
                                        for (var i = 0; i < (8 >> round); i++)
                                          Positioned(
                                              left: round * 220,
                                              top: 30 +
                                                  ((1 << round) *
                                                      (i + .5) *
                                                      100) -
                                                  40,
                                              width: 200,
                                              height: 80,
                                              child: Container(
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      border: Border.all(
                                                          color:
                                                              Colors.blueGrey)),
                                                  child: Builder(
                                                      builder: (context) {
                                                    final m = matches
                                                        .where((m) =>
                                                            m['round'] ==
                                                                round &&
                                                            m['slot'] == i)
                                                        .first;
                                                    return Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                              '${m['date']} ${m['time']}',
                                                              style: const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .black54)),
                                                          for (final side in [
                                                            'home',
                                                            'away'
                                                          ])
                                                            Text(
                                                                '${m[side]}${m['score_$side'] == null ? '' : '  ${m['score_$side']}'}',
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style:
                                                                    const TextStyle(
                                                                        fontSize:
                                                                            12)),
                                                        ]);
                                                  }))),
                                      ],
                                    ])),
                              )))),
                  const Padding(
                      padding: EdgeInsets.all(6),
                      child: Text(
                          '出典：熊本県野球・ソフトボール連絡協議会（高野連掲載組合せ）。未実施試合の得点は表示しません。',
                          style: TextStyle(fontSize: 10))),
                ]);
          });
}

class _BracketLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 1;
    for (var round = 0; round < 3; round++) {
      for (var i = 0; i < (4 >> round); i++) {
        final x = round * 220.0 + 200;
        final first = 30 + (1 << round) * (2 * i + .5) * 100;
        final last = first + (1 << round) * 100;
        canvas.drawLine(Offset(x, first), Offset(x + 10, first), pen);
        canvas.drawLine(Offset(x, last), Offset(x + 10, last), pen);
        canvas.drawLine(Offset(x + 10, first), Offset(x + 10, last), pen);
        canvas.drawLine(Offset(x + 10, (first + last) / 2),
            Offset(x + 20, (first + last) / 2), pen);
      }
    }
  }

  @override
  bool shouldRepaint(_BracketLines old) => false;
}
