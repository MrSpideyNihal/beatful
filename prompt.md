# BUILD PROMPT: Beatful — Multiplayer Card Game (Android, Flutter + Node.js + MongoDB)

You are building a **complete, production-quality, bug-free** mobile card game called **Beatful**, targeting **Android** first. Read this entire spec before writing any code. Build incrementally, test each layer before moving to the next, and handle every error path explicitly — no silent failures, no unhandled exceptions, no crashes.

---

## 1. PROJECT OVERVIEW

Beatful is a traditional Indian card game (also known as "Sevens"). Players build all four suits outward from each 7, playing upward (8,9,10,J,Q,K) or downward (6,5,4,3,2,A). First player to empty their hand wins.

**Modes:**
- **Solo vs Bots** — fully offline, no internet/server required
- **Play with Friends** — online room, host creates, others join via code or link, custom player count (2–8)

No random matchmaking with strangers. No forced account creation. Guest-based identity with optional name change.

---

## 2. FULL GAME RULES (implement exactly — this is the source of truth)

- Standard 52-card deck, no jokers. 4 suits: ♥ ♦ ♣ ♠. Each suit ranked A,2,3,4,5,6,7,8,9,10,J,Q,K.
- Each suit is a separate sequence anchored at 7. 7 must be played before any other card in that suit.
- From 7, a suit extends **upward** (7→8→9→10→J→Q→K) and **downward** (7→6→5→4→3→2→A) independently. Both directions are always open once 7 is down.
- A card is legal to play **only if** it is the next card outward from the current end of that suit's built sequence in that direction. No skipping.
- On a player's turn: they may play exactly **one legal card**, or **Pass** if they have none.
- Passing does not eliminate a player or skip future turns — they play again next round if they get a move.
- Deal: `cardsPerPlayer = floor(52 / playerCount)`, remainder distributed one extra card each to the first `52 % playerCount` players (by turn order). Support 2–8 players in Friends mode. Bot mode: fixed setup, 2–4 total (player + bots), configurable by host.
- Turn order fixed at game start (order players joined, or shuffled — host setting).
- Win condition: first player to reach **zero cards** wins the round. Remaining players are ranked by cards remaining (fewer = better rank).
- **Turn timer**: configurable by host (default 15s). If timer expires:
  - If player has ≥1 legal move → server auto-plays a **random legal move** for them.
  - If player has 0 legal moves → server auto-passes for them.
  - This logic lives **server-side only**, never trust client timers for enforcement.

