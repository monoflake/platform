/***
 * `Remote` and the send's address held to RFC p8e8k, a send's shell, what it prints read back,
 * and an address with no scheme reached as plain HTTP.
 */
open Node

test("an address with no scheme is plain HTTP, an instance's key before its export", () => {
  deepEqual(Http.plainHttp("10.88.0.5:8080/echo"), "http://10.88.0.5:8080/echo")
  deepEqual(Http.plainHttp("https://a.example/echo"), "https://a.example/echo")
  deepEqual(
    Http.sendUrl(~to="10.88.0.5:8080", ~export="echo", ~key=None),
    "http://10.88.0.5:8080/echo",
  )
  deepEqual(
    Http.sendUrl(~to="https://a.example", ~export="increment", ~key=Some("a")),
    "https://a.example/a/increment",
  )
})

test("the shell posts stdin to a plain URL, and refuses one a shell would read", () => {
  switch Remote.posted("http://10.88.0.5:8080/echo") {
  | Ok(shell) =>
    ok(shell->String.includes("--data-binary @- 'http://10.88.0.5:8080/echo'"))
    ok(shell->String.includes("%{http_code}"))
  | Error(why) => JsError.throwWithMessage(why)
  }
  ok(Remote.posted("http://a/'; rm -rf /")->Result.isError)
  ok(Remote.posted("file:///etc/passwd")->Result.isError)
})

test("what the shell printed is the body and then its status on a line of its own", () => {
  let read = text => Remote.readPosted(Web.utf8(text))->Result.map(((s, b)) => (s, Web.text(b)))
  deepEqual(read(`{"text": "a\nb"}\n200`), Ok((200, `{"text": "a\nb"}`)))
  deepEqual(read("\n503\n"), Ok((503, "")))
  ok(read("no status")->Result.isError)
  ok(read("body\nnot a status")->Result.isError)
})

test("a send answered is read as an export's answer or the platform's refusal", () => {
  deepEqual(
    Http.sent(200, Web.utf8(`{"text": "hello"}`)),
    Answered(JSON.parseOrThrow(`{"text": "hello"}`)),
  )
  deepEqual(
    Http.sent(
      503,
      Web.utf8(`{"status": "error", "failure": "unavailable", "reason": "stopped", "message": "m"}`),
    ),
    Failed({failure: "unavailable", reason: "stopped", message: "m"}),
  )
  switch Http.sent(503, Web.utf8("the deployment is not running")) {
  | Failed({failure: "unknown"}) => ()
  | Failed(_) | Answered(_) => JsError.throwWithMessage("a body that is no answer is not unknown")
  }
})
