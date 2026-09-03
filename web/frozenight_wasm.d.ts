/* tslint:disable */
/* eslint-disable */

/**
 * Debug: try to parse a UCI move and return info about what happened.
 */
export function debug_parse_move(fen: string, uci_move: string): string;

export function dispose(): void;

export function get_eval(): number;

/**
 * Returns the FEN of the current board position (for debugging).
 */
export function get_fen(): string;

export function init(hash_mb: number): void;

export function search(depth: number): string;

export function set_position(fen: string, moves: string): void;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly debug_parse_move: (a: number, b: number, c: number, d: number) => [number, number];
    readonly dispose: () => void;
    readonly get_eval: () => number;
    readonly get_fen: () => [number, number];
    readonly init: (a: number) => void;
    readonly search: (a: number) => [number, number];
    readonly set_position: (a: number, b: number, c: number, d: number) => void;
    readonly __externref_table_alloc: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
