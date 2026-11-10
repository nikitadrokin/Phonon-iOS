# Phonon 40m Core ML compatibility

## Finding

`itsmechico/phonon-40m-en-coreml` does **not** load with an official `xn-ptts`
Swift release, including 0.4.2. Its model card says the bundle adds a
`flow-step` graph and requires a runtime exposing `Phonon.setSteps(_:)`.

The compatible runtime is a custom build of `xn-ptts` 0.4.2 plus
[`tools/phonon-coreml/steps.patch`](https://github.com/gabfssilva/inkear/blob/f0d94b181a059d6477777fafdba4c156927f37c1/tools/phonon-coreml/steps.patch).
The patch and its first consumer were published together in Inkear commit
[`f0d94b181a059d6477777fafdba4c156927f37c1`](https://github.com/gabfssilva/inkear/commit/f0d94b181a059d6477777fafdba4c156927f37c1).
There is no official `gradium-ai/xn-ptts` commit or tag containing
`Phonon.setSteps(_:)`, `ptts_set_steps`, or the corresponding four-graph
Core ML driver, so changing the current SwiftPM version to another official
tag is not sufficient.

Sources:

- [40m English model card](https://huggingface.co/itsmechico/phonon-40m-en-coreml)
- [Custom runtime model card](https://huggingface.co/itsmechico/phonon-core-runtime)
- [Official 0.4.2 Swift wrapper](https://github.com/gradium-ai/xn-ptts/blob/v0.4.2/ios/PhononTTS/Sources/PhononTTS/Phonon.swift)
- [Official 0.4.2 Core ML driver](https://github.com/gradium-ai/xn-ptts/blob/v0.4.2/ptts-coreml/src/phonon/driver.rs)

## Exact runtime pin

Use the publisher's newest compatible binary revision. It rebuilds the same
patched runtime without `target-cpu=native`, which the publisher notes used
instructions unavailable on older iPhones:

```swift
.binaryTarget(
  name: "PhononCore",
  url: "https://huggingface.co/itsmechico/phonon-core-runtime/resolve/11d38f27745061df2b8372a8a3f28061b8046b0b/PhononCore.xcframework.zip",
  checksum: "96280157cd0a1e327b4a3ad45ab20c27c3ace35c9cfa3441dcc5e56081e19db6"
)
```

The original binary revision used by the Inkear commit was
`d70123932f1de84a824b160a423d136ac9a6b248` with checksum
`61cedbdd9555b08939739ffa607b0465a3baca5aa04ffe0ad8e7bf952264549a`.
The newer artifact supersedes it specifically for device compatibility.

Sources:

- [Runtime commit history](https://huggingface.co/itsmechico/phonon-core-runtime/commits/main)
- [Inkear binary target pin](https://github.com/gabfssilva/inkear/blob/f0d94b181a059d6477777fafdba4c156927f37c1/InkearKit/Package.swift)

## Swift package shape

The Hugging Face runtime repository contains only the binary zip, not a Swift
package manifest. A consumer therefore needs a small package that:

1. Declares the exact `PhononCore` binary target above.
2. Declares a `PhononTTS` source target depending on `PhononCore`.
3. Uses the patched 0.4.2 Swift wrapper sources. Inkear vendors the matching
   [`Phonon.swift`](https://github.com/gabfssilva/inkear/blob/f0d94b181a059d6477777fafdba4c156927f37c1/InkearKit/Sources/PhononTTS/Phonon.swift),
   [`PhononModels.swift`](https://github.com/gabfssilva/inkear/blob/f0d94b181a059d6477777fafdba4c156927f37c1/InkearKit/Sources/PhononTTS/PhononModels.swift), and
   [`PhononPlayer.swift`](https://github.com/gabfssilva/inkear/blob/f0d94b181a059d6477777fafdba4c156927f37c1/InkearKit/Sources/PhononTTS/PhononPlayer.swift).

The existing remote `xn-ptts` dependency should be replaced by that local
package to avoid linking two `PhononCore` products or accidentally resolving
back to the official incompatible binary.

## App call sequence

No `setSteps` call is required merely to load and run this bundle. The patched
runtime reads `steps` and `time_norm` from `bundle.json` during
`Phonon.load`; the English bundle declares `steps: 1`. `setSteps(_:)` only
changes quality/speed for subsequent utterances and can be called after load,
before synthesis, if the app wants more than the bundle default:

```swift
let phonon = try await Phonon.load(models: directory, language: .english)
try await phonon.setSteps(3) // Optional; bundle default is 1.
```

The patch documents that the change is immediate and applies from the next
utterance. The app can retain its present load and generation flow when using
the compatible package.
