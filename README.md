# DDM MAX – IDRISH

Flutter-based Android audio effects console.

## Current implementation
- Two main work areas: **LIVE MIC** and **PICK FILE**.
- Digital controls for level, feedback, delay time, effect mix, five-band EQ, dual delay, ping-pong and bypass.
- WAV import, original playback controls, effect rendering, processed WAV preview, and WAV sharing/export.
- Android MediaCodec-based audio-to-PCM-WAV decoding for supported device codecs (for example MP3/AAC/M4A/OGG where the Android device has a decoder).
- Native Android live microphone processing using AudioRecord/AudioTrack, with platform NoiseSuppressor and AcousticEchoCanceler when the device supports them.
- Microphone recording to WAV with record, hold/resume, repeat playback and stop controls.
- Offline WAV processing includes EQ, delay, gain, noise-reduction filtering and noise gate.

## Important limitations (do not mistake these for verified features)
- Android audio codec support varies by device and file encoding. DRM-protected or unsupported files may fail to decode.
- The app's file ANC control is software filtering/noise-gate processing; it is **not** hardware active noise cancellation.
- Live noise suppression and echo cancellation depend on Android device support; the app reports whether those platform effects activate.
- The current source does not yet provide a dedicated manual microphone/input-device selector or verified connected-hardware inventory.
- The app has not been verified on a physical Android phone in this repository workflow. A successful CI build confirms compilation and APK packaging, not real-device audio behavior.
- No Naat collection/library feature is included in the current two-tab UI.

## Build and checks
```sh
flutter pub get
flutter analyze
flutter build apk --release
```

The GitHub Actions workflow builds the release APK. Run the app on a physical device and test file import, original playback, processed preview, export, microphone permissions, live monitoring and external audio routing before treating the release as device-verified.
