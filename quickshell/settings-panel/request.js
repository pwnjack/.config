import GLib from "gi://GLib"
import Gio from "gi://Gio"
import GioUnix from "gi://GioUnix"
import System from "system"
import { dispatch } from "./backend.js"

// One line, not EOF: the panel never has to close its end of the pipe.
function stdinLine() {
    const stream = new Gio.DataInputStream({ base_stream: new GioUnix.InputStream({ fd: 0, close_fd: false }) })
    const [line] = stream.read_line_utf8(null)
    if (!line || !line.trim()) throw new Error("Expected one JSON request on stdin")
    return line
}

const loop = new GLib.MainLoop(null, false)
let exitCode = 0
Promise.resolve().then(() => dispatch(JSON.parse(ARGV[0] === "-" ? stdinLine() : ARGV[0]))).then(result => {
    print(JSON.stringify({ ok: true, ...result }))
}).catch(error => {
    print(JSON.stringify({ ok: false, error: error.message }))
    exitCode = 1
}).finally(() => loop.quit())
loop.run()
System.exit(exitCode)
