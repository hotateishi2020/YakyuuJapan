import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';

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
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    fetchPredictions();
  }

  Future<void> fetchPredictions() async {
    try {
      final response = await http.get(Uri.parse('http://192.168.0.58:5050/predictions'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        setState(() {
          predictions = data.map((e) => Map<String, dynamic>.from(e)).toList();
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

    return PredictionGrid(predictions: predictions);
  }
}

class PredictionGrid extends StatelessWidget {
  final List<Map<String, dynamic>> predictions;

  const PredictionGrid({super.key, required this.predictions});

  @override
  Widget build(BuildContext context) {
    // ユーザーごとにグループ化
    final groupedByUser = <String, List<Map<String, dynamic>>>{};
    for (var item in predictions) {
      final user = item['name_user_last'];
      groupedByUser.putIfAbsent(user, () => []).add(item);
    }

    return Center( // 全体を中央寄せ
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // ✅ 中央に配置
          crossAxisAlignment: CrossAxisAlignment.start,
          children: groupedByUser.entries.map((entry) {
            final userName = entry.key;
            final userPredictions = entry.value;

            final league1 = userPredictions
                .where((e) => e['id_league'] == 1)
                .toList()
              ..sort((a, b) => a['int_rank'].compareTo(b['int_rank']));
            final league2 = userPredictions
                .where((e) => e['id_league'] == 2)
                .toList()
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
          }).toList(),
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