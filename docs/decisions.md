# Decisions

This file records the choices for RecTunnelX.
Each choice has a reason.

## The goal

RecTunnelX sends the screen of an iPhone 4S on iOS 6 to OBS on a computer.
OBS shows the screen and records it.

## The link

- The phone serves one TCP port.
- Over USB, `iproxy` forwards the port to `localhost` on the computer.
- Over Wi-Fi, OBS connects to the IP address of the phone.
- Reason: USB gives the lowest delay, and the setup is the same as the SSH
  tunnel. Wi-Fi removes the cable.

## The stream format

- The video is H.264 from the hardware encoder of the A5.
- The stream is MPEG-TS.
- OBS reads the stream with a Media Source, from `tcp://` or `http://`.
- The MPEG-TS muxer comes from the `RTTS` muxer in RetroTube.
- Reason: H.264 gives the best quality and frame rate for the bandwidth.
  OBS reads MPEG-TS with FFmpeg and needs no plugin.

## The parts on the phone

- A root LaunchDaemon captures the screen with IOSurface and
  IOMobileFramebuffer. It encodes the video and runs the server.
- A small app in `/Applications` starts and stops the daemon.
  It shows the address for OBS.
- Reason: the daemon continues to capture when another app is open.
  iOS 6 stops an app that is in the background.

## The screen capture

- `IOMobileFramebufferGetMainDisplay` and
  `IOMobileFramebufferGetLayerDefaultSurface(fb, 0)` give the screen surface.
- The surface is 640x960, BGRA, 2560 bytes for each row.
- Layers 1 and 2 have no surface (kr -536870212).
- The accelerator (`IOSurfaceAcceleratorTransferSurface`) copies the screen
  into a surface of our own at 173.7 fps. A CPU copy gives 82.4 fps.
- The capture uses the accelerator.
- iOS 6 has the accelerator functions in `IOSurface.framework`.
  It has no `IOSurfaceAccelerator.framework`.
- The probe gets all functions with `dlsym`. It runs as root, with no
  entitlements, after `ldid -S`.
- Measured with `probe/cap.m`, 60 frames, home screen, on 2026-10-18.
- Not known yet: does the seed of the screen surface change on each new frame?
  The seed stayed at 86871 while the screen did not change.

## The video encoder

- iOS 6 has `VTCompressionSessionCreate` and the other functions of the
  compression session in `VideoToolbox.framework`. They are private on iOS 6,
  so the code gets them with `dlsym`. The signatures are the same as on
  iOS 8.
- The encoder accepts the property keys `RealTime`, `ProfileLevel`
  (`H264_Baseline_AutoLevel`), `AllowFrameReordering`, `AverageBitRate`,
  `ExpectedFrameRate`, and `MaxKeyFrameInterval`. Each one gave status 0.
- The encoder takes BGRA pixel buffers directly. A 420v buffer also works.
- The output is H.264 Baseline, level 3.1, 640x960, with no B-frames.
- The format description has the SPS and the PPS in an `avcC` atom.
  `CMVideoFormatDescriptionGetH264ParameterSetAtIndex` is not on iOS 6, so
  `RXAVCConfig` reads the atom.
- Measured with `probe/enc.m` at 30 fps and 3 Mbit/s: 300 frames of 300 in
  10.01 s. `ffprobe` on the Mac reads the MPEG-TS file and counts 300 frames.
- The screen is black when the display sleeps. The copy then gives Y=16 in
  a 420v buffer. `activator send libactivator.system.homebutton` wakes it for
  a test.

## No audio

- The stream carries only video. It has no audio track.
- Reason: the human asked to remove all audio. A capture of the system
  audio reads every sound of the phone, which includes calls, so the
  project does not do it.
- To add sound to a recording, OBS takes it from another source, for
  example a cable from the headphone jack of the phone.

## The screen stays awake

- While the daemon captures, it holds a power assertion of the type
  `PreventUserIdleDisplaySleep`. It makes the assertion with
  `IOPMAssertionCreateWithName` from `IOKit.framework`, through `dlsym`.
- iOS 6 has `IOPMAssertionCreateWithName`. The type
  `PreventUserIdleDisplaySleep` gives result 0. The type `NoDisplaySleep`
  gives an error, so the code does not use it.
- The daemon holds the assertion only while a client watches. The status
  shows `awake`. A test saw `awake` go to true at the first client and back
  to false when the client left.
- The assertion stops the idle timer, so the phone does not auto-lock in the
  middle of a stream. It does not stop a lock from the power button.
- Not proven: the test phone did not auto-lock in 75 seconds with no
  assertion, so the test did not show the assertion stop an auto-lock. The
  assertion is the standard way to stop idle display sleep, and the call
  gives result 0.

## The device

- The device is an iPhone 4S (`iPhone4,1`) on iOS 6.1.3, Darwin 13.0.0.
- MobileSubstrate 0.9.6301 is on the device.
- `IOSurface.framework` and `IOMobileFramebuffer.framework` are in
  `/System/Library/PrivateFrameworks`.
- `VideoToolbox.framework` and `AVFoundation.framework` are in
  `/System/Library/Frameworks`.

## The daemon and launchd

- Over ssh, `launchctl load` fails with "Socket is not connected" and still
  exits with 0. `launchctl unload` and `launchctl list` work.
- This stays the same after a clean reboot, so a cleaner is not the cause.
  The ssh session of this jailbreak cannot send a load to launchd.
- `launchctl bsexec 1` fails, because `task_for_pid` of launchd is refused.
- At boot, launchd starts the daemon from `/Library/LaunchDaemons`. This was
  checked after a reboot on 2026-10-18.
- So `postinst` looks for the job in `launchctl list`. If it is not there,
  `postinst` starts the daemon with `nohup`.

## The network

- Over USB, `iproxy 7272 7272` forwards the port. ffmpeg on the Mac reads
  `tcp://127.0.0.1:7272` and `http://127.0.0.1:7272/stream.ts`.
- On the test network, the router isolates the Wi-Fi clients. The Mac gets no
  ARP answer from the phone, and a TCP connection from the phone to the Mac
  times out. The phone reaches the router and the Internet. So the stream
  over Wi-Fi is not tested.
- A connection from the phone to its own Wi-Fi address on port 7272 works,
  so the server listens on that interface.

## The delay

- `scripts/latency.py` presses the Home button with Activator over a shared
  ssh connection and waits for the first changed frame from ffmpeg.
- The median of 5 tries is 625 ms over USB at 30 fps and 3 Mbit/s. This time
  includes Activator and the start of the animation of SpringBoard.
- `probe/enc.m` measures 26.6 ms from a frame to its encoded output.

## OBS

- OBS 32.1.2 on macOS reads `tcp://127.0.0.1:7272` with a Media Source.
- The source uses: Input Format `mpegts`, Network Buffering 0 MB, Reconnect
  Delay 2 s, hardware decoding, and the FFmpeg Options
  `fflags=nobuffer flags=low_delay probesize=32768 analyzeduration=0`.
  These options stop ffmpeg from waiting to fill a buffer before it shows
  a frame.
- The canvas and the output are 640x960 at 30 fps, the same as the stream.
  OBS then does not scale the picture.
- The stream and the recording use the Apple hardware H.264 encoder of the
  Mac. The Mic/Auxiliary device is off, because the stream has no audio.
- A recording of 10.73 s had 321 frames at 640x960, 29.9 fps.
