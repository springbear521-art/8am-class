# 8 AM Class

适用于 Forerunner 255 的 Connect IQ 原型。睡前打开应用，用 UP/DOWN 每次调整最晚起床时间 5 分钟，按 START 启动。在最晚起床时间前 30 分钟内，应用尝试识别安静后出现的连续翻身活动，并通过振动唤醒；若未检测到符合条件的活动，到达最晚时间也会振动。START 停止响铃，BACK 取消。

本应用使用加速度计活动量，并在能取得读数时结合光学心率的上升趋势，作为**适合唤醒时机的近似信号**。它不能读取 Garmin 已判定的实时睡眠分期。应用须在夜间保持前台运行，这可能影响 Garmin 的睡眠分数和 Body Battery。SmartWake PRO 的商店说明也对 Forerunner 255 提示了这一问题。在验证可靠性期间，请另外设置一个相同时间的手表原生闹钟。

## 编译和安装

1. `dist/8am-class.prg` 是使用 Connect IQ SDK 9.3.0 为 Forerunner 255 编译的版本。将它复制到手表的 `GARMIN/APPS` 目录。详见 [Garmin 的侧载教程](https://developer.garmin.com/connect-iq/connect-iq-basics/your-first-app/)。
2. 如需自行构建，在 [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/) 中安装 SDK 和 Forerunner 255 设备定义，并准备 RSA 4096 位开发者签名密钥。密钥应存放在项目目录之外，不要提交到仓库。
3. 在 VS Code 中打开此目录，把 **Monkey C: Developer Key Path** 指向自己的密钥，选择 Forerunner 255 后执行 **Monkey C: Build for Device**。也可使用 `monkeyc -f monkey.jungle -d fr255 -y <密钥路径> -o build/8am-class.prg`。

编译已通过，模拟器中已验证启动、调整时间、启动监测与取消。尚未进行真机测试。正式依赖闹钟前，必须在手表上验证传感器采样、振动和夜间续航。
