pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "about.mjs" as About

ColumnLayout {
    id: page
    required property var controller
    required property var theme
    objectName: "aboutView"
    readonly property var account: controller.about
    readonly property var accountData: account || ({})
    readonly property bool fullPending: accountData.session === undefined
    readonly property string displayName: accountData.realName || accountData.user || "Account"
    // Relative dates are evaluated when the page is shown, without a background timer.
    property double shownAt: Date.now()
    onVisibleChanged: if (visible) shownAt = Date.now()
    readonly property var systemRows: [
        {id:"os", label:"Operating system", value:accountData.os},
        {id:"kernel", label:"Kernel", value:accountData.kernel},
        {id:"hyprland", label:"Hyprland", value:accountData.hyprland},
        {id:"installed", label:"Installed", value:About.formatInstalled(accountData.installed, shownAt)},
        {id:"uptime", label:"Up for", value:About.formatUptime(accountData.uptimeSeconds)},
        {id:"upgrade", label:"Last full upgrade", value:About.formatLastUpgrade(accountData.lastUpgrade, shownAt)}
    ].filter(row => !!row.value && (!fullPending || !["installed", "upgrade"].includes(row.id)))
    readonly property var hardwareRows: {
        if (fullPending) return [];
        const rows = [];
        const cpu = accountData.cpu;
        if (cpu && cpu.name) rows.push({id:"cpu",label:"Processor",value:cpu.name
            + (cpu.cores ? " · " + cpu.cores + (cpu.cores === 1 ? " core" : " cores") : "")
            + (cpu.threads && cpu.threads !== cpu.cores ? " · " + cpu.threads + (cpu.threads === 1 ? " thread" : " threads") : "")});
        (accountData.gpus || []).forEach((gpu, index) => { if (gpu) rows.push({id:"gpu-" + index,label:"Graphics",value:gpu}); });
        if (accountData.memoryGB) rows.push({id:"memory",label:"Memory",value:accountData.memoryGB + " GB"});
        if (accountData.storage) rows.push({id:"storage",label:"Storage",value:accountData.storage.used + " of " + accountData.storage.total + " GB used",fraction:accountData.storage.fraction});
        if (accountData.machine && accountData.machine.value) rows.push({id:"machine",label:accountData.machine.label,value:accountData.machine.value});
        return rows;
    }
    spacing: 22
    RowLayout {
        visible: !!page.account
        Layout.fillWidth: true
        spacing: 16
        Avatar { theme: page.theme; size: 64; source: page.accountData.avatar || ""; name: page.displayName }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 4
            Label {
                text: page.displayName
                color: page.theme.foreground; font.pixelSize: 18; font.bold: true
                Layout.fillWidth: true; elide: Text.ElideRight
            }
            Label {
                objectName: "about-session"
                text: [(page.accountData.user && page.accountData.host ? page.accountData.user + "@" + page.accountData.host : page.accountData.user || page.accountData.host || ""), page.accountData.session || ""].filter(Boolean).join(" · ")
                color: page.theme.dim; font.pixelSize: 13
                Layout.fillWidth: true; wrapMode: Text.Wrap
            }
        }
    }
    SettingsSection {
        objectName: "aboutSystem"
        theme: page.theme
        title: "System"
        visible: page.systemRows.length > 0 || page.fullPending
        Repeater {
            model: page.systemRows
            delegate: InfoRow { theme: page.theme }
        }
        PanelRow {
            theme: page.theme
            visible: page.fullPending
            divider: page.systemRows.length > 0
            Label {
                objectName: "aboutReading"
                text: "Reading system information…"
                color: page.theme.dim; font.pixelSize: 13
                Layout.fillWidth: true
            }
        }
    }
    SettingsSection {
        objectName: "aboutHardware"
        theme: page.theme
        title: "Hardware"
        visible: page.hardwareRows.length > 0
        Repeater {
            model: page.hardwareRows
            delegate: InfoRow { theme: page.theme }
        }
    }
    component InfoRow: PanelRow {
        id: info
        required property var modelData
        required property int index
        objectName: "about-" + modelData.id
        divider: index > 0
        Label {
            text: info.modelData.label
            color: info.theme.foreground; font.pixelSize: 13
            Layout.fillWidth: true
        }
        Rectangle {
            objectName: info.modelData.id === "storage" ? "about-storage-bar" : ""
            visible: info.modelData.id === "storage"
            implicitWidth: 120; implicitHeight: 5; radius: 2.5
            color: info.theme.raised
            Rectangle {
                height: parent.height
                width: parent.width * Math.max(0, Math.min(1, info.modelData.fraction || 0))
                radius: 2.5; color: info.theme.accent
            }
        }
        Label {
            objectName: "about-" + info.modelData.id + "-value"
            text: info.modelData.value
            color: info.theme.dim; font.pixelSize: 13
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.Wrap
            Layout.maximumWidth: page.width * 0.65
        }
    }
}
