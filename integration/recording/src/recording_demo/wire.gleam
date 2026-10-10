// THROWAWAY: application-owned JSON format, not a timetravel wire standard.
import gleam/dynamic/decode
import gleam/json
import gleam/result
import recording_demo/domain.{type Card, type Message, Card}
import timetravel/recording.{type Checkpoint, type Entry, type Origin}

pub type Archive {
  Archive(
    initial: Checkpoint(Card),
    entries: List(Entry(Message)),
    final: Checkpoint(Card),
  )
}

fn origin_json(origin: Origin) -> json.Json {
  json.object([
    #("recording_id", json.string(origin.recording_id)),
    #("contract_id", json.string(origin.contract_id)),
  ])
}

fn checkpoint_json(checkpoint: Checkpoint(Card)) -> json.Json {
  json.object([
    #("origin", origin_json(checkpoint.origin)),
    #("sequence", json.int(checkpoint.sequence)),
    #("elapsed_ms", json.int(checkpoint.elapsed_ms)),
    #(
      "model",
      json.object([
        #("points", json.int(checkpoint.model.points)),
        #("status", json.string(checkpoint.model.status)),
      ]),
    ),
  ])
}

pub fn encode(archive: Archive) -> String {
  json.object([
    #("format", json.int(1)),
    #("initial", checkpoint_json(archive.initial)),
    #(
      "entries",
      json.array(archive.entries, fn(entry) {
        json.object([
          #("origin", origin_json(entry.origin)),
          #("sequence", json.int(entry.sequence)),
          #("elapsed_ms", json.int(entry.elapsed_ms)),
          #("event", json.string(domain.name(entry.event))),
        ])
      }),
    ),
    #("final", checkpoint_json(archive.final)),
  ])
  |> json.to_string
}

fn origin_decoder() -> decode.Decoder(Origin) {
  use id <- decode.field("recording_id", decode.string)
  use contract <- decode.field("contract_id", decode.string)
  decode.success(recording.Origin(id, contract))
}

fn card_decoder() -> decode.Decoder(Card) {
  use points <- decode.field("points", decode.int)
  use status <- decode.field("status", decode.string)
  case
    points >= 0
    && { status == "ready" || status == "pending" || status == "finished" }
  {
    True -> decode.success(Card(points, status))
    False -> decode.failure(Card(0, "ready"), "valid card state")
  }
}

fn checkpoint_decoder() -> decode.Decoder(Checkpoint(Card)) {
  use origin <- decode.field("origin", origin_decoder())
  use sequence <- decode.field("sequence", decode.int)
  use elapsed <- decode.field("elapsed_ms", decode.int)
  use model <- decode.field("model", card_decoder())
  decode.success(recording.Checkpoint(origin, sequence, elapsed, model))
}

fn message_decoder() -> decode.Decoder(Message) {
  use name <- decode.then(decode.string)
  case name {
    "increment" -> decode.success(domain.Increment)
    "no_change" -> decode.success(domain.NoChange)
    "request_native" -> decode.success(domain.RequestNative)
    "native_finished" -> decode.success(domain.NativeFinished)
    _ -> decode.failure(domain.NoChange, "known card event")
  }
}

fn entry_decoder() -> decode.Decoder(Entry(Message)) {
  use origin <- decode.field("origin", origin_decoder())
  use sequence <- decode.field("sequence", decode.int)
  use elapsed <- decode.field("elapsed_ms", decode.int)
  use message <- decode.field("event", message_decoder())
  decode.success(recording.Entry(origin, sequence, elapsed, message))
}

pub fn decode_archive(input: String) -> Result(Archive, String) {
  let decoder = {
    use format <- decode.field("format", decode.int)
    use initial <- decode.field("initial", checkpoint_decoder())
    use entries <- decode.field("entries", decode.list(entry_decoder()))
    use final <- decode.field("final", checkpoint_decoder())
    case format {
      1 -> decode.success(Archive(initial, entries, final))
      _ -> decode.failure(Archive(initial, [], final), "archive format 1")
    }
  }
  json.parse(input, decoder)
  |> result.map_error(fn(_) { "Invalid archive JSON or format" })
}
