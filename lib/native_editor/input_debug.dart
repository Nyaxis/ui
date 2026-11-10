import 'dart:io';

/// temporary: notes what the input method does, in a file, to find why typing
/// does not work on windows. it never records the text that is typed.
void inputLog(String message) {
  try {
    final base = Platform.environment['APPDATA'];
    if (base == null) {
      return;
    }
    final directory = Directory('$base\\Nyaxis');
    if (!directory.existsSync()) {
      return;
    }
    File('${directory.path}\\input-debug.log').writeAsStringSync(
      '${DateTime.now().toIso8601String()} $message\n',
      mode: FileMode.append,
    );
  } on Object {
    // logging must never get in the way
  }
}
