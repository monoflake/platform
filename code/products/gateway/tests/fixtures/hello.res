let default: Worker.worker = {
  fetch: async (_, _) =>
    ControlOrganization.Web.answered(~status=200, "hello from the local rehearsal"),
}
