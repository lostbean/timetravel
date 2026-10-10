# Recording and replay experiment

**THROWAWAY / experimental branch.** Question: can one `timetravel` package
provide a small portable recording/replay core and reuse its existing inspector,
without a second replay package or replacing the debugger?

The candidate is on `experiment/recording-replay` in
<https://github.com/lostbean/timetravel>. It is not a published release or an
upstream proposal. The upstream package metadata and MIT license are preserved.

## Shape of the experiment

```text
Live application → safe event/state projection → timetravel/recording
                                               ↓ typed entries/checkpoints
                                     app-owned codec / outbox / transport
                                               ↓
                               timetravel/recording → pure reducer
                                               ↓
                               timetravel inspector → inert app view
```

The executable demo connects these boundaries by exporting JSON and importing it
in an independent browser context. It does not implement the outbox or transport
in this diagram. Those remain application integration points.

Three independently reviewable changes:

1. Clamp negative `GoTo` positions. Upstream's recursive seek otherwise does not
   return after reaching an empty past.
2. Add `init_with_capacity` to configure the inspector's retained transition
   count. Existing `init` and `application` retain their 100-transition default.
   Invalid capacity is rejected before calling application initialization.
3. Add experimental `timetravel/recording`, plus two external consumer packages.
   The module deliberately reworks the previously tested local recording core;
   there is no `retrace` dependency. It imports no Lustre, JSON, OS or network API.

The debugger's existing pause behavior is unchanged: it ignores application
messages while viewing the past. Therefore the live application must not be
inside the rewindable inspector for this capture pattern. The demo inspector
receives a separate, inert reconstruction. Its reducer has no live command
handler, and imported messages cannot invoke native functionality.

## Public recording API

```gleam
import timetravel/recording

let origin = recording.Origin("session-id", "card-schema-and-reducer-v1")
let assert Ok(#(recorder, initial)) = recording.start(origin, safe_initial)
let assert Ok(#(recorder, entry)) =
  recording.record(recorder, safe_message, elapsed_ms: 25)
let checkpoint = recording.checkpoint(recorder, safe_updated_model)

// A different process, browser or server can consume the decoded values.
let assert Ok(player) = recording.replay(initial, origin.contract_id, pure_reduce)
let assert Ok(player) = recording.step(player, entry)
let assert Ok(Nil) = recording.verify(player, checkpoint, fn(a, b) { a == b })
let reconstructed = recording.model(player)
```

This is illustrative caller code; a production application must handle errors.
The executable consumers demonstrate complete examples and recovery.

| Boundary | Package owns | Application owns |
| --- | --- | --- |
| Capture | Origin, monotonic sequence/time checks, typed entries | Consent, safe projection, clock, accepting events, durable outbox |
| Resume | Checked cursor reconstruction | Atomic checkpoint/outbox recovery, single writer per recording |
| Replay | Compatibility/identity/order checks; typed reducer errors | Safe decoder, deterministic pure reducer, missing-range fetch |
| Checkpoint | Cursor/time/state comparison using caller equality | Correct model at capture time, trusted source, checkpoint cadence |
| Inspection | Bounded snapshot navigation and existing inspector | Inert view, loading a bounded range, absolute sequence labels |
| Delivery | Nothing | Retry, acknowledgement, deduplication, storage, indexing, authorization |

`Recorder` holds only origin, sequence and elapsed time. `Player` holds origin,
cursor, current model and a reducer. Neither accumulates an event history.
Public `Entry` and `Checkpoint` values are candidates that may come from decoded
storage; `replay` and `step` validate their stream invariants.

`resume(checkpoint)` restores a capture cursor. Callers must recover a consistent
durable position first; it does not implement locking or exactly-once delivery.
The elapsed clock must continue monotonically after recovery. Equal times are
accepted. Counters and times are restricted to JavaScript's exact integer range.

No-op messages are entries too. Effect results must arrive as recorded messages;
clock reads, randomness, subscriptions and backend updates belong at that same
boundary. A replay callback can still perform side effects or throw: Gleam's
function type does not enforce purity. Supply a separate pure reducer.

