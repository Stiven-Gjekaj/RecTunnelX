# Roadmap

The tasks come here when the owner chooses them. The reason for each choice
is in [docs/decisions.md](docs/decisions.md).

## Next

- No task is chosen now.

## Known problems

- The stream over Wi-Fi is not tested. On the test network, the router does
  not let two Wi-Fi clients connect to each other. The server listens on the
  Wi-Fi address, and a connection from the phone to that address works.
- A lock from the power button turns the screen off, and then the stream is
  black. The daemon stops the idle auto-lock, but not a lock from the button.
- The auto-lock stop is not proven. The test phone did not auto-lock in
  75 seconds with no assertion, so the test did not show the stop.
- Over ssh, `launchctl load` does not work. The package then starts the
  daemon directly. launchd starts it at each boot.
