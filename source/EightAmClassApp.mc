import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
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
    // Pages: 0 = home, 1 = alarm, 2 = manual, 3 = settings.
    var _page = 0;
    var _menuIndex = 0;
    var _manualPage = 0;
    var _settingsIndex = 0;
    var _langZh = true;
    // 0 = off, 1 = alarm tone, 2 = loud beep.
    var _soundMode = 1;
    // 0 = off, 1 = gentle, 2 = strong. Forerunner vibration intensity is fixed;
    // modes vary the duration and repetition interval instead.
    var _vibeMode = 2;
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
    var _nextAlert = 0;
    var _ringEnd = 0;
    var _vibrationUnavailable = false;
    var _toneUnavailable = false;

    function initialize() {
        View.initialize();
        _timer = new Timer.Timer();
        _chineseFont = WatchUi.loadResource(Rez.Fonts.Chinese);
        var savedLang = Application.Storage.getValue("langZh");
        var savedSound = Application.Storage.getValue("soundMode");
        var savedVibe = Application.Storage.getValue("vibeMode");
        if (savedLang != null) { _langZh = savedLang; }
        if (savedSound != null && savedSound >= 0 && savedSound <= 2) {
            _soundMode = savedSound;
        }
        if (savedVibe != null && savedVibe >= 0 && savedVibe <= 2) {
            _vibeMode = savedVibe;
        }
    }

    function onShow() {
        _timer.stop();
        _timer.start(method(:onTick), 5000, true);
        onTick();
    }

    function cleanup() {
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
        if (_page == 0) {
            _menuIndex = (_menuIndex + delta + 3) % 3;
        } else if (_page == 2) {
            _manualPage = (_manualPage + delta + 3) % 3;
        } else if (_page == 3) {
            _settingsIndex = (_settingsIndex + delta + 3) % 3;
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
                enterAlarm();
            } else if (_menuIndex == 1) {
                _manualPage = 0;
                _page = 2;
            } else {
                _page = 3;
            }
        } else if (_page == 2) {
            _manualPage = (_manualPage + 1) % 3;
        } else if (_page == 3) {
            if (_settingsIndex == 0) {
                _langZh = !_langZh;
                Application.Storage.setValue("langZh", _langZh);
            } else if (_settingsIndex == 1) {
                _soundMode = (_soundMode + 1) % 3;
                if (_soundMode == 0 && _vibeMode == 0) { _vibeMode = 1; }
                Application.Storage.setValue("soundMode", _soundMode);
                Application.Storage.setValue("vibeMode", _vibeMode);
            } else {
                _vibeMode = (_vibeMode + 1) % 3;
                if (_vibeMode == 0 && _soundMode == 0) { _soundMode = 1; }
                Application.Storage.setValue("vibeMode", _vibeMode);
                Application.Storage.setValue("soundMode", _soundMode);
            }
        } else if (_state == 0) {
            if (_editField == 0) {
                _editField = 1;
                WatchUi.requestUpdate();
                return;
            }
            var now = Time.now();
            var clock = Gregorian.info(now, Time.FORMAT_SHORT);
            var currentMinutes = clock.hour * 60 + clock.min;
            var remaining = _wakeMinutes - currentMinutes;
            if (remaining <= 0) { remaining += 1440; }
            _deadline = now.value() + remaining * 60 - clock.sec;
            _quietSeconds = 0;
            _candidateUntil = 0;
            _motionSeconds = 0;
            _baselineHr = null;
            _lastHr = null;
            _sensorUnavailable = false;
            _vibrationUnavailable = false;
            _toneUnavailable = false;
            _state = 1;
        } else if (_state == 2) {
            _state = 0;
            _editField = 0;
            _page = 0;
            stopSensor();
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
        _state = 0;
        _editField = 0;
        _page = 0;
        stopSensor();
        WatchUi.requestUpdate();
        return true;
    }

    function onTick() {
        var now = Time.now().value();
        checkAlarm(now);
        if (_state == 1) {
            if (!_sensorOn && !_sensorUnavailable && now >= _deadline - 35 * 60) {
                startSensor();
            }
        }
        WatchUi.requestUpdate();
    }

    function checkAlarm(now) {
        if (_state == 1 && now >= _deadline) {
            ring(now);
        }
        if (_state == 2) {
            if (now >= _ringEnd) {
                _state = 0;
                _page = 0;
            } else if (now >= _nextAlert) {
                alertNow(now);
            }
        }
    }

    function alertNow(now) {
        _nextAlert = now + (_vibeMode == 2 ? 3 : 5);
        if (_vibeMode != 0) {
            try {
                Attention.vibrate([new Attention.VibeProfile(100,
                    _vibeMode == 2 ? 2000 : 500)]);
            } catch (ex) {
                _vibrationUnavailable = true;
            }
        }
        if (_soundMode != 0) {
            try {
                Attention.playTone(_soundMode == 2 ?
                    Attention.TONE_LOUD_BEEP : Attention.TONE_ALARM);
            } catch (ex) {
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
        } catch (ex) {
            // The fixed latest wake time still works if sampling is unavailable.
            _sensorOn = false;
            _sensorUnavailable = true;
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
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        if (_state != 1) { return; }
        var now = Time.now().value();
        if (now >= _deadline) {
            ring(now);
            return;
        }
        if (data.accelerometerData == null) { return; }
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
            _quietSeconds += 1;
        } else {
            // Require a quiet period followed by sustained movement, not one jolt.
            if (_quietSeconds >= 90 && now >= _deadline - 30 * 60) {
                _candidateUntil = now + 20;
                _motionSeconds = 0;
            }
            _quietSeconds = 0;
        }
        if (_candidateUntil != 0) {
            if (now > _candidateUntil) {
                _candidateUntil = 0;
                _motionSeconds = 0;
            } else if (active) {
                _motionSeconds += 1;
                var hrRising = _lastHr != null && _baselineHr != null &&
                    _lastHr >= _baselineHr + 8;
                if (_motionSeconds >= 3 || (_motionSeconds >= 2 && hrRising)) {
                    ring(now);
                }
            }
        }
    }

    function abs(value) {
        return value < 0 ? -value : value;
    }

    function ring(now) {
        if (_state != 1) { return; }
        stopSensor();
        _state = 2;
        _ringEnd = now + 10 * 60;
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
        if (_langZh && font != Graphics.FONT_LARGE) {
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
        line(dc, 130, Graphics.FONT_SMALL,
            (_menuIndex == 0 ? "> " : "  ") + tr("Set alarm", "设置闹钟"));
        line(dc, 165, Graphics.FONT_SMALL,
            (_menuIndex == 1 ? "> " : "  ") + tr("Manual", "说明书"));
        line(dc, 200, Graphics.FONT_SMALL,
            (_menuIndex == 2 ? "> " : "  ") + tr("Settings", "设置"));
    }

    function drawManual(dc) {
        line(dc, 35, Graphics.FONT_SMALL,
            tr("Manual", "说明书") + " " + (_manualPage + 1) + "/3");
        if (_manualPage == 0) {
            line(dc, 95, Graphics.FONT_SMALL, tr("Set deadline", "设置截止时间"));
            line(dc, 125, Graphics.FONT_SMALL, tr("Starts at now", "从当前时间开始"));
            line(dc, 155, Graphics.FONT_SMALL, tr("UP/DOWN: change", "上下键调时间"));
            line(dc, 185, Graphics.FONT_SMALL, tr("START: next/arm", "确认切换并启动"));
        } else if (_manualPage == 1) {
            line(dc, 95, Graphics.FONT_SMALL, tr("30 min wake window", "提前30分钟监测"));
            line(dc, 125, Graphics.FONT_SMALL, tr("Motion + heart rate", "参考动作和心率"));
            line(dc, 155, Graphics.FONT_SMALL, tr("Deadline triggers", "截止时间触发"));
            line(dc, 185, Graphics.FONT_SMALL, tr("Keep app open", "应用保持打开"));
        } else {
            line(dc, 95, Graphics.FONT_SMALL, tr("Turn DND off", "睡前关闭勿扰"));
            line(dc, 125, Graphics.FONT_SMALL, tr("Tone/vibe in settings", "音振可在设置中改"));
            line(dc, 155, Graphics.FONT_SMALL, tr("Use native backup", "建议原生闹钟备份"));
            line(dc, 185, Graphics.FONT_SMALL, tr("UP/DOWN: pages", "上下键翻页"));
        }
        line(dc, 220, Graphics.FONT_SMALL, tr("BACK: menu", "返回主页"));
    }

    function drawSettings(dc) {
        line(dc, 35, Graphics.FONT_SMALL, tr("Settings", "设置"));
        var sound = _soundMode == 0 ? tr("Off", "关闭") :
            (_soundMode == 1 ? tr("Alarm", "闹铃") : tr("Loud", "响亮"));
        var vibe = _vibeMode == 0 ? tr("Off", "关闭") :
            (_vibeMode == 1 ? tr("Gentle", "柔和") : tr("Strong", "强烈"));
        line(dc, 95, Graphics.FONT_SMALL,
            (_settingsIndex == 0 ? "> " : "  ") +
            tr("Language: ", "语言: ") + (_langZh ? "中文" : "English"));
        line(dc, 135, Graphics.FONT_SMALL,
            (_settingsIndex == 1 ? "> " : "  ") + tr("Tone: ", "声音: ") + sound);
        line(dc, 175, Graphics.FONT_SMALL,
            (_settingsIndex == 2 ? "> " : "  ") + tr("Vibe: ", "振动: ") + vibe);
        line(dc, 215, Graphics.FONT_SMALL, tr("START: change", "确认键切换"));
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
        else { drawSettings(dc); }
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
