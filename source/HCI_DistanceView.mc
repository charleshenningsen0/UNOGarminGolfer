import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class HCI_DistanceView extends WatchUi.View {

    const BG     = 0x0B0C0A;
    const LIME   = 0xCCFF66;
    const WHITE  = 0xF2F2F0;
    const MUTED  = 0x8A8C86;
    const RED    = 0xFF4433;
    const GRASS  = 0x7AB52A;
    const POLE   = 0x9A9C96;

    // Set to false to hide the category debug line at the bottom.
    const SHOW_DEBUG = false;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var app = getApp();
        var r = app.result as Dictionary?;
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        var hole = app.hole.toString();
        var yards = "--";
        var wind  = "-- mph";   // no wind source on the watch yet

        // Distance to the mapped green center, rounded to whole yards
        if (r != null) {
            var g = r["green"] as Dictionary?;
            if (g != null) {
                var c = g["center"] as Float?;
                if (c != null) {
                    yards = (c + 0.5).toNumber().toString();
                }
            }
        }

        dc.setColor(BG, BG);
        dc.clear();

        // Vertical layout as fractions of screen height
        var yHole  = h * 12 / 100;
        var flagT  = h * 17 / 100;
        var flagS  = h * 12 / 100;
        var yToPin = h * 36 / 100;
        var yMain  = h * 50 / 100;
        var yYards = h * 69 / 100;
        var yWind  = h * 85 / 100;

        // HOLE label
        dc.setColor(MUTED, BG);
        dc.drawText(cx, yHole, Graphics.FONT_XTINY, "HOLE " + hole,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Flag on grass
        drawFlag(dc, cx, flagT, flagS);

        // Main distance
        dc.setColor(WHITE, BG);
        dc.drawText(cx, yMain, Graphics.FONT_NUMBER_MEDIUM, yards,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Unit label
        dc.setColor(LIME, BG);
        dc.drawText(cx, yYards, Graphics.FONT_XTINY, app.unit.toUpper(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Wind row
        var iconS = h * 9 / 100;
        var iconX = cx - iconS - 6;
        var iconY = yWind - iconS / 2;
        drawWindIcon(dc, iconX, iconY, iconS);

        dc.setColor(MUTED, BG);
        dc.drawText(iconX + iconS + 6, yWind, Graphics.FONT_XTINY, wind,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // TO PIN label, drawn last so nothing covers it
        dc.setColor(MUTED, BG);
        dc.drawText(cx, yToPin, Graphics.FONT_XTINY, "TO PIN",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Debug: categories the watch reads from the loaded hole file
        if (SHOW_DEBUG) {
            dc.setColor(MUTED, BG);
            dc.drawText(cx, h * 95 / 100, Graphics.FONT_XTINY,
                debugText(app),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Shows whether a ball is saved and whether GPS is available.
    function debugText(app as HCI_GOLFApp) as String {
        var ball = app.hasBall() ? "ball" : "noBall";
        var gps  = (app.gpsLat != null) ? "GPS" : "noGPS";
        return ball + " " + gps;
    }
    
    // Golf flag: grass patch, pole, cup, and red pennant.
    function drawFlag(dc as Dc, cx as Number, top as Number, s as Number) as Void {
        var groundY = top + s * 85 / 100;
        var poleW   = s * 8 / 100;
        if (poleW < 2) { poleW = 2; }
        var poleX   = cx - poleW / 2;

        // Grass ellipse
        dc.setColor(GRASS, BG);
        dc.fillEllipse(cx, groundY, s * 46 / 100, s * 12 / 100);

        // Pole
        dc.setColor(POLE, BG);
        dc.fillRectangle(poleX, top, poleW, groundY - top);

        // Cup
        dc.setColor(BG, BG);
        dc.fillEllipse(poleX + poleW / 2, groundY, s * 12 / 100, s * 4 / 100);

        // Red pennant
        dc.setColor(RED, BG);
        dc.fillPolygon([
            [poleX + poleW, top],
            [poleX + poleW + s * 52 / 100, top + s * 20 / 100],
            [poleX + poleW, top + s * 42 / 100]
        ]);
    }

    // Wind icon: three strokes, with a curl on the top and bottom.
    // x, y = top-left of the icon box, s = box size
    function drawWindIcon(dc as Dc, x as Number, y as Number, s as Number) as Void {
        var t = s * 9 / 100;
        if (t < 1) { t = 1; }
        var r = t / 2;
        var curl = s * 9 / 100;

        dc.setColor(LIME, BG);
        dc.setPenWidth(t);

        // Top gust
        var topY = y + s * 30 / 100;
        var topEndX = x + s * 55 / 100;
        dc.fillCircle(x + s * 15 / 100, topY, r);
        dc.drawLine(x + s * 15 / 100, topY, topEndX, topY);
        dc.drawArc(topEndX, topY - curl, curl,
            Graphics.ARC_COUNTER_CLOCKWISE, 270, 90);

        // Middle gust
        var midY = y + s * 50 / 100;
        dc.fillCircle(x, midY, r);
        dc.drawLine(x, midY, x + s * 85 / 100, midY);

        // Bottom gust
        var botY = y + s * 70 / 100;
        var botEndX = x + s * 70 / 100;
        dc.fillCircle(x + s * 30 / 100, botY, r);
        dc.drawLine(x + s * 30 / 100, botY, botEndX, botY);
        dc.drawArc(botEndX, botY + curl, curl,
            Graphics.ARC_CLOCKWISE, 90, 270);

        dc.setPenWidth(1);
    }
}