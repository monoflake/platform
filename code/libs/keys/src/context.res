/***
 * Every context the platform derives under, RFC b8f35, the one list of them.
 */

type t =
  | Salt
  | Key
  | Journal
  | Parcel
  | Gear
  | Placement

let all = [Salt, Key, Journal, Parcel, Gear, Placement]

let text = context =>
  switch context {
  | Salt => "monoflake:organization:salt:1"
  | Key => "monoflake:organization:key:1"
  | Journal => "monoflake:journal:key:1"
  | Parcel => "monoflake:parcel:key:1"
  | Gear => "monoflake:organization:gear:1"
  | Placement => "monoflake:parcel:placement:1"
  }
