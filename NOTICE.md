# Licensing & Attribution

CrispChess is **MIT-licensed** (see [`LICENSE`](LICENSE)). That covers the app and
its first-party built-in engine, **CrispEngine** (`lib/engines/`, pure Dart).

## Pluggable engines

CrispChess can run different chess engines behind a common interface. Each engine
keeps its own license, and the license of a *distributed build* depends on which
engine is bundled:

| Engine | Location | License | Effect when bundled |
|---|---|---|---|
| CrispEngine | `lib/engines/` (Dart) | MIT | Build stays MIT |
| Frozenight (planned) | — (Rust) | MIT / Apache-2.0 | Build stays permissive |
| **Stockfish** (optional) | `native/` (C++ via FFI) | **GPL-3.0** | **Build becomes GPL-3.0** |

**Stockfish is GPL-3.0.** A build that bundles the Stockfish engine is a combined
work that must be distributed under GPL-3.0 (source available). That is why
Stockfish is offered as an *optional* engine and is excluded on iOS. A build using
only CrispEngine (or another permissive engine) remains MIT.

This mirrors the dual-licensing of the underlying Stockfish Flutter plugin
(GPL-3.0 engine + permissive app code).

> The MIT `LICENSE` text is kept canonical so the license is machine-detectable;
> the engine-licensing nuance lives here in `NOTICE.md`.
