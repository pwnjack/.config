import Gtk from "gi://Gtk?version=4.0"

export default function SearchEntry(p: { onChanged: (q: string) => void; onStop?: () => void }): Gtk.SearchEntry {
    const entry = new Gtk.SearchEntry({
        placeholderText: "Search settings…", cssClasses: ["search-entry"], hexpand: true,
    })
    entry.connect("search-changed", () => p.onChanged(entry.get_text()))
    // GtkSearchEntry consumes Esc itself and emits stop-search instead of
    // letting the key reach the window controller
    if (p.onStop) entry.connect("stop-search", p.onStop)
    return entry
}
