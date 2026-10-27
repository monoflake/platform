let default: Worker.worker = {
  fetch: async (_, _) => Web.answered(~status=200, "hello from the local rehearsal"),
}
