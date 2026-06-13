use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use cozy_chess::{Board, Move};
use frozenight::{Eval, MtFrozenight, SearchInfo, TimeConstraint};

struct EngineState {
    engine: MtFrozenight,
}

static STATE: Mutex<Option<EngineState>> = Mutex::new(None);
static RESULT: Mutex<Option<SearchResult>> = Mutex::new(None);
static SEARCH_DONE: (Mutex<bool>, Condvar) = (Mutex::new(false), Condvar::new());

struct SearchResult {
    best_move: CString,
    score_cp: i32,
    depth: i32,
}

fn eval_to_cp(eval: Eval) -> i32 {
    // Eval is #[repr(transparent)] over i16 and derives Pod.
    // Extract the raw i16 value via bytemuck.
    let raw: i16 = bytemuck::cast(eval);
    raw as i32
}

#[no_mangle]
pub extern "C" fn frozenight_init(hash_mb: u32) -> i32 {
    let engine = MtFrozenight::new(hash_mb as usize);
    *STATE.lock().unwrap() = Some(EngineState { engine });
    0
}

#[no_mangle]
pub extern "C" fn frozenight_set_position(fen: *const c_char, moves: *const c_char) -> i32 {
    let fen_str = unsafe {
        if fen.is_null() { return -1; }
        match CStr::from_ptr(fen).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };

    let board = if fen_str == "startpos" {
        Board::default()
    } else {
        match fen_str.parse::<Board>() {
            Ok(b) => b,
            Err(_) => return -1,
        }
    };

    let mut move_list = Vec::new();
    let mut current = board.clone();

    if !moves.is_null() {
        let moves_str = unsafe {
            match CStr::from_ptr(moves).to_str() {
                Ok(s) => s,
                Err(_) => "",
            }
        };
        for uci in moves_str.split_whitespace() {
            if let Some(mv) = parse_uci_move(&current, uci) {
                current.play(mv);
                move_list.push(mv);
            }
        }
    }

    let mut state = STATE.lock().unwrap();
    if let Some(s) = state.as_mut() {
        s.engine.set_position(board, move_list.into_iter());
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn frozenight_search(depth: i32) -> i32 {
    {
        let mut done = SEARCH_DONE.0.lock().unwrap();
        *done = false;
    }

    let result_holder: Arc<Mutex<Option<SearchResult>>> = Arc::new(Mutex::new(None));
    let result_for_info = result_holder.clone();
    let result_for_finish = result_holder.clone();

    {
        let mut state = STATE.lock().unwrap();
        let s = match state.as_mut() {
            Some(s) => s,
            None => return -1,
        };

        let tc = TimeConstraint {
            depth: depth as i16,
            ..TimeConstraint::INFINITE
        };

        s.engine.search(
            tc,
            move |info: &SearchInfo| {
                let uci = format!("{}{}", info.best_move.from, info.best_move.to);
                let promo = match info.best_move.promotion {
                    Some(p) => format!("{}", p).to_lowercase(),
                    None => String::new(),
                };
                let full_uci = format!("{}{}", uci, promo);
                let score = eval_to_cp(info.eval);
                *result_for_info.lock().unwrap() = Some(SearchResult {
                    best_move: CString::new(full_uci).unwrap_or_default(),
                    score_cp: score,
                    depth: info.depth as i32,
                });
            },
            move |info: &SearchInfo| {
                let uci = format!("{}{}", info.best_move.from, info.best_move.to);
                let promo = match info.best_move.promotion {
                    Some(p) => format!("{}", p).to_lowercase(),
                    None => String::new(),
                };
                let full_uci = format!("{}{}", uci, promo);
                let score = eval_to_cp(info.eval);
                *result_for_finish.lock().unwrap() = Some(SearchResult {
                    best_move: CString::new(full_uci).unwrap_or_default(),
                    score_cp: score,
                    depth: info.depth as i32,
                });
                let mut done = SEARCH_DONE.0.lock().unwrap();
                *done = true;
                SEARCH_DONE.1.notify_all();
            },
        );
    }

    let mut done = SEARCH_DONE.0.lock().unwrap();
    while !*done {
        done = SEARCH_DONE.1.wait(done).unwrap();
    }

    let final_result = result_holder.lock().unwrap().take();
    *RESULT.lock().unwrap() = final_result;

    if RESULT.lock().unwrap().is_some() { 0 } else { -1 }
}

#[no_mangle]
pub extern "C" fn frozenight_get_best_move() -> *const c_char {
    let guard = RESULT.lock().unwrap();
    match guard.as_ref() {
        Some(r) => r.best_move.as_ptr(),
        None => std::ptr::null(),
    }
}

#[no_mangle]
pub extern "C" fn frozenight_get_score() -> i32 {
    RESULT.lock().unwrap().as_ref().map(|r| r.score_cp).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn frozenight_get_depth() -> i32 {
    RESULT.lock().unwrap().as_ref().map(|r| r.depth).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn frozenight_dispose() {
    *STATE.lock().unwrap() = None;
    *RESULT.lock().unwrap() = None;
}

fn parse_uci_move(board: &Board, uci: &str) -> Option<Move> {
    if uci.len() < 4 { return None; }
    let from = uci[0..2].parse().ok()?;
    let to = uci[2..4].parse().ok()?;
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

    let mut result = None;
    board.generate_moves(|moves| {
        for mv in moves {
            if mv.from == from && mv.to == to {
                match (promotion, mv.promotion) {
                    (Some(p), Some(mp)) if p == mp => { result = Some(mv); return false; }
                    (None, None) => { result = Some(mv); return false; }
                    (None, Some(_)) => { result = Some(mv); return false; }
                    _ => {}
                }
            }
        }
        true
    });
    result
}
