/***
 * How each layer's record is named, RFC b8f35, by BLAKE3 keyed or unkeyed, 32 bytes.
 */

let keyed = (~salt, content) =>
  TypedArray.length(salt) == 32
    ? Ok(Blake3.hashWith(content, {key: salt}))
    : Error(Derive.Length({part: "salt", length: 32}))

let plain = Blake3.hash
