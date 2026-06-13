use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Arc, Mutex};

use cozy_chess::Board;
use frozenight::{Eval, MtFrozenight, TimeConstraint};

/// Global engine instance behind a mutex for FFI safety.
static ENGINE: Mutex<Option<MtFrozenight>> = Mutex::new(None);
static LAST_BEST_MOVE: Mutex<Option<CString>> = Mutex::new(None);
static LAST_EVAL: Mutex<(i32, i32)> = Mutex::new((0, 0)); // (score_cp, depth)

/// Initialize the engine with the given hash size in MB.
#[no_mangle]
pub extern "C" fn frozenight_init(hash_mb: u32) -> i32 {
    let engine = MtFrozenight::new(hash_mb as usize);
    *ENGINE.lock().unwrap() = Some(engine);
    0 // success
}

/// Set the position from a FEN string, then apply moves.
/// `fen` is a null-terminated FEN string (or "startpos").
/// `moves` is a null-terminated space-separated UCI moves string (or null for none).
#[no_mangle]
pub extern "C" fn frozenight_set_position(
    fen: *const c_char,
    moves: *const c_char,
) -> i32 {
    let fen_str = unsafe {
        if fen.is_null() { return -1; }
        CStr::from_ptr(fen).to_str().unwrap_or("startpos")
    };

    let board = if fen_str == "startpos" {
        Board::default()
    } else {
        match fen_str.parse::<Board>() {
            Ok(b) => b,
            Err(_) => return -1,
        }
    };

    let mut engine = ENGINE.lock().unwrap();
    let engine = match engine.as_mut() {
        Some(e) => e,
        None => return -2,
    };

    engine.set_position(board.clone(), &[]);

    // Apply moves if provided
    if !moves.is_null() {
        let moves_str = unsafe { CStr::from_ptr(moves).to_str().unwrap_or("") };
        if !moves_str.is_empty() {
            let mut current = board;
            let mut move_list = Vec::new();
            for uci_move in moves_str.split_whitespace() {
                if let Some(mv) = parse_uci_move(&current, uci_move) {
                    current.play(mv);
                    move_list.push(mv);
                }
            }
            engine.set_position(board, &move_list);
        }
    }

    0
}

/// Search for the best move with the given depth limit.
/// Returns 0 on success, stores result accessible via frozenight_get_best_move().
#[no_mangle]
pub extern "C" fn frozenight_search(depth: i32) -> i32 {
    let mut engine = ENGINE.lock().unwrap();
    let engine = match engine.as_mut() {
        Some(e) => e,
        None => return -1,
    };

    let tc = TimeConstraint::Depth(depth as i16);
    let mut best_move = None;
    let mut best_score = 0i32;
    let mut best_depth = 0i32;

    engine.search(tc, &mut |info| {
        best_move = Some(info.best_move);
        best_score = match info.eval {
            Eval::Centipawns(cp) => cp as i32,
            Eval::MateIn(m) => 30000 - m as i32,
            Eval::MatedIn(m) => -30000 + m as i32,
        };
        best_depth = info.depth as i32;
    });

    if let Some(mv) = best_move {
        let uci = format_uci_move(mv);
        *LAST_BEST_MOVE.lock().unwrap() = CString::new(uci).ok();
        *LAST_EVAL.lock().unwrap() = (best_score, best_depth);
        0
    } else {
        -1
    }
}

/// Get the best move from the last search as a null-terminated string.
/// Returns null if no search has been performed.
#[no_mangle]
pub extern "C" fn frozenight_get_best_move() -> *const c_char {
    let guard = LAST_BEST_MOVE.lock().unwrap();
    match guard.as_ref() {
        Some(s) => s.as_ptr(),
        None => std::ptr::null(),
    }
}

/// Get the evaluation score in centipawns from the last search.
#[no_mangle]
pub extern "C" fn frozenight_get_score() -> i32 {
    LAST_EVAL.lock().unwrap().0
}

/// Get the search depth reached in the last search.
#[no_mangle]
pub extern "C" fn frozenight_get_depth() -> i32 {
    LAST_EVAL.lock().unwrap().1
}

/// Dispose the engine and free resources.
#[no_mangle]
pub extern "C" fn frozenight_dispose() {
    *ENGINE.lock().unwrap() = None;
    *LAST_BEST_MOVE.lock().unwrap() = None;
}

/// Parse a UCI move string (e.g. "e2e4", "e7e8q") into a cozy_chess Move.
fn parse_uci_move(board: &Board, uci: &str) -> Option<cozy_chess::Move> {
    if uci.len() < 4 { return None; }

    let from = parse_square(&uci[0..2])?;
    let to = parse_square(&uci[2..4])?;
    let promotion = if uci.len() > 4 {
        match uci.as_bytes()[4] {
            b'q' => Some(cozy_chess::Piece::Queen),
            b'r' => Some(cozy_chess::Piece::Rook),
            b'b' => Some(cozy_chess::Piece::Bishop),
            b'n' => Some(cozy_chess::Piece::Knight),
            _ => None,
        }
    } else {
        None
    };

    // Find the matching legal move
    let mut result = None;
    board.generate_moves(|moves| {
        for mv in moves {
            if mv.from == from && mv.to == to {
                if let Some(promo) = promotion {
                    if mv.promotion == Some(promo) {
                        result = Some(mv);
                        return false;
                    }
                } else if mv.promotion.is_none() || mv.promotion == Some(cozy_chess::Piece::Queen) {
                    result = Some(mv);
                    return false;
                }
            }
        }
        true
    });
    result
}

fn parse_square(s: &str) -> Option<cozy_chess::Square> {
    let bytes = s.as_bytes();
    if bytes.len() < 2 { return None; }
    let file = match bytes[0] {
        b'a'..=b'h' => cozy_chess::File::index((bytes[0] - b'a') as usize),
        _ => return None,
    };
    let rank = match bytes[1] {
        b'1'..=b'8' => cozy_chess::Rank::index((bytes[1] - b'1') as usize),
        _ => return None,
    };
    Some(cozy_chess::Square::new(file, rank))
}

fn format_uci_move(mv: cozy_chess::Move) -> String {
    let from = format!("{}{}", (b'a' + mv.from.file() as u8) as char, (b'1' + mv.from.rank() as u8) as char);
    let to = format!("{}{}", (b'a' + mv.to.file() as u8) as char, (b'1' + mv.to.rank() as u8) as char);
    let promo = match mv.promotion {
        Some(cozy_chess::Piece::Queen) => "q",
        Some(cozy_chess::Piece::Rook) => "r",
        Some(cozy_chess::Piece::Bishop) => "b",
        Some(cozy_chess::Piece::Knight) => "n",
        _ => "",
    };
    format!("{}{}{}", from, to, promo)
}
