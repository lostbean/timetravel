// THROWAWAY: app-owned safe types and deterministic replay contract.
pub const contract = "card-v1"

pub type Card {
  Card(points: Int, status: String)
}

pub type Message {
  Increment
  NoChange
  RequestNative
  NativeFinished
}

pub fn initial() -> Card {
  Card(0, "ready")
}

pub fn reduce(card: Card, message: Message) -> Result(Card, Nil) {
  Ok(case message {
    Increment -> Card(..card, points: card.points + 1)
    NoChange -> card
    RequestNative -> Card(..card, status: "pending")
    NativeFinished -> Card(..card, status: "finished")
  })
}

pub fn name(message: Message) -> String {
  case message {
    Increment -> "increment"
    NoChange -> "no_change"
    RequestNative -> "request_native"
    NativeFinished -> "native_finished"
  }
}
