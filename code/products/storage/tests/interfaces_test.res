/***
 * The values the storage product's interfaces fix, RFC vuanj.
 */
open Node

test("an extension holds at most 16 characters", () => deepEqual(Names.longest, 16))
