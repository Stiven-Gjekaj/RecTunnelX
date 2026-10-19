# Changelog

Every release is written here, newest first. A version is
`MAJOR.MINOR.PATCH`. Before 1.0.0, each big addition raises the minor number.
From 1.0.0, a fix raises the patch number, and a new function raises the
minor number.
Each release on GitHub has the `.deb` package as an asset.

## 1.0.0 (2026-10-19)

Keep the screen awake.

- While a client watches, the daemon holds a `PreventUserIdleDisplaySleep`
  power assertion, so the phone does not auto-lock in the middle of a
  stream. It releases the assertion when the client leaves.
- The status shows `awake`. A test saw `awake` go to true at the first
  client and back to false when the client left.
- A lock from the power button still turns the screen off.

## 0.2.0 (2026-10-18)

Remove all audio.

- The stream is video only. The audio setting, the audio switch in the app,
  and the audio path of the muxer and the MPEG-TS writer are gone.
- The PMT lists only the video stream.
- Reason: the owner asked to remove all audio.

## 0.1.0 (2026-10-18)

The first release: the video of the screen in OBS.

- A daemon captures the screen with IOSurface and encodes it with the
  hardware H.264 encoder of the phone.
- OBS reads the stream with a Media Source. The input is
  `tcp://127.0.0.1:7272` over USB with `iproxy`, or `tcp://PHONE:7272` over
  Wi-Fi. `http://HOST:7272/stream.ts` also works.
- 640x960 or 320x480, at 15, 24, or 30 frames per second, at 1.5, 3, or
  6 Mbit/s.
- The capture runs only while a client is connected.
- An app shows the state and the addresses, and changes the settings.
- `obs/RecTunnelX.json` is a scene collection for OBS with the source.
- Over USB, ffmpeg on the Mac read 300 frames in 10.0 seconds at 30 frames
  per second, 640x960, and 96 frames in 4.0 seconds at 24 frames per
  second, 320x480.
- The delay from a press of the Home button to the new frame on the Mac is
  625 ms (the median of 5), with Activator and SpringBoard in that time.
  The encoder takes 27 ms of it.
