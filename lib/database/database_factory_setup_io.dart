import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> initializeDatabaseFactory({required bool isWeb}) async {
  if (isWeb ||
      (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
    return;
  }

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
