import 'url_open_stub.dart'
    if (dart.library.js_interop) 'url_open_web.dart' as impl;

void openUrlInNewTab(String url) => impl.openUrlInNewTab(url);
