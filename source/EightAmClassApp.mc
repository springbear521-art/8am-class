import Toybox.Application;
import Toybox.ActivityMonitor;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.UserProfile;
import Toybox.WatchUi;

class EightAmClassApp extends Application.AppBase {
    var _view;
    var _input;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        _view = new EightAmClassView();
        _input = new EightAmClassInput(_view);
        return [_view, _input];
    }

    function onStop(state) {
        if (_view != null) {
            _view.cleanup();
        }
        if (_input != null) {
            _input.cleanup();
        }
    }
}

class EightAmClassView extends WatchUi.View {
    // Pages: 0 = home, 1 = alarm, 2 = manual, 3 = settings, 4 = logs.
    var _page = 0;
    var _menuIndex = 0;
    var _manualPage = 0;
    var _settingsIndex = 0;
    var _langZh = true;
    // 0 = off, 1 = alarm tone, 2 = loud beep, 3 = progressive beeps.
    var _soundMode = 3;
    // 0 = off, 1 = gentle, 2 = strong. Forerunner vibration intensity is fixed;
    // modes vary the duration and repetition interval instead.
    var _vibeMode = 3;
    var _fixedMinutes = null;
    var _repeatDaily = true;
    var _notice = "";
    // Alarm states: 0 = edit, 1 = armed, 2 = ringing.
    var _state = 0;
    var _wakeMinutes = 0;
    var _editField = 0; // 0 = hour, 1 = minute.
    var _deadline = 0;
    var _timer;
    var _chineseFont;
    var _sensorOn = false;
    var _sensorUnavailable = false;
    var _quietSeconds = 0;
    var _candidateUntil = 0;
    var _motionSeconds = 0;
    var _baselineHr = null;
    var _lastHr = null;
    var _lastX = null;
    var _lastY = null;
    var _lastZ = null;
    var _nextVibe = 0;
    var _nextTone = 0;
    var _ringStarted = 0;
    var _alertStage = -1;
    var _ringEnd = 0;
    var _vibrationUnavailable = false;
    var _toneUnavailable = false;
    var _log;
    var _summary = null;
    var _lastTriggered = null;
    var _logIndex = 0;
    var _logDetails = false;
    var _sessionStart = 0;
    var _sessionActive = false;
    var _triggerReason = "none";
    var _triggerAt = 0;
    var _lastSampleAt = 0;
    var _sampledSeconds = 0;
    var _quietSampledSeconds = 0;
    var _sampleGaps = 0;
    var _nextSnapshot = 0;
    var _lastDeviceCheck = 0;
    var _lastMode = null;
    var _lastDeviceFlags = "";
    var _modeTrueSeconds = 0;
    var _modeValidSamples = 0;
    var _modeMissingSamples = 0;

    function initialize() {
        View.initialize();
        _timer = new Timer.Timer();
        _log = new RunLog();
        _chineseFont = WatchUi.loadResource(Rez.Fonts.Chinese);
        var savedLang = loadValue("langZh");
        var savedSound = loadValue("soundMode");
        var savedVibe = loadValue("vibeMode");
        if (savedLang != null) { _langZh = savedLang; }
        if (savedSound != null && savedSound >= 0 && savedSound <= 3) {
            _soundMode = savedSound;
        }
        if (savedVibe != null && savedVibe >= 0 && savedVibe <= 3) {
            _vibeMode = savedVibe;
        }
        var fixed = loadValue("fixedMinutes");
        if (fixed != null && fixed >= 0 && fixed < 1440) { _fixedMinutes = fixed; }
        var repeat = loadValue("repeatDaily");
        if (repeat != null) { _repeatDaily = repeat; }
        _summary = loadValue("lastSessionV1");
        _lastTriggered = loadValue("lastTriggeredSessionV1");
        _log.add("boot", "version=0.2.1 native_sleep_s=NA", true);
    }

    function loadValue(key) {
        try { return Application.Storage.getValue(key); } catch (ex) { return null; }
    }

    function saveValue(key, value) {
        try { Application.Storage.setValue(key, value); } catch (ex) {
            _log.add("storage_error", "key=" + key, false);
        }
    }

    function onShow() {
        _timer.stop();
        _timer.start(method(:onTick), 5000, true);
        onTick();
    }