Build the rules engine as a **pure, isolated module** (no UI/network dependencies) so it can be:
1. Unit tested exhaustively (legal move detection, skip-prevention, win detection, edge cases like a player receiving zero cards if player count doesn't divide evenly, single-player-left scenarios).
2. Reused identically for bot logic, server validation, and any offline solo mode.

---

## 3. TECH STACK & ARCHITECTURE (decided — do not deviate)

- **Client:** Flutter (Android target, use Riverpod or Bloc for state management — pick one and be consistent)
- **Backend:** Node.js (Express or Fastify), plain REST API — **no Socket.IO, no WebSockets, no Redis**
- **Realtime strategy:** **long-polling**. Client calls `GET /room/:id/state?since=<version>`. Server holds the request open (~25s timeout) until room state's version counter changes, then responds immediately; times out with "no change" if nothing happens. Client immediately re-issues the request after any response.
- **Database:** MongoDB Atlas (free M0 tier initially)
- **Hosting:** Render (or Railway/Fly.io) free tier initially, single web service
- Client's own moves are **never** delayed by polling — a move is sent instantly via `POST /room/:id/play`, applied server-side immediately, and reflected in the response to that same call. Long-polling is only how a client learns about *other* players' actions.
- **Server is the single source of truth for everything.** Client never computes legal moves, never decides who won, never enforces the timer — it only renders state pushed from the server and sends intended actions. Every action is re-validated server-side regardless of what the client thinks is legal.
- Pause polling when: it's the local player's turn (no need to poll), or the app is backgrounded (`AppLifecycleState.paused`/`inactive`). Resume on foreground or after submitting a move.

---

## 4. IDENTITY & ACCOUNTS

- On first launch, generate a persistent **guest ID** (UUID) stored locally (secure storage), sent to server, server creates a `users` doc.
- No email/password/signup flow required to play.
- Editable display name, synced to server, editable anytime from settings.
- Avatar: simple preset icon picker (no image upload for v1).
- Do not block any core gameplay behind account creation.

---

## 5. ROOMS (Friends Mode)

- Host creates room → server generates a short unique room code (e.g. 6 alphanumeric chars) + a deep link (`beatful://join/<code>`).
- Others join via typing the code or opening the link.
- Host-only controls (enforced server-side, not just hidden in UI): player count (2–8), turn timer duration, number of rounds, kick player, lock room (prevent further joins), start game.
- Lobby state: shows joined players, ready status, waits for host to start.
- **Reconnect handling:** if a player's connection drops mid-game, keep their seat reserved for a grace period (e.g. 60s) during which their turns still resolve via auto-play/auto-pass on timer expiry as normal — this doubles as disconnect handling, no special-case code needed. If they reconnect, they resume by simply re-polling current state.
- If a seat never reconnects and host wants to continue, host can replace the seat with a bot (host action) or the game just continues auto-passing/auto-playing that seat's cards, whichever you implement — pick one, document it clearly in-app, and be consistent.

---

## 6. BOT AI (Solo Mode)

Implement three difficulty tiers, all built on top of the same rules engine (no duplicated legal-move logic):

- **Easy:** pick uniformly at random among all currently legal moves.
- **Medium:** prefer the move that reduces hand size fastest; if a card is "stuck" (unlikely to become playable soon, e.g. holding both ends of a suit far from 7), prioritize playing it when legal.
- **Hard:** additionally tracks which suits/ranks haven't appeared yet to infer what other players might be waiting on; deprioritizes releasing a card that clearly unblocks an opponent unless it also unblocks itself significantly; dumps genuinely hard-to-place cards early (e.g. face cards far from 7 in a suit not yet opened).

Bots must call the exact same `isLegalMove()` function used by server validation — never a separate/simplified copy that could drift out of sync with real rules.

---

## 7. ECONOMY

- Persistent **coin** balance per guest user.
- **Free matches**: no coins at stake, purely for practice/casual play.
- **Coin matches**: entry fee deducted from all players when match starts, winner (or ranked split — pick one, make it configurable) receives the pool.
- All coin transactions go through a single server-side, atomic operation (use MongoDB transactions or findOneAndUpdate with proper checks) to avoid race conditions/double-spend — **no client ever decides or reports its own coin balance changes.**
- Shop: cosmetic-only purchases (card backs, table themes) using coins or optional IAP.
- Rewarded ads → small coin grant, capped per day server-side (e.g. max 5/day) to prevent abuse — track ad-grant count per user per day in DB.
- **No cash-out of coins to real money, ever.** Coins are a closed-loop virtual currency. State this explicitly in a Terms screen.

---

## 8. UI/UX REQUIREMENTS (this is the most important part — get this right)

**Design tone:** bright, playful, high-contrast, big touch targets. Must be usable by someone with **zero gaming experience and imperfect eyesight** (explicitly design for elderly users) — no tiny text, no cryptic icons without labels, no more than one menu level deep from Home to starting a game.

**Home screen:** two big clear buttons — "Play vs Bots" and "Play with Friends." Settings/coins/shop accessible from clearly marked icons, not buried.

**Game board:**
- Each suit's built sequence clearly laid out (e.g. 4 horizontal rows, one per suit, cards visually placed left-to-right in rank order with gaps for unplayed ranks).
- Player's own hand fixed at the bottom, cards large enough to read at a glance, fanned or in a clean row — no overlap so severe that ranks are hidden.
- **Legal moves are visually highlighted** (glow/lift/border) on the player's hand; illegal cards are visibly dimmed/greyed but not hidden — player should never wonder "why can't I play this."
- Tap a highlighted card = play it. No drag-and-drop.
- Clear, large "Pass" button, only enabled when the player genuinely has no legal move (auto-detected — don't let a player accidentally pass when they had a move, though you may allow voluntary pass among multiple legal choices only if you decide that's a house rule — default to: pass button is enabled always, but game should nudge/confirm if they pass while a legal move exists, to prevent misclicks).
- **Turn timer**: visible countdown ring/bar around the active player's avatar or seat, unmistakable.
- On timeout: briefly show *what* was auto-played/auto-passed and for whom, so it's never confusing ("Ravi's turn timed out — auto-played 8♥").
- Opponent seats show name, avatar, and card count only (never their actual hand).
- Win/round-end screen: clear ranking, coins won/lost, "Play Again"/"Home" options big and obvious.

**Accessibility specifics:**
- Minimum tappable target ~48dp.
- Text scalable / respects system font size where feasible.
- Avoid relying on color alone to convey legality (also use glow/border/size difference) for colorblind users.
- Sound + haptic feedback on: your turn starts, card played, pass, timer warning (e.g. last 3 seconds), win/lose.

**Audio:** background music (loop, volume slider, mute toggle persisted locally), SFX for play/pass/win/coin. All audio must be interruptible/mutable without restarting the app.

---

## 9. DATABASE SCHEMA (MongoDB — starting point, refine as needed)

```
users
  _id
  guestId (unique, indexed)
  displayName
  coins
  stats { wins, matchesPlayed }
  createdAt

rooms   (active/ephemeral — short TTL, e.g. expire 6h after creation)
  _id / roomCode (indexed, unique)
  hostUserId
  players [{ userId, seatIndex, connected, name }]
  settings { playerCount, timerSeconds, rounds, coinMatch, entryFee }
  gameState { hand data per seat, tableState per suit, currentTurnSeat, turnStartedAt, version }
  status (lobby | in_progress | finished)
  createdAt (TTL index)

matches   (persistent history)
  _id
  roomCode
  players [{ userId, finalRank, cardsRemaining }]
  mode (bot | friends)
  coinMatch, stakes, payouts
  createdAt (TTL index, e.g. expire after 30-90 days)

transactions
  _id
  userId
  type (match_win | match_entry | ad_reward | iap | shop_purchase)
  amount
  balanceAfter
  createdAt
```

Add TTL indexes on `rooms.createdAt` and `matches.createdAt` so old data self-cleans — do not rely on manual cleanup jobs.

---

## 10. API ENDPOINTS (minimum set)

```
POST   /user/init                 -> create/return guest user from device guestId
PATCH  /user/name                 -> update display name

POST   /room/create                -> host creates room, returns roomCode + link
POST   /room/join                  -> join by code
POST   /room/:id/start             -> host starts game (deals cards, sets turn order)
GET    /room/:id/state?since=v     -> long-poll for state, returns full state when version > v, or timeout "no change"
POST   /room/:id/play               -> submit a card play (server validates fully)
POST   /room/:id/pass               -> submit a pass (server validates no legal move exists)
POST   /room/:id/settings          -> host updates settings (pre-start only)
POST   /room/:id/kick               -> host kicks a player

GET    /shop/items
POST   /shop/purchase
POST   /ads/reward                 -> grant capped daily ad coins
```

Every endpoint must:
- Validate the requesting user actually belongs to that room/seat before acting.
- Never trust a client-supplied "it's my turn" claim — check server state.
- Return clear, consistent error shapes (e.g. `{ error: "NOT_YOUR_TURN" }`) so the client can show meaningful messages, never a raw stack trace or generic 500 with no context.

---

## 11. SECURITY & ERROR HANDLING (non-negotiable — this is where bugs hide)

- MongoDB connection string lives **only** in server environment variables (Render dashboard), never in client code, never committed to git. `.env` in `.gitignore` from the first commit.
- Client never has direct DB access — only talks to the Node API.
- Every server route wrapped in try/catch; unhandled promise rejections and uncaught exceptions must be caught globally (process-level handlers) and logged, never crash the whole server process for one bad request.
- Input validation on every endpoint (room code format, name length/characters, numeric bounds on settings) — reject bad input with a clear error, don't let it reach game logic.
- Rate-limit sensitive endpoints (join, play) per user/IP to prevent spam/abuse.
- Coin balance mutations must be atomic — no read-then-write race conditions. Use a single atomic update operation, verify sufficient balance server-side before deducting.
- Server-side move validation is the **only** validation that matters — client-side legal-move highlighting is a UX convenience, never treat it as authoritative even implicitly.
- Log errors with enough context to debug (room id, user id, action) but never log secrets or full request bodies containing sensitive data.
- Flutter side: wrap all network calls in proper error handling — show the user a retry-able, human-readable message on failure (timeout, no connection, server error), never a silent hang or a raw exception surfaced to the UI. Handle: no internet, server sleeping/cold-starting (show "connecting..." state, not an error, for the first ~60s), room not found, room full, room already started.

---

## 12. DEPLOYMENT NOTES

- Deploy Node server to Render as a Web Service (free tier to start).
- MongoDB Atlas free M0 cluster, restrict network access to Render's IPs where possible, create a least-privilege DB user (not admin).
- Optional: GitHub Actions cron job pinging the server every ~10 min to reduce cold-start frequency during active hours — document this clearly as an optional workaround, not a permanent architecture piece.
- Environment variables required: `MONGO_URI`, `PORT`, `NODE_ENV`, any JWT/session secret used for guest auth tokens.

---

## 13. TESTING REQUIREMENTS

- Unit tests for the rules engine covering: normal play, skip-prevention, both directions from 7, pass detection (true zero legal moves), win detection, uneven card distribution across odd player counts, edge case of a suit fully completed.
- Bot-vs-bot simulation (run full games bot-vs-bot headlessly) to catch rules engine bugs before any UI exists.
- API-level tests for: illegal move rejection, out-of-turn rejection, timer auto-play/auto-pass correctness, coin transaction atomicity under concurrent requests.
- Manual QA pass on real Android device (not just emulator) for: touch target sizing, timer visibility in bright/dim conditions, reconnect behavior (turn WiFi off/on mid-game), app backgrounding during opponent's turn.

---

## 14. BUILD ORDER (follow this sequence, don't skip ahead)

1. Rules engine as standalone module + full unit test suite + bot-vs-bot simulation running clean.
2. Node API with in-memory or basic Mongo-backed room state, all endpoints from Section 10, fully validated per Section 11.
3. Flutter UI for Solo vs Bots (fully playable offline-feeling loop against the same engine, even though bots run server-side — confirms UI/UX end to end without networking complexity).
4. Long-polling integration + Friends mode (create/join/lobby/host settings).
5. Guest accounts + coins + transactions.
6. Shop + ads integration.
7. Polish pass: music, SFX, haptics, animations, timer visuals, accessibility check.
8. Full QA pass per Section 13 before considering this "done."

---

## 15. DEFINITION OF DONE

Do not consider this complete until:
- No unhandled exceptions anywhere in server logs during a full bot-vs-bot stress run and a real multi-device Friends match.
- Every client network call has a visible loading/error/retry state — nothing ever hangs silently.
- A first-time user with no explanation can open the app and correctly play a full game vs bots without confusion.
- Coin balances are verified consistent (no drift) after 50+ simulated coin matches with concurrent requests.
- App tested and confirmed working on a real Android device, not just an emulator.
