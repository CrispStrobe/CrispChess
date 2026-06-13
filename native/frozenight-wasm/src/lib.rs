use wasm_bindgen::prelude::*;
use cozy_chess::Board;
use frozenight::{Frozenight, TimeConstraint};

static mut ENGINE: Option<Frozenight> = None;
static mut CURRENT_BOARD: Option<Board> = None;

#[wasm_bindgen]
pub fn init(hash_mb: u32) {
    unsafe {
        ENGINE = Some(Frozenight::new(hash_mb as usize));
        CURRENT_BOARD = Some(Board::default());
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

        // Store the final board position for debugging
        CURRENT_BOARD = Some(current);

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

        format!("{}{}{}",
            result.best_move.from,
            result.best_move.to,
            match result.best_move.promotion {
                Some(p) => format!("{}", p).to_lowercase(),
                None => String::new(),
            }
        )
    }
}

/// Returns the FEN of the current board position (for debugging).
#[wasm_bindgen]
pub fn get_fen() -> String {
    unsafe {
        match &CURRENT_BOARD {
            Some(b) => b.to_string(),
            None => String::from("no board"),
        }
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
        CURRENT_BOARD = None;
    }
}

/// Debug: try to parse a UCI move and return info about what happened.
#[wasm_bindgen]
pub fn debug_parse_move(fen: &str, uci_move: &str) -> String {
    let board = if fen == "startpos" {
        Board::default()
    } else {
        match fen.parse::<Board>() {
            Ok(b) => b,
            Err(e) => return format!("FEN parse error: {:?}", e),
        }
    };

    if uci_move.len() < 4 {
        return format!("Move too short: {}", uci_move);
    }

    let from_str = &uci_move[0..2];
    let to_str = &uci_move[2..4];

    let from: cozy_chess::Square = match from_str.parse() {
        Ok(s) => s,
        Err(_) => return format!("Cannot parse from square: '{}'", from_str),
    };
    let to: cozy_chess::Square = match to_str.parse() {
        Ok(s) => s,
        Err(_) => return format!("Cannot parse to square: '{}'", to_str),
    };

    // List all legal moves
    let mut all_moves = Vec::new();
    let mut matching = Vec::new();
    board.generate_moves(|moves| {
        for mv in moves {
            all_moves.push(format!("{}{}", mv.from, mv.to));
            if mv.from == from && mv.to == to {
                matching.push(format!("{}{} promo={:?}", mv.from, mv.to, mv.promotion));
            }
        }
        true
    });

    format!(
        "from={} to={} matching={:?} total_moves={} side={:?}",
        from, to, matching, all_moves.len(),
        board.side_to_move()
    )
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
