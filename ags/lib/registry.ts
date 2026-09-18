import Gtk from "gi://Gtk?version=4.0"

export interface RowSpec {
    id: string           // unique, e.g. "appearance.blur"
    title: string
    description: string
    icon: string
    keywords?: string[]  // extra search terms
    build: () => Gtk.Widget
}

export interface CategoryDef {
    id: string
    label: string
    group: "Look & Feel" | "Behavior" | "Hardware" | "System"
    icon: string
    description: string
    rows: () => RowSpec[]          // called on every (re)build → fresh values
    extra?: () => Gtk.Widget[]     // non-row widgets (monitor cards) above rows
}

let categories: CategoryDef[] = []
export const setCategories = (defs: CategoryDef[]) => { categories = defs }
export const allCategories = (): CategoryDef[] => categories

export function searchRows(query: string): { cat: CategoryDef; row: RowSpec }[] {
    const q = query.toLowerCase().trim()
    if (!q) return []
    const out: { cat: CategoryDef; row: RowSpec }[] = []
    for (const cat of categories) {
        for (const row of cat.rows()) {
            const hay = [row.title, row.description, cat.label, ...(row.keywords ?? [])]
                .join(" ").toLowerCase()
            if (q.split(/\s+/).every(w => hay.includes(w))) out.push({ cat, row })
        }
    }
    return out
}

// Shell registers its rebuild function; rows call requestRefresh() after resets.
let refreshFn: (() => void) | null = null
export const setRefreshHandler = (fn: () => void) => { refreshFn = fn }
export const requestRefresh = () => refreshFn?.()

let statusFn: ((message: string) => void) | null = null
export const setStatusHandler = (fn: (message: string) => void) => { statusFn = fn }

/** GTK callbacks end here: async failures stay visible and controls re-read live values. */
export function runSettingChange(change: () => Promise<void>, refresh = false): void {
    statusFn?.("")
    change().then(() => { if (refresh) requestRefresh() }).catch(error => {
        console.error("Settings change failed:", error)
        statusFn?.(error instanceof Error ? error.message : "The setting could not be changed. Please try again.")
        requestRefresh()
    })
}
