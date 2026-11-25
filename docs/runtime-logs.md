# 0.2.2 运行日志与反馈

不创建外部文件时，应用也会把最近128条事件和会话摘要保存到 Application.Storage，首页「运行记录」可以查看。START切换摘要/事件，UP/DOWN切换事件，BACK返回。详情里的时间是 Unix epoch 秒，电脑解析器可转成北京时间。

0.2.2从最晚起床时间前20分钟才开始动作与心率采样，并只在这20分钟内允许提前唤醒；这不是原生睡眠分期监测。0.2.1已修复整夜累积日志后的启动watchdog。升级时只替换PRG，保留手表上的TXT/BAK及应用Storage，不要用空TXT覆盖已有运行日志。

## USB文本日志启用

1. 将 `dist/8am-class.prg` 复制到手表 `GARMIN/APPS`。
2. 将随包提供的空 `8am-class.TXT` 复制到 `GARMIN/APPS/LOGS`。
3. **TXT文件名必须与手表上实际运行的PRG文件名一致（只改扩展名）。** 若商店安装或设备处理后的PRG叫 `A1B2C3D4.PRG`，日志应为 `A1B2C3D4.TXT`。新建文件时确认没有变成 `.TXT.txt`。
4. 拔掉USB后运行应用，进行一次几分钟后的试响。重新连接，复制同名TXT与BAK到电脑的 `device-logs` 文件夹，保留原始文件。

Garmin普通应用不能自动创建此文本日志文件。`System.println`只在已有同名TXT时写入。SDK文档说明TXT约5KB时轮转为BAK并覆盖旧BAK，因此不要逐秒打印全部传感器数据。应用已把心跳限制为每10分钟一次。

## 电脑解析

在项目目录运行：

```powershell
.\tools\read-run-log.ps1 -InputPath '.\device-logs\8am-class.BAK','.\device-logs\8am-class.TXT'
```

只有TXT时只传TXT路径。默认输出旁边的 `8am-class-events.csv`，含Epoch、北京时间、Event、Details，去除精确重复并保留同秒事件的先后顺序，不修改输入。

关键事件：`armed`（截止时间、固定时刻、每日重复和音振选择）、`planned_schedule`（计划睡/醒时刻，相对本地午夜秒数）、`device_state`（勿扰、系统音振开关、旧睡眠模式标记）、`sensor_start/error`、`candidate`、`trigger`、`alert_stage`、`tone_error/vibe_error`、`session_end`、`sampling`。

`trigger.reason=deadline`表示截止触发；`movement`表示安静后连续动作；`movement_hr`表示动作结合心率上升。API请求未抛错并不证明佩戴者实际听到或感觉到提醒，反馈时请同时记录是否听到/感觉到、佩戴情况和电量变化。

## 睡眠字段的含义

- `native_sleep_s=NA` / `nativeSleepDuration=null`：FR255公开接口无法读取实际睡眠时长，不填造假的数值。
- `elapsed_s` / `armedElapsedSeconds`：应用运行监测时间。
- `sampled_s` / `sensorSampledSeconds`：有传感器样本覆盖的时间；从最晚起床时间前20分钟开始，不代表实际睡眠时长。
- `quiet_s` / `quietSampledSeconds`：采样期间的安静时间，不等于睡眠。
- `legacy_mode_true_s`：旧模式标记为真、且相邻采样间隔有效的累计时间；`mode_valid/mode_missing`记录可读/不可读样本数。睡眠模式不等于实际入睡。

日志包括心率等个人数据；应用不自动上传。将真实日志放在被Git忽略的 `device-logs/`，不要加入公开仓库。后续可把日志与同一天的Garmin原生睡眠记录人工对照。

官方参考：[Storage](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)、[Developer FAQ](https://forums.garmin.com/developer/connect-iq/w/wiki/4/new-developer-faq)、本机SDK `doc/docs/Core_Topics/Debugging.html`。
