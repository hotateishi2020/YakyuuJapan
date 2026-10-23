import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/org_config.dart';
import '../tools/Env.dart';
import '../widgets/baseball_loading.dart';
import '../logic/season_titles.dart';
import 'season_titles_table.dart';
import 'mlb_season_titles_table.dart';

class SeasonTitlesBoard extends StatefulWidget {
  const SeasonTitlesBoard({super.key, required this.org, required this.year, this.individualOnly = false});
  final bool individualOnly;
  final OrgConfig org;
  final int year;
  @override
  State<SeasonTitlesBoard> createState() => _SeasonTitlesBoardState();
}

class _SeasonTitlesBoardState extends State<SeasonTitlesBoard> {
  Map<String, dynamic>? data;
  bool failed = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(SeasonTitlesBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year || oldWidget.org.kind != widget.org.kind) {
      load();
    }
  }

  Future<void> load() async {
    final token = ++request;
    setState(() {
      data = null;
      failed = false;
    });
    try {
      final response = await http.get(Env.api('/records?org=${widget.org.kind.name}&year=${widget.year}&section=titles')).timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) throw const FormatException();
      final parsed = Map<String, dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)));
      if (mounted && token == request) setState(() => data = parsed);
    } catch (_) {
      if (mounted && token == request) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('タイトル情報を取得できませんでした'), TextButton(onPressed: load, child: const Text('再読み込み'))]));
    }
    if (data == null) return const Center(child: BaseballLoading());
    if (data!['pending'] == true) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${data!['message']}'),
        TextButton(onPressed: load, child: const Text('再読み込み')),
      ]));
    }
    return SeasonTitlesGrid(data: data!, year: widget.year, org: widget.org, individualOnly: widget.individualOnly);
  }
}

class SeasonTitlesGrid extends StatelessWidget {
  const SeasonTitlesGrid({super.key, required this.data, required this.year, required this.org, this.individualOnly = false});
  final bool individualOnly;
  final Map<String, dynamic> data;
  final int year;
  final OrgConfig org;
  @override
  Widget build(BuildContext context) {
    final groups = buildSeasonTitles(data, year);
    if (individualOnly) {
      if (org.kind == OrgKind.mlb) return MlbSeasonTitlesTable(groups: groups, year: year, individualOnly: true);
      final table = SeasonTitlesTable(groups: groups, year: year);
      return table.surface(table.statistical(portrait: true));
    }
    return org.kind == OrgKind.mlb ? MlbSeasonTitlesTable(groups: groups, year: year) : SeasonTitlesTable(groups: groups, year: year);
  }
}
