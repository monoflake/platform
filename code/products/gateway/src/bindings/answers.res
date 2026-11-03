/***
 * What the gateway takes of a response and its configuration beyond the control's bindings.
 */
module Web = ControlOrganization.Web

@get external body: Web.response => Nullable.t<Web.body> = "body"

/** A response made again from another, so its headers may be set. */
@new external rewrapped: (Nullable.t<Web.body>, Web.response) => Web.response = "Response"

/** The organization's storage as the gateway is configured with it, `{id}.b{binding}`. */
@get external storageOf: ControlOrganization.Stores.env => Nullable.t<string> = "STORAGE"
