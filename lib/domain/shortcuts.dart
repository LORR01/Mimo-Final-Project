// Shared by Flutter and the Dart PC Agent. No platform/UI dependencies.
const modifierKeys = ['Ctrl', 'Alt', 'Shift', 'Win'];
final Map<String, int> virtualKeys = {
  'Ctrl': 0x11,
  'Alt': 0x12,
  'Shift': 0x10,
  'Win': 0x5b,
  'Esc': 0x1b,
  'Tab': 9,
  'Enter': 13,
  'Space': 32,
  'Backspace': 8,
  'Delete': 0x2e,
  'Insert': 0x2d,
  'Home': 0x24,
  'End': 0x23,
  'PageUp': 0x21,
  'PageDown': 0x22,
  'Left': 0x25,
  'Up': 0x26,
  'Right': 0x27,
  'Down': 0x28,
  'PrintScreen': 0x2c,
  'CapsLock': 0x14,
  '-': 0xbd,
  '=': 0xbb,
  '[': 0xdb,
  ']': 0xdd,
  '\\': 0xdc,
  ';': 0xba,
  "'": 0xde,
  ',': 0xbc,
  '.': 0xbe,
  '/': 0xbf,
  '`': 0xc0,
  'MediaPlayPause': 0xb3,
  'VolumeMute': 0xad,
  'VolumeUp': 0xaf,
  'VolumeDown': 0xae,
  for (var i = 0; i < 26; i++) String.fromCharCode(65 + i): 65 + i,
  for (var i = 0; i < 10; i++) '$i': 48 + i,
  for (var i = 1; i <= 24; i++) 'F$i': 0x6f + i,
};

List<String> normalizeChord(Iterable<String> values) {
  final keys = values.toSet();
  if (keys.isEmpty ||
      keys.length > 6 ||
      keys.any((k) => !virtualKeys.containsKey(k))) {
    throw const FormatException('เลือกคีย์ที่รองรับ 1–6 ปุ่ม');
  }
  if (keys.every(modifierKeys.contains)) {
    throw const FormatException('เพิ่มปุ่มหลัก เช่น C พร้อมกับ Ctrl');
  }
  if (keys.containsAll(['Ctrl', 'Alt', 'Delete'])) {
    throw const FormatException('Windows ไม่อนุญาตส่ง Ctrl + Alt + Delete');
  }
  return [
    ...modifierKeys.where(keys.contains),
    ...(keys.where((k) => !modifierKeys.contains(k)).toList()..sort()),
  ];
}

List<String> parseChord(String binding) => normalizeChord(
  binding.split('+').map((k) => k.trim()).where((k) => k.isNotEmpty),
);

/// Confirms the largest simultaneously held chord only after all contacts lift.
/// Sequential taps never accumulate into a multi-key shortcut.
class ChordCapture {
  final Map<int, String> _contacts = {};
  Set<String> _peak = {};
  bool _releasing = false, _invalid = false;
  Set<String> get held => _contacts.values.toSet();
  bool get active => _contacts.isNotEmpty;
  String? error;
  void down(int contact, String key) {
    if (_contacts.containsKey(contact)) return;
    if (_contacts.isEmpty) {
      _peak = {};
      _releasing = false;
      _invalid = false;
      error = null;
    } else if (_releasing) {
      _invalid = true;
    }
    _contacts[contact] = key;
    if (held.length >= _peak.length) _peak = {...held};
  }

  List<String>? up(int contact, {bool cancelled = false}) {
    if (!_contacts.containsKey(contact)) return null;
    if (cancelled) _invalid = true;
    _releasing = true;
    _contacts.remove(contact);
    if (_contacts.isNotEmpty) return null;
    if (_invalid) {
      error = 'ยกเลิกชุดคีย์ กรุณากดทุกปุ่มพร้อมกันแล้วปล่อยมือทั้งหมด';
      return null;
    }
    try {
      return normalizeChord(_peak);
    } on FormatException catch (e) {
      error = e.message;
      return null;
    }
  }

  void cancel() {
    _contacts.clear();
    _peak.clear();
    _releasing = false;
    _invalid = false;
  }
}
