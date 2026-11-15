import Toybox.Lang;
import Toybox.WatchUi;

// Start hole screen: START opens the locate screen; UP/DOWN change the hole.
class HCI_StartDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        WatchUi.pushView(new HCI_LocateBallView(), new HCI_LocateDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

    function onNextPage() as Boolean {
        getApp().changeHole(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        getApp().changeHole(-1);
        return true;
    }
}

// Locate ball screen: SELECT saves the ball position, then shows the distance screen.
class HCI_LocateDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        if (getApp().setBallHere()) {
            // Replace the locate screen with the distance screen.
            // BACK from distance then returns to the start screen.
            WatchUi.switchToView(new HCI_DistanceView(), new HCI_DistanceDelegate(), WatchUi.SLIDE_LEFT);
        }
        // With no GPS fix yet, stay on this screen and try again.
        return true;
    }
}

// Distance screen: UP/DOWN change the hole. BACK returns to the start screen.
class HCI_DistanceDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onNextPage() as Boolean {
        getApp().changeHole(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        getApp().changeHole(-1);
        return true;
    }
}