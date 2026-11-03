open Node

let clock = (~start=100., ()) => {
  let time = ref(start)
  let waits = []
  let now = () => time.contents
  let wait = async milliseconds => {
    waits->Array.push(milliseconds)
    time.contents = time.contents +. milliseconds
  }
  (time, now, wait, waits)
}

testAsync("lookup finishes on the first ask without waiting", async () => {
  let (_, now, wait, waits) = clock()
  let asks = ref(0)
  let steps = async () => {
    asks.contents = asks.contents + 1
    Ok({Lookup.committed: [1], finished: true})
  }
  deepEqual(
    await Lookup.looked(~steps, ~expires=200., ~deadline=10., ~now, ~wait),
    (Lookup.Finished, 0.),
  )
  deepEqual(asks.contents, 1)
  deepEqual(waits, [])
})

testAsync("lookup finishes after two open asks", async () => {
  let (_, now, wait, waits) = clock()
  let asks = ref(0)
  let steps = async () => {
    asks.contents = asks.contents + 1
    Ok({Lookup.committed: [1], finished: asks.contents == 3})
  }
  deepEqual(
    await Lookup.looked(~steps, ~expires=200., ~deadline=10., ~now, ~wait),
    (Lookup.Finished, 2.),
  )
  deepEqual(asks.contents, 3)
  deepEqual(waits, [1., 1.])
})

testAsync("lookup finds none committed past expiry", async () => {
  let (_, now, wait, waits) = clock()
  let steps = async () => Ok({Lookup.committed: [], finished: false})
  deepEqual(
    await Lookup.looked(~steps, ~expires=99., ~deadline=10., ~now, ~wait),
    (Lookup.NotSeen, 0.),
  )
  deepEqual(waits, [])
})

testAsync("lookup stays open at the deadline with the last committed sequence", async () => {
  let (_, now, wait, waits) = clock()
  let steps = async () => Ok({Lookup.committed: [1, 2], finished: false})
  deepEqual(
    await Lookup.looked(~steps, ~expires=99., ~deadline=2., ~now, ~wait),
    (Lookup.Open(Some(2)), 2.),
  )
  deepEqual(waits, [1., 1.])
})

testAsync("lookup counts a refused ask as none known", async () => {
  let (_, now, wait, _) = clock()
  let steps = async () => Error("store unavailable")
  deepEqual(
    await Lookup.looked(~steps, ~expires=200., ~deadline=2., ~now, ~wait),
    (Lookup.Open(None), 2.),
  )
  deepEqual(
    await Lookup.looked(~steps, ~expires=99., ~deadline=2., ~now, ~wait),
    (Lookup.NotSeen, 0.),
  )
})

testAsync("lookup reports time spent asking as well as waiting", async () => {
  let (time, now, wait, waits) = clock(~start=500., ())
  let steps = async () => {
    time.contents = time.contents +. 7.
    Ok({Lookup.committed: [1], finished: true})
  }
  deepEqual(
    await Lookup.looked(~steps, ~expires=1000., ~deadline=10., ~now, ~wait),
    (Lookup.Finished, 7.),
  )
  deepEqual(waits, [])
})

testAsync("lookup waits until strictly past expiry when none committed", async () => {
  let (_, now, wait, waits) = clock()
  let steps = async () => Ok({Lookup.committed: [], finished: false})
  deepEqual(
    await Lookup.looked(~steps, ~expires=100., ~deadline=10., ~now, ~wait),
    (Lookup.NotSeen, 1.),
  )
  deepEqual(waits, [1.])
})

testAsync("lookup caps its wait at the deadline and accepts a finished final ask", async () => {
  let (_, now, wait, waits) = clock()
  let steps = async () => Ok({Lookup.committed: [1], finished: now() >= 100.5})
  deepEqual(
    await Lookup.looked(~steps, ~expires=99., ~deadline=0.5, ~now, ~wait),
    (Lookup.Finished, 0.5),
  )
  deepEqual(waits, [0.5])
})
