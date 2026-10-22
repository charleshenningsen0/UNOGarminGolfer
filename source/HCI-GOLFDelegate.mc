import Toybox.Lang;
import Toybox.WatchUi;

class HCI_GOLFDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new HCI_GOLFMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}