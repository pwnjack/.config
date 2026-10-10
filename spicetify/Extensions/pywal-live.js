// Recolours a running Spotify when the wallpaper changes.
//
// spicetify/apply_wal_colors.sh rewrites the client's colors.css through
// `spicetify refresh`, which Spotify loaded once at startup. This rereads that
// file every few seconds and, when it changes, adopts its rules as a
// constructed stylesheet. A <style> would not do: Spicetify links colors.css
// from the page body, after <head>, so a sheet added to the head loses to it,
// whereas adopted sheets cascade after every sheet in the document. The query
// string keeps any cache from answering with the old file.
//
// Each read is a couple of kilobytes from the client's own files, and it is
// skipped while the window is hidden.
(function pywalLive() {
    const intervalMs = 3000;
    let last = null;
    let sheet = null;

    async function check() {
        if (document.visibilityState !== "visible") return;
        let css;
        try {
            const response = await fetch(`colors.css?pywal=${Date.now()}`, { cache: "no-store" });
            if (!response.ok) return;
            css = await response.text();
        } catch (_) {
            return;
        }
        if (last !== null && css !== last) {
            if (!sheet) {
                sheet = new CSSStyleSheet();
                document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
            }
            sheet.replaceSync(css);
        }
        last = css;
    }

    check();
    setInterval(check, intervalMs);
    document.addEventListener("visibilitychange", check);
})();
