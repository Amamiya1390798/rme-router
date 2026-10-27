# RME Router

在 TotalMix FX 之上，用“谁的声音送到哪里”的方式管理 RME MADIface XT、12Mic、OctaMic XTC 之间路由的 macOS 应用。TotalMix 仍在后台负责实际的混音和路由，本 App 是更清楚的操作界面。

## 能做什么

- **设备页**：前 / 后面板图、实际接线，TotalMix 式通道条（输入、回放、输出，外加 P16 的 16 路），点一路看它送到哪里。
- **输出 / 前级**：每个输出现在送出什么；三台设备的话放增益、48V、相位。
- **跨设备送一路声音**：自动算出要经过哪些设备、哪些路由，自动步骤和要人工做的步骤分开列。
- **体检**：时钟主从、采样率、MADI 格式、Lock / Sync、P16 限制等，问题会写清楚原因。
- **场景**：存下整套设置，之后对比或恢复。
- **设备组成可选**：主卡可选 MADIface XT、Fireface UFX III 或任意 TotalMix 设备；12Mic、XTC、P16 可以分别关掉。
- **主题**：多套配色，另有两套藏起来的二次元主题。

## 安全

- 读取不会改动任何设置。
- 所有写入先进“待应用”栏，确认后才发送，发完再读回核对，可以撤销。
- 48V、音量一次抬高 20 dB 以上，总是要再确认一次。

## 要求

- macOS 14 或更新，Apple 芯片。
- TotalMix FX 在后台运行，OSC 设为：In Use、Port incoming 7011、outgoing 9011、Remote Host 127.0.0.1、兼容模式 Global OSC。
- 12Mic 要另接 USB 或网线（HTTP Remote）；XTC 走 MIDI（USB 或 MADI）。

## 安装与构建

下载 Releases 里的 `RME-Router.dmg`，把 App 拖进“应用程序”。第一次打开如果提示无法验证开发者，右键 → 打开。

从源码构建（需要 Xcode 命令行工具）：

```bash
cd RMERouter
swift test
scripts/make-app.sh release --install
```

更多说明见 [使用手册](RMERouter/docs/使用手册.md)，设计与协议出处见 [需求与设计](RMERouter/docs/v3-需求与设计.md)。

## 素材与许可

- 代码：作者 A.M（cly20041110@gmail.com）。
- 设备面板图来自 RME 官方产品图，见 `RMERouter/Resources/Panels/sources.json`。
- 二次元模式“深海女仆工坊”美术：CC BY-NC-SA 4.0（上善 → ZipZipPipe → Small-tailqwq），仅限非商用。
- 其他素材来源记在各自目录的 `sources.json` 里。RME、TotalMix、DeepSeek、Claude 等名称与标志归各自所有者，本项目与它们无关。
