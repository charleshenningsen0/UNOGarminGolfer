
import Toybox.Graphics;
import Toybox.WatchUi;

class HCI_GOLFView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var col = w / 3;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var hole = "1";
        var direction = "NW";
        var front = "235";
        var center = "250";
        var back = "267";

        // Header
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(
            w / 2, 15,
            Graphics.FONT_SMALL,
            "HOLE " + hole + " | " + direction,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Main distance
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(
            w / 2, 65,
            Graphics.FONT_LARGE,
            center,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Label below main distance
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(
            w / 2, 115,
            Graphics.FONT_XTINY,
            "YARDS TO CENTER",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Divider
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(25, 175, w - 25, 175);

        
        // Front and back labels
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);

        dc.drawText(
            w / 4, 205,
            Graphics.FONT_XTINY,
            "FRONT",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        dc.drawText(
            w * 3 / 4, 205,
            Graphics.FONT_XTINY,
            "BACK",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Front and back distances
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);

        dc.drawText(
            w / 4, 25,
            Graphics.FONT_SMALL,
            front,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        dc.drawText(
            w * 3 / 4, 235,
            Graphics.FONT_SMALL,
            back,
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }
}
