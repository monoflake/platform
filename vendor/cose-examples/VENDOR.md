# cose-examples

- **Upstream**: https://github.com/cose-wg/Examples, the Unlicense, `LICENSE` here.
- **Version**: commit `53c9d634333bb4f529d78f5980fffa2667ee2c12`, of 2024-03-13; the upstream has no
  tags.
- **Taken**: `sign1-tests/`, `eddsa-examples/` and `CWT/`, each case a JSON file, and `LICENSE`,
  byte for byte. Not taken: the other algorithms' cases, `RFC8152/`, `KeySet.txt`,
  `examples.cddl` and the spreadsheet.
- **Consumed**: samples `codec*` is held to -- every `Sign1` case, `sign0` in the upstream's
  files: `sign1-tests/`, the two `eddsa-sig-` cases and CWT's `A_3`, the others being MACs and
  encryption -- `model/graph/libraries.res`: COSE's `Sign1` by RFC
  9052 and a CWT by RFC 8392, as RFC fhg6w asks. They were written before RFC 9864, so their EdDSA
  is algorithm -8, where the platform's is -19, b8f35.
- **Checked**: by `codec*`'s own tests, each language's, which read these files as they are.
- **Upgraded**: cloned at a newer commit and the three directories copied again.
