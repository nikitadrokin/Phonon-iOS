# Patched PhononTTS package

This local Swift package combines the `PhononTTS` Swift wrapper from
[`gradium-ai/xn-ptts` 0.4.2](https://github.com/gradium-ai/xn-ptts/tree/v0.4.2/ios/PhononTTS)
with the model publisher's
[`steps.patch`](https://github.com/gabfssilva/inkear/blob/f0d94b181a059d6477777fafdba4c156927f37c1/tools/phonon-coreml/steps.patch)
and matching prebuilt `PhononCore` binary.

The patch adds the `flow-step` graph support required by
`itsmechico/phonon-40m-en-coreml`. The package retains xn-ptts's Apache-2.0 OR MIT license.
