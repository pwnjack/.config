// Prints the Waybar tooltip for custom/updates. stdin is one JSON object, the
// input of model.tooltip(); the copy is the update card's own, so the bar and
// the card say the same thing. scripts/waybar/updates.sh falls back to a
// one-line tooltip if this fails.
import { readFileSync } from 'node:fs'
import { tooltip } from '../../quickshell/updates/model.mjs'

process.stdout.write(tooltip(JSON.parse(readFileSync(0, 'utf8'))))
