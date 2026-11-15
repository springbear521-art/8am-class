import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Bounded diagnostics independent of the optional GARMIN/APPS/LOGS text file.
// ASCII records keep this single Storage value comfortably below its 32 KB limit.
// Callers choose when to persist: critical events immediately, telemetry in batches.
class RunLog {
    const STORAGE_KEY = "runLogV1";
    const MAX_ENTRIES = 128;
    const MAX_LINE_LENGTH = 180;

    var _entries = [];
    var _dirty = false;
    var _storageOk = true;

    function initialize() {
        try {
            var saved = Application.Storage.getValue(STORAGE_KEY);
            if (saved instanceof Lang.Array) {
                var first = saved.size() > MAX_ENTRIES ? saved.size() - MAX_ENTRIES : 0;
                for (var i = first; i < saved.size(); i++) {
                    if (saved[i] instanceof Lang.String) {
                        // These records were already sanitized by add(). Cleaning
                        // the whole overnight history again trips the device
                        // watchdog on startup. Reuse bounded immutable strings.
                        var entry = saved[i];
                        _entries.add(entry.length() > MAX_LINE_LENGTH ?
                            entry.substring(0, MAX_LINE_LENGTH) : entry);
                    }
                }
            }
        } catch (ex) {
            _storageOk = false;
        }
    }

    // Output format: 8AMC <epoch seconds> <event> <key=value details>
    // Non-ASCII and control characters are replaced so every event is one line.
    function add(name, details, persist) {
        try {
            var eventName = name == null ? "EVENT" : name.toString();
            var detailText = details == null ? "" : details.toString();
            var entry = clean("8AMC " + Time.now().value() + " " + eventName + " " + detailText);
            if (_entries.size() >= MAX_ENTRIES) {
                _entries = _entries.slice(1, null);
            }
            _entries.add(entry);
            _dirty = true;
            try {
                System.println(entry);
            } catch (printError) {
                // Device text logging is optional; persistent logs still work.
            }
            if (persist) { flush(); }
        } catch (ex) {
            // Diagnostics must never interrupt alarm processing.
        }
    }

    function flush() {
        if (!_dirty) { return; }
        try {
            Application.Storage.setValue(STORAGE_KEY, _entries);
            _storageOk = true;
            _dirty = false;
        } catch (ex) {
            _storageOk = false;
            // Keep dirty data in RAM so a later flush can retry.
        }
    }

    function getEntries() {
        return _entries.slice(0, null);
    }

    function isStorageOk() {
        return _storageOk;
    }

    function clean(value) {
        var result = "";
        var characters = value.toCharArray();
        var count = characters.size() < MAX_LINE_LENGTH ? characters.size() : MAX_LINE_LENGTH;
        for (var i = 0; i < count; i++) {
            var code = characters[i].toNumber();
            if (code >= 32 && code <= 126) {
                result += characters[i].toString();
            } else if (code == 9 || code == 10 || code == 13) {
                result += " ";
            } else {
                result += "?";
            }
        }
        return result;
    }
}
