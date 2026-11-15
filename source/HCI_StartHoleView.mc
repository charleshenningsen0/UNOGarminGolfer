import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class HCI_StartHoleView extends WatchUi.View {

    const BG    = 0x0B0C0A;
    const LIME  = 0xCCFF66;
    const Green = 0x7AB52A;
    const WHITE = 0xF2F2F0;
    const MUTED = 0x8A8C86;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        // Placeholder data; replace with course database values
        var hole   = getApp().hole.toString();
        var par    = getApp().holeInfoText();

        dc.setColor(BG, BG);
        dc.clear();

        // Course name
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 15 / 100, Graphics.FONT_TINY, "Elmwood Park",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // HOLE label
        dc.setColor(Green, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 27 / 100, Graphics.FONT_TINY, "HOLE",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Hole number
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 46 / 100, Graphics.FONT_NUMBER_HOT, hole,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Par and yardage
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 63 / 100, Graphics.FONT_XTINY, par,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // START button
        var btnW = w * 62 / 100;
        var btnH = h * 14 / 100;
        var btnX = cx - btnW / 2;
        var btnY = h * 74 / 100;
        var radius = btnH / 2;

        dc.setColor(LIME, BG);
        dc.fillRoundedRectangle(btnX, btnY, btnW, btnH, radius);

        // Label and chevron, centered as a group
        var label = "START";
        var labelW = dc.getTextWidthInPixels(label, Graphics.FONT_XTINY);
        var chevW  = h * 3 / 100;
        var gap    = 6;
        var groupW = labelW + gap + chevW;
        var groupX = cx - groupW / 2;
        var midY   = btnY + btnH / 2;

        dc.setColor(BG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(groupX, midY, Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Chevron ">" drawn as two lines
        var chevX = groupX + labelW + gap;
        var chevH = chevW;
        dc.setPenWidth(2);
        dc.drawLine(chevX, midY - chevH / 2, chevX + chevW, midY);
        dc.drawLine(chevX + chevW, midY, chevX, midY + chevH / 2);
        dc.setPenWidth(1);
    }
}