    function cleanup() {
        if (_sessionActive) { finishSession("app_stop"); }
        _log.add("app_stop", "", true);
        _timer.stop();
        stopSensor();
    }

    function adjust(delta) {
        if (!isEditing()) { return; }
        var hour = _wakeMinutes / 60;
        var minute = _wakeMinutes % 60;
        if (_editField == 0) {
            hour = (hour + delta + 24) % 24;
        } else {
            minute = (minute + delta + 60) % 60;
        }
        _wakeMinutes = hour * 60 + minute;
        WatchUi.requestUpdate();
    }

    function isEditing() {
        return _page == 1 && _state == 0;
    }

    function navigate(delta) {
        _notice = "";
        if (_page == 0) {
            _menuIndex = (_menuIndex + delta + 5) % 5;
        } else if (_page == 2) {
            _manualPage = (_manualPage + delta + 4) % 4;
        } else if (_page == 3) {
            _settingsIndex = (_settingsIndex + delta + 5) % 5;
        } else if (_page == 4) {
            var count = _log.getEntries().size();
            if (count > 0) { _logIndex = (_logIndex + delta + count) % count; }
            _logDetails = true;
        } else if (isEditing()) {
            adjust(-delta);
            return;
        }
        WatchUi.requestUpdate();
    }

    function canNavigate() {
        return _page != 1 || _state == 0;
    }

    function enterAlarm() {
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        _wakeMinutes = now.hour * 60 + now.min;
        _editField = 0;
        _state = 0;
        _page = 1;
    }

    function confirm() {
        if (_page == 0) {
            if (_menuIndex == 0) {
                if (_fixedMinutes == null) { enterAlarm(); }
                else { _wakeMinutes = _fixedMinutes; _page = 1; armAlarm(0); }
            } else if (_menuIndex == 1) {
                enterAlarm();
            } else if (_menuIndex == 2) {
                _page = 4;
                _logIndex = _log.getEntries().size() - 1;
                _logDetails = false;
            } else if (_menuIndex == 3) {
                _manualPage = 0;
                _page = 2;
            } else {
                _page = 3;
            }
        } else if (_page == 2) {
            _manualPage = (_manualPage + 1) % 4;
        } else if (_page == 4) {
            _logDetails = !_logDetails;
        } else if (_page == 3) {
            if (_settingsIndex == 0) {
                _langZh = !_langZh;
                saveValue("langZh", _langZh);
            } else if (_settingsIndex == 1) {
                _soundMode = (_soundMode + 1) % 4;
                if (_soundMode == 0 && _vibeMode == 0) { _vibeMode = 1; }
                saveValue("soundMode", _soundMode);
                saveValue("vibeMode", _vibeMode);
            } else if (_settingsIndex == 2) {
                _vibeMode = (_vibeMode + 1) % 4;
                if (_vibeMode == 0 && _soundMode == 0) { _soundMode = 1; }
                saveValue("vibeMode", _vibeMode);
                saveValue("soundMode", _soundMode);
            } else if (_settingsIndex == 3) {
                _repeatDaily = !_repeatDaily;
                saveValue("repeatDaily", _repeatDaily);
            } else {
                importWakeTime();
            }
        } else if (_state == 0) {
            if (_editField == 0) {
                _editField = 1;
                WatchUi.requestUpdate();
                return;
            }
            armAlarm(0);
        } else if (_state == 2) {
            var previousDeadline = _deadline;
            finishSession("dismiss");
            if (_repeatDaily) { armAlarm(previousDeadline); }
            else { resetToHome(); }
        }
        WatchUi.requestUpdate();
    }

    function cancel() {
        if (_page == 0) { return false; }
        if (_page == 1 && _state == 0 && _editField == 1) {
            _editField = 0;
            WatchUi.requestUpdate();
            return true;
        }
        if (_sessionActive) { finishSession("cancel"); }
        resetToHome();
        WatchUi.requestUpdate();
        return true;
    }

    function resetToHome() {
        _state = 0;
        _editField = 0;
        _page = 0;
        stopSensor();
        _timer.stop();
        _timer.start(method(:onTick), 5000, true);
    }

