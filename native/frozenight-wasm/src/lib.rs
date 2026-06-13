// Frozenight WASM build — single-threaded for browser.
// MIT/Apache-2.0 licensed. ~2960 ELO NNUE engine.
//
// Compiled with: wasm-pack build --target web --release
// Output: pkg/frozenight_wasm.js + frozenight_wasm_bg.wasm

use wasm_bindgen::prelude::*;
use cozy_chess::Board;
use frozenight::{Eval, Frozenight, TimeConstraint};

static mut ENGINE: Option<Frozenight> = None;

#[wasm_bindgen]
pub fn init(hash_mb: u32) {
    unsafe {
        ENGINE = Some(Frozenight::new(hash_mb as usize));
    }
}

#[wasm_bindgen]
pub fn set_position(fen: &str, moves: &str) {
    unsafe {
        let engine = match ENGINE.as_mut() {
            Some(e) => e,
            None => return,
        };

        let board = if fen == "startpos" {
            Board::default()
        } else {
            match fen.parse::<Board>() {
                Ok(b) => b,
                Err(_) => return,
            }
        };

        let mut current = board.clone();
        let mut move_list = Vec::new();

        if !moves.is_empty() {
            for uci in moves.split_whitespace() {
                if let Some(mv) = parse_uci_move(&current, uci) {
                    current.play(mv);
                    move_list.push(mv);
                }
            }
        }

        engine.set_position(board, move_list.into_iter());
    }
}

#[wasm_bindgen]
pub fn search(depth: i32) -> String {
    unsafe {
        let engine = match ENGINE.as_mut() {
            Some(e) => e,
            None => return String::from("0000"),
        };

        let tc = TimeConstraint {
            depth: depth as i16,
            ..TimeConstraint::INFINITE
        };

        let result = engine.search(tc, |_| {});

        let uci = format!("{}{}", result.best_move.from, result.best_move.to);
        let promo = match result.best_move.promotion {
            Some(p) => format!("{}", p).to_lowercase(),
            None => String::new(),
        };

        format!("{}{}", uci, promo)
    }
}

#[wasm_bindgen]
pub fn get_eval() -> i32 {
    unsafe {
        let engine = match ENGINE.as_mut() {
            Some(e) => e,
            None => return 0,
        };

        let tc = TimeConstraint {
            depth: 1,
            ..TimeConstraint::INFINITE
        };

        let result = engine.search(tc, |_| {});
        let raw: i16 = bytemuck::cast(result.eval);
        raw as i32
    }
}

#[wasm_bindgen]
pub fn dispose() {
    unsafe {
        ENGINE = None;
    }
}

fn parse_uci_move(board: &Board, uci: &str) -> Option<cozy_chess::Move> {
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
