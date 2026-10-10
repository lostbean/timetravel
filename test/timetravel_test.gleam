import gleam/int
import gleeunit
import lustre/effect
import timetravel

pub fn main() -> Nil {
  gleeunit.main()
}

fn initialise(value: Int) {
  timetravel.init(arguments: value, with: fn(initial) {
    #(initial, effect.none())
  })
}

fn add(model: Int, amount: Int) {
  #(model + amount, effect.none())
}

fn dispatch(model, message) {
  timetravel.update(model: model, message: message, with: add)
}

pub fn init_starts_at_the_present_test() {
  let #(model, _) = initialise(42)
  assert timetravel.current(model) == 42
  assert timetravel.position(model) == #(0, 0)
}

pub fn app_messages_record_snapshots_test() {
  let #(initial, _) = initialise(1)
  let #(updated, _) = dispatch(initial, timetravel.App(2))
  assert timetravel.current(updated) == 3
  assert timetravel.position(updated) == #(1, 1)
}

pub fn back_and_forward_restore_snapshots_test() {
  let #(initial, _) = initialise(1)
  let #(first, _) = dispatch(initial, timetravel.App(2))
  let #(second, _) = dispatch(first, timetravel.App(4))
  let #(past, _) = dispatch(second, timetravel.Back)
  assert timetravel.current(past) == 3
  assert timetravel.position(past) == #(1, 2)

  let #(present, _) = dispatch(past, timetravel.Forward)
  assert timetravel.current(present) == 7
  assert timetravel.position(present) == #(2, 2)
}

pub fn app_messages_are_ignored_while_viewing_the_past_test() {
  let #(initial, _) = initialise(1)
  let #(present, _) = dispatch(initial, timetravel.App(2))
  let #(past, _) = dispatch(present, timetravel.Back)
  let #(unchanged, _) = dispatch(past, timetravel.App(100))
  assert timetravel.current(unchanged) == 1
  assert timetravel.position(unchanged) == #(0, 1)
}

pub fn go_to_and_return_to_present_test() {
  let #(initial, _) = initialise(0)
  let #(one, _) = dispatch(initial, timetravel.App(1))
  let #(three, _) = dispatch(one, timetravel.App(2))
  let #(six, _) = dispatch(three, timetravel.App(3))
  let #(first, _) = dispatch(six, timetravel.GoTo(1))
  assert timetravel.current(first) == 1
  assert timetravel.position(first) == #(1, 3)

  let #(present, _) = dispatch(first, timetravel.ReturnToPresent)
  assert timetravel.current(present) == 6
  assert timetravel.position(present) == #(3, 3)
}

pub fn history_is_limited_to_one_hundred_transitions_test() {
  let #(initial, _) = initialise(0)
  let model =
    int.range(from: 1, to: 106, with: initial, run: fn(model, _) {
      let #(updated, _) = dispatch(model, timetravel.App(1))
      updated
    })

  assert timetravel.current(model) == 105
  assert timetravel.position(model) == #(100, 100)
}

pub fn negative_go_to_clamps_to_first_retained_state_test() {
  let #(initial, _) = initialise(42)
  let #(empty, _) = dispatch(initial, timetravel.GoTo(-1))
  assert timetravel.current(empty) == 42
  assert timetravel.position(empty) == #(0, 0)

  let #(present, _) = dispatch(initial, timetravel.App(2))
  let #(first, _) = dispatch(present, timetravel.GoTo(-100))
  assert timetravel.current(first) == 42
  assert timetravel.position(first) == #(0, 1)

  let #(returned, _) = dispatch(first, timetravel.GoTo(100))
  assert timetravel.current(returned) == 44
  assert timetravel.position(returned) == #(1, 1)
}

pub fn custom_capacity_retains_only_requested_transitions_test() {
  let assert Ok(#(initial, _)) =
    timetravel.init_with_capacity(
      arguments: 10,
      with: fn(value) { #(value, effect.none()) },
      capacity: 2,
    )
  let #(one, _) = dispatch(initial, timetravel.App(1))
  let #(two, _) = dispatch(one, timetravel.App(2))
  let #(three, _) = dispatch(two, timetravel.App(4))
  assert timetravel.position(three) == #(2, 2)
  let #(oldest, _) = dispatch(three, timetravel.GoTo(0))
  assert timetravel.current(oldest) == 11
  let #(latest, _) = dispatch(oldest, timetravel.ReturnToPresent)
  assert timetravel.current(latest) == 17
}

pub fn invalid_capacity_does_not_initialise_application_test() {
  let result =
    timetravel.init_with_capacity(
      arguments: Nil,
      with: fn(_) { panic as "Application init must not run" },
      capacity: 0,
    )
  assert result == Error(timetravel.InvalidCapacity(0))
  let result =
    timetravel.init_with_capacity(
      arguments: Nil,
      with: fn(_) { panic as "Application init must not run" },
      capacity: -1,
    )
  assert result == Error(timetravel.InvalidCapacity(-1))
}