    function importWakeTime() {
        try {
            var profile = UserProfile.getProfile();
            if (profile.wakeTime != null) {
                _fixedMinutes = (profile.wakeTime.value() / 60) % 1440;
                saveValue("fixedMinutes", _fixedMinutes);
                _notice = tr("Saved ", "已保存 ") + clockText(_fixedMinutes);
                _log.add("import_schedule", "wake_min=" + _fixedMinutes, true);
                return;
            }
        } catch (ex) {}
        _notice = tr("Not available", "作息数据不可用");
        _log.add("import_schedule", "unavailable", true);
    }

    function armAlarm(previousDeadline) {
        var now = Time.now();
        var clock = Gregorian.info(now, Time.FORMAT_SHORT);
        _deadline = AlarmPolicy.nextDeadline(_wakeMinutes, now.value(),
            clock.hour * 60 + clock.min, clock.sec);
        if (previousDeadline > 0) {
            _deadline = AlarmPolicy.repeatDeadline(_deadline, previousDeadline);
        }
        _fixedMinutes = _wakeMinutes;
        saveValue("fixedMinutes", _fixedMinutes);
        _quietSeconds = 0;
        _candidateUntil = 0;
        _motionSeconds = 0;
        _baselineHr = null;
        _lastHr = null;
        _sensorUnavailable = false;
        _vibrationUnavailable = false;
        _toneUnavailable = false;
        _sessionStart = now.value();
        _sessionActive = true;
        _triggerReason = "none";
        _triggerAt = 0;
        _lastSampleAt = 0;
        _sampledSeconds = 0;
        _quietSampledSeconds = 0;
        _sampleGaps = 0;
        _lastDeviceCheck = 0;
        _lastDeviceFlags = "";
        _lastMode = null;
        _modeTrueSeconds = 0;
        _modeValidSamples = 0;
        _modeMissingSamples = 0;
        _nextSnapshot = now.value() + 600;
        _state = 1;
        _page = 1;
        _timer.stop();
        _timer.start(method(:onTick), 5000, true);
        _log.add("armed", "deadline=" + _deadline + " fixed_min=" + _fixedMinutes +
            " repeat=" + _repeatDaily + " tone=" + _soundMode + " vibe=" + _vibeMode, true);
        try {
            var profile = UserProfile.getProfile();
            _log.add("planned_schedule", "bed_s=" +
                valueText(profile.sleepTime == null ? null : profile.sleepTime.value()) +
                " wake_s=" + valueText(profile.wakeTime == null ? null : profile.wakeTime.value()), false);
        } catch (ex) { _log.add("planned_schedule", "unavailable", false); }
        sampleDevice(now.value());
        snapshot(now.value());
    }

    function valueText(value) { return value == null ? "NA" : value.toString(); }

    function sampleDevice(now) {
        var mode = null;
        try {
            var info = ActivityMonitor.getInfo();
            if (info has :isSleepMode) { mode = info.isSleepMode; }
        } catch (ex) {}
        if (mode == null) { _modeMissingSamples += 1; }
        else { _modeValidSamples += 1; }
        if (_lastMode == true && _lastDeviceCheck > 0 && now - _lastDeviceCheck <= 120) {
            _modeTrueSeconds += now - _lastDeviceCheck;
        }
        _lastMode = mode;
        _lastDeviceCheck = now;
        var settings = System.getDeviceSettings();
        var flags = "dnd=" + settings.doNotDisturb + " tones=" + settings.tonesOn +
            " vibe=" + settings.vibrateOn + " legacy_sleep_mode=" + valueText(mode);
        if (!flags.equals(_lastDeviceFlags)) {
            _lastDeviceFlags = flags;
            _log.add("device_state", flags, true);
        }
    }

    function saveSummary(now, status) {
        var summary = { "start" => _sessionStart, "end" => now, "deadline" => _deadline,
            "trigger" => _triggerAt, "reason" => _triggerReason, "status" => status,
            "armedElapsedSeconds" => (_triggerAt > 0 ? _triggerAt : now) - _sessionStart,
            "sensorSampledSeconds" => _sampledSeconds, "quietSampledSeconds" => _quietSampledSeconds,
            "sampleGaps" => _sampleGaps, "legacySleepModeTrueSeconds" => _modeTrueSeconds,
            "modeValidSamples" => _modeValidSamples, "modeMissingSamples" => _modeMissingSamples,
            "nativeSleepDurationAvailable" => false, "nativeSleepDuration" => null };
        saveValue("currentSessionV1", summary);
        if (_triggerAt > 0) {
            _lastTriggered = summary;
            saveValue("lastTriggeredSessionV1", summary);
        }
        if (!status.equals("armed") && !status.equals("ringing")) {
            _summary = summary;
            saveValue("lastSessionV1", _summary);
        }
    }

