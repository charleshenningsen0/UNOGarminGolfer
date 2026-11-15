import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;

class HCI_GOLFApp extends Application.AppBase {

    const FIRST_HOLE = 1;
    const LAST_HOLE  = 5;

    // From the scorecard, holes 1-5
    const PARS  = [4, 3, 4, 4, 3];
    const YARDS = [280, 130, 344, 349, 175];
    const HCPS  = [13, 15, 11, 5, 9];

    var hole     = 1;
    var model    = null;    // current hole's JSON dictionary
    var lengthYd = null;    // mapped tee-to-green estimate, in yards
    var result   = null;    // GolfGeo.analyze output, from the saved ball position

    // Live GPS, used only when locating the ball
    var gpsLat = null;
    var gpsLon = null;

    // Saved ball per hole (index = hole - 1): [lat, lon] or null
    var balls = [null, null, null, null, null];

    var radius = 200.0;
    var unit   = "yards";
    var timer  = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        timer = new Timer.Timer();
        timer.start(method(:pollPosition), 1000, true);
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
        if (timer != null) { timer.stop(); }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
    }

    // The app opens on the start hole screen
    function getInitialView() as [Views] or [Views, InputDelegates] {
        loadBalls();
        loadHole();
        return [ new HCI_StartHoleView(), new HCI_StartDelegate() ];
    }

    // ---------------- storage ----------------

    // Reads every saved ball position from storage at startup.
    function loadBalls() as Void {
        for (var i = 0; i < balls.size(); i++) {
            var v = Application.Storage.getValue("ball" + (i + 1).toString());
            if (v instanceof Lang.Array && v.size() == 2) {
                balls[i] = v;
            }
        }
    }

    // Saves the current GPS position as this hole's ball position.
    // Returns false if there is no GPS fix yet.
    function setBallHere() as Boolean {
        if (gpsLat == null || gpsLon == null) { return false; }
        var idx = hole - 1;
        balls[idx] = [gpsLat, gpsLon];
        Application.Storage.setValue("ball" + hole.toString(), balls[idx]);
        recompute();
        return true;
    }

    // Removes this hole's saved ball position (useful for testing).
    function clearBall() as Void {
        balls[hole - 1] = null;
        Application.Storage.deleteValue("ball" + hole.toString());
        recompute();
    }

    function hasBall() as Boolean {
        return balls[hole - 1] != null;
    }

    // ---------------- GPS ----------------

    function onPosition(info as Position.Info) as Void {
        if (info.position != null) {
            var deg = info.position.toDegrees();
            gpsLat = deg[0];
            gpsLon = deg[1];
        }
        WatchUi.requestUpdate();
    }

    // The simulator may not deliver repeated events, so also poll once per second.
    function pollPosition() as Void {
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            var deg = info.position.toDegrees();
            gpsLat = deg[0];
            gpsLon = deg[1];
        }
        WatchUi.requestUpdate();
    }

    // ---------------- holes ----------------

    // step = +1 or -1; wraps around the exported holes
    function changeHole(step as Number) as Void {
        hole = hole + step;
        if (hole > LAST_HOLE) { hole = FIRST_HOLE; }
        if (hole < FIRST_HOLE) { hole = LAST_HOLE; }
        loadHole();
        WatchUi.requestUpdate();
    }

    // Loads only the current hole's file to keep memory low.
    function loadHole() as Void {
        if (hole == 1)      { model = WatchUi.loadResource(Rez.JsonData.hole01); }
        else if (hole == 2) { model = WatchUi.loadResource(Rez.JsonData.hole02); }
        else if (hole == 3) { model = WatchUi.loadResource(Rez.JsonData.hole03); }
        else if (hole == 4) { model = WatchUi.loadResource(Rez.JsonData.hole04); }
        else if (hole == 5) { model = WatchUi.loadResource(Rez.JsonData.hole05); }

        lengthYd = null;
        if (model != null) {
            var m = GolfGeo.playingLineLengthM(GolfGeo.dget(model, "features"));
            if (m != null) { lengthYd = (m / 0.9144 + 0.5).toNumber(); }
        }
        recompute();
    }

    // Distances are measured from the saved ball position, not the watch.
    function recompute() as Void {
        var idx = hole - 1;
        if (model == null || balls[idx] == null) {
            result = null;
            return;
        }
        var b = balls[idx];
        result = GolfGeo.analyze(model, b[0], b[1], radius, unit, false);
    }

    // e.g. "PAR 4 | 280 YD" or "PAR 4 | ~412 YD" when only the mapped estimate is known
    function holeInfoText() as String {
        var idx = hole - 1;

        var parStr = "PAR --";
        if (PARS[idx] > 0) { parStr = "PAR " + PARS[idx].toString(); }

        var ydStr = "-- YD";
        if (YARDS[idx] > 0) {
            ydStr = YARDS[idx].toString() + " YD";
        } else if (lengthYd != null) {
            ydStr = "~" + lengthYd.toString() + " YD";
        }

        return parStr + " | " + ydStr;
    }
}

function getApp() as HCI_GOLFApp {
    return Application.getApp() as HCI_GOLFApp;
}