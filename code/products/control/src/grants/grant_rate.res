type window = {start: float, mutable count: int}

let windows: Map.t<string, window> = Map.make()

let allowed = (~grant, ~now) => {
  switch windows->Map.get(grant) {
  | Some(window) if now >= window.start && now < window.start +. 60000. =>
    window.count = window.count + 1
    window.count <= 60
  | Some(_) | None =>
    if windows->Map.size >= 1024 {
      windows->Map.clear
    }
    windows->Map.set(grant, {start: now, count: 1})
    true
  }
}
