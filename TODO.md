# Roadmap

The tasks come here when the owner chooses them. The reason for each choice
is in [docs/decisions.md](docs/decisions.md).

## Next

- The system audio: a MobileSubstrate tweak in `mediaserverd` takes the sound
  that the apps play. The daemon encodes it to AAC and puts it in the stream.

## Known problems

- The stream over Wi-Fi is not tested. On the test network, the router does
  not let two Wi-Fi clients connect to each other. The server listens on the
  Wi-Fi address, and a connection from the phone to that address works.
- OBS itself is not tested. ffmpeg on the Mac reads the stream, and the
  Media Source of OBS uses ffmpeg.
- When the screen sleeps, the stream is black.
- If a cleaner removed `/var/tmp/launchd`, `launchctl load` does not work
  until the next boot. The package then starts the daemon directly.
