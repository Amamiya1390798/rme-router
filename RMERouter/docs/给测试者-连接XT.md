# 给测试者：在接着 MADIface XT 的 Mac 上测试 RME Router

谢谢帮忙！这份说明让你在自己的 Mac 上编译 App、连上 XT，按清单测一遍，把结果发回来。
**原则：先只读。** 任何“确认发送”都先和仓库主人确认再点。

## 1. 准备

- macOS 14 或更新；
- Xcode，或命令行工具：终端运行 `xcode-select --install`；
- RME 的 MADIface XT 驱动（没装过的话去 RME 官网 Downloads 下载 MADIface XT 的 macOS 驱动安装，装完重启）；
- TotalMix FX 2.1 或更新，MADIface XT 已用 USB（或 PCIe）连上，TotalMix 里看得到设备；
- 跑 `swift test` 需要完整的 Xcode（只有命令行工具会报 `no such module 'XCTest'`）；第一次用 Xcode 可能要先接受许可：`sudo xcodebuild -license`；
- 仓库主人已在 GitHub 上把你加为协作者（私有仓库）。

## 2. 下载与编译

```bash
git clone <仓库地址>
cd <仓库目录>/RMERouter
swift build && swift test
scripts/make-app.sh release
open .build/RMERouter.app
```

`swift test` 应全部通过。第一次编译要几分钟。

## 3. TotalMix 设置（一次）

1. Options 菜单勾 **OSC Control**。
2. Settings → OSC：选一个空闲的 Controller，勾 **In Use**，然后：
   - Port (incoming) 填 `7011`、Port (outgoing) 填 `9011`；
   - Remote Host 填 `127.0.0.1`；
   - Compatibility 选 **Global OSC**；
   - 关闭 Follow Submix；
   - 勾 **Send Level Data**。
3. 开着 Wi-Fi 时 TotalMix 可能用 IPv6；App 连不上时，把 App“连接”页的 TotalMix 地址改成 `::1` 再试。

## 4. 测试清单（按顺序，全部只读）

注意：`rme-probe` 和 App 不能同时开，它们要用同一个端口。测 probe 前先退出 App。

| # | 做什么 | 预期 | 记下 |
| --- | --- | --- | --- |
| 1 | 终端运行 `swift run -c release rme-probe --port 7011 --listen 9011 > probe.txt` | 第二行写“连接：已连接” | 把 `probe.txt` 发回来 |
| 2 | 打开 App，点右上“读取设备”（↻） | 顶部状态写 XT 已连接；“设备”页 XT 通道条有名字 | 截图 |
| 3 | 对着 XT 前面板 Mic 1 说话 | 设备页 XT 通道条 Mic 1 有电平；Mic 1 接口旁出现绿点 | 截图 |
| 4 | 设备页右上“信号核对…”→ 选 MADIface XT 的 Mic 1 → 开始 → 说话 | 结果“一致”，进了 MADIface XT Mic 1 | 截图 |
| 5 | 如果接着 12Mic 或 XTC：“信号核对…”选它们的一支麦克风再测 | “一致”或“出现在别处”（都算有用的结果） | 截图结果那一页 |
| 6 | 在 TotalMix 里把一对立体声输入拆开，再合回去 | App 一秒内跟着变（不用按读取） | 有没有跟上 |
| 7 | 在 TotalMix 里改一个发送的推子 | App 里对应电平一秒内更新 | 有没有跟上 |
| 8 | 活动监视器里看 RME Router 的 CPU | 平时应在几个百分点以内 | 数字 |

## 4b. 第二轮复测（2026-10-26 修复后）

| # | 做什么 | 预期 |
| --- | --- | --- |
| A | 设备页 XT 通道条往右滚到 MADI 通道（名字是 1、2、5/6 …） | 每条都有“无信号”或电平，点上面的数字能改发送（不再是“—”或“?”） |
| B | 输出页 | 送到 MADI 输出的发送都出现在对应卡片上 |
| C | 再拆一次 AES 3/4 | App 出现两条：AES、AES 2（右声道），合回后变回一条 |
| D | 活动监视器看 RME Router 的 CPU，放着 1 分钟后记 3 次 | 比上次的 29–42% 明显低 |
| E | 有麦克风时：对着 XT Mic 1 说话 + 信号核对 | 电平动；核对结果“一致” |

## 5. 不要做的事

- 不要点“确认发送”，除非主人同意。改动都会先进底部“待应用”栏，不点确认就不会发出去。
- 不要打开 48V（App 会要求勾选确认；不确定接的是什么话筒时不要开）。
- 不要在 TotalMix 里调大输出音量去“试声音”。

## 6. 如果用 Claude Code 帮忙

在仓库目录里打开 Claude Code，它会先读 `RMERouter/CLAUDE.md`（项目规则）。可以这样说：

> 按 `RMERouter/docs/给测试者-连接XT.md` 做第 4 节的测试，全部只读；任何写入设备的操作先问我。

## 7. 发回什么

把以下发给仓库主人：
- `probe.txt`；
- 截图；
- 第 4 节每一项的“记下”；
- 任何报错的原文。
