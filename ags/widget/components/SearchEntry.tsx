import Gtk from "gi://Gtk?version=4.0"

export default function SearchEntry(p: { onChanged: (q: string) => void }): Gtk.SearchEntry {
    const entry = new Gtk.SearchEntry({
        placeholderText: "Search settings…", cssClasses: ["search-entry"], hexpand: true,
    })
    entry.connect("search-changed", () => p.onChanged(entry.get_text()))
    return entry
}
