#!/usr/bin/env python3
"""Play this app's Lc0 against lc0 itself, on the same weights.

The layer-by-layer comparison in compare_network.py checks one network
evaluation. It cannot see the search: whether the tree is built correctly,
whether values are backed up with the right sign, whether the leaf evaluations
describe the positions they claim to. A game does see that, and an opponent
running the same weights is the control — if the two are faithful to each
other, neither should dominate.

Both modes give each engine the same *node* budget rather than the same clock,
so the result is about the implementation and not about how fast a pure-Dart
ONNX runtime is.

  agreement  ask both engines for a move in the same positions, at several
             node budgets. Divergence that grows with the budget points at the
             search; divergence already at one node points at the network.
  match      play games, alternating colours.

    python3 tool/oracle/match.py match --ours "dart run ..." --lc0 ./lc0 \\
        --weights maia-1900.pb.gz --games 20 --nodes 100
"""
import argparse
import math
import shlex
import subprocess
import sys

import chess


class Uci:
    def __init__(self, command, name):
        self.name = name
        self.recent = []
        self.proc = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.send("uci")
        self.wait("uciok")

    def send(self, line):
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def wait(self, token):
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError(
                    f"{self.name} exited waiting for {token!r}; last output:\n"
                    + "\n".join(self.recent[-8:]))
            self.recent.append(line.rstrip())
            if line.split(" ")[0].strip() == token:
                return line.strip()

    def new_game(self):
        self.send("ucinewgame")
        self.send("isready")
        self.wait("readyok")

    def best_move(self, moves, nodes):
        played = " moves " + " ".join(moves) if moves else ""
        self.send(f"position startpos{played}")
        self.send(f"go nodes {nodes}")
        return self.wait("bestmove").split()[1]

    def close(self):
        try:
            self.send("quit")
            self.proc.wait(timeout=15)
        except Exception:
            self.proc.kill()


def elo(score, games):
    """Elo difference implied by a score, with the ends clamped."""
    if games == 0:
        return 0.0
    p = min(max(score / games, 1e-3), 1 - 1e-3)
    return -400 * math.log10(1 / p - 1)


def agreement(ours, theirs, positions, budgets):
    print(f"{'nodes':>6}  {'same move':>12}  examples of divergence")
    for nodes in budgets:
        same = 0
        total = 0
        examples = []
        for name, moves in positions:
            board = chess.Board()
            ok = True
            for uci in moves:
                try:
                    board.push(chess.Move.from_uci(uci))
                except Exception:
                    ok = False
                    break
            if not ok or board.is_game_over() or board.legal_moves.count() < 2:
                continue
            total += 1
            a = ours.best_move(moves, nodes)
            b = theirs.best_move(moves, nodes)
            if a == b:
                same += 1
            elif len(examples) < 3:
                examples.append(f"{name}: ours {a}, lc0 {b}")
        print(f"{nodes:>6}  {same:>5}/{total:<6}  {'; '.join(examples)}")


def play(ours, theirs, games, nodes, ply_cap, openings):
    """Play `games`, alternating colours and openings.

    Both engines are deterministic, so without an opening line every game is
    the same game: six games from the start position produce one result
    repeated six times and look like evidence. Each opening is played twice,
    once with each colour.
    """
    results = {"win": 0, "draw": 0, "loss": 0}
    for game in range(games):
        ours_is_white = game % 2 == 0
        opening = openings[(game // 2) % len(openings)] if openings else []
        ours.new_game()
        theirs.new_game()
        board = chess.Board()
        moves = []
        for uci in opening:
            move = chess.Move.from_uci(uci)
            if move not in board.legal_moves:
                break
            board.push(move)
            moves.append(uci)
        reason = "ply cap"
        while len(moves) < ply_cap:
            if board.is_game_over(claim_draw=True):
                reason = board.result(claim_draw=True)
                break
            to_move = ours if (board.turn == chess.WHITE) == ours_is_white \
                else theirs
            uci = to_move.best_move(moves, nodes)
            try:
                move = chess.Move.from_uci(uci)
            except Exception:
                move = None
            if move is None or move not in board.legal_moves:
                # An illegal move loses the game and is worth saying out loud:
                # it is a different failure from playing badly.
                print(f"  game {game + 1}: {to_move.name} returned an illegal "
                      f"move {uci!r} in {board.fen()}")
                reason = "0-1" if to_move is ours and ours_is_white else "1-0"
                break
            board.push(move)
            moves.append(uci)

        outcome = board.result(claim_draw=True) if board.is_game_over(
            claim_draw=True) else (reason if reason in ("1-0", "0-1") else "1/2-1/2")
        if outcome == "1/2-1/2":
            results["draw"] += 1
            tag = "draw"
        else:
            white_won = outcome == "1-0"
            we_won = white_won == ours_is_white
            results["win" if we_won else "loss"] += 1
            tag = "win" if we_won else "loss"
        print(f"  game {game + 1:>2}/{games}  ours as "
              f"{'white' if ours_is_white else 'black'}  {len(moves):>3} plies"
              f"  opening {' '.join(opening) or '(none)':<24}  {tag}")

    played = sum(results.values())
    score = results["win"] + 0.5 * results["draw"]
    print(f"\n  ours {results['win']}W {results['draw']}D {results['loss']}L"
          f"  =  {score}/{played}  ({elo(score, played):+.0f} Elo)")
    return results


def read_positions(path):
    out = []
    for line in open(path):
        if line.startswith("#") or not line.strip():
            continue
        name, _, moves = line.rstrip("\n").partition("\t")
        out.append((name, moves.split()))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["agreement", "match"])
    ap.add_argument("--ours", required=True, help="command line for our engine")
    ap.add_argument("--lc0", required=True)
    ap.add_argument("--weights", required=True)
    ap.add_argument("--backend", default="eigen")
    ap.add_argument("--positions", default="tool/oracle/positions.txt")
    ap.add_argument("--games", type=int, default=20)
    ap.add_argument("--nodes", type=int, default=100)
    ap.add_argument("--ply-cap", type=int, default=200)
    ap.add_argument("--budgets", default="1,10,100,800")
    ap.add_argument("--cpuct", default="2.5")
    ap.add_argument("--opening-plies", type=int, default=4,
                    help="plies of opening taken from --positions per game")
    args = ap.parse_args()

    ours = Uci(shlex.split(args.ours), "ours")
    # cpuct matches the app's MctsConfig default, so the two searches are
    # exploring on the same terms; without that, divergence in move choice
    # says more about the constant than about either implementation.
    theirs = Uci([args.lc0, f"--weights={args.weights}",
                  f"--backend={args.backend}", "--policy-softmax-temp=1.0",
                  "--minibatch-size=1", "--threads=1",
                  f"--cpuct={args.cpuct}"], "lc0")
    try:
        if args.mode == "agreement":
            agreement(ours, theirs, read_positions(args.positions),
                      [int(b) for b in args.budgets.split(",")])
        else:
            # Openings come from the same generated file the rest of the
            # oracle uses, trimmed to a few plies so the games diverge early
            # without handing either side a decided position.
            openings = [moves[:args.opening_plies]
                        for name, moves in read_positions(args.positions)
                        if name.startswith("random-")
                        and len(moves) >= args.opening_plies]
            play(ours, theirs, args.games, args.nodes, args.ply_cap, openings)
    finally:
        ours.close()
        theirs.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
