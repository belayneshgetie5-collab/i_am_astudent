import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<String> exportCsv(String filename, String csv) async {
  final directory = await getDatabasesPath();
  final file = File(path.join(directory, filename));
  await file.writeAsString('\uFEFF$csv', encoding: utf8, flush: true);
  return file.path;
}
