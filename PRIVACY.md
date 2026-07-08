# Privacy Policy — CrispChess

**Last updated:** July 2026

## Short version

CrispChess does not collect, sell, or share any personal data. It has no
analytics, no tracking, no advertising, and no account system.

## What data is collected

None. CrispChess does not collect, transmit, or have any way to access
personal data about you. There is no server component operated by
CrispChess that receives or stores user data.

## What's stored on your device

- **Settings and preferences** (engine choice, board theme, language,
  time control, bookmarked positions, puzzle/drill progress) are saved
  locally on your device using standard platform storage
  (`UserDefaults`/`SharedPreferences`). This data never leaves your device.
- **In-progress game state** (current board position, move history) exists
  only in memory while the app is open and is lost when you close it,
  unless you explicitly save/export it (e.g. copying PGN).
- **Downloaded engine files** (Lc0, Stockfish, Lynx binaries or neural
  network weights) are cached locally after first download so they don't
  need to be re-fetched.

None of the above is transmitted anywhere — it stays on your device.

## Network requests

CrispChess makes network requests for functional purposes only:

- **Downloading chess engines and neural network weights** (Lc0,
  Stockfish, Lynx) the first time you select one, typically from GitHub
  Releases or similar public hosting.
- **Querying a public opening-book/tablebase API** when you use the
  Opening Explorer feature.

These requests carry no personal data from CrispChess — no account
identifiers, no analytics payloads, nothing app-specific beyond what's
needed to fetch the file or position you requested. Like any network
request, they inherently expose your IP address to the receiving server,
which is outside CrispChess's control and covered by that server's own
practices, not this app's.

There is no analytics SDK, no crash reporting, no advertising, and no
telemetry of any kind.

## Web version

The web version at crispchess.vercel.app is a static site hosted on
Vercel. Vercel may log standard HTTP access data (IP address, user agent)
per their own privacy policy. CrispChess itself sends no personal data to
any server; the same engine-download and opening-book requests described
above apply to the web version as well.

## Third-party services

- Engine/model hosting (e.g. GitHub Releases) — receives only the request
  needed to download a file.
- Public opening-book/tablebase API — receives only the board position
  queried.
- Vercel (web version hosting only) — standard HTTP access logs.

No analytics SDKs, no crash reporting services, no advertising networks.

## Children

This app is safe for all ages. No personal data of any kind is collected
or transmitted.

## Changes

If we ever add features that involve collecting or transmitting personal
data, this policy will be updated first and any such collection will be
opt-in.

## Contact

Christian Stroebele
postmaster@crispstro.be
