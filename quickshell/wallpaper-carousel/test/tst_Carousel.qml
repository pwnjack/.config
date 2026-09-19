import QtQuick
import QtTest
import ".."

Item {
    width: 1280
    height: 800

    QtObject {
        id: controller
        property bool loading: false
        property bool submitting: false
        property bool previewReady: false
        property bool searchVisible: false
        property bool reducedMotion: true
        property bool closed: false
        property int submissions: 0
        property int selectedIndex: 0
        property string query: ""
        property string problem: ""
        property color background: "#05090c"
        property color foreground: "#cfddde"
        property color accent: "#6097a1"
        property var snapshot: ({
                entries: [],
                current: ""
            })
        property var entries: []
        readonly property var selected: entries[selectedIndex] || null
        function close() {
            closed = true;
        }
        function navigate(step) {
            if (!submitting && entries.length)
                selectedIndex = (selectedIndex + step + entries.length) % entries.length;
        }
        function confirm() {
            if (submitting)
                return;
            submissions++;
            submitting = true;
        }
        onQueryChanged: {
            entries = snapshot.entries.filter(e => e.name.includes(query));
            selectedIndex = 0;
        }
    }
    Carousel {
        id: carousel
        anchors.fill: parent
        controller: controller
        pixelScale: 1
    }
    TestCase {
        name: "Carousel"
        when: windowShown
        readonly property string pixel: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" fill="teal"/></svg>')
        function init() {
            controller.submitting = false;
            controller.loading = false;
            controller.closed = false;
            controller.submissions = 0;
            controller.searchVisible = false;
            controller.query = "";
            controller.snapshot = {
                current: "a.png",
                entries: [
                    {
                        path: "a.png",
                        name: "a.png",
                        url: pixel
                    },
                    {
                        path: "b.png",
                        name: "b.png",
                        url: pixel
                    },
                    {
                        path: "missing.png",
                        name: "missing.png",
                        url: "file:///nonexistent-carousel-fixture.png"
                    }
                ]
            };
            controller.entries = controller.snapshot.entries;
            controller.selectedIndex = 0;
            carousel.forceActiveFocus();
            tryVerify(() => carousel.currentCard !== null);
            tryCompare(carousel.currentCard, "ready", true);
        }
        function test_mouse_select_then_confirm() {
            const cards = findChild(carousel, "wallpaperCards");
            const next = cards.itemAtIndex(1);
            verify(next !== null);
            mouseClick(next, next.width / 2, next.height / 2);
            compare(controller.selectedIndex, 1);
            compare(controller.submissions, 0);
            tryCompare(carousel.currentCard, "ready", true);
            mouseClick(carousel.currentCard, carousel.currentCard.width / 2, carousel.currentCard.height / 2);
            compare(controller.submissions, 1);
            mouseClick(carousel.currentCard, carousel.currentCard.width / 2, carousel.currentCard.height / 2);
            compare(controller.submissions, 1);
        }
        function test_mouse_wheel() {
            const cards = findChild(carousel, "wallpaperCards");
            mouseWheel(cards, cards.width / 2, cards.height / 2, 0, -120);
            compare(controller.selectedIndex, 1);
            compare(controller.submissions, 0);
        }
        function test_wheel_over_background() {
            // The pointer commonly stays above/below the cards when opening.
            mouseWheel(carousel, 30, 30, 0, -120);
            compare(controller.selectedIndex, 1);
            mouseWheel(carousel, 30, carousel.height - 10, 0, 120);
            compare(controller.selectedIndex, 0);
            compare(controller.submissions, 0);
        }
        function test_horizontal_wheel() {
            mouseWheel(carousel, 30, 30, -120, 0);
            compare(controller.selectedIndex, 1);
        }
        function test_high_resolution_wheel() {
            for (let i = 0; i < 7; i++)
                mouseWheel(carousel, 30, 30, 0, -15);
            compare(controller.selectedIndex, 0);
            mouseWheel(carousel, 30, 30, 0, -15);
            compare(controller.selectedIndex, 1);
        }
        function test_keyboard_search_and_cancel() {
            keyClick(Qt.Key_Right);
            compare(controller.selectedIndex, 1);
            keyClick(Qt.Key_F, Qt.ControlModifier);
            const search = findChild(carousel, "filenameSearch");
            tryCompare(search, "activeFocus", true);
            keyClick(Qt.Key_Z);
            compare(controller.entries.length, 0);
            keyClick(Qt.Key_Escape);
            compare(controller.closed, true);
            compare(controller.submissions, 0);
        }
        function test_empty_folder_dismissal() {
            controller.entries = [];
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Return);
            compare(controller.submissions, 0);
            keyClick(Qt.Key_Escape);
            compare(controller.closed, true);
        }
        function test_unreadable_preview_cannot_apply() {
            controller.selectedIndex = 2;
            tryVerify(() => carousel.currentCard && carousel.currentCard.imageUrl.includes("nonexistent"));
            tryCompare(carousel.currentCard, "ready", false);
            compare(findChild(carousel, "applyWallpaper").enabled, false);
            keyClick(Qt.Key_Return);
            compare(controller.submissions, 0);
            keyClick(Qt.Key_Escape);
            compare(controller.closed, true);
        }
    }
}
