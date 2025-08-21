import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:koko/tools/Env.dart';
import 'dart:collection';

final logger = Logger();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter + Neon',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: Text("順位予想")),
        body: PredictionPage(),
      ),
    );
  }
}

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  List<Map<String, dynamic>> predictions = [];
  List<Map<String, dynamic>> standings = []; // 👈 追加
  List<Map<String, dynamic>> npbPlayerStats = [];
  bool isLoading = true;
  String? error;
  String _usernameForId(String idUser) {
    final m = npbPlayerStats.firstWhere(
      (e) => '${e['id_user']}' == idUser,
      orElse: () => const {},
    );
    return (m.isNotEmpty ? (m['username'] ?? '—') : '—').toString();
  }

  @override
  void initState() {
    super.initState();
    fetchPredictions();
  }

  Future<void> fetchPredictions() async {
    try {
      final response =
          await http.get(Uri.parse('${Env.baseUrl()}/predictions'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final users = (data['users'] as List).cast<Map<String, dynamic>>();
        final npb = (data['npbstandings'] as List).cast<Map<String, dynamic>>();
        final stats =
            (data['npbPlayerStats'] as List).cast<Map<String, dynamic>>();

        setState(() {
          predictions = users;
          standings = npb; // 👈 保存
          npbPlayerStats = stats;
          isLoading = false;
        });
      } else {
        setState(() {
          error = 'HTTPエラー: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      logger.e('通信エラー: $e');
      setState(() {
        error = '通信エラー: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text(error!));

    return Column(
      children: [
        Expanded(
            child:
                PredictionGrid(predictions: predictions, standings: standings)),
        Divider(),
        Expanded(child: _buildNpbPlayerStats()),
      ],
    );
  }

  Widget _buildNpbPlayerStats() {
    if (npbPlayerStats.isEmpty) {
      return const Center(child: Text('選手成績がありません'));
    }

    // リーグごと
    final Map<String, List<Map<String, dynamic>>> byLeague = {};
    for (final e in npbPlayerStats) {
      final league = (e['league_name'] ?? '').toString();
      byLeague.putIfAbsent(league, () => []).add(e as Map<String, dynamic>);
    }

    // セル（プレイヤー名の結合テキストとハイライト）
    Widget aggCell({required String text, required bool highlight}) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: highlight ? Colors.yellow[200] : null,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text.isNotEmpty ? text : '—',
          textAlign: TextAlign.center,
        ),
      );
    }

    // 左端のスタッツ名セル
    Widget titleCell(String title) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            title.isNotEmpty ? title : '不明',
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // プレイヤー名リストをコンマ結合。重複は除外（順序は出現順）
    String joinPlayers(Iterable<String> names) {
      final seen = <String>{};
      final deduped = <String>[];
      for (final n in names) {
        if (n.isEmpty) continue;
        if (seen.add(n)) deduped.add(n);
      }
      return deduped.join(', ');
    }

    final List<Widget> sections = [];

    byLeague.forEach((leagueName, leagueRows) {
      // リーグ見出し
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Center(
            child: Text(
              leagueName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );

      // ユーザーヘッダー（リーグ直下）
      sections.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Expanded(flex: 2, child: Center(child: Text('スタッツ'))),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(_usernameForId('1'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(_usernameForId('0'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(_usernameForId('2'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
      sections.add(const Divider(height: 1));

      // スタッツごと（id_stats + title）。id_stats が null は unknown
      final Map<String, List<Map<String, dynamic>>> byStat = {};
      for (final r in leagueRows) {
        final String idStatStr =
            (r['id_stats'] == null) ? 'unknown' : '${r['id_stats']}';
        final String title = (r['title'] ?? '不明').toString();
        final String statKey = '$idStatStr|$title';
        byStat.putIfAbsent(statKey, () => []).add(r);
      }

      // 各スタッツ → 1行にまとめる（4列：title / id_user=1 / id_user=0 / id_user=2）
      final statEntries = byStat.entries.toList()
        ..sort((a, b) {
          // タイトル昇順（任意）
          final ta = a.key.split('|').last;
          final tb = b.key.split('|').last;
          return ta.compareTo(tb);
        });

      for (final entry in statEntries) {
        final parts = entry.key.split('|');
        final String title = parts.length > 1 ? parts[1] : '不明';
        final rows = entry.value;

        // ユーザー別に player_name と flg_atari を収集
        final user1Rows = rows.where((e) => '${e['id_user']}' == '1');
        final user0Rows = rows.where((e) => '${e['id_user']}' == '0');
        final user2Rows = rows.where((e) => '${e['id_user']}' == '2');

        final user1Players =
            user1Rows.map((e) => (e['player_name'] ?? '').toString());
        final user0Players =
            user0Rows.map((e) => (e['player_name'] ?? '').toString());
        final user2Players =
            user2Rows.map((e) => (e['player_name'] ?? '').toString());

        final user1Text = joinPlayers(user1Players);
        final user0Text = joinPlayers(user0Players);
        final user2Text = joinPlayers(user2Players);

        // flg_atari が true のデータがそのセルにあるかどうか
        final user1Hi = user1Rows.any((e) => e['flg_atari'] == true);
        final user0Hi = user0Rows.any((e) => e['flg_atari'] == true);
        final user2Hi = user2Rows.any((e) => e['flg_atari'] == true);

        sections.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: titleCell(title)),
              Expanded(
                  flex: 2, child: aggCell(text: user1Text, highlight: user1Hi)),
              Expanded(
                  flex: 2, child: aggCell(text: user0Text, highlight: user0Hi)),
              Expanded(
                  flex: 2, child: aggCell(text: user2Text, highlight: user2Hi)),
            ],
          ),
        );
      }

      sections.add(const SizedBox(height: 6));
      sections.add(const Divider(height: 1));
    });

    // 全体ヘッダー無し。リーグから開始。
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [...sections],
    );
  }
}

class PredictionGrid extends StatelessWidget {
  final List<Map<String, dynamic>> predictions;
  final List<Map<String, dynamic>> standings;

  const PredictionGrid({
    super.key,
    required this.predictions,
    required this.standings,
  });

  @override
  Widget build(BuildContext context) {
    final groupedByUser = <String, List<Map<String, dynamic>>>{};
    for (var item in predictions) {
      final user = item['name_user_last'];
      groupedByUser.putIfAbsent(user, () => []).add(item);
    }

    final userEntries = groupedByUser.entries.toList();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (userEntries.isNotEmpty) _buildUserCard(context, userEntries[0]),
            _buildStandingsCard(context),
            if (userEntries.length > 1) _buildUserCard(context, userEntries[1]),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context,
      MapEntry<String, List<Map<String, dynamic>>> entry) {
    final userName = entry.key;
    final userPredictions = entry.value;

    final league1 = userPredictions.where((e) => e['id_league'] == 1).toList()
      ..sort((a, b) => a['int_rank'].compareTo(b['int_rank']));
    final league2 = userPredictions.where((e) => e['id_league'] == 2).toList()
      ..sort((a, b) => a['int_rank'].compareTo(b['int_rank']));

    return SizedBox(
      width: 300,
      child: Card(
        elevation: 3,
        margin: const EdgeInsets.only(right: 16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('$userName さんの予想',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              Text('セ・リーグ', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              ...league1.map(_buildTeamRow),
              const SizedBox(height: 12),
              Text('パ・リーグ', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              ...league2.map(_buildTeamRow),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandingsCard(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Card(
        elevation: 3,
        margin: const EdgeInsets.only(right: 16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ✅ タイトルはループの外
              Text('現在の順位',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),

              // ✅ ここから各リーグの表示
              ...standings.map((league) {
                final leagueName = league['league'];
                final teams =
                    (league['teams'] as List).cast<Map<String, dynamic>>();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('$leagueName',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    ...teams.map((team) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text(team['rank']),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  team['team'],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 12),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamRow(Map<String, dynamic> team) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${team['int_rank']}'),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              team['name_team_short'],
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
