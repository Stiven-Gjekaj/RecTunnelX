#!/usr/bin/env python3
"""Measure the delay from the screen of the phone to this Mac.

Usage: scripts/latency.py [INPUT] [TRIES]

The script reads the stream with ffmpeg as small gray frames. It presses the
Home button of the phone with Activator over "ssh iphone4s", and finds the
first frame that is different. The delay is the time from the press to the
arrival of that frame. It includes the time of ssh and of Activator, so the
real delay is a little shorter. Open an app on the phone first, so that the
Home button changes the screen.
"""
import subprocess
import sys
import threading
import time

INPUT = sys.argv[1] if len(sys.argv) > 1 else "tcp://127.0.0.1:7272"
TRIES = int(sys.argv[2]) if len(sys.argv) > 2 else 3
W, H = 40, 60

frames = []  # (arrival time, mean of the frame)
lock = threading.Lock()


def read_frames(process):
    size = W * H
    while True:
        data = process.stdout.read(size)
        if len(data) < size:
            return
        with lock:
            frames.append((time.monotonic(), sum(data) / size))


def main():
    ffmpeg = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-fflags", "nobuffer", "-flags", "low_delay", "-threads", "1",
         "-probesize", "32768", "-analyzeduration", "0", "-i", INPUT,
         "-vf", f"scale={W}:{H}", "-pix_fmt", "gray", "-f", "rawvideo", "-"],
        stdout=subprocess.PIPE)
    threading.Thread(target=read_frames, args=(ffmpeg,), daemon=True).start()
    time.sleep(4)
    results = []
    for _ in range(TRIES):
        subprocess.run(["ssh", "iphone4s", "open io.github.stivengjekaj.rectunnelx"], check=False)
        time.sleep(3)
        with lock:
            before = frames[-1][1]
            count = len(frames)
        start = time.monotonic()
        subprocess.run(["ssh", "iphone4s", "activator send libactivator.system.homebutton"], check=False)
        found = None
        while time.monotonic() - start < 5 and found is None:
            time.sleep(0.01)
            with lock:
                for arrival, mean in frames[count:]:
                    if abs(mean - before) > 8:
                        found = arrival
                        break
        if found is None:
            print("no change seen")
        else:
            results.append(found - start)
            print(f"delay {1000 * (found - start):.0f} ms")
        time.sleep(2)
    ffmpeg.kill()
    if results:
        print(f"median {1000 * sorted(results)[len(results) // 2]:.0f} ms of {len(results)}")


if __name__ == "__main__":
    main()
