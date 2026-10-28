import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';

Future<Map<String, dynamic>>? _pending;
Map<String, dynamic>? _cached;
DateTime? _loadedAt;

/// Shared by the calendar, favorite school, and bracket. Offline builds retain
/// bundled schedules; subsequent polls retry the server without reloading.
Future<Map<String, dynamic>> loadHighSchoolSchedule() async {
  if (_pending != null) return _pending!;
  if (_cached != null &&
      _loadedAt != null &&
      DateTime.now().difference(_loadedAt!) < const Duration(minutes: 1)) {
    return _cached!;
  }
  final request = _load();
  _pending = request;
  try {
    final data = await request;
    _cached = data;
    _loadedAt = DateTime.now();
    return data;
  } finally {
    _pending = null;
  }
}

Future<Map<String, dynamic>> _load() async {
  try {
    final response = await http.get(Env.api('/high-school/schedule'), headers: {
      'Cache-Control': 'no-cache'
    }).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['calendar'] is Map && data['kyushu'] is Map) return data;
    }
  } catch (_) {}
  if (_cached != null) return _cached!;
  return {
    'calendar': jsonDecode(await rootBundle
        .loadString('backend/assets/data/high_school_calendar.json')),
    'kyushu': jsonDecode(await rootBundle
        .loadString('backend/assets/data/autumn_kyushu_2026.json')),
  };
}

Future<Map<String, dynamic>> loadAutumnKyushuSchedule() async =>
    Map<String, dynamic>.from((await loadHighSchoolSchedule())['kyushu']);
