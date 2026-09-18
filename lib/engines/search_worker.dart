// Picks the owned native search worker on VM/AOT builds and a stub on web.
// Web has no isolates in the dart2js sense used here; the browser path keeps
// using the chess-package search inside DartEngine._searchWeb.
export 'native_search_worker.dart'
    if (dart.library.js_interop) 'native_search_worker_stub.dart';
