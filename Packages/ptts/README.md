# Patched PhononTTS package

This local Swift package combines the `PhononTTS` Swift wrapper from
[`gradium-ai/xn-ptts` 0.4.2](https://github.com/gradium-ai/xn-ptts/tree/v0.4.2/ios/PhononTTS)
with the model publisher's
[`steps.patch`](https://github.com/gabfssilva/inkear/blob/f0d94b181a059d6477777fafdba4c156927f37c1/tools/phonon-coreml/steps.patch)
and matching prebuilt `PhononCore` binary.

The patch adds the `flow-step` graph support required by
`itsmechico/phonon-40m-en-coreml`.

## Licenses

- The xn-ptts wrapper code is licensed under Apache-2.0 OR MIT, at your option
  (`LICENSE-APACHE`, `LICENSE-MIT`). The files in `Sources/PhononTTS` have been modified
  from the upstream 0.4.2 release to apply the flow-steps patch.
- The flow-steps patch comes from [Inkear](https://github.com/gabfssilva/inkear) by
  Gabriel F. Silva and is MIT licensed (`LICENSE-INKEAR`).
