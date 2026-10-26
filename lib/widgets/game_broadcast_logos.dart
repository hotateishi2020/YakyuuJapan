import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../logic/auth_session.dart';
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import 'broadcast_logo.dart';

class GameBroadcastLogos extends StatefulWidget {
  const GameBroadcastLogos({super.key, required this.game});
  final Map<String,dynamic> game;
  @override
  State<GameBroadcastLogos> createState() => _GameBroadcastLogosState();
}
class _GameBroadcastLogosState extends State<GameBroadcastLogos> {
  static final _cache = <String, ({DateTime at, Future<List<Map<String,dynamic>>> rows})>{};
  String? _key;
  Future<List<Map<String,dynamic>>>? _rows;
  @override
  void initState() { super.initState(); AuthSession.instance.addListener(_changed); _load(); }
  @override
  void dispose() { AuthSession.instance.removeListener(_changed); super.dispose(); }
  @override
  void didUpdateWidget(covariant GameBroadcastLogos oldWidget) { super.didUpdateWidget(oldWidget); _load(); }
  void _changed() { if (mounted) setState(_load); }
  void _load() {
    final game = widget.game;
    final query = {'date':'${game['date_game'] ?? ''}'.split(RegExp('[ T]')).first,
      'home':'${game['name_team_home'] ?? ''}', 'away':'${game['name_team_away'] ?? ''}',
      'prefecture':AuthSession.instance.user?.residencePrefecture ?? ''};
    final uri = Env.api('/game-broadcasts').replace(queryParameters: query);
    if (_key == uri.toString()) return;
    _key = uri.toString();
    final old = _cache[_key];
    if (old != null && DateTime.now().difference(old.at).inMinutes < 30) { _rows = old.rows; return; }
    _rows = http.get(uri).timeout(const Duration(seconds: 45)).then((r) {
      if (r.statusCode != 200) return <Map<String,dynamic>>[];
      return listMapFromJson(jsonDecode(utf8.decode(r.bodyBytes))['broadcasts']);
    }).catchError((_) => <Map<String,dynamic>>[]);
    if (_cache.length > 100) _cache.clear();
    _cache[_key!] = (at: DateTime.now(), rows: _rows!);
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String,dynamic>>>(
    key: ValueKey(_key), future: _rows, builder: (context, snapshot) {
      final rows = snapshot.data ?? [];
      if (rows.isEmpty) return const SizedBox.shrink();
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(
        mainAxisSize: MainAxisSize.min, children: [for (final row in rows)
          Padding(padding: const EdgeInsets.only(left: 5), child: Tooltip(
            message: '${row['name']}${row['kind'] == 'stream' && row['stream_url'] == null ? '（試合配信URL未確認）' : ''}',
            child: Semantics(label: '${row['name']}', button: row['stream_url'] != null,
              child: GestureDetector(onTap: row['kind'] == 'stream' && row['stream_url'] != null ? () async {
                final url = Uri.tryParse('${row['stream_url']}');
                if (url == null || url.scheme != 'https') return;
                final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
                if (!opened && context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('配信を開けませんでした。')));
              } : null,
              child: Container(width: 56, height: 28, padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
                child: BroadcastLogo(row: row)),
            )),
          )),
        ],
      ));
    });
}
