import Toybox.Lang;
import Toybox.Test;

// These cases check user-visible scheduling boundaries, independent of device time.
(:test)
function alarmEarlyWindowStartsExactlyTwentyMinutesBeforeDeadline(logger as Test.Logger) as Boolean {
    // 06:40 deadline; 06:19:59 cannot start sampling or trigger an early alert.
    var deadline = 1700000000;
    Test.assertEqual(AlarmPolicy.EARLY_WAKE_SECONDS, 1200);
    Test.assertEqual(AlarmPolicy.inEarlyWindow(deadline - 1201, deadline), false);
    Test.assertEqual(AlarmPolicy.inEarlyWindow(deadline - 1200, deadline), true);
    Test.assertEqual(AlarmPolicy.inEarlyWindow(deadline - 1, deadline), true);
    Test.assertEqual(AlarmPolicy.inEarlyWindow(deadline, deadline), false);
    return true;
}

(:test)
function alarmDeadlineStaysOnTheMinute(logger as Test.Logger) as Boolean {
    var now = 1700000000;
    Test.assertEqual(AlarmPolicy.nextDeadline(480, now, 420, 10) - now, 3590);
    Test.assertEqual(AlarmPolicy.nextDeadline(420, now, 480, 40) - now, 82760);
    return true;
}

(:test)
function alarmDeadlineCrossesMidnight(logger as Test.Logger) as Boolean {
    var now = 1700000000;
    // At 23:59:59, a 00:00 deadline is one second away.
    Test.assertEqual(AlarmPolicy.nextDeadline(0, now, 1439, 59) - now, 1);
    // At 23:50:17, the next 07:00 is 7 h 9 min 43 s away.
    Test.assertEqual(AlarmPolicy.nextDeadline(420, now, 1430, 17) - now, 25783);
    return true;
}

(:test)
function alarmSameMinuteMeansNextDay(logger as Test.Logger) as Boolean {
    var now = 1700000000;
    Test.assertEqual(AlarmPolicy.nextDeadline(420, now, 420, 0) - now, 86400);
    Test.assertEqual(AlarmPolicy.nextDeadline(420, now, 420, 37) - now, 86363);
    return true;
}

(:test)
function alarmEarlyDismissRepeatsTomorrow(logger as Test.Logger) as Boolean {
    var previousDeadline = 1700001000;
    // Smart wake rang before 07:00; dismiss at 06:50:30 must not rearm 07:00 today.
    var dismissAt = previousDeadline - 570;
    var candidate = AlarmPolicy.nextDeadline(420, dismissAt, 410, 30);
    Test.assertEqual(candidate, previousDeadline);
    Test.assertEqual(AlarmPolicy.repeatDeadline(candidate, previousDeadline),
        previousDeadline + 86400);
    return true;
}

(:test)
function alarmLateDismissDoesNotSkipAnExtraDay(logger as Test.Logger) as Boolean {
    var previousDeadline = 1700001000;
    // After a 07:00 alarm, dismiss at 07:01:05 already selects tomorrow.
    var dismissAt = previousDeadline + 65;
    var candidate = AlarmPolicy.nextDeadline(420, dismissAt, 421, 5);
    Test.assertEqual(candidate, previousDeadline + 86400);
    Test.assertEqual(AlarmPolicy.repeatDeadline(candidate, previousDeadline), candidate);
    // A candidate before the previous deadline also moves forward one day.
    Test.assertEqual(AlarmPolicy.repeatDeadline(previousDeadline - 60, previousDeadline),
        previousDeadline + 86340);
    return true;
}

(:test)
function alarmProgressiveStageBoundaries(logger as Test.Logger) as Boolean {
    Test.assertEqual(AlarmPolicy.stage(29), 0);
    Test.assertEqual(AlarmPolicy.stage(30), 1);
    Test.assertEqual(AlarmPolicy.stage(59), 1);
    Test.assertEqual(AlarmPolicy.stage(60), 2);
    return true;
}

(:test)
function alarmProgressiveCadenceAndDuration(logger as Test.Logger) as Boolean {
    Test.assertEqual(AlarmPolicy.interval(3, 29), 10);
    Test.assertEqual(AlarmPolicy.interval(3, 30), 5);
    Test.assertEqual(AlarmPolicy.interval(3, 59), 5);
    Test.assertEqual(AlarmPolicy.interval(3, 60), 2);
    Test.assertEqual(AlarmPolicy.vibeLength(3, 29), 300);
    Test.assertEqual(AlarmPolicy.vibeLength(3, 30), 1000);
    Test.assertEqual(AlarmPolicy.vibeLength(3, 59), 1000);
    Test.assertEqual(AlarmPolicy.vibeLength(3, 60), 2000);
    return true;
}

(:test)
function alarmFixedAlertModesDoNotEscalate(logger as Test.Logger) as Boolean {
    Test.assertEqual(AlarmPolicy.interval(1, 0), 5);
    Test.assertEqual(AlarmPolicy.interval(1, 600), 5);
    Test.assertEqual(AlarmPolicy.interval(2, 0), 3);
    Test.assertEqual(AlarmPolicy.interval(2, 600), 3);
    Test.assertEqual(AlarmPolicy.vibeLength(1, 0), 500);
    Test.assertEqual(AlarmPolicy.vibeLength(1, 600), 500);
    Test.assertEqual(AlarmPolicy.vibeLength(2, 0), 2000);
    Test.assertEqual(AlarmPolicy.vibeLength(2, 600), 2000);
    return true;
}
