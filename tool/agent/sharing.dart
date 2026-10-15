import 'dart:convert';
import 'dart:io';
import 'dart:math';

const maxUploadBytes = 100 * 1024 * 1024;

String safeUploadName(String encoded) {
  final name = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
  final stem = name.split('.').first.toUpperCase();
  if (name.isEmpty ||
      name.length > 160 ||
      name.trim() != name ||
      name.endsWith('.') ||
      RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
      RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem) ||
      name == '.' ||
      name == '..') {
    throw const FormatException(
      'ชื่อไฟล์ไม่รองรับ กรุณาเปลี่ยนชื่อแล้วลองอีกครั้ง',
    );
  }
  return name;
}

/// Streams to an exclusive temporary file, bounds bytes, and publishes only
/// after complete receipt. Never overwrites or executes a received file.
Future<Map<String, dynamic>> receiveFile(
  HttpRequest request,
  Directory directory,
) async {
  final length = request.contentLength;
  if (length < 0 || length > maxUploadBytes) {
    throw const HttpException('ไฟล์ต้องมีขนาดไม่เกิน 100 MB');
  }
  final name = safeUploadName(request.headers.value('x-mimo-filename') ?? '');
  await directory.create(recursive: true);
  if (await FileSystemEntity.type(directory.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FileSystemException('โฟลเดอร์รับไฟล์ไม่พร้อม');
  }
  final id =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
  final pending = File('${directory.path}/.mimo-$id.part');
  await pending.create(exclusive: true);
  final output = await pending.open(mode: FileMode.writeOnly);
  var bytes = 0;
  bool closed = false;
  try {
    await for (final chunk in request.timeout(const Duration(seconds: 30))) {
      bytes += chunk.length;
      if (bytes > length || bytes > maxUploadBytes) {
        throw const HttpException('ขนาดไฟล์ไม่ตรงกัน');
      }
      await output.writeFrom(chunk);
    }
    if (bytes != length) {
      throw const HttpException('รับไฟล์ไม่ครบ กรุณาลองใหม่');
    }
    await output.close();
    closed = true;
    final storedName = '$id-$name';
    await pending.rename('${directory.path}/$storedName');
    return {'name': name, 'storedName': storedName, 'bytes': bytes};
  } finally {
    if (!closed) await output.close();
    if (await pending.exists()) await pending.delete();
  }
}
