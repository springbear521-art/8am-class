import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Exercise reopening the exact legacy upper bound: 128 distinct ASCII records
// of 180 characters each. Accept a smaller retained count if recovery migrates
// old logs to a safer bounded capacity, but never accept losing the newest entry.
(:test)
function runLogFullRecoveryAndViewStartup(logger as Test.Logger) as Boolean {
    var keys = ["runLogV1", "fixedMinutes", "repeatDaily", "langZh", "soundMode",
        "vibeMode", "lastSessionV1", "currentSessionV1", "lastTriggeredSessionV1"];
    var saved = [];
    for (var i = 0; i < keys.size(); i++) {
        saved.add(Application.Storage.getValue(keys[i]));
    }

    var view = null;
    var runLog = null;
    var reopened = null;
    var fixture = null;
    var entries = null;
    var failure = null;
    try {
        var filler = "";
        for (var fillIndex = 0; fillIndex < 180; fillIndex++) { filler += "X"; }
        fixture = [];
        for (var recordIndex = 0; recordIndex < 128; recordIndex++) {
            var record = "8AMC " + (1700000000 + recordIndex) +
                " seed_index=" + recordIndex + " " + filler;
            fixture.add(record.substring(0, 180));
        }
        Application.Storage.setValue("runLogV1", fixture);
        fixture = null;
        logger.debug("Before full log recovery free=" + System.getSystemStats().freeMemory);

        var recoveryStarted = System.getTimer();
        runLog = new RunLog();
        logger.debug("Full log recovery ms=" + (System.getTimer() - recoveryStarted));
        entries = runLog.getEntries();
        var retained = entries.size();
        Test.assertMessage(retained > 0 && retained <= 128,
            "Full log recovery must retain a bounded nonempty tail");
        Test.assertMessage(entries[retained - 1].find("seed_index=127") != null,
            "Full recovery must keep the latest persisted record");
        for (var lineIndex = 0; lineIndex < retained; lineIndex++) {
            Test.assertMessage(entries[lineIndex].length() <= 180,
                "Recovered records must obey the line length bound");
        }
        var oldest = entries[0];
        entries = null;

        runLog.add("RECOVERY_APPEND", "after_full_restore=1", false);
        runLog.flush();
        Test.assertMessage(runLog.isStorageOk(), "The full rolling log must persist");
        entries = runLog.getEntries();
        Test.assertEqualMessage(entries.size(), retained,
            "Appending to a full restored log must roll rather than grow");
        Test.assertMessage(!entries[0].equals(oldest), "Rollover must evict the oldest record");
        Test.assertMessage(entries[entries.size() - 1].find("RECOVERY_APPEND") != null,
            "The appended event must be retained");
        entries = null;
        runLog = null;

        reopened = new RunLog();
        entries = reopened.getEntries();
        Test.assertEqualMessage(entries.size(), retained,
            "Reopening must recover the bounded persisted log");
        Test.assertMessage(entries[entries.size() - 1].find("RECOVERY_APPEND") != null,
            "Reopening must recover the event appended after rollover");
        entries = null;
        reopened = null;

        var summary = {
            "start" => 1700000000, "end" => 1700028200, "deadline" => 1700028800,
            "trigger" => 1700028100, "reason" => "movement_hr", "status" => "dismiss",
            "armedElapsedSeconds" => 28100, "sensorSampledSeconds" => 1500,
            "quietSampledSeconds" => 1300, "sampleGaps" => 0,
            "legacySleepModeTrueSeconds" => 0, "modeValidSamples" => 0,
            "modeMissingSamples" => 470, "nativeSleepDurationAvailable" => false,
            "nativeSleepDuration" => null
        };
        Application.Storage.setValue("fixedMinutes", 430);
        Application.Storage.setValue("repeatDaily", true);
        Application.Storage.setValue("langZh", true);
        Application.Storage.setValue("soundMode", 3);
        Application.Storage.setValue("vibeMode", 3);
        Application.Storage.setValue("lastSessionV1", summary);
        Application.Storage.setValue("lastTriggeredSessionV1", summary);
        Application.Storage.setValue("currentSessionV1", summary);
        summary = null;

        logger.debug("Before full View startup free=" + System.getSystemStats().freeMemory);
        var viewStarted = System.getTimer();
        view = new EightAmClassView();
        logger.debug("Full log View startup ms=" + (System.getTimer() - viewStarted));
        Test.assertEqualMessage(view._fixedMinutes, 430,
            "View startup with full logs must still recover the fixed alarm");
        var recoveredSummary = view._summary as Lang.Dictionary;
        Test.assert(recoveredSummary != null);
        Test.assertEqualMessage(recoveredSummary["reason"], "movement_hr",
            "View startup must recover the existing completed summary");
        Test.assertMessage(view._log.isStorageOk(), "Boot event must persist after full recovery");
        logger.debug("After full View startup free=" + System.getSystemStats().freeMemory);
        view.cleanup();
        view = null;
    } catch (ex) {
        failure = ex;
    }

    // Release fixture references before restoration and always stop a created
    // View, including when assertions fail. Restore every key independently.
    entries = null;
    fixture = null;
    runLog = null;
    reopened = null;
    try {
        cleanupRunLogRecoveryView(view);
    } catch (ex) { if (failure == null) { failure = ex; } }
    view = null;
    for (var restoreIndex = 0; restoreIndex < keys.size(); restoreIndex++) {
        try {
            if (saved[restoreIndex] == null) {
                Application.Storage.deleteValue(keys[restoreIndex]);
            } else {
                Application.Storage.setValue(keys[restoreIndex], saved[restoreIndex]);
            }
        } catch (ex) { if (failure == null) { failure = ex; } }
    }
    if (failure != null) {
        logger.error(failure.toString());
        throw failure;
    }
    return true;
}

function cleanupRunLogRecoveryView(view as EightAmClassView or Null) as Void {
    if (view != null) { view.cleanup(); }
}
