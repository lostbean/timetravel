// THROWAWAY: does live recording remain independent of replay navigation?
import gleam/int
import gleam/list
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import recording_demo/domain.{type Card}
import recording_demo/viewer
import recording_demo/wire
import timetravel
import timetravel/recording

type PrivateModel {
  PrivateModel(email: String, card: Card)
}

type Model {
  Model(
    live: PrivateModel,
    recorder: recording.Recorder,
    initial: recording.Checkpoint(Card),
    entries: List(recording.Entry(domain.Message)),
    count: Int,
    inspector: viewer.Inspector,
    capacity: Int,
    archive: String,
    notice: String,
  )
}

type Message {
  Live(domain.Message)
  Inspect(timetravel.Message(recording.Entry(domain.Message)))
  Export
  Import
  EditArchive(String)
  Capacity(Int)
  CompleteNative
}

fn archive(model: Model) -> wire.Archive {
  wire.Archive(
    model.initial,
    list.reverse(model.entries),
    recording.checkpoint(model.recorder, model.live.card),
  )
}

fn init(_: Nil) -> #(Model, Effect(Message)) {
  let card = domain.initial()
  let assert Ok(#(recorder, initial)) =
    recording.start(recording.Origin("demo-session", domain.contract), card)
  let empty = wire.Archive(initial, [], initial)
  let assert Ok(inspector) = viewer.load(empty, 3)
  #(
    Model(
      PrivateModel("never-captured@example.invalid", card),
      recorder,
      initial,
      [],
      0,
      inspector,
      3,
      wire.encode(empty),
      "Record events, export, then import into the viewer.",
    ),
    effect.none(),
  )
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    Live(app_message) -> {
      // Bound the fixture's in-memory archive. A production app owns its outbox.
      case model.count >= 2000 {
        True -> #(
          Model(..model, notice: "Demo archive full; reload to start again."),
          effect.none(),
        )
        False -> {
          let assert Ok(card) = domain.reduce(model.live.card, app_message)
          let count = model.count + 1
          // A synthetic monotonic clock makes the test repeatable.
          // Only safe Card/Message values cross the recording boundary.
          let assert Ok(#(recorder, entry)) =
            recording.record(
              model.recorder,
              app_message,
              elapsed_ms: count * 10,
            )
          let command = case app_message {
            domain.RequestNative ->
              effect.from(fn(dispatch) {
                request_native(fn() { dispatch(Live(domain.NativeFinished)) })
              })
            domain.Increment | domain.NoChange | domain.NativeFinished ->
              effect.none()
          }
          #(
            Model(
              ..model,
              live: PrivateModel(..model.live, card: card),
              recorder: recorder,
              entries: [entry, ..model.entries],
              count: count,
            ),
            command,
          )
        }
      }
    }
    Inspect(message) -> {
      let #(inspector, command) =
        timetravel.update(
          model: model.inspector,
          message: message,
          with: viewer.inert_update,
        )
      #(Model(..model, inspector: inspector), effect.map(command, Inspect))
    }
    Export -> #(
      Model(
        ..model,
        archive: wire.encode(archive(model)),
        notice: "Safe archive exported. Copy it to another browser's viewer.",
      ),
      effect.none(),
    )
    EditArchive(value) -> #(Model(..model, archive: value), effect.none())
    Import -> {
      let loaded = case wire.decode_archive(model.archive) {
        Error(reason) -> Error(reason)
        Ok(archive) -> viewer.load(archive, model.capacity)
      }
      case loaded {
        Error(reason) -> #(Model(..model, notice: reason), effect.none())
        Ok(inspector) -> #(
          Model(
            ..model,
            inspector: inspector,
            notice: "Loaded and verified. Navigation runs no application effects.",
          ),
          effect.none(),
        )
      }
    }
    Capacity(capacity) -> #(
      Model(
        ..model,
        capacity: capacity,
        notice: "Capacity applies on the next import.",
      ),
      effect.none(),
    )
    CompleteNative -> #(model, effect.from(fn(_) { complete_native() }))
  }
}

