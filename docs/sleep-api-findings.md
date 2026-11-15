# FR255 睡眠 API 核对记录

核对日期：2026-11-12。参考 Connect IQ 官方在线文档、已安装的 SDK 9.3.0，以及本机 FR255 设备定义（Connect IQ API 5.2.0）。

2026-11-13补充：真机诊断报告显示该设备固件29.05、Connect IQ 6.0.4，高于本机SDK设备定义的5.2.0。因此不能仅根据旧设备定义断言新版睡眠分数/计划作息API在该真机上不可用，相关能力需后续独立核查。该发现不提供实际实时睡眠分期或已睡时长接口。

## 可以读取与不能读取的数据

- 应用运行时原生睡眠记录仍然正常，说明原生记录与本次应用运行能够共存；这不等于 Connect IQ 向第三方应用公开了原生睡眠数据。
- 当前 FR255 的公开 Connect IQ API 没有原生实时睡眠分期、实际入睡时刻或实际睡眠时长读取接口。因此本应用无法直接依据 Garmin 判定的浅睡阶段唤醒，也不能记录原生实际睡眠时长。
- `ActivityMonitor.Info.isSleepMode` 是已弃用的旧睡眠模式标记，官方允许返回 `null`，并提示可能在 System 4 后移除。FR255 的本地 API 定义仍有此符号，但不能假定每台设备都返回有效值，更不能将它等同于“用户已经入睡”。本轮实现仅以 `has`/空值检查读取它作诊断记录，**不根据这个标记触发唤醒**。
- `UserProfile.Profile.sleepTime` 与 `wakeTime` 是用户配置的计划就寝、起床时刻，以相对当地午夜的 `Duration` 表示，不是实际睡眠时长。应用可以导入 `wakeTime` 作为固定闹钟，并将计划作息写入诊断记录。读取该资料需 `UserProfile` 权限。
- `upcomingSleepTime`、`upcomingWakeTime` 需要 API 6.0.0；睡眠分数 complication 需要 API 6.0.2。本机旧FR255设备定义不暴露这些新增字段；真机6.0.4的可用性尚未单独验证。即使设备支持睡眠分数，它也是汇总分数，不能代替实时睡眠分期。
- Background 的 Sleep/Wake 事件在用户配置的作息时刻触发，不表示实际检测到入睡或醒来。

## 日志中的时长含义

日志区分应用监测运行时长、旧睡眠模式标记为真的可观测累计时长，以及不可获得的原生睡眠时长。旧标记为空或不可用时按未知记录。**监测运行时长不称为睡眠时长**；旧模式标记累计时间也不称为实际睡眠时长。

当前加速度计只在截止前的监测窗口开启，不能据此反推整夜实际睡眠时长。记录触发原因、心率、活动量、计划作息与提醒设置，可以用于后续对照 Garmin Connect 的原生睡眠结果。

## 官方资料

- [ActivityMonitor.Info：isSleepMode 的弃用与空值说明](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityMonitor/Info.html)
- [UserProfile.Profile：计划作息字段与 API 版本](https://developer.garmin.com/connect-iq/api-docs/Toybox/UserProfile/Profile.html)
- [UserProfile：所需权限](https://developer.garmin.com/connect-iq/api-docs/Toybox/UserProfile.html)
- [Complications：睡眠分数需 API 6.0.2](https://developer.garmin.com/connect-iq/api-docs/Toybox/Complications.html)
- [Background：计划睡眠与起床事件](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)
- [Garmin Connect Personal API：同步后可供个人分析的睡眠接口](https://developer.garmin.com/gc-developer-program/personal/swagger-docs/)

Personal API 属于 Garmin Connect 云端访问，需要用户自己的密钥和同步数据，不是手表应用的实时睡眠接口，本轮未接入。
