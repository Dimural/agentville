# 0005: Datagram socket in the per-user Darwin temp dir
Status: Accepted
Date: 2026-10-01

## Context
The hook and the app need a rendezvous point that both can compute without configuration. It must be private to the user, leave no clutter, and stay under the 104-byte `sun_path` limit.

## Decision
`AF_UNIX` + `SOCK_DGRAM` at `confstr(_CS_DARWIN_USER_TEMP_DIR) + "agentville.sock"` (e.g. `/var/folders/ab/xyz…/T/agentville.sock`). The environment variable `AGENTVILLE_SOCKET` overrides it (used by tests and replay).

## Consequences
- The directory is per-user, mode 700, and cleared on reboot, so nothing is left on disk.
- Unlike `$TMPDIR`, `confstr` gives the same answer to processes launched by terminals, IDEs and the desktop app.
- Datagrams mean the hook never blocks. If the app's receive buffer is full, events are dropped, which is acceptable: the store self-heals on the next event.
- The app unlinks a stale socket file at bind time and on quit (only if the file is still the one it bound, so an old instance never removes a newer one's socket).
- macOS caps local datagrams at `net.local.dgram.maxdgram` = 2048 bytes; larger sends fail in the sender. `WireCodec.maxReceiveBytes` matches this cap. The app raises its receive buffer to 1 MB so bursts aren't dropped.
