# DDM-MAX

Flutter Android Naat audio console.

## Included modules
- Digital delay controls: level, feedback, delay time, effect mix, single/dual mode, ping-pong and bypass.
- WAV file echo processor with five-band EQ, playback, loop, output saving and sharing.
- Microphone recording to WAV, playback and post-recording effects.
- Naat collection: add local audio files, play and share.
- Madinah-themed console UI.

## Audio notes
- Offline processing currently supports uncompressed PCM 16-bit mono/stereo WAV.
- The app records microphone audio to WAV. Effects are applied after recording; realtime low-latency mic monitoring is a separate native audio-engine task.
- MP3/AAC transcoding, persistent library storage, and full device testing remain to be completed.
- Always test at low speaker volume first to avoid feedback.

## Build
```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
