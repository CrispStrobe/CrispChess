#!/usr/bin/env python3
"""lc0's INPUT_CLASSICAL_112_PLANE encoding, transcribed from lc0.

Ground truth is `EncodePositionForNN` in lc0's src/neural/encoder.cc. This is a
transcription of the classical branch of it, using python-chess for the board,
so the app's Dart encoder can be diffed against something other than itself.

The planes come out the way lc0 stores them — an `InputPlane` is a 64-bit mask
plus the value its set bits carry, bit i being square i with a1 = 0.

The two things worth stating because they are easy to get backwards:

  * Planes 104-107 are queenside first. lc0's own comment:
        Plane 104 filled with 1 if we can castle queenside.
        Plane 105 filled with ones if we can castle kingside.
    and likewise 106/107 for the opponent.
  * Plane 109 holds the rule-50 counter as a *raw ply count*. The division by
    100 belongs to the "hectoplies" input formats, which the Maia networks are
    not — they are classical.
"""
import chess

KAUX = 104
PLANES_PER_BOARD = 13
MOVE_HISTORY = 8


def _mask(squares):
    m = 0
    for sq in squares:
        m |= 1 << sq
    return m


def _position_key(board):
    """What counts as the same position for repetition purposes."""
    return (board.board_fen(), board.turn, board.castling_rights,
            board.ep_square)


def encode(moves, history_fill="fen_only"):
    """Encode the position reached by playing `moves` from the start.

    Returns a list of 112 (mask, value) pairs.
    """
    board = chess.Board()
    positions = [board.copy(stack=False)]
    seen = {_position_key(board): 1}
    repetitions = [0]
    for uci in moves:
        board.push(chess.Move.from_uci(uci))
        key = _position_key(board)
        repetitions.append(seen.get(key, 0))
        seen[key] = seen.get(key, 0) + 1
        positions.append(board.copy(stack=False))

    planes = [(0, 0.0)] * 112
    current = positions[-1]
    we_are_black = current.turn == chess.BLACK

    # --- history planes -----------------------------------------------------
    # Every slot is presented from the *root* player's point of view. lc0 gets
    # there by mirroring every other board as it walks back through the game
    # (each one is stored from its own side-to-move's view); the effect is that
    # planes 0-5 are always the root player's pieces, on the root player's
    # orientation.
    for i in range(MOVE_HISTORY):
        idx = len(positions) - 1 - i
        if idx < 0:
            # fen_only: a game that began at the start position stops here
            # rather than repeating it into the remaining slots.
            if history_fill == "fen_only" and positions[0].board_fen() == \
                    chess.STARTING_BOARD_FEN:
                break
            idx = 0
        position = positions[idx]

        us = chess.BLACK if we_are_black else chess.WHITE
        them = not us
        base = i * PLANES_PER_BOARD

        def squares(colour, piece_type):
            out = []
            for sq in position.pieces(piece_type, colour):
                out.append(chess.square_mirror(sq) if we_are_black else sq)
            return out

        for offset, piece_type in enumerate(
                [chess.PAWN, chess.KNIGHT, chess.BISHOP, chess.ROOK,
                 chess.QUEEN, chess.KING]):
            planes[base + offset] = (_mask(squares(us, piece_type)), 1.0)
            planes[base + 6 + offset] = (_mask(squares(them, piece_type)), 1.0)

        if repetitions[idx] >= 1:
            planes[base + 12] = ((1 << 64) - 1, 1.0)

    # --- auxiliary planes ---------------------------------------------------
    def can_castle(colour, kingside):
        return bool(current.castling_rights &
                    (chess.BB_H1 if kingside else chess.BB_A1) <<
                    (0 if colour == chess.WHITE else 56))

    us = chess.BLACK if we_are_black else chess.WHITE
    them = not us
    full = (1 << 64) - 1
    for offset, (colour, kingside) in enumerate(
            [(us, False), (us, True), (them, False), (them, True)]):
        if can_castle(colour, kingside):
            planes[KAUX + offset] = (full, 1.0)

    if we_are_black:
        planes[KAUX + 4] = (full, 1.0)
    planes[KAUX + 5] = (full, float(current.halfmove_clock))
    # KAUX + 6 stays zero: it used to be the move counter.
    planes[KAUX + 7] = (full, 1.0)
    return planes
