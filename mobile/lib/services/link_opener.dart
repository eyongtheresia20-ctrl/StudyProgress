import 'link_opener_stub.dart'
    if (dart.library.js_interop) 'link_opener_web.dart' as impl;

Future<bool> openExternalUrl(String url) => impl.openExternalUrl(url);

