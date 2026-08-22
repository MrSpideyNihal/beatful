# Beatful

Sevens, the Indian family card game, for Android. Play against bots offline, or
share a six character code and play with friends over the internet.

One deck, no jokers. Each suit is its own run that starts at its 7 and grows in
both directions, one card per turn. Whoever empties their hand first wins the
round, and everyone else is ranked by how many cards they were left holding.

## Layout

    app/          Flutter client (Android)
    server/       Node and Express API
    tools/        one off generators, currently the audio cues
    Assests/      source card artwork, copied into app/assets/cards

The rules live twice on purpose: `server/src/game/rules.js` is the authority for
every online match, and `app/lib/game/rules.dart` is the same logic for offline
solo play. `server/scripts/gen-vectors.js` writes golden vectors that both sides
replay in their test suites, so the two cannot quietly drift apart.

## Running the server

    cd server
    npm install
    cp .env.example .env
    npm run dev

With no `MONGO_URI` set outside production the server runs on an in memory store,
which is enough for the whole game on one machine. `GET /health` reports the
store it ended up using.

## Running the app

    cd app
    flutter pub get
    flutter run --dart-define=BEATFUL_API=http://10.0.2.2:3000

`10.0.2.2` is how the Android emulator reaches the host machine. On a physical
device use the machine's LAN address. Without the define the app talks to the
deployed service, `https://beatful-api.onrender.com`, which is the default in
`app/lib/services/api.dart`. Debug and profile builds are allowed to use plain
HTTP so a LAN server works; release builds are HTTPS only.

Release build, no define needed unless you are pointing it somewhere else:

    flutter build apk --release

## Tests

    cd server && npm test          # rules, engine, API, economy, bot simulation
    cd app && flutter test         # rules parity, parsing, wording, widgets

    cd server && npm run simulate  # headless bot table, prints win shares

`npm test` covers the parts that are easy to get wrong and impossible to eyeball:
turn expiry auto playing and auto passing, a poll parking and waking, 50
concurrent coin matches ending with every balance and ledger row consistent, and
the daily ad cap holding under concurrent claims.

## Deploying

**Atlas.** An M0 cluster is enough. Create a database user that can read and
write only the `beatful` database, nothing else. Restrict network access to the
Render egress addresses if you are on a paid Render plan; on the free plan the
outbound address is not fixed, so `0.0.0.0/0` plus a strong password and a least
privilege user is the practical setting. The connection string goes in Render's
environment, never in a file in this repo.

**Render.** One web service, no background worker needed. `render.yaml` at the
root is a blueprint, so New > Blueprint reads the whole definition and asks only
for `MONGO_URI`. To set it up by hand instead:

    Root directory     server
    Build command      npm ci
    Start command      npm start
    Health check path   /health

Environment variables to set in the Render dashboard:

| Variable | Notes |
| --- | --- |
| `MONGO_URI` | required, from Atlas |
| `AUTH_SECRET` | required, `node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"` |
| `NODE_ENV` | `production` |
| `PORT` | Render sets this; the server reads it |
| `MONGO_DB_NAME` | defaults to `beatful` |
| `LOG_LEVEL` | `info` in production |

Everything else in `.env.example` is optional and has a working default.

**Cold starts.** A free Render service sleeps after 15 minutes idle and takes
tens of seconds to wake. The app already handles this: for the first minute of a
slow request it says "Connecting to the game server" rather than showing an
error. If you would rather it never sleep, a scheduled ping is the usual
workaround. It is optional, and it is a workaround, not a fix:

```yaml
# .github/workflows/keepalive.yml
name: keepalive
on:
  schedule:
    - cron: '*/10 * * * *'
jobs:
  ping:
    runs-on: ubuntu-latest
    steps:
      - run: curl -fsS https://beatful-api.onrender.com/health
```

GitHub throttles scheduled workflows on busy repositories, so treat this as best
effort.

**Invite links.** `beatful://join/ABC123` is registered in
`app/android/app/src/main/AndroidManifest.xml`. It works from any app that makes
a custom scheme tappable. For links that open from a browser you would need an
`https` App Link with a verified domain, which this build does not use.

## Decisions worth knowing

- The server is the only judge. It validates every move, owns the turn timer, and
  decides winners. The client draws what it is told and never computes legality.
- Realtime is long polling only. `GET /room/:id/state?since=<version>` is held up
  to 25 seconds and answers the moment the room changes. A player's own move is
  never delayed by it: `POST /room/:id/play` applies and returns the new state.
- A seat that goes quiet keeps taking its turns on the timer, and the host is
  offered a button to hand it to a bot. It is never silently removed. The app
  says this in the leave dialog before anyone walks out.
- Coins are a closed loop. They buy cosmetics and coin match entries and nothing
  else. There is no cash out, and the Terms screen in the app says so.
- Every balance change is one atomic update with the balance checked in the
  filter, so two requests can never spend the same coin.

## Not done

The spec asks for a pass on real hardware: touch targets under a thumb, timer
visibility in daylight, WiFi off and on mid match, backgrounding during someone
else's turn, and a match across two physical devices. That has not been run here,
only the emulator and the automated suites. It is the last thing to do before
shipping.
