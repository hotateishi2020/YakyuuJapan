import '../logic/replay_motion.dart';
import '../tools/color_parse.dart';
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
      if (!frames[index].after &&
          index + 1 < frames.length &&
          frames[index + 1].after) {
        index++;
      }
      playing = true;
    });
    _schedule();
  }

  void _schedule() {
    timer = Timer(
        Duration(
            milliseconds: frames[index].after
                ? ((replayResultSeconds(frames[index]) + 2) * 1000).round()
                : 0), () {
      if (!mounted || !playing) return;
      if (index >= frames.length - 1) {
        _pause();
        return;
      }
      setState(() {
        index++;
        if (!frames[index].after &&
            index + 1 < frames.length &&
            frames[index + 1].after) {
          index++;
        }
      });
      _schedule();
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
    final screen = MediaQuery.sizeOf(context);
    Widget controls() => LayoutBuilder(builder: (context, constraints) {
          final buttons = Row(mainAxisSize: MainAxisSize.min, children: [
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
                  icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                  iconSize: 32),
            IconButton(
                tooltip: '一つ進む',
                onPressed: index < frames.length - 1 ? () => _step(1) : null,
                icon: const Icon(Icons.skip_next)),
          ]);
          final mode = Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('手動'),
            Switch(
                value: automatic,
                onChanged: (value) {
                  _pause();
                  setState(() => automatic = value);
                }),
            const Text('自動'),
          ]);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                height: 28,
                child: Slider(
                    value: index.toDouble(),
                    max: frames.length > 1 ? (frames.length - 1).toDouble() : 1,
                    divisions: frames.length > 1 ? frames.length - 1 : null,
                    onChanged: frames.length > 1
                        ? (v) {
                            _pause();
                            setState(() => index = v.round());
                          }
                        : null)),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              mode,
              if (constraints.maxWidth >= 500) buttons,
              Text('${index + 1} / ${frames.length}'),
            ]),
            if (constraints.maxWidth < 500) buttons,
          ]);
        });
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SizedBox(
        key: const Key('replay-dialog-body'),
        width: 1100,
        height: screen.height,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            SizedBox(
                height: 36,
                child: Row(children: [
                  const Expanded(
                      child: Text('試合ストーリー',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18))),
                  const Tooltip(
                      message:
                          '記録に基づく模式アニメーションです。軌道は実際の映像とは異なります。移動先を特定できない走者は塁状況のみ表示します。',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.info_outline, size: 20))),
                  IconButton(
                      tooltip: '閉じる',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ])),
            if (frame != null) ...[
              Expanded(
                  child: LayoutBuilder(
                      builder: (context, constraints) => FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: constraints.maxHeight < 300
                                ? 300
                                : constraints.maxHeight,
                            child: ReplayField(
                              frame: frame,
                              scoreboard: ReplayScoreboard(
                                  frames: frames,
                                  index: index,
                                  home:
                                      '${widget.game['name_team_home'] ?? ''}',
                                  away:
                                      '${widget.game['name_team_away'] ?? ''}'),
                              homeBackground: parseColorNameOrNull(
                                      '${widget.game['color_back_home'] ?? ''}') ??
                                  Colors.blue,
                              homeForeground: parseColorNameOrNull(
                                  '${widget.game['color_font_home'] ?? ''}'),
                              awayBackground: parseColorNameOrNull(
                                      '${widget.game['color_back_away'] ?? ''}') ??
                                  Colors.red,
                              awayForeground: parseColorNameOrNull(
                                  '${widget.game['color_font_away'] ?? ''}'),
                            ),
                          )))),
              controls(),
            ] else
              Expanded(
                  child: Center(
                      child: loading
                          ? const CircularProgressIndicator()
                          : error != null
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                      Text(error!),
                                      TextButton(
                                          onPressed: () {
                                            setState(() {
                                              loading = true;
                                              error = null;
                                            });
                                            _load();
                                          },
                                          child: const Text('再試行')),
                                    ])
                              : const Text('再生できる打席・交代記録がまだありません。'))),
          ]),
        ),
      ),
    );
  }
}
