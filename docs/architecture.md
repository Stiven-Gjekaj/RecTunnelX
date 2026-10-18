# Architecture

RecTunnelX has two programs on the phone and one file for OBS:

- `rectunnelxd`, a daemon that runs as root. launchd starts it at boot.
- `RecTunnelX.app`, a small app that controls the daemon.
- `obs/RecTunnelX.json`, a scene collection for OBS with one Media Source.

All code is Objective-C with ARC. The daemon uses Foundation, CoreMedia,
CoreVideo, and some private functions of iOS 6.

## The path of a frame

```
screen surface -> accelerator -> pixel buffer -> H.264 encoder -> muxer -> server -> OBS
```

1. **Screen.** `RXScreen` gets the surface of the screen from
   `IOMobileFramebufferGetLayerDefaultSurface`. It is 640x960 BGRA.
2. **Copy.** For each frame, the accelerator of `IOSurface.framework` copies
   the screen into a pixel buffer from a pool. It also scales the image when
   the size is 320x480. The CPU does not touch the pixels.
3. **Encode.** `RXEncoder` gives the pixel buffer to a compression session of
   VideoToolbox. The hardware encoder of the A5 makes H.264 Baseline with no
   B-frames. A key frame comes every 2 seconds, or at once when a new client
   connects.
4. **Annex B.** The encoder gives NAL units with a length before each one.
   `RXAVCConfig` reads the SPS and the PPS from the `avcC` atom of the format
   description. `RXTSAnnexB` changes the frame to Annex B form, with an access
   unit delimiter, and puts the SPS and the PPS before each key frame.
5. **Mux.** `RXMuxer` writes the frame into MPEG-TS packets with `RXTSWriter`.
   Each key frame starts with the PAT and the PMT, so that a client can start
   at any key frame. The times come from the clock of the phone and start at
   1 second.
6. **Serve.** `RXStreamServer` sends the bytes of each frame to each client.
   A new client starts at the next key frame. A client with more than 4 MB
   that waits loses frames until the next key frame. Then it continues.

The capture thread runs at the frame rate of the settings. It skips the
frames that are late, so the stream keeps the real time.

## The server

`RXStreamServer` listens on port 7272 on all interfaces. A client can:

| Request | Answer |
| ------- | ------ |
| Connect and send nothing for 0.7 s | The raw MPEG-TS stream. OBS uses `tcp://HOST:7272`. |
| `GET /stream.ts` | The same stream with an HTTP header. |
| `GET /status` | JSON: the settings, the clients, the size, the frames, the addresses. |
| `GET /control?KEY=VALUE` | Changes the settings. Only from `127.0.0.1`. |

The keys of `/control` are `enabled` (yes or no), `fps` (5 to 60),
`bitrate` (250000 to 10000000), and `scale` (1 or 2).

The capture and the encoder run only while the stream is enabled and at
least one client is connected. With no client, the daemon only waits on its
socket.

## The settings

`RXSettings` keeps the settings in
`/var/mobile/Library/Preferences/io.github.stivengjekaj.rectunnelx.plist`.
A value out of its limits becomes the nearest limit. A change of the size,
the frame rate, or the bitrate starts a new encoder.

## The app

`RXMainController` asks `GET /status` each second. It shows the state, the
address for USB, and one address for each network interface. The switches
and the segmented controls send `GET /control`. A tap on an address copies
it.

## The log

The daemon writes its log to
`/var/mobile/Library/Caches/RecTunnelX/daemon.log`. A log larger than 256 KB
starts again when the daemon starts.

## The code

| Directory | Contents |
| --------- | -------- |
| `src/core` | Code with no UIKit and no private API. The tests run it on the Mac and on the phone. |
| `src/phone` | The capture, the encoder, and the streamer. Only for the phone. |
| `src/daemon` | `main` of `rectunnelxd`. |
| `src/ui` | The app. |
| `tests` | The tests of `src/core`. |
| `probe` | Tools that run on the phone and measure one thing. |
