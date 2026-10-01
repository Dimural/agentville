// agentville-hook: run by Claude Code on each hook event (docs/architecture/hook.md).
//
// Hard rules: never write stdout, never write stderr, never exit non-zero, never wait on the app,
// never write files. Reads stdin, keeps only allowlisted fields, sends one datagram, exits 0.
import AgentvilleWire
import Darwin
import Foundation

signal(SIGPIPE, SIG_IGN)

/// Reads up to `limit + 1` bytes of stdin, then drains (and discards) the rest so Claude Code never
/// sees a broken pipe. Returns nil if the input exceeded `limit`.
func readStdin(limit: Int) -> Data? {
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 64 * 1024)
    var overflow = false
    while true {
        let n = read(STDIN_FILENO, &buf, buf.count)
        if n > 0 {
            if !overflow {
                data.append(buf, count: n)
                if data.count > limit { overflow = true; data = Data() }
            }
        } else if n < 0 && errno == EINTR {
            continue
        } else {
            break
        }
    }
    return overflow ? nil : data
}

if let input = readStdin(limit: HookPayloadFilter.maxInputBytes),
   let event = HookPayloadFilter.filter(data: input),
   let datagram = WireCodec.encode(event),
   let path = SocketPath.resolve()
{
    DatagramSocket.send(datagram, to: path)
}
exit(0)
