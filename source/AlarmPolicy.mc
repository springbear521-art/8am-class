module AlarmPolicy {
    function nextDeadline(wakeMinutes, nowEpoch, currentMinutes, seconds) {
        var remaining = wakeMinutes - currentMinutes;
        if (remaining <= 0) { remaining += 1440; }
        return nowEpoch + remaining * 60 - seconds;
    }

    function stage(elapsed) {
        return elapsed < 30 ? 0 : (elapsed < 60 ? 1 : 2);
    }

    function repeatDeadline(candidate, previousDeadline) {
        return candidate <= previousDeadline ? candidate + 86400 : candidate;
    }

    function interval(mode, elapsed) {
        if (mode == 3) { return [10, 5, 2][stage(elapsed)]; }
        return mode == 2 ? 3 : 5;
    }

    function vibeLength(mode, elapsed) {
        if (mode == 3) { return [300, 1000, 2000][stage(elapsed)]; }
        return mode == 2 ? 2000 : 500;
    }
}