fn field(label: String, id: String, value: String) -> Element(message) {
  html.p([], [
    html.text(label <> ": "),
    html.strong([attribute.id(id)], [html.text(value)]),
  ])
}

fn replay_view(
  player: viewer.Player,
) -> Element(recording.Entry(domain.Message)) {
  let card = recording.model(player)
  html.section([attribute.class("card")], [
    html.h2([], [html.text("Replay · inert snapshot")]),
    field(
      "Absolute sequence",
      "replay-sequence",
      int.to_string(recording.position(player)),
    ),
    field("Points", "replay-points", int.to_string(card.points)),
    field("Native result", "replay-status", card.status),
  ])
}

fn view(model: Model) -> Element(Message) {
  let #(selected, latest) = timetravel.position(model.inspector)
  html.main([], [
    html.h1([], [html.text("One package. Independent recording and replay.")]),
    html.p([], [
      html.text(
        "Experimental timetravel fork · synthetic clock · controlled native callback · no storage or upload",
      ),
    ]),
    html.section([attribute.class("columns")], [
      html.section([attribute.class("card")], [
        html.h2([], [html.text("Live application")]),
        field(
          "Private field (excluded from recording)",
          "private",
          model.live.email,
        ),
        field("Points", "live-points", int.to_string(model.live.card.points)),
        field("Native result", "live-status", model.live.card.status),
        field("Recorded entries", "recorded", int.to_string(model.count)),
        html.button([event.on_click(Live(domain.Increment))], [
          html.text("Increment"),
        ]),
        html.button([event.on_click(Live(domain.NoChange))], [
          html.text("No change"),
        ]),
        html.button([event.on_click(Live(domain.RequestNative))], [
          html.text("Native request"),
        ]),
        html.button([event.on_click(CompleteNative)], [
          html.text("Complete native callback"),
        ]),
      ]),
      timetravel.view_with_formatters(
        model: model.inspector,
        app: replay_view,
        formatters: timetravel.Formatters(
          fn(entry: recording.Entry(domain.Message)) {
            domain.name(entry.event)
          },
          string.inspect,
          fn(player) { string.inspect(recording.model(player)) },
        ),
      )
        |> element.map(Inspect),
    ]),
    html.section([attribute.class("card")], [
      html.h2([], [html.text("Application-owned archive codec")]),
      field(
        "Inspector window position",
        "window",
        int.to_string(selected) <> "/" <> int.to_string(latest),
      ),
      field(
        "Capacity for next import",
        "capacity",
        int.to_string(model.capacity),
      ),
      html.button([event.on_click(Export)], [html.text("Export recording")]),
      html.button([event.on_click(Import)], [html.text("Import recording")]),
      html.button([event.on_click(Capacity(3))], [html.text("3 transitions")]),
      html.button([event.on_click(Capacity(100))], [
        html.text("100 transitions"),
      ]),
      html.textarea(
        [
          attribute.id("archive"),
          attribute.attribute("aria-label", "Archive JSON"),
          event.on_input(EditArchive),
        ],
        model.archive,
      ),
      html.p([attribute.id("notice"), attribute.attribute("role", "status")], [
        html.text(model.notice),
      ]),
      html.details([], [
        html.summary([], [html.text("All captured entries (safe projection)")]),
        html.pre([attribute.id("entries")], [
          html.text(string.inspect(list.reverse(model.entries))),
        ]),
      ]),
    ]),
  ])
}

pub fn main() -> Nil {
  let assert Ok(_) =
    lustre.application(init, update, view) |> lustre.start("#app", Nil)
  Nil
}

@external(javascript, "./native_fixture.mjs", "requestNative")
fn request_native(callback: fn() -> Nil) -> Nil

@external(javascript, "./native_fixture.mjs", "completeNative")
fn complete_native() -> Nil
