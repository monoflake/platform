/***
 * What the library takes of the model, `model/contracts.json` imported whole as JSON, this file
 * lying at `code/libs/vocabulary/src/bindings/`. Read whole rather than generated, RFC b194m.
 */
@module({from: "../../../../../model/contracts.json", with: {type_: "json"}})
external contracts: JSON.t = "default"
