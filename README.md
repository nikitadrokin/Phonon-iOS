# Phonon for iOS

A SwiftUI app that turns long text into speech entirely on the iPhone, using Gradium's
[Phonon](https://huggingface.co/gradium/phonon-40m-en) text-to-speech model running on the
Neural Engine through Core ML. Nothing is sent to a server: after the one-time model download,
generation works offline.

Use it as a template: it shows how to take an open on-device speech model and put a real
interface around it.

## Features

- **Create**: paste or import an essay or article and export it as an audio file. Text is
  generated paragraph by paragraph and written to disk as it goes, so memory stays flat
  however long the text is. Output is AAC (`.m4a`) or WAV.
- **Library**: exported files, also visible in the Files app, with share and delete.
- **Player**: a full-screen player with a scrubber, playback speed, and a transcript that
  follows the audio paragraph by paragraph. Playback continues in the background and works
  with Lock Screen and Control Center controls.
- **Voices**: browse, preview and pick from the model's built-in voices.
- **Model management**: first-run download with progress, a warning before downloading on
  cellular, on-device compile, and updates when the hosted model changes.
- Liquid Glass on iOS 26, with a material fallback on iOS 18 to 25.

## Requirements

- Xcode 16 or later; iOS 18 or later on an Apple silicon device.
- The simulator works but is several times slower (it has no Neural Engine). Test on a device.

## Getting started

1. Clone the repo and open `Phonon-iOS.xcodeproj`.
2. In **Signing & Capabilities**, select your own team and change the bundle identifier.
3. Build and run on a device. On first launch the app downloads the model (about 160 MB)
   and compiles it for the device.

## Where the model comes from

The model is **not** bundled in the app. It is downloaded on first launch from the URL in the
`PHONON_MODEL_BASE_URL` build setting, which must point to a folder holding a Core ML export of
the model and its `bundle.json`.

By default it points to
[`itsmechico/phonon-40m-en-coreml`](https://huggingface.co/itsmechico/phonon-40m-en-coreml),
a third-party Core ML export of Phonon 40m. That repository is not maintained by this project
and could change or disappear. To host your own copy, use `scripts/publish-model.sh`; it
uploads a Core ML bundle to a Hugging Face repo you own and prints the URL to set.

Phonon 40m needs a patched runtime, which is vendored in `Packages/ptts`. See
[`docs/phonon-40m-compatibility.md`](docs/phonon-40m-compatibility.md) for the details.

## Licenses

**The code in this repository** is MIT licensed (see [`LICENSE`](LICENSE)), except
`Packages/ptts`, which keeps its own licenses (Apache-2.0 OR MIT for the xn-ptts wrapper, MIT for
the Inkear patch). See [`Packages/ptts/README.md`](Packages/ptts/README.md).

**The model is licensed separately.** The Phonon 40m weights, tokenizer and voices are by
[Gradium](https://huggingface.co/gradium) and are licensed under
[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/): **non-commercial use only**.
This repository does not contain the model; the app downloads it at runtime. If you build a
commercial app from this template, you need a separate agreement with Gradium, or a model
whose license allows commercial use. Phonon 31m English is Apache-2.0, and
`scripts/publish-model.sh` can publish it (`PHONON_MODEL=31m`); the app's model settings in
`Phonon-iOS/Model/ModelConfiguration.swift` would need to change to match.

Gradium also asks that Phonon not be used to impersonate real people, to deceive listeners
about who is speaking, or to clone a voice without the speaker's consent.

## Credits

- [Gradium](https://github.com/gradium-ai) for the Phonon models, voices and the
  [xn-ptts](https://github.com/gradium-ai/xn-ptts) runtime.
- [itsmechico](https://huggingface.co/itsmechico) for the Phonon 40m Core ML export and the
  patched runtime binary.
- [Gabriel F. Silva / Inkear](https://github.com/gabfssilva/inkear) for the flow-steps patch.
