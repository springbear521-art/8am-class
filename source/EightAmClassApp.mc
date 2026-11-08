import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

class EightAmClassApp extends Application.AppBase {
    var _view;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        _view = new EightAmClassView();
        return [_view, new EightAmClassInput(_view)];
    }

    function onStop(state) {
        if (_view != null) {
            _view.cleanup();
        }
    }
}

class EightAmClassView extends WatchUi.View {
    // States: 0 = edit, 1 = armed, 2 = ringing.
    var _state = 0;
    var _wakeMinutes = 420; // 07:00, local time.
    var _deadline = 0;
    var _timer;
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
    var _nextVibration = 0;
    var _ringEnd = 0;

    function initialize() {
        View.initialize();
        _timer = new Timer.Timer();
    }

    function onShow() {
        _timer.stop();
        _timer.start(method(:onTick), 5000, true);
    }

    function cleanup() {
        _timer.stop();
        stopSensor();
    }

    function adjust(minutes) {
        if (_state != 0) { return; }
        _wakeMinutes = (_wakeMinutes + minutes + 1440) % 1440;
        WatchUi.requestUpdate();
    }

    function confirm() {
        if (_state == 0) {
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
            _state = 1;
        } else if (_state == 2) {
            _state = 0;
            stopSensor();
        }
        WatchUi.requestUpdate();
    }

    function cancel() {
        if (_state != 0) {
            _state = 0;
            stopSensor();
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function onTick() {
        var now = Time.now().value();
        if (_state == 1) {
            if (now >= _deadline) {
                ring(now);
            } else if (!_sensorOn && !_sensorUnavailable && now >= _deadline - 35 * 60) {
                startSensor();
            }
        }
        if (_state == 2) {
            if (now >= _ringEnd) {
                _state = 0;
            } else if (now >= _nextVibration) {
                Attention.vibrate([new Attention.VibeProfile(80, 800), new Attention.VibeProfile(0, 300), new Attention.VibeProfile(100, 800)]);
                _nextVibration = now + 5;
            }
        }
        WatchUi.requestUpdate();
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
        if (_state != 1 || data.accelerometerData == null) { return; }
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

        var now = Time.now().value();
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
        _nextVibration = now;
        _ringEnd = now + 10 * 60;
        WatchUi.requestUpdate();
    }

    function twoDigits(n) {
        return n < 10 ? "0" + n : n.toString();
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var center = width / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(center, height * 35 / 260, Graphics.FONT_SMALL, "8 AM CLASS", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(center, height * 85 / 260, Graphics.FONT_LARGE,
            twoDigits(_wakeMinutes / 60) + ":" + twoDigits(_wakeMinutes % 60),
            Graphics.TEXT_JUSTIFY_CENTER);
        if (_state == 0) {
            dc.drawText(center, height * 145 / 260, Graphics.FONT_SMALL, "UP/DOWN: 5 min", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(center, height * 175 / 260, Graphics.FONT_SMALL, "START: arm", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (_state == 1) {
            dc.drawText(center, height * 140 / 260, Graphics.FONT_SMALL, "Wake window: 30 min", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(center, height * 170 / 260, Graphics.FONT_SMALL, "BACK: cancel", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(center, height * 200 / 260, Graphics.FONT_SMALL,
                _sensorOn ? "Sensing" :
                    (_sensorUnavailable ? "Fixed alarm" : "Waiting"),
                Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(center, height * 145 / 260, Graphics.FONT_MEDIUM, "WAKE UP", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(center, height * 185 / 260, Graphics.FONT_SMALL, "START: stop", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

class EightAmClassInput extends WatchUi.InputDelegate {
    var _view;

    function initialize(view) {
        InputDelegate.initialize();
        _view = view;
    }

    function onKey(event) {
        var key = event.getKey();
        if (key == WatchUi.KEY_UP) {
            _view.adjust(5);
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            _view.adjust(-5);
            return true;
        } else if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            _view.confirm();
            return true;
        } else if (key == WatchUi.KEY_ESC || key == WatchUi.KEY_LAP) {
            return _view.cancel();
        }
        return false;
    }
}
