import 'package:web/web.dart' as web;

Future<bool> openExternalUrl(String url) async {
  final clean = url.trim();
  if (clean.isEmpty) return false;
  try {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = clean;
    anchor.target = '_blank';
    anchor.rel = 'noopener noreferrer';
    anchor.style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    try {
      web.window.open(clean, '_blank', 'noopener,noreferrer');
      return true;
    } catch (_) {
      return false;
    }
  }
}

