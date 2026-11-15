import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Uses the real application Storage API and View integration, but advances the
// alarm by supplying its deadline to checkAlarm() instead of waiting two minutes.
// Only the bounded diagnostic log is intentionally left as a test trace.
(:test)
function alarmIntegrationPersistsTriggersAndRepeats(logger as Test.Logger) as Boolean {
    var keys = ["fixedMinutes", "repeatDaily", "langZh", "soundMode", "vibeMode",
        "lastSessionV1", "currentSessionV1", "lastTriggeredSessionV1"];
    var saved = [];
    for (var i = 0; i < keys.size(); i++) {
        saved.add(Application.Storage.getValue(keys[i]));
    }

    var view = null;
    var reloaded = null;
    var failure = null;
    try {
        view = new EightAmClassView();
        var clock = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var wakeMinutes = (clock.hour * 60 + clock.min + 2) % 1440;
        view._wakeMinutes = wakeMinutes;
        view._soundMode = 3;
        view._vibeMode = 3;
        view._repeatDaily = true;
        view.armAlarm(0);

        Test.assertEqualMessage(view._state, 1, "Arming must enter monitoring state");
        Test.assertEqualMessage(Application.Storage.getValue("fixedMinutes"), wakeMinutes,
            "Arming must persist the selected fixed alarm time");
        var deadline = view._deadline;

        view.checkAlarm(deadline);
        Test.assertEqualMessage(view._state, 2, "Deadline check must enter ringing state");
        Test.assertEqualMessage(view._triggerReason, "deadline",
            "Deadline trigger must preserve its actual reason");
        Test.assertEqual(view._alertStage, 0);
        view.checkAlarm(deadline + 30);
        Test.assertEqual(view._alertStage, 1);
        view.checkAlarm(deadline + 60);
        Test.assertEqual(view._alertStage, 2);
        Test.assertEqual(view._toneUnavailable, false);
        Test.assertEqual(view._vibrationUnavailable, false);

        view.confirm();
        Test.assertEqualMessage(view._state, 1, "Dismissing daily alarm must rearm");
        Test.assertEqualMessage(view._deadline, deadline + 86400,
            "Daily alarm must repeat tomorrow rather than ring again today");
        var completed = Application.Storage.getValue("lastSessionV1") as Lang.Dictionary;
        Test.assert(completed != null);
        Test.assertEqualMessage(completed["reason"], "deadline",
            "Next day's armed snapshot must not erase the finished trigger reason");
        Test.assertEqualMessage(completed["status"], "dismiss",
            "Completed session must record how the user stopped the alarm");

        view.cleanup();
        view = null;
        reloaded = new EightAmClassView();
        Test.assertEqualMessage(reloaded._fixedMinutes, wakeMinutes,
            "A newly constructed view must restore the fixed alarm from Storage");
    } catch (ex) {
        failure = ex;
    }

    // Always stop timers before restoring Storage, including when an assertion
    // throws. Try each restoration independently so one failure cannot skip others.
    try {
        cleanupAlarmTestView(view);
    } catch (ex) { if (failure == null) { failure = ex; } }
    try {
        cleanupAlarmTestView(reloaded);
    } catch (ex) { if (failure == null) { failure = ex; } }
    for (var j = 0; j < keys.size(); j++) {
        try {
            if (saved[j] == null) {
                Application.Storage.deleteValue(keys[j]);
            } else {
                Application.Storage.setValue(keys[j], saved[j]);
            }
        } catch (ex) { if (failure == null) { failure = ex; } }
    }
    if (failure != null) {
        logger.error(failure.toString());
        throw failure;
    }
    return true;
}

function cleanupAlarmTestView(view as EightAmClassView or Null) as Void {
    if (view != null) { view.cleanup(); }
}
