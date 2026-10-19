import Toybox.Lang;
import Toybox.WatchUi;

class UNOGarminGolferDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new UNOGarminGolferMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}