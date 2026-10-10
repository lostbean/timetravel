// THROWAWAY: integrate public recording and inspector APIs without live effects.
import gleam/list
import gleam/result
import gleam/string
import lustre/effect.{type Effect}
import recording_demo/domain.{type Card, type Message}
import recording_demo/wire.{type Archive}
import timetravel
import timetravel/recording

pub type Player =
  recording.Player(Card, Message, Nil)

pub type Inspector =
  timetravel.Model(Player, recording.Entry(Message))

// No reference to the live application's effect handler exists in this module.
pub fn inert_update(
  player: Player,
  _: recording.Entry(Message),
) -> #(Player, Effect(recording.Entry(Message))) {
  #(player, effect.none())
}

pub fn load(archive: Archive, capacity: Int) -> Result(Inspector, String) {
  use initial <- result.try(
    recording.replay(archive.initial, domain.contract, domain.reduce)
    |> result.map_error(string.inspect),
  )
  use #(inspector, _) <- result.try(
    timetravel.init_with_capacity(
      arguments: initial,
      with: fn(player) { #(player, effect.none()) },
      capacity: capacity,
    )
    |> result.map_error(string.inspect),
  )
  use loaded <- result.try(
    list.try_fold(archive.entries, inspector, fn(inspector, entry) {
      // Validate BEFORE pushing: an invalid input must not make a phantom snapshot.
      use next <- result.try(
        recording.step(timetravel.current(inspector), entry)
        |> result.map_error(string.inspect),
      )
      let #(inspector, _) =
        timetravel.update(
          model: inspector,
          message: timetravel.App(entry),
          with: fn(_, _) { #(next, effect.none()) },
        )
      Ok(inspector)
    }),
  )
  use _ <- result.try(
    recording.verify(timetravel.current(loaded), archive.final, fn(a, b) {
      a == b
    })
    |> result.map_error(string.inspect),
  )
  Ok(loaded)
}
