import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../logic/auth_session.dart';
import '../widgets/baseball_loading.dart';
import 'high_school_records_board.dart';
import 'other_baseball_board.dart' show AutumnKyushuBracket;

String favoriteSchoolForUser(AuthUser? user) => user == null
    ? ''
    : user.favoriteHighSchool.isNotEmpty
        ? user.favoriteHighSchool
        : user.id == 1
            ? '佐賀北'
            : '';

List<Map<String, dynamic>> schoolResults(List<Map<String, dynamic>> records,
    List<Map<String, dynamic>> supplement, String school, int year) {
  final result = <String, Map<String, dynamic>>{};
  String key(Map<String, dynamic> r) =>
      '${r['year']}:${r['season']}:${r['scope']}:${r['region']}:${r['division'] ?? '0'}';
  for (final r in records.where((r) => (r['year'] as int) <= year)) {
    for (final entry in (r['places'] as Map).entries) {
      if (!(entry.value as List).contains(school)) continue;
      final label = {
        '1': '優勝',
        '2': '準優勝',
        '4': 'ベスト4',
        '8': 'ベスト8',
        '16': 'ベスト16'
      }['${entry.key}'];
      if (label != null) result[key(r)] = {...r, 'result': label};
    }
  }
  for (final r in supplement
      .where((r) => r['school'] == school && (r['year'] as int) <= year)) {
    result[key(r)] = r;
  }
  return result.values.toList()
    ..sort((a, b) {
      final yearOrder = (b['year'] as int).compareTo(a['year'] as int);
      if (yearOrder != 0) return yearOrder;
      const seasons = {'春': 0, '夏': 1, '秋': 2};
      return (seasons[b['season']] ?? 0).compareTo(seasons[a['season']] ?? 0);
    });
}

Map<String, dynamic>? nextSchoolMatch(
    Map<String, dynamic> tournament, String school, DateTime now) {
  if (school.isEmpty) return null;
  final year = tournament['year'] as int;
  DateTime startsAt(Map<String, dynamic> m) {
    final date = '${m['date']}'.split('/').map(int.parse).toList();
    final time = '${m['time'] ?? '0:00'}'.split(':').map(int.parse).toList();
    return DateTime(year, date[0], date[1], time[0], time[1]);
  }

  final matches =
      (tournament['matches'] as List).cast<Map<String, dynamic>>().where((m) {
    final involved = ['home', 'away']
        .any((side) => '${m[side]}'.split(RegExp('[（(]')).first == school);
    if (!involved || m['score_home'] != null || m['score_away'] != null) {
      return false;
    }
    return !startsAt(m).isBefore(now);
  }).toList()
        ..sort((a, b) => startsAt(a).compareTo(startsAt(b)));
  return matches.firstOrNull;
}

class FavoriteHighSchoolBoard extends StatefulWidget {
  const FavoriteHighSchoolBoard({super.key, required this.year, this.user});
  final int year;
  final AuthUser? user;
  @override
  State<FavoriteHighSchoolBoard> createState() =>
      _FavoriteHighSchoolBoardState();
}

