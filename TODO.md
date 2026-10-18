# Roadmap

The tasks come here when the owner chooses them. The reason for each choice
is in [docs/decisions.md](docs/decisions.md).

## Next

- No task is chosen now. The stream is video only, and the owner does not
  want audio in it.

## Known problems

- The stream over Wi-Fi is not tested. On the test network, the router does
  not let two Wi-Fi clients connect to each other. The server listens on the
  Wi-Fi address, and a connection from the phone to that address works.
- When the screen sleeps, the stream is black.
- Over ssh, `launchctl load` does not work. The package then starts the
  daemon directly. launchd starts it at each boot.
