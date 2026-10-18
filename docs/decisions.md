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

## The audio

- The stream carries the system audio, as AAC in the MPEG-TS.
- A MobileSubstrate tweak in `mediaserverd` takes the audio that the apps play.
- Reason: the human wants the sound of the apps, not the microphone.
- The video comes first. The audio is a later step.

## The device

- The device is an iPhone 4S (`iPhone4,1`) on iOS 6.1.3, Darwin 13.0.0.
- MobileSubstrate 0.9.6301 is on the device.
- `IOSurface.framework` and `IOMobileFramebuffer.framework` are in
  `/System/Library/PrivateFrameworks`.
- `VideoToolbox.framework` and `AVFoundation.framework` are in
  `/System/Library/Frameworks`.