class _FavoriteHighSchoolBoardState extends State<FavoriteHighSchoolBoard> {
  late String school = favoriteSchoolForUser(widget.user);
  late final future = Future.wait([
    loadHighSchoolCatalog(),
    rootBundle
        .loadString('backend/assets/data/high_school_results_supplement.json')
        .then((s) => jsonDecode(s) as Map<String, dynamic>),
    rootBundle.loadString('backend/assets/data/autumn_kyushu_2026.json').then(
        (s) => <String, dynamic>{
              ...jsonDecode(s) as Map<String, dynamic>,
              'year': 2026
            }),
  ]);
  @override
  void didUpdateWidget(covariant FavoriteHighSchoolBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      school = favoriteSchoolForUser(widget.user);
    }
  }

  Future<void> selectSchool(List<String> schools) async {
    var selected = school;
    final picked = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('推し高校を選択'),
              content: SizedBox(
                  width: 320,
                  child: Autocomplete<String>(
                    initialValue: TextEditingValue(text: school),
                    optionsBuilder: (value) => value.text.trim().isEmpty
                        ? const Iterable<String>.empty()
                        : schools
                            .where((s) => s.contains(value.text.trim()))
                            .take(30),
                    onSelected: (s) => selected = s,
                    fieldViewBuilder: (context, controller, focus, submit) =>
                        TextField(
                            controller: controller,
                            focusNode: focus,
                            decoration: const InputDecoration(
                                labelText: '高校名', hintText: '佐賀北など'),
                            onChanged: (s) => selected = s.trim()),
                  )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル')),
                TextButton(
                    onPressed: () {
                      if (schools.contains(selected)) {
                        Navigator.pop(context, selected);
                      }
                    },
                    child: const Text('保存'))
              ],
            ));
    if (picked == null || !mounted) return;
    final user = widget.user;
    if (user == null) return;
    final error = await AuthSession.instance.updateProfile(
        nameLast: user.nameLast,
        mailaddress: user.mailaddress,
        idTeamFav: user.idTeamFav,
        idPlayerFav: user.idPlayerFav,
        favoriteHighSchool: picked);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => school = picked);
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('高校野球の情報を取得できませんでした。'));
            }
            if (!snapshot.hasData) {
              return const Center(child: BaseballLoading());
            }
            final catalog = snapshot.data![0],
                extra = snapshot.data![1],
                tournament = snapshot.data![2];
            final records =
                (catalog['tournaments'] as List).cast<Map<String, dynamic>>();
            final history = schoolResults(
                records,
                (extra['results'] as List).cast<Map<String, dynamic>>(),
                school,
                widget.year);
            final next = nextSchoolMatch(tournament, school, DateTime.now());
            final schools = {
              for (final r in records)
                for (final names in (r['places'] as Map).values)
                  ...List<String>.from(names as List)
            }.toList()
              ..sort();
            return ListView(children: [
              ListTile(
                  title: Text(school.isEmpty ? '推し高校が未設定です' : '推し高校：$school',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: widget.user == null
                      ? null
                      : TextButton(
                          onPressed: () => selectSchool(schools),
                          child: const Text('変更'))),
              if (widget.user == null)
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('ログインすると推し高校を設定できます。')),
              if (school.isNotEmpty) ...[
                const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('次回出場大会',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                if (next == null)
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('次の試合の組合せは未登録です。'))
                else ...[
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                          "次戦 ${tournament['year']}/${next['date']} ${next['time']}　${next['home']} − ${next['away']}")),
                  SizedBox(
                      height: 460,
                      child: AutumnKyushuBracket(
                          year: tournament['year'] as int,
                          highlightSchool: school)),
                ],
                Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('${widget.year}年までの大会結果',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                if (history.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(8), child: Text('大会結果は未収録です。'))
                else
                  SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        horizontalMargin: 10,
                        columnSpacing: 18,
                        headingRowHeight: 32,
                        dataRowMinHeight: 34,
                        dataRowMaxHeight: 42,
                        columns: const [
                          DataColumn(label: Text('年度')),
                          DataColumn(label: Text('大会')),
                          DataColumn(label: Text('結果'))
                        ],
                        rows: [
                          for (final r in history)
                            DataRow(cells: [
                              DataCell(Text('${r['year']}')),
                              DataCell(Tooltip(
                                  message: '出典：${r['source']}',
                                  child:
                                      Text("${r['season']} ${r['region']}大会"))),
                              DataCell(Text('${r['result']}',
                                  style: TextStyle(
                                      fontWeight: r['result'] == '優勝'
                                          ? FontWeight.bold
                                          : FontWeight.normal))),
                            ])
                        ],
                      )),
                const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('確認できた大会結果を掲載しています。未収録の大会を初戦敗退として扱うことはありません。',
                        style: TextStyle(fontSize: 11, color: Colors.black54))),
              ],
            ]);
          });
}
