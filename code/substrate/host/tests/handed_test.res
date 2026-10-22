/***
 * `Handed.call` held to the deployments samples as they stand, its driver a fake answering them and
 * each send of theirs made through the host.
 */
open Node
open Sample

let files = [
  "tests/kinds/deployments/deploys.json",
  "tests/kinds/deployments/forms.json",
  "tests/kinds/deployments/instances.json",
  "tests/kinds/deployments/lifecycle.json",
]

let json = (body: JSON.t): Handed.request => {
  contentType: Some("application/json"),
  accept: Some("application/json"),
  body: utf8(JSON.stringify(body)),
}

/** What a post answers as a step expects, an export's answer or a refusal. */
let answerOf = (expect): result<Handed.response, Contracts.Error.t> =>
  switch (member(expect, "answer"), member(expect, "failure")) {
  | (Some(answer), None) =>
    Ok({status: 200, contentType: Some("application/json"), body: utf8(JSON.stringify(answer))})
  | (None, Some(failed)) =>
    Error({failure: failure(failed), reason: expect->at(["reason"])->string, message: ""})
  | _ => JsError.throwWithMessage(`${JSON.stringify(expect)}: no one answer`)
  }

/** A refusal as a sample matches it, its failure and reason and never its message. */
let matched = (answer: Handed.answer): Handed.answer =>
  switch answer {
  | Refused({failure, reason}) => Refused({failure, reason, message: ""})
  | Answered(_) => answer
  }

/** A send made through the host, to the deployment of `runs` rather than to its address. */
let send = async (fake, runs, step, message) => {
  let send = step->at(["send"])
  let address = switch send->at(["to"])->placeholder("$use") {
  | Some(name) => Fake.addressOf(name)
  | None => JsError.throwWithMessage(`${message}: a send to no captured address`)
  }
  let export = send->at(["export"])->string
  let key = member(send, "key")->Option.map(string)
  let request = json(member(send, "body")->Option.getOr(JSON.Object(dict{})))
  let expect = step->at(["expect"])
  let posted = []
  let post = async (url, given) => {
    posted->Array.push(url)
    deepEqual(given, request, ~message=`${message}: the request passed on as it came`)
    answerOf(expect)
  }
  let answer = await Handed.call(Fake.driver(fake), ~post, {runs, export, key, request})
  let expected: Handed.answer = switch answerOf(expect) {
  | Ok(response) => Answered(response)
  | Error(error) => Refused(error)
  }
  deepEqual(matched(answer), expected, ~message)
  if member(expect, "answer") != None {
    let url = switch key {
    | Some(key) => `${address}/${key}/${export}`
    | None => `${address}/${export}`
    }
    deepEqual(posted, [url], ~message=`${message}: posted to its deployment's address`)
  }
}

/** A call to what its driver does not find is refused as the driver refused it, nothing posted. */
let unfound = async (fake, runs, message) => {
  let post = async (url, _) => JsError.throwWithMessage(`${message}: posted to ${url}`)
  let request = json(JSON.Object(dict{}))
  let answer = await Handed.call(
    Fake.driver(fake),
    ~post,
    {runs, export: "echo", key: None, request},
  )
  deepEqual(
    matched(answer),
    Refused({failure: Rejected, reason: "not_found", message: ""}),
    ~message=`${message}: not found`,
  )
}

let rec walk = async (fake, runs, steps, index, description) =>
  switch steps->Array.get(index) {
  | None => ()
  | Some(step) =>
    let message = `${description}, step ${Int.toString(index)}`
    let runs = switch member(step, "call") {
    | Some(operation) =>
      Fake.step(fake, step)
      let runs = step->at(["input", "runs"])->Sample.runs
      let expect = step->at(["expect"])
      if (
        operation->string == "describe" &&
          member(expect, "reason")->Option.map(string) == Some("not_found")
      ) {
        await unfound(fake, runs, message)
      }
      Some(runs)
    | None =>
      switch runs {
      | Some(runs) => await send(fake, runs, step, message)
      | None => JsError.throwWithMessage(`${message}: a send before any deployment is named`)
      }
      runs
    }
    await walk(fake, runs, steps, index + 1, description)
  }

files->Array.forEach(file =>
  read(file)
  ->at(["cases"])
  ->items
  ->Array.forEach(case => {
    let description = case->at(["description"])->string
    test(
      `${file}: ${description}`,
      () => walk(Fake.make(), None, case->at(["steps"])->items, 0, description),
    )
  })
)