    function snapshot(now) {
        saveSummary(now, _state == 2 ? "ringing" : "armed");
        _log.add("snapshot", "elapsed_s=" + (now - _sessionStart) +
            " sampled_s=" + _sampledSeconds + " quiet_s=" + _quietSampledSeconds +
            " hr=" + valueText(_lastHr) + " battery=" + System.getSystemStats().battery +
            " native_sleep_s=NA", true);
    }

    function finishSession(reason) {
        if (!_sessionActive) { return; }
        var now = Time.now().value();
        saveSummary(now, reason);
        _log.add("session_end", "status=" + reason + " trigger=" + _triggerReason +
            " elapsed_s=" + (now - _sessionStart) + " native_sleep_s=NA", true);
        _log.add("sampling", "sampled_s=" + _sampledSeconds + " quiet_s=" +
            _quietSampledSeconds + " gaps=" + _sampleGaps + " legacy_mode_true_s=" +
            _modeTrueSeconds + " mode_valid=" + _modeValidSamples +
            " mode_missing=" + _modeMissingSamples, true);
        _sessionActive = false;
    }

    function onTick() {
        var now = Time.now().value();
        checkAlarm(now);
        if (_state == 1) {
            if (!_sensorOn && !_sensorUnavailable && now >= _deadline - 35 * 60) {
                startSensor();
            }
        }
        if (_sessionActive) {
            if (now - _lastDeviceCheck >= 60) { sampleDevice(now); }
            if (now >= _nextSnapshot) {
                snapshot(now);
                _nextSnapshot = now + 600;
            }
        }
        WatchUi.requestUpdate();
    }

    function checkAlarm(now) {
        if (_state == 1 && now >= _deadline) {
            ring(now, "deadline");
        }
        if (_state == 2) {
            if (now >= _ringEnd) {
                var previousDeadline = _deadline;
                finishSession("timeout");
                if (_repeatDaily) { armAlarm(previousDeadline); } else { resetToHome(); }
            } else {
                alertNow(now);
            }
        }
    }

    function alertNow(now) {
        var elapsed = now - _ringStarted;
        var stage = AlarmPolicy.stage(elapsed);
        if ((_vibeMode == 3 || _soundMode == 3) && stage != _alertStage) {
            _alertStage = stage;
            _log.add("alert_stage", "stage=" + stage + " elapsed_s=" + elapsed, true);
        }
        if (_vibeMode != 0 && now >= _nextVibe) {
            _nextVibe = now + AlarmPolicy.interval(_vibeMode, elapsed);
            try {
                Attention.vibrate([new Attention.VibeProfile(100,
                    AlarmPolicy.vibeLength(_vibeMode, elapsed))]);
            } catch (ex) {
                if (!_vibrationUnavailable) { _log.add("vibe_error", ex.toString(), true); }
                _vibrationUnavailable = true;
            }
        }
        if (_soundMode != 0 && now >= _nextTone) {
            _nextTone = now + (_soundMode == 3 ? AlarmPolicy.interval(3, elapsed) : 5);
            try {
                if (_soundMode == 3) {
                    var notes = [new Attention.ToneProfile(2000, 100)];
                    if (stage >= 1) { notes.add(new Attention.ToneProfile(2500, 200)); }
                    if (stage >= 2) { notes.add(new Attention.ToneProfile(3000, 300)); }
                    Attention.playTone({ :toneProfile => notes });
                } else {
                    Attention.playTone(_soundMode == 2 ?
                        Attention.TONE_LOUD_BEEP : Attention.TONE_ALARM);
                }
            } catch (ex) {
                if (!_toneUnavailable) { _log.add("tone_error", ex.toString(), true); }
                _toneUnavailable = true;
            }
        }
    }

