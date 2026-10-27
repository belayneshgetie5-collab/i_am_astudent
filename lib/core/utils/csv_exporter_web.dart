import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<String> exportCsv(String filename, String csv) async {
  final blob = web.Blob(
    ['\uFEFF$csv'.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return filename;
}
