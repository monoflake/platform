open Envelope

type objects = {
  write: Contracts.ObjectWrite.t => promise<Contracts.Answer.t<Contracts.ObjectWritten.t>>,
  read: Contracts.ObjectRead.t => promise<Contracts.Answer.t<Contracts.ObjectContent.t>>,
  describe: Contracts.ObjectName.t => promise<Contracts.Answer.t<Contracts.ObjectDescribed.t>>,
  delete: Contracts.ObjectName.t => promise<Contracts.Answer.t<Contracts.ObjectDeleted.t>>,
  list: Contracts.ObjectList.t => promise<Contracts.Answer.t<Contracts.ObjectListed.t>>,
}
type context = {salt: Uint8Array.t, objects: objects}
let write = (_, _) => failwith("operations seat")
let read = (_, _) => failwith("operations seat")
let describe = (_, _) => failwith("operations seat")
let delete = (_, _) => failwith("operations seat")
let list = (_, _) => failwith("operations seat")
