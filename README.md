# 我上早八 / 8 AM Class

当前测试版本：**0.1.6**，适用于 Forerunner 255。手表应用内可切换中文和英文。首页用 UP/DOWN 在「设置闹钟」「说明书」「设置」间移动，按 START 进入，按 BACK 返回。

## 设置闹钟

进入「设置闹钟」时，时间从**手表当前时刻**开始显示，不再固定为 07:00。先调小时，再按 START 调分钟；UP/DOWN 单击增减 1，长按连续调整并加速。分钟调好后按 START 启动监测。若设定时刻已经过去，闹钟安排在第二天的同一时刻。

监测页同时显示**设置好的截止闹钟时刻**和**剩余倒计时**。在截止时间前 30 分钟，应用尝试结合加速度计活动量与可用的光学心率读数，寻找合适的提前唤醒时机；否则在截止时间触发提醒。按 BACK 取消监测，响铃时按 START 停止。

首页的「说明书」有三页：时间设置、唤醒逻辑、睡前注意事项。UP/DOWN 翻页，BACK 返回。首页「设置」可切换语言、声音和振动：

- 语言：中文 / English。
- 声音：关闭 / 闹铃提示音 / 响亮提示音。Connect IQ 提供的是预置提示音，这里切换音色，不能直接设定手表扬声器音量。
- 振动：关闭 / 柔和 / 强烈。Forerunner 的振动强度不可由此应用调节；「柔和」「强烈」改变的是振动时长与重复间隔。程序不允许声音和振动同时关闭。

这些设置保存在手表应用中。**睡前请关闭勿扰模式**，并检查睡眠模式不会自动重新打开勿扰。真机对照测试确认：之前的无声、无振动是勿扰模式开启所致。应用显示「勿扰已开」时，Connect IQ 的声音和振动提示可能被静音。

本应用不能读取 Garmin 已判定的实时睡眠分期。应用须在夜间保持前台运行，这可能影响 Garmin 的睡眠分数和 Body Battery。SmartWake PRO 的商店说明也对 Forerunner 255 提示了这一问题。在验证可靠性期间，请另设一个相同时间的手表原生闹钟。

## 编译和安装

1. `dist/8am-class.prg` 是使用 Connect IQ SDK 9.3.0 为 Forerunner 255 编译的版本。将它复制到手表的 `GARMIN/APPS` 目录。详见 [Garmin 的侧载教程](https://developer.garmin.com/connect-iq/connect-iq-basics/your-first-app/)。Connect IQ 开发者后台上传时使用 `dist/8am-class.iq`。
2. 如需自行构建，在 [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/) 中安装 SDK 和 Forerunner 255 设备定义，并准备 RSA 4096 位开发者签名密钥。密钥应存放在项目目录之外，不要提交到仓库。
3. 在 VS Code 中打开此目录，把 **Monkey C: Developer Key Path** 指向自己的密钥，选择 Forerunner 255 后执行 **Monkey C: Build for Device**。也可使用 `monkeyc -f monkey.jungle -d fr255 -y <密钥路径> -o build/8am-class.prg`。

中文界面采用应用自带的精简点阵字体，因为英文系统语言下的 FR255 模拟器无法用内置字体显示汉字。字形由 Noto Sans SC 生成；相关版权和 SIL OFL 1.1 许可见 `fonts/OFL.txt`。若修改中文文案，在 Windows 上运行 `tools/generate-chinese-font.ps1` 更新字形图集，再重新编译。

0.1.6 已在 FR255 模拟器中检查中文首页、时间编辑、倒计时、说明书和设置页，未发现文字遮挡；分钟单击、语言和声音/振动选项切换也已验证。长按加速和声音、振动的实际输出仍需在真机上验证。正式依赖闹钟前，仍建议进行一次短时间真机试响。
