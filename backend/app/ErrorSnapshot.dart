import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Private files, served only by the authenticated administrator endpoint.
class ErrorSnapshotStore {
  ErrorSnapshotStore({String? path})
      : directory = Directory(path ??
            Platform.environment['ERROR_SNAPSHOT_DIR'] ??
            'var/error-snapshots');
  final Directory directory;
  static final _idPattern = RegExp(r'^[a-f0-9]{48}$');
  static final _random = Random.secure();

  static Uint8List? decode(dynamic value) {
    if (value is! String || value.length > 2000000) return null;
    try {
      final bytes = base64Decode(value);
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      if (bytes.length < 33 || bytes.length > 1500000) return null;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[i] != signature[i]) return null;
      }
      final data = ByteData.sublistView(bytes);
      final width = data.getUint32(16);
      final height = data.getUint32(20);
      if (width == 0 || height == 0 || width > 1280 || height > 1280)
        return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<String?> save(dynamic value) async {
    final bytes = decode(value);
    if (bytes == null) return null;
    try {
      await directory.create(recursive: true);
      // Bound disk usage; errors are still logged when storage is full.
      if (await directory.list().take(1000).length >= 1000) return null;
      final id = List.generate(
              24, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      await File('${directory.path}/$id.png').writeAsBytes(bytes, flush: true);
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> read(String id) async {
    if (!_idPattern.hasMatch(id)) return null;
    try {
      return await File('${directory.path}/$id.png').readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
