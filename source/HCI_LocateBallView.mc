import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class HCI_LocateBallView extends WatchUi.View {

    const BG    = 0x0B0C0A;
    const LIME  = 0xCCFF66;
    const HALO  = 0x1F2A10;
    const BALL  = 0xF8F6F9;   // ball face
    const SHADE = 0xD4D2DA;   // shadow crescent and dimples
    const MUTED = 0x8A8C86;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h * 46 / 100;

        dc.setColor(BG, BG);
        dc.clear();

        // Header
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 14 / 100, Graphics.FONT_XTINY, "SHOT TRACKING",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Halo and lime button
        var outerR = h * 25 / 100;
        var innerR = h * 21 / 100;
        dc.setColor(HALO, BG);
        dc.fillCircle(cx, cy, outerR);
        dc.setColor(LIME, BG);
        dc.fillCircle(cx, cy, innerR);

        // Ball in the upper part of the lime circle
        drawGolfBall(dc, cx, cy - h * 9 / 100, h * 4 / 100);

        // Labels: transparent background so nothing sticks out of the circle
        dc.setColor(BG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + h * 3 / 100, Graphics.FONT_XTINY, "LOCATED",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy + h * 9 / 100, Graphics.FONT_XTINY, "BALL",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Shorter hint
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 80 / 100, Graphics.FONT_XTINY, "Press at ball",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

        // Golf ball with depth: drop shadow on the lime, shaded rim,
    // lit face offset toward the light, and a small highlight.
    // x, y = center, r = radius
    function drawGolfBall(dc as Dc, x as Number, y as Number, r as Number) as Void {
        // Drop shadow: a darker lime disc offset down-right
        dc.setColor(0x8DB53A, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + r * 18 / 100, y + r * 22 / 100, r * 98 / 100);

        // Shaded rim: the full ball in a mid gray
        dc.setColor(0xB4B2BC, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);

        // Lit face, offset up-left to leave the shaded crescent on the lower-right
        dc.setColor(BALL, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - r * 10 / 100, y - r * 12 / 100, r * 88 / 100);

        // Highlight near the upper-left
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - r * 32 / 100, y - r * 36 / 100, r * 16 / 100);

        // Dimples, same staggered pattern, in the mid tone
        var d = r * 13 / 100;
        if (d < 1) { d = 1; }

        var row1Y = 14;
        var row1X = [-181, -91, 0, 89, 179];
        var row2Y = 89;
        var row2X = [-137, -51, 51, 139];
        var row3Y = 164;
        var row3X = [-101, 0, 99];

        dc.setColor(0xB4B2BC, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < row1X.size(); i++) {
            dc.fillCircle(x + row1X[i] * r / 256, y + row1Y * r / 256, d);
        }
        for (var i = 0; i < row2X.size(); i++) {
            dc.fillCircle(x + row2X[i] * r / 256, y + row2Y * r / 256, d);
        }
        for (var i = 0; i < row3X.size(); i++) {
            dc.fillCircle(x + row3X[i] * r / 256, y + row3Y * r / 256, d);
        }
    }
}