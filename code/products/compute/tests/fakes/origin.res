type t = {
  sent: array<Worker.request>,
  answer: Worker.response,
  restore: unit => unit,
}

let make = (~fails=false, ()) => {
  let original = Node.currentFetch
  let sent = []
  let answer = Node.response("app answer", {status: 202})
  Node.setFetch(async request => {
    sent->Array.push(request)
    if fails {
      Node.fail()
    }
    answer
  })
  {sent, answer, restore: () => Node.setFetch(original)}
}