A gap, duplicate, wrong recording, incompatible contract, backwards timestamp,
reducer failure or mismatching checkpoint returns a structured error. The old
immutable player remains usable. Gap recovery is explicit: fetch missing input
and retry, or start from a later trusted checkpoint while displaying the gap.
The package does not silently claim uninterrupted history.

## Run and play

Requirements: Gleam 1.16+, Node 24, Erlang/OTP and rebar3 for the portable consumer.
Package versions and Playwright are locked in the consumer manifests/lockfile.

From this checkout, run all relevant checks:

```sh
sh integration/recording/run.sh
```

The runner installs the pinned browser test dependency and Chromium when needed.
Set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` to reuse an installed browser.
It closes the temporary server and browser after checking. Generated receipts
`integration/recording/report.json` and `recording.png` are ignored.

In the original workspace the existing Nix mobile shell supplies the toolchain:

```sh
nix develop /code/gleam-dream/oversight#mobile --command bash -c \
  'cd /code/gleam-dream/timetravel && sh integration/recording/run.sh'
```

After building, launch the interactive demo:

```sh
cd integration/recording
npm start
# http://127.0.0.1:5175
```

Click Increment, No change and Native request. Export, then import. Open the
existing timetravel panel and rewind. Close the panel and complete the native
callback: the live recorder advances while the replay stays selected. Export
again and paste the JSON into a second browser's import field. That browser
reconstructs the result without making a native request. Delete an entry to see
gap rejection; restore it to recover without losing the previously loaded view.

The callback is manually controlled, and time advances by ten synthetic
milliseconds per event. No actual native permission or network request occurs.
The demo holds at most 2,000 captured entries in memory and loses them on reload.
Its decoder loads the whole JSON input before validation: it is not a hardened
untrusted-upload endpoint. Capacity bounds inspector transitions, not bytes or
total archive parsing/reconstruction work.

## Evidence and interpretation

`integration/recording_core` uses only the public recording API and native
application records/variants. It covers ordinary recording, checkpoint-based
replay, resume, application-specific errors, gaps and retry, duplicate input,
time reversal, compatibility, identity, state mismatch and integer exhaustion.
The same consumer runs on JavaScript and Erlang.

`integration/recording` adds an application-owned codec and the real Lustre
runtime. The browser checks cover paused replay with live async completion,
no-op capture, excluding a private field, configurable window trimming and
absolute sequence, navigation without re-running effects, eight invalid-archive
cases with recovery, and JSON import in a fresh browser context. The existing
inspector suite remains in place, with bounds and capacity regressions added.

This is local runtime evidence. It does not establish iOS/Android lifecycle
behavior, crash-safe outbox recovery, backend collection, S3 persistence,
production privacy guarantees or cross-build visual fidelity. Matching contract
IDs do not prove reducer equivalence; the application must version that contract
honestly and retain the appropriate reducer/rendering build.

**Decision supported:** reuse the existing inspector and add the bounded
recording domain; rewriting timetravel is unnecessary for this experiment.
Published timetravel alone does not supply the recording contract.

**Packaging remains open:** even when a consumer imports only the pure module,
the timetravel package brings Lustre and its transitive dependencies. A separate
portable recording package could avoid that dependency cost and leave the
upstream debugger focused. Its API would be substantially the same. The small
seek fix and configurable capacity can be considered independently from whether
the maintainer wants recording in the package. No PR or upstream issue was made.

## Source map and provenance

- `src/timetravel.gleam`: original inspector plus bounds fix and capacity.
- `src/timetravel/recording.gleam`: proposed portable capture/reconstruction API.
- `integration/recording_core/`: separate portable consumer and recovery cases.
- `integration/recording/src/recording_demo.gleam`: live host and safe projection.
- `integration/recording/src/recording_demo/domain.gleam`: application reducer.
- `integration/recording/src/recording_demo/wire.gleam`: application JSON format.
- `integration/recording/src/recording_demo/viewer.gleam`: public API composition.
- `integration/recording/src/native_fixture.mjs`: controlled effect callback.
- `integration/recording/{serve,check}.mjs`: loopback harness and browser evidence.

Base: `bmehder/timetravel`, revision
`24db1c91d98e485e194ec8ff6710dfd420aee229` (0.2.2), MIT licensed.
The branch is deliberately experimental; package version 0.2.2 has not been
republished with these changes.
