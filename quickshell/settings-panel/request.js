import GLib from "gi://GLib"
import System from "system"
import { dispatch } from "./backend.js"

const loop = new GLib.MainLoop(null, false)
let exitCode = 0
Promise.resolve().then(() => dispatch(JSON.parse(ARGV[0]))).then(result => {
    print(JSON.stringify({ ok: true, ...result }))
}).catch(error => {
    print(JSON.stringify({ ok: false, error: error.message }))
    exitCode = 1
}).finally(() => loop.quit())
loop.run()
System.exit(exitCode)
