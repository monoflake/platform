module Web = ControlOrganization.Web
module Stores = ControlOrganization.Stores
module Reach = ControlOrganization.Reach

/** A mount is passed to the app's entry, every other path answers 404, RFC oomwh. */
type worker = {fetch: (Web.request, Stores.env) => promise<Web.response>}

let reachOf: Stores.env => option<Reach.t>

let default: worker
