// Picks the native bitboard search on VM/AOT builds and a stub on web. Web must
// never reach the bitboard library (64-bit, not dart2js-compilable), so the
// import is gated on `dart.library.js_interop`.
export 'native_search_bitboard.dart'
    if (dart.library.js_interop) 'native_search_stub.dart';
