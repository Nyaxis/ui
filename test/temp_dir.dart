import 'dart:io';

/// deletes [dir], waiting for the writes that still have a file in it open,
/// which windows does not delete from under them
Future<void> deleteTemp(Directory dir) async {
  for (var i = 0; i < 100; i++) {
    try {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}
