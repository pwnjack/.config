import { loadColors } from "./lib/colors"

export function buildCss(): string {
    const c = loadColors()
    return `
.settings-window {
    background-color: transparent;
}

.panel-backdrop {
    background-color: transparent;
}

.panel-container {
    background-color: alpha(${c.background}, 0.85);
    border-radius: 16px;
    border: 1px solid alpha(${c.colors[4]}, 0.4);
    padding: 0;
}

.panel-layout {
    min-width: 880px;
    min-height: 640px;
}

.category-nav {
    background-color: alpha(${c.colors[0]}, 0.5);
    padding: 16px;
    min-width: 180px;
    border-radius: 16px 0 0 16px;
}

.nav-button {
    background-color: transparent;
    color: ${c.colors[7]};
    padding: 6px 12px;
    border-radius: 8px;
    border: none;
    font-size: 13px;
}

.nav-button:hover {
    background-color: alpha(${c.colors[4]}, 0.2);
}

.nav-active {
    background-color: alpha(${c.colors[4]}, 0.3);
    color: ${c.colors[6]};
    font-weight: bold;
}

.nav-active:hover {
    background-color: alpha(${c.colors[4]}, 0.35);
}

.content-area {
    padding: 24px 28px;
}

.content-scroll {
    border-radius: 0 16px 16px 0;
}

.content-scroll undershoot.top,
.content-scroll undershoot.bottom {
    background: none;
}

.content-scroll scrollbar {
    background-color: transparent;
    padding: 2px;
}

.content-scroll scrollbar slider {
    background-color: alpha(${c.colors[8]}, 0.3);
    border-radius: 99px;
    min-width: 4px;
}

.content-scroll scrollbar slider:hover {
    background-color: alpha(${c.colors[8]}, 0.5);
}

.category-content {
    padding: 4px;
}

.category-title {
    font-size: 20px;
    font-weight: bold;
    color: ${c.foreground};
}

.category-desc {
    font-size: 12px;
    color: ${c.colors[8]};
    margin-bottom: 4px;
}

.content-separator {
    min-height: 1px;
    background-color: alpha(${c.colors[8]}, 0.2);
    margin-bottom: 8px;
}

.slider-value {
    font-size: 13px;
    font-family: monospace;
    color: ${c.colors[6]};
}

.settings-scale trough {
    background-color: alpha(${c.colors[8]}, 0.3);
    border-radius: 4px;
    min-height: 6px;
}

.settings-scale highlight {
    background-color: ${c.colors[4]};
    border-radius: 4px;
}

.settings-scale slider {
    background-color: ${c.colors[6]};
    border-radius: 50%;
    min-width: 16px;
    min-height: 16px;
}

.app-entry {
    background-color: alpha(${c.colors[0]}, 0.6);
    color: ${c.foreground};
    border: 1px solid alpha(${c.colors[8]}, 0.3);
    border-radius: 6px;
    padding: 6px 10px;
    font-size: 13px;
}

.app-entry:focus {
    border-color: ${c.colors[4]};
}

switch {
    background-color: alpha(${c.colors[8]}, 0.3);
    border-radius: 12px;
    min-width: 48px;
    min-height: 24px;
}

switch:checked {
    background-color: ${c.colors[4]};
}

switch slider {
    background-color: ${c.foreground};
    border-radius: 50%;
    min-width: 20px;
    min-height: 20px;
    margin: 2px;
}

.settings-dropdown {
    background-color: alpha(${c.colors[0]}, 0.6);
    color: ${c.foreground};
    border: 1px solid alpha(${c.colors[8]}, 0.3);
    border-radius: 6px;
    padding: 4px 8px;
    font-size: 13px;
    min-width: 140px;
}

.settings-dropdown:hover {
    border-color: alpha(${c.colors[4]}, 0.5);
}

.settings-dropdown popover contents {
    background-color: alpha(${c.background}, 0.95);
    border: 1px solid alpha(${c.colors[4]}, 0.3);
    border-radius: 8px;
    padding: 4px;
}

.nav-section {
    font-size: 10px; letter-spacing: 1.5px; font-weight: bold;
    color: alpha(${c.colors[8]}, 0.9);
    margin: 10px 8px 2px 8px;
}
.search-entry {
    background-color: alpha(${c.colors[0]}, 0.6);
    color: ${c.foreground};
    border: 1px solid alpha(${c.colors[8]}, 0.3);
    border-radius: 8px; padding: 4px 8px; font-size: 13px;
    margin-bottom: 8px;
}
.search-entry:focus-within { border-color: ${c.colors[4]}; }

.setting-row { padding: 8px; border-radius: 10px; }
.setting-row:hover { background-color: alpha(${c.colors[4]}, 0.08); }
.row-icon {
    min-width: 32px; min-height: 32px; border-radius: 8px;
    background-color: alpha(${c.colors[4]}, 0.18);
    color: ${c.colors[6]};
}
.row-title { font-size: 14px; color: ${c.foreground}; }
.row-desc { font-size: 11px; color: alpha(${c.colors[8]}, 0.95); }
.row-crumb { font-size: 10px; color: ${c.colors[4]}; }
.reset-btn {
    background: transparent; border: none; padding: 4px;
    color: alpha(${c.colors[8]}, 0.6); opacity: 0;
}
.setting-row:hover .reset-btn { opacity: 1; }
.reset-btn:hover { color: ${c.colors[6]}; }

.panel-footer {
    border-top: 1px solid alpha(${c.colors[8]}, 0.2);
    padding: 10px 16px;
}
.action-chip {
    background-color: alpha(${c.colors[0]}, 0.6);
    color: ${c.colors[7]};
    border: 1px solid alpha(${c.colors[8]}, 0.3);
    border-radius: 99px; padding: 4px 12px; font-size: 12px;
}
.action-chip:hover { border-color: ${c.colors[4]}; color: ${c.colors[6]}; }

.monitor-card {
    background-color: alpha(${c.colors[0]}, 0.5);
    border: 1px solid alpha(${c.colors[8]}, 0.25);
    border-radius: 10px; padding: 10px 12px;
}
.monitor-name { font-size: 14px; font-weight: bold; color: ${c.foreground}; }
.monitor-detail { font-size: 11px; font-family: monospace; color: alpha(${c.colors[8]}, 0.95); }
.monitor-main-badge {
    font-size: 9px; font-weight: bold; color: ${c.background};
    background-color: ${c.colors[4]}; border-radius: 99px; padding: 2px 8px;
}
.monitor-set-main {
    font-size: 11px; border-radius: 99px; padding: 2px 10px;
    background-color: alpha(${c.colors[4]}, 0.2); color: ${c.colors[6]}; border: none;
}
.results-empty { font-size: 13px; color: alpha(${c.colors[8]}, 0.9); margin-top: 24px; }
`
}