    function startSensor() {
        // The accelerometer is sampled only near the wake window to limit battery use.
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :accelerometer => { :enabled => true, :sampleRate => 5 }
            });
            _sensorOn = true;
            _log.add("sensor_start", "rate_hz=5 native_sleep_s=NA", true);
        } catch (ex) {
            // The fixed latest wake time still works if sampling is unavailable.
            _sensorOn = false;
            _sensorUnavailable = true;
            _log.add("sensor_error", ex.toString(), true);
        }
    }

    function stopSensor() {
        if (_sensorOn) {
            Sensor.unregisterSensorDataListener();
            _sensorOn = false;
        }
        _lastX = null;
        _lastY = null;
        _lastZ = null;
        _lastSampleAt = 0;
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        if (_state != 1) { return; }
        var now = Time.now().value();
        if (now >= _deadline) {
            ring(now, "deadline");
            return;
        }
        if (data.accelerometerData == null) { return; }
        var sampleSeconds = _lastSampleAt == 0 ? 1 : now - _lastSampleAt;
        _lastSampleAt = now;
        if (sampleSeconds <= 0) { return; }
        if (sampleSeconds > 3) {
            _sampleGaps += 1;
            _quietSeconds = 0;
            _candidateUntil = 0;
            sampleSeconds = 1;
        }
        _sampledSeconds += sampleSeconds;
        var accel = data.accelerometerData;
        var movement = 0;
        for (var i = 0; i < accel.x.size(); i++) {
            var x = accel.x[i];
            var y = accel.y[i];
            var z = accel.z[i];
            if (_lastX != null) {
                var delta = abs(x - _lastX) + abs(y - _lastY) + abs(z - _lastZ);
                if (delta > 220) { movement += 1; }
            }
            _lastX = x;
            _lastY = y;
            _lastZ = z;
        }

        var active = movement >= 2;
        // Optical heart rate is available through Connect IQ when the watch
        // provides a current reading. It is an extra wake cue, not a sleep stage.
        var currentHr = Sensor.getInfo().heartRate;
        if (currentHr != null && currentHr > 0) {
            _lastHr = currentHr;
            if (!active && _candidateUntil == 0) {
                if (_baselineHr == null) {
                    _baselineHr = currentHr;
                } else {
                    _baselineHr = (_baselineHr * 9 + currentHr) / 10;
                }
            }
        }
        if (!active) {
            _quietSeconds += sampleSeconds;
            _quietSampledSeconds += sampleSeconds;
        } else {
            // Require a quiet period followed by sustained movement, not one jolt.
            if (_quietSeconds >= 90 && now >= _deadline - 30 * 60) {
                _candidateUntil = now + 20;
                _motionSeconds = 0;
                _log.add("candidate", "quiet_s=" + _quietSeconds +
                    " hr=" + valueText(_lastHr), false);
            }
            _quietSeconds = 0;
        }
        if (_candidateUntil != 0) {
            if (now > _candidateUntil) {
                _candidateUntil = 0;
                _motionSeconds = 0;
            } else if (active) {
                _motionSeconds += sampleSeconds;
                var hrRising = _lastHr != null && _baselineHr != null &&
                    _lastHr >= _baselineHr + 8;
                if (_motionSeconds >= 3 || (_motionSeconds >= 2 && hrRising)) {
                    ring(now, _motionSeconds >= 3 ? "movement" : "movement_hr");
                }
            }
        }
    }

    function abs(value) {
        return value < 0 ? -value : value;
    }

    function ring(now, reason) {
        if (_state != 1) { return; }
        stopSensor();
        _state = 2;
        _triggerReason = reason;
        _triggerAt = now;
        _ringStarted = now;
        _nextVibe = 0;
        _nextTone = 0;
        _alertStage = -1;
        _ringEnd = now + 10 * 60;
        _timer.stop();
        _timer.start(method(:onTick), 1000, true);
        _log.add("trigger", "reason=" + reason + " early_s=" + (_deadline - now) +
            " hr=" + valueText(_lastHr) + " baseline_hr=" + valueText(_baselineHr) +
            " native_sleep_s=NA", true);
        saveSummary(now, "ringing");
        alertNow(now);
        WatchUi.requestUpdate();
    }

    function twoDigits(n) {
        return n < 10 ? "0" + n : n.toString();
    }

    function tr(en, zh) {
        return _langZh ? zh : en;
    }

    function clockText(minutes) {
        return twoDigits(minutes / 60) + ":" + twoDigits(minutes % 60);
    }

    function line(dc, y, font, caption) {
        if (_langZh && (font == Graphics.FONT_SMALL || font == Graphics.FONT_MEDIUM)) {
            font = _chineseFont;
        }
        dc.drawText(dc.getWidth() / 2, dc.getHeight() * y / 260,
            font, caption, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawHome(dc, dndOn) {
        line(dc, 35, Graphics.FONT_SMALL,
            dndOn ? tr("DND ON", "勿扰已开") : tr("8 AM CLASS", "我上早八"));
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        line(dc, 75, Graphics.FONT_LARGE,
            clockText(now.hour * 60 + now.min));
        var first = _menuIndex < 2 ? 0 : (_menuIndex > 3 ? 2 : _menuIndex - 1);
        for (var row = 0; row < 3; row++) {
            var index = first + row;
            line(dc, 130 + row * 35, Graphics.FONT_SMALL,
                (index == _menuIndex ? "> " : "  ") + menuLabel(index));
        }
    }

    function menuLabel(index) {
        if (index == 0) { return _fixedMinutes == null ? tr("Set first alarm", "先设置闹钟") :
            tr("Arm ", "启动 ") + clockText(_fixedMinutes); }
        if (index == 1) { return tr("Edit alarm", "修改闹钟"); }
        if (index == 2) { return tr("Run logs", "运行记录"); }
        if (index == 3) { return tr("Manual", "说明书"); }
        return tr("Settings", "设置");
    }

    function drawManual(dc) {
        line(dc, 35, Graphics.FONT_SMALL,
            tr("Manual", "说明书") + " " + (_manualPage + 1) + "/4");
        if (_manualPage == 0) {
            line(dc, 95, Graphics.FONT_SMALL, tr("Set deadline", "设置截止时间"));
            line(dc, 125, Graphics.FONT_SMALL, tr("Starts at now", "从当前时间开始"));
            line(dc, 155, Graphics.FONT_SMALL, tr("UP/DOWN: change", "上下键调时间"));
            line(dc, 185, Graphics.FONT_SMALL, tr("START: next/arm", "确认切换并启动"));
        } else if (_manualPage == 1) {
            line(dc, 95, Graphics.FONT_SMALL, tr("Wake time is saved", "闹钟时刻自动保存"));
            line(dc, 125, Graphics.FONT_SMALL, tr("Arm from home", "主页一键启动"));
            line(dc, 155, Graphics.FONT_SMALL, tr("Daily: rearm on stop", "每日重复在设置中改"));
            line(dc, 185, Graphics.FONT_SMALL, tr("Keep app open", "需要应用保持打开"));
        } else if (_manualPage == 2) {
            line(dc, 95, Graphics.FONT_SMALL, tr("30 min wake window", "提前30分钟监测"));
            line(dc, 125, Graphics.FONT_SMALL, tr("Motion + heart rate", "参考动作和心率"));
            line(dc, 155, Graphics.FONT_SMALL, tr("Deadline triggers", "截止时间触发"));
            line(dc, 185, Graphics.FONT_SMALL, tr("Sleep stages: N/A", "原生睡眠分期不可读"));
        } else {
            line(dc, 95, Graphics.FONT_SMALL, tr("Turn DND off", "睡前关闭勿扰"));
            line(dc, 125, Graphics.FONT_SMALL, tr("Tone/vibe in settings", "音振可在设置中改"));
            line(dc, 155, Graphics.FONT_SMALL, tr("Use native backup", "建议原生闹钟备份"));
            line(dc, 185, Graphics.FONT_SMALL, tr("Logs on home menu", "主页可查看运行记录"));
        }
        line(dc, 220, Graphics.FONT_SMALL, tr("BACK: menu", "返回主页"));
    }

    function drawSettings(dc) {
        line(dc, 35, Graphics.FONT_SMALL, tr("Settings", "设置"));
        var first = _settingsIndex < 2 ? 0 : (_settingsIndex > 3 ? 2 : _settingsIndex - 1);
        for (var row = 0; row < 3; row++) {
            var index = first + row;
            line(dc, 95 + row * 40, Graphics.FONT_SMALL,
                (index == _settingsIndex ? "> " : "  ") + settingsLabel(index));
        }
        line(dc, 215, Graphics.FONT_SMALL, _notice != "" ? _notice : tr("START: change", "确认键切换"));
    }

    function settingsLabel(index) {
        var sound = _soundMode == 0 ? tr("Off", "关闭") :
            (_soundMode == 1 ? tr("Alarm", "闹铃") :
            (_soundMode == 2 ? tr("Loud", "响亮") : tr("Ramp", "渐进")));
        var vibe = _vibeMode == 0 ? tr("Off", "关闭") :
            (_vibeMode == 1 ? tr("Gentle", "柔和") :
            (_vibeMode == 2 ? tr("Strong", "强烈") : tr("Ramp", "渐进")));
        if (index == 0) { return tr("Language: ", "语言: ") + (_langZh ? "中文" : "English"); }
        if (index == 1) { return tr("Tone: ", "声音: ") + sound; }
        if (index == 2) { return tr("Vibe: ", "振动: ") + vibe; }
        if (index == 3) { return tr("Daily: ", "每日重复: ") +
            (_repeatDaily ? tr("On", "开") : tr("Off", "关")); }
        return tr("Import wake time", "导入作息起床时刻");
    }

    function reasonLabel(reason) {
        if (reason.equals("deadline")) { return tr("Deadline", "截止时间"); }
        if (reason.equals("movement")) { return tr("Movement", "连续动作"); }
        if (reason.equals("movement_hr")) { return tr("Motion + HR", "动作及心率"); }
        return tr("Not triggered", "尚未触发");
    }

    function drawLogs(dc) {
        var entries = _log.getEntries();
        if (_logDetails && entries.size() > 0) {
            if (_logIndex < 0 || _logIndex >= entries.size()) { _logIndex = entries.size() - 1; }
            line(dc, 35, Graphics.FONT_SMALL, tr("Event ", "事件 ") + (_logIndex + 1) + "/" + entries.size());
            var text = entries[_logIndex];
            for (var row = 0; row < 6; row++) {
                var start = row * 30;
                if (start >= text.length()) { break; }
                var end = start + 30;
                if (end > text.length()) { end = text.length(); }
                line(dc, 75 + row * 25, Graphics.FONT_XTINY, text.substring(start, end));
            }
            return;
        }
        var summary = _lastTriggered != null ? _lastTriggered : _summary;
        line(dc, 35, Graphics.FONT_SMALL, _lastTriggered != null ?
            tr("Last trigger", "最近触发") : tr("Last run", "最近运行"));
        if (summary == null) {
            line(dc, 100, Graphics.FONT_SMALL, tr("No session yet", "尚无运行记录"));
        } else {
            line(dc, 85, Graphics.FONT_SMALL, reasonLabel(summary["reason"]));
            line(dc, 120, Graphics.FONT_SMALL, tr("Armed min: ", "监测分钟: ") +
                (summary["armedElapsedSeconds"] / 60));
            line(dc, 155, Graphics.FONT_SMALL, tr("Native sleep: N/A", "原生睡眠时长不可读"));
        }
        line(dc, 190, Graphics.FONT_SMALL, tr("START: events", "确认查看事件"));
        line(dc, 220, Graphics.FONT_SMALL, _log.isStorageOk() ?
            tr("Logs saved", "日志已保存") : tr("Storage error", "日志存储异常"));
    }

    function drawAlarm(dc, dndOn) {
        if (_state == 0) {
            line(dc, 35, Graphics.FONT_SMALL,
                dndOn ? tr("DND ON: muted", "勿扰已开") :
                tr("Set alarm", "设置闹钟"));
            line(dc, 85, Graphics.FONT_LARGE, clockText(_wakeMinutes));
            line(dc, 135, Graphics.FONT_SMALL,
                _editField == 0 ? tr("HOUR", "小时") : tr("MINUTE", "分钟"));
            line(dc, 165, Graphics.FONT_SMALL,
                tr("UP/DOWN: 1 / hold", "上下键调节/长按加速"));
            line(dc, 195, Graphics.FONT_SMALL,
                _editField == 0 ? tr("START: minute", "确认调分钟") :
                tr("START: arm", "确认启动"));
        } else if (_state == 1) {
            line(dc, 35, Graphics.FONT_SMALL,
                dndOn ? tr("DND ON: muted", "勿扰已开") :
                tr("Deadline", "截止闹钟"));
            line(dc, 85, Graphics.FONT_LARGE, clockText(_wakeMinutes));
            line(dc, 140, Graphics.FONT_SMALL,
                _sensorOn ? tr("Sensing", "监测中") :
                (_sensorUnavailable ? tr("Fixed time", "定时唤醒") :
                tr("Waiting", "等待中")));
            var minutesLeft = (_deadline - Time.now().value() + 59) / 60;
            if (minutesLeft < 0) { minutesLeft = 0; }
            line(dc, 170, Graphics.FONT_SMALL,
                tr("Left ", "剩余 ") + clockText(minutesLeft));
            line(dc, 205, Graphics.FONT_SMALL, tr("BACK: cancel", "返回键取消"));
        } else {
            line(dc, 35, Graphics.FONT_SMALL, tr("8 AM CLASS", "我上早八"));
            line(dc, 85, Graphics.FONT_LARGE, clockText(_wakeMinutes));
            line(dc, 145, Graphics.FONT_MEDIUM, tr("WAKE UP", "该起床了"));
            line(dc, 185, Graphics.FONT_SMALL, tr("START: stop", "确认键停止"));
            var settings = System.getDeviceSettings();
            var alertInfo = "D" + (settings.doNotDisturb ? "1" : "0") +
                " T" + (settings.tonesOn ? "1" : "0") +
                " V" + (settings.vibrateOn ? "1" : "0");
            if (_toneUnavailable) { alertInfo += " TE"; }
            if (_vibrationUnavailable) { alertInfo += " VE"; }
            line(dc, 225, Graphics.FONT_SMALL, alertInfo);
        }
    }

    function onUpdate(dc) {
        checkAlarm(Time.now().value());
        var dndOn = System.getDeviceSettings().doNotDisturb;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (_page == 0) { drawHome(dc, dndOn); }
        else if (_page == 1) { drawAlarm(dc, dndOn); }
        else if (_page == 2) { drawManual(dc); }
        else if (_page == 3) { drawSettings(dc); }
        else { drawLogs(dc); }
    }
}

class EightAmClassInput extends WatchUi.InputDelegate {
    var _view;
    var _repeatTimer;
    var _heldKey = null;
    var _repeatCount = 0;

    function initialize(view) {
        InputDelegate.initialize();
        _view = view;
        _repeatTimer = new Timer.Timer();
    }

    function cleanup() {
        stopRepeat();
    }

    function stopRepeat() {
        _repeatTimer.stop();
        _heldKey = null;
    }

    function onKeyPressed(event) {
        var key = event.getKey();
        if (key != WatchUi.KEY_UP && key != WatchUi.KEY_DOWN) {
            return false;
        }
        if (!_view.canNavigate()) { return true; }
        stopRepeat();
        _view.navigate(key == WatchUi.KEY_DOWN ? 1 : -1);
        if (_view.isEditing()) {
            _heldKey = key;
            _repeatCount = 0;
            _repeatTimer.start(method(:repeatStep), 600, false);
        }
        return true;
    }

    function repeatStep() {
        if (_heldKey == null || !_view.isEditing()) {
            stopRepeat();
            return;
        }
        _repeatCount += 1;
        _view.navigate(_heldKey == WatchUi.KEY_DOWN ? 1 : -1);
        _repeatTimer.start(method(:repeatStep), _repeatCount < 8 ? 220 : 100, false);
    }

    function onKeyReleased(event) {
        var key = event.getKey();
        if (key == WatchUi.KEY_UP || key == WatchUi.KEY_DOWN) {
            stopRepeat();
            return true;
        }
        return false;
    }

    function onKey(event) {
        var key = event.getKey();
        if (key == WatchUi.KEY_UP || key == WatchUi.KEY_DOWN) {
            return true;
        } else if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            stopRepeat();
            _view.confirm();
            return true;
        } else if (key == WatchUi.KEY_ESC || key == WatchUi.KEY_LAP) {
            stopRepeat();
            return _view.cancel();
        }
        return false;
    }
}
