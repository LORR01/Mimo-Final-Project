import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Durable Mimo favorites, separate from the expiring clipboard cache.
/// Paths are derived only from validated server-generated IDs.
class FavoriteArchive {
  FavoriteArchive(this.directory);
  final Directory directory;
  Map<String, Map<String, dynamic>> _items = {};
  bool validId(String id) => RegExp(r'^pc-\d+-\d+$').hasMatch(id);
  File _blob(String id) {
    if (!validId(id)) throw const FormatException('Invalid clipboard ID');
    return File('${directory.path}/$id.bin');
  }

  Future<List<Map<String, dynamic>>> load() async {
    await directory.create(recursive: true);
    final manifest = File('${directory.path}/favorites.json');
    if (await manifest.exists()) {
      final raw = jsonDecode(await manifest.readAsString()) as List;
      _items = {
        for (final item in raw.whereType<Map>())
          if (item['id'] is String && validId(item['id'] as String))
            item['id'] as String: {
              ...Map<String, dynamic>.from(item),
              'isFavorite': true,
              'expiresAt': null,
            },
      };
    }
    return _items.values.map((item) => {...item}).toList();
  }

  Future<void> _commit(Map<String, Map<String, dynamic>> next) async {
    await directory.create(recursive: true);
    final temp = File('${directory.path}/favorites.json.tmp');
    await temp.writeAsString(jsonEncode(next.values.toList()), flush: true);
    await temp.rename('${directory.path}/favorites.json');
    _items = next;
  }

  Future<void> pin(Map<String, dynamic> item, Uint8List? bytes) async {
    final id = item['id'] as String;
    final file = _blob(id);
    await directory.create(recursive: true);
    if (item['fileName'] != null && bytes == null && !await file.exists()) {
      throw const FileSystemException('ไฟล์แนบไม่พร้อมบันทึก');
    }
    if (bytes != null) {
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    }
    await _commit({
      ..._items,
      id: {...item, 'isFavorite': true, 'expiresAt': null},
    });
  }

  Future<Uint8List?> bytes(String id) async {
    if (!_items.containsKey(id)) return null;
    final file = _blob(id);
    if (!await file.exists() || await file.length() > 20 * 1024 * 1024) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<void> remove(String id) async {
    final next = {..._items}..remove(id);
    await _commit(next);
    final file = _blob(id);
    if (await file.exists()) await file.delete();
  }
}
