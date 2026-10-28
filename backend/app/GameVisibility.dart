import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:koko_shared/game_visibility.dart';
import 'package:koko_shared/prediction_visibility.dart';

/// Apply after route/snapshot caches so privileged cached data is never served
/// to a different account. Resolve identity from the authenticated request.
Middleware gameVisibility(Future<int?> Function(Request) userIdOf) => (handler) => (request) async {
      final response = await handler(request);
      if (response.statusCode != 200 || !(response.headers['content-type'] ?? '').contains('application/json')) {
        return response;
      }
      final body = await response.readAsString();
      final decoded = jsonDecode(body);
      final publicData = publicPredictionData(publicGameData(decoded));
      final isGroupResponse = request.url.path == 'predict-groups';
      if (isGroupResponse && publicData is Map) publicData['groups'] = <Object>[];
      final publicBody = jsonEncode(publicData);
      if (!isGroupResponse && publicBody == jsonEncode(decoded)) return response.change(body: body);
      final userId = await userIdOf(request);
      return Response(
        response.statusCode,
        context: response.context,
        body: userId == null
            ? publicBody
            : canViewRestrictedGames(userId)
                ? body
                : jsonEncode(publicGameData(decoded)),
        headers: {
          for (final entry in response.headers.entries)
            if (entry.key != 'content-length') entry.key: entry.value,
          'cache-control': 'private, no-store',
          'vary': [if (response.headers['vary'] != null) response.headers['vary'], 'Authorization', 'Cookie'].join(', ')
        },
      );
    };
