// Pure model for the keybindings overlay: filtering, highlighting, contrast and
// column layout. Imported by Overlay.qml and SectionBlock.qml, and tested
// directly by node, so nothing here may touch QML or Quickshell.

export const COLUMN_WIDTH = 360
export const MAX_COLUMNS = 4
// A section's heading costs about two rows of height when balancing columns.
const HEADING_WEIGHT = 2

function words(query) {
    return String(query || '').toLocaleLowerCase().split(/\s+/).filter(Boolean)
}

export function keyText(row) {
    return row.keys.join(' + ')
}

export function countRows(sections) {
    return sections.reduce((n, s) => n + s.rows.length, 0)
}

// Every word must appear in the label or the key text. A newline separates the
// two so that no word can match across the boundary.
export function filterSheet(sections, query) {
    const terms = words(query)
    if (!terms.length)
        return sections
    const matches = row => {
        const hay = (row.label + '\n' + keyText(row)).toLocaleLowerCase()
        return terms.every(t => hay.includes(t))
    }
    return sections
        .map(s => ({name: s.name, rows: s.rows.filter(matches)}))
        .filter(s => s.rows.length)
}

// Sorted, merged [start, end) ranges of every query word inside label.
export function matchRanges(label, query) {
    const lower = label.toLocaleLowerCase()
    const ranges = []
    for (const t of words(query)) {
        for (let i = lower.indexOf(t); i !== -1; i = lower.indexOf(t, i + t.length))
            ranges.push([i, i + t.length])
    }
    ranges.sort((a, b) => a[0] - b[0])
    const merged = []
    for (const r of ranges) {
        const last = merged[merged.length - 1]
        if (last && r[0] <= last[1])
            last[1] = Math.max(last[1], r[1])
        else
            merged.push([...r])
    }
    return merged
}

function escapeHtml(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

// StyledText markup for a label with its matches drawn bold in color. Labels
// come from config comments, so everything outside the markup is escaped.
export function highlight(label, query, color) {
    let out = ''
    let at = 0
    for (const [start, end] of matchRanges(label, query)) {
        out += escapeHtml(label.slice(at, start))
        out += `<font color="${color}"><b>${escapeHtml(label.slice(start, end))}</b></font>`
        at = end
    }
    return out + escapeHtml(label.slice(at))
}

export function capMatches(cap, query) {
    const lower = cap.toLocaleLowerCase()
    return words(query).some(t => lower.includes(t))
}

// minWidth is the narrowest a column may be; the overlay passes COLUMN_WIDTH
// scaled to the output, so a larger sheet earns its columns at the same rate.
export function columnCount(width, minWidth = COLUMN_WIDTH) {
    return Math.max(2, Math.min(MAX_COLUMNS, Math.floor(width / minWidth)))
}

// Split sections, in order and never mid-section, into at most n columns while
// minimising the tallest one: the smallest capacity that a greedy fill fits
// into n columns. Sizes here are tens of rows, so a linear scan is enough.
export function distribute(sections, n) {
    if (!sections.length)
        return []
    const weight = s => s.rows.length + HEADING_WEIGHT
    const total = sections.reduce((t, s) => t + weight(s), 0)
    for (let cap = Math.max(...sections.map(weight)); cap <= total; cap++) {
        const columns = [[]]
        let height = 0
        for (const s of sections) {
            if (height + weight(s) > cap && columns[columns.length - 1].length) {
                columns.push([])
                height = 0
            }
            columns[columns.length - 1].push(s)
            height += weight(s)
        }
        if (columns.length <= n)
            return columns
    }
    return [sections.slice()]
}

function luminance(hex) {
    const v = hex.replace('#', '').slice(-6)
    const [r, g, b] = [0, 2, 4].map(i => {
        const c = parseInt(v.slice(i, i + 2), 16) / 255
        return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
    })
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

export function contrast(a, b) {
    const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x)
    return (hi + 0.05) / (lo + 0.05)
}

// A wallpaper palette gives no contrast guarantee, so accent-coloured text falls
// back to the foreground on wallpapers where the accent would vanish.
export function readableAccent(accent, background, foreground) {
    return contrast(accent, background) >= 3 ? accent : foreground
}
