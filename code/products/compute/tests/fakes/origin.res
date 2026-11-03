type t = {
  sent: array<Worker.request>,
  answer: Worker.response,
  restore: unit => unit,
}

let make = (~fails=false, ~status=202, ~body="app answer", ~headers=dict{}, ()) => {
  let original = Node.currentFetch
  let sent = []
  let answer = Node.response(body, {status, headers})
  Node.setFetch(async request => {
    sent->Array.push(request)
    if fails {
      Node.fail()
    }
    answer
  })
  {sent, answer, restore: () => Node.setFetch(original)}
}
