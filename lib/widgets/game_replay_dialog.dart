import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../logic/auth_session.dart';
import '../logic/game_replay.dart';
import 'replay_field.dart';
import 'replay_scoreboard.dart';
import '../tools/Env.dart';

Future<void> showGameReplay(
    BuildContext context, Map<String, dynamic> game) async {
  if (!AuthSession.instance.showDetailedGames) return;
  await showDialog<void>(
      context: context, builder: (_) => GameReplayDialog(game: game));
}

class GameReplayDialog extends StatefulWidget {
  const GameReplayDialog({super.key, required this.game, this.frames});
  final Map<String, dynamic> game;
  final List<ReplayFrame>? frames;
  @override
  State<GameReplayDialog> createState() => _GameReplayDialogState();
}

class _GameReplayDialogState extends State<GameReplayDialog> {
  List<ReplayFrame> frames = [];
  int index = 0;
  bool automatic = true, playing = false, loading = true;
  String? error;
  Timer? timer;
  int? owner;
  @override
  void initState() {
    super.initState();
    owner = AuthSession.instance.user?.id;
    AuthSession.instance.addListener(_authChanged);
    if (widget.frames != null) {
      frames = widget.frames!;
      loading = false;
    } else {
      _load();
    }
  }

  void _authChanged() {
    if (!AuthSession.instance.showDetailedGames ||
        owner != AuthSession.instance.user?.id) {
      timer?.cancel();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    AuthSession.instance.removeListener(_authChanged);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final token = AuthSession.instance.token;
      final id = widget.game['id_game'] ?? widget.game['id'];
      final response = await http.get(
          Env.api('/game-replay').replace(queryParameters: {'id': '$id'}),
          headers: {
            if (token != null) 'Authorization': 'Bearer $token'
          }).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw const FormatException();
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      final rows = (body['play_rows'] as List? ?? [])
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      if (!mounted ||
          !AuthSession.instance.showDetailedGames ||
          owner != AuthSession.instance.user?.id) {
        return;
      }
      setState(() {
        frames = buildGameReplay(widget.game, rows);
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '再生用の詳細情報を取得できませんでした';
        });
      }
    }
  }

  void _play() {
    timer?.cancel();
    if (frames.isEmpty) return;
    setState(() {
      if (index == frames.length - 1) index = 0;
      playing = true;
    });
    timer = Timer.periodic(const Duration(milliseconds: 4200), (_) {
      if (!mounted) return;
      if (index >= frames.length - 1) {
        _pause();
        return;
      }
      setState(() => index++);
      if (index == frames.length - 1) _pause();
    });
  }

  void _pause() {
    timer?.cancel();
    if (mounted) setState(() => playing = false);
  }

  void _step(int delta) {
    _pause();
    setState(() => index = (index + delta).clamp(0, frames.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final frame = frames.isEmpty ? null : frames[index];
    return Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 780),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Expanded(
                      child: Text('試合ストーリー',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18))),
                  IconButton(
                      tooltip: '閉じる',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ]),
                Flexible(
                    child: SingleChildScrollView(
                        child: Column(children: [
                  if (loading)
                    const Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator()),
                  if (error != null) ...[
                    Text(error!),
                    TextButton(
                        onPressed: () {
                          setState(() {
                            loading = true;
                            error = null;
                          });
                          _load();
                        },
                        child: const Text('再試行'))
                  ],
                  if (!loading && error == null && frame == null)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('再生できる打席・交代記録がまだありません。')),
                  if (frame != null) ...[
                    ReplayScoreboard(frames:frames,index:index,home:'${widget.game['name_team_home'] ?? ''}',away:'${widget.game['name_team_away'] ?? ''}'),
                    const SizedBox(height: 6),
                    ReplayField(frame: frame),
                    const SizedBox(height: 8),
                    const SizedBox(height: 6),
                    const Text(
                        '記録に基づく模式アニメーションです。軌道は実際の映像とは異なります。移動先を特定できない走者は塁状況のみ表示します。',
                        style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ]))),
                if (frame != null) ...[
                  Row(children: [
                    const Text('手動'),
                    Switch(
                        value: automatic,
                        onChanged: (value) {
                          _pause();
                          setState(() => automatic = value);
                        }),
                    const Text('自動'),
                    const Spacer(),
                    Text('${index + 1} / ${frames.length}')
                  ]),
                  Slider(
                      value: index.toDouble(),
                      max: (frames.length - 1).toDouble(),
                      divisions: frames.length > 1 ? frames.length - 1 : null,
                      onChanged: (v) {
                        _pause();
                        setState(() => index = v.round());
                      }),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(
                        tooltip: '最初に戻る',
                        onPressed: index > 0
                            ? () {
                                _pause();
                                setState(() => index = 0);
                              }
                            : null,
                        icon: const Icon(Icons.first_page)),
                    IconButton(
                        tooltip: '一つ戻る',
                        onPressed: index > 0 ? () => _step(-1) : null,
                        icon: const Icon(Icons.skip_previous)),
                    if (automatic)
                      IconButton(
                          tooltip: playing ? '一時停止' : '自動再生',
                          onPressed: playing ? _pause : _play,
                          icon: Icon(
                              playing ? Icons.pause_circle : Icons.play_circle),
                          iconSize: 36),
                    IconButton(
                        tooltip: '一つ進む',
                        onPressed:
                            index < frames.length - 1 ? () => _step(1) : null,
                        icon: const Icon(Icons.skip_next)),
                  ]),
                ],
              ])),
        ));
  }
}
