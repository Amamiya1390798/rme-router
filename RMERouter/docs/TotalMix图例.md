# TotalMix FX 中文图例（对照 RME Router）

看 TotalMix 时对照用：每个按钮、旋钮、菜单是什么意思，在本 App 里能不能做、在哪做。

出处：TotalMix FX 自带帮助（`/Applications/Totalmix.app/Contents/Resources/TotalMix FX Help`，A）、官方 Global OSC 协议表（2026-07-21 版，A）、本机 TotalMix 只读读回（2026-10-26）。没有出处的标“推断”。

**图例里的“本 App”一列**：
- ✅ 已做：在本 App 里能看能改（写入都走待应用 / 确认流程）
- 🔜 计划：协议里有，第 8.2 节 E10 / E8 会做
- ⛔ 做不了：Global OSC 协议里没有，只能在 TotalMix 里操作

---

## 1. 三行通道条

TotalMix 主窗口从上到下三行：**硬件输入**（Hardware Inputs，接口进来的声音 = 电脑录音）、**软件回放**（Software Playback，DAW 送来的声音）、**硬件输出**（Hardware Outputs，每个输出是一个子混音）。本 App 设备页的三行通道条一一对应。

### 1.1 输入、回放通道条（上两行）

| TotalMix 上 | 意思 | 本 App |
| --- | --- | --- |
| 顶部名字（Mic 1、M1-9…） | 通道名，双击可改名 | ✅ 显示同名（只读） |
| MONO / 立体声标记 | 这一条是单声道还是立体声一对 | ✅ “单声道 / 立体声”按钮可合并、拆分 |
| 话筒小图标和数字（如 33） | 话放增益（只有带话放的通道） | ✅ 前级页“增益” |
| 左右旋钮（L100、C、R…） | 声像：这一路送到当前输出时偏左还是偏右 | ✅ 点电平数字弹窗里的“声像” |
| **M** | 静音 | ✅ 通道条 M |
| **S** | 独奏（Solo；Live 模式下变成 PFL 预听） | ⛔ 本机读不到这一项，协议写法不清，暂不做 |
| **UFL** / 数字 | 电平数字显示。UFL = 低于显示下限（没信号，推断），OVR = 过载 | ✅ 通道条电平条、“无信号” |
| 大推子 | 这一路送到**当前选中的输出**的电平（不是总音量） | ✅ 通道条上的电平数字（点了改） |
| 推子下面的数字（0.0、-oo） | 推子当前值，-oo = 关 | ✅ 同上 |
| **T** | Trim：推子一次改这一路送到所有输出的电平（相当于传统调音台通道推子） | ⛔ 协议里没有 |
| **⚙**（设置） | 打开这条的设置面板（见 1.3） | — 只是开面板的按钮 |
| **EQ** | 均衡器 | 🔜 E8（参数很多，放最后） |
| **D** | 动态（压缩 / 扩展 / 自动电平） | 🔜 E8 之后 |
| 最底下“M1-1 ⌄” | 推子当前送去的输出（下方标签） | ✅ 设备页点一个输出条 = 选当前输出 |

### 1.2 输出通道条（第三行）

| TotalMix 上 | 意思 | 本 App |
| --- | --- | --- |
| 顶部 C 旋钮 | 输出左右平衡 | ✅ 检查器“平衡” |
| **M** | 静音 | ✅ |
| **CUE** | 把这个输出临时送到主输出（或耳机）上监听 | ⛔ 本机读不到每条的 Cue 状态，暂不做 |
| 大推子 | 这个输出的总音量 | ✅ 输出卡 / 检查器“音量” |
| EQ、D、⚙ | 同上 | 🔜 / — |

### 1.3 设置面板（点 ⚙ 打开）

输入、回放：

| TotalMix 上 | 意思 | 本 App |
| --- | --- | --- |
| stereo | 合并 / 拆分立体声 | ✅ |
| +48V | 幻象电源（只有话放通道） | ✅ 前级页，打开一律确认 |
| auto set | 自动降增益防过载，保持约 6 dB 余量 | 🔜 E10 |
| gain | 话放增益 | ✅ 前级页 |
| send FX | 送到效果总线（混响、回声）的量，跟着这一路最高的那个子混音走 | 🔜 E10 |
| width | 立体声宽度：1.00 全立体声，0.00 单声道，-1.00 左右互换 | 🔜 E10 |
| MS proc. | M/S 处理：单声道信息送左、立体声信息送右 | 🔜 E10 |
| phase / ØL ØR | 相位反转（立体声可左右分开） | ✅ 通道条 Ø |
| Level（部分设备） | 模拟输入参考电平 | ⛔ XT 没有（本机读不到） |

输出：

| TotalMix 上 | 意思 | 本 App |
| --- | --- | --- |
| stereo、phase | 同上 | ✅ |
| return FX | 效果（混响、回声）混进这个输出的量 | 🔜 E10 |
| talkback | 这个输出接收对讲信号 | 🔜 E10（总的对讲开关已做，见 2） |
| no trim | 这个输出不受 T（Trim）影响 | ⛔ 协议里没有 |
| loopback | 把这个输出的混音送进电脑同号录音通道（顶替那一路硬件输入） | ✅ 输出条“录”，打开一律确认 |

---

## 2. 控制室（Control Room）与右侧控制条

| TotalMix 上 | 意思 | 本 App |
| --- | --- | --- |
| Assign → Main Out | 主输出接哪一对 | ✅ 控制室“主输出”，改了一律确认 |
| Assign → Phones 1/2 | 耳机用哪一对 | ✅ 控制室“耳机 1 / 2” |
| Dim | 主输出临时降音量 | ✅ |
| Mono | 主输出合成单声道 | ✅ “Main 单声道” |
| Talkback | 对讲（需先指定对讲话筒） | ✅ 指定了才显示 |
| Recall | 主输出回到预设音量 | ⛔ 暂未做 |
| External In | 外部立体声输入替换主输出 | ✅ 控制室“外部输入”（TotalMix 里指定了外部输入通道才显示） |
| Mute FX | 主输出静音效果返回 | ✅ 控制室“静音效果” |
| 快照 1–8 | 整套混音的快照 | ✅ 调用（一律确认）；保存 ⛔（协议没说存到哪一格） |
| 全局静音 / 独奏 | 所有静音 / 独奏的总开关 | ✅ 全局静音；全局独奏 ⛔ |
| Undo / Redo | TotalMix 自己的撤销 | ⛔ 不做（会和本 App 的撤销混淆，本 App 有自己的撤销） |
| DSP 负载、设备名 | 状态 | 部分显示 |

---

## 3. 顶部菜单

按本机 TotalMix 实际菜单逐项列出（2026-10-26 只读列出，未点击）。**这些基本都不经 Global OSC，本 App 做不了，在 TotalMix 里点。**

### TotalMix FX（程序菜单）
| 条目 | 意思 |
| --- | --- |
| About TotalMix FX | 版本信息 |
| Settings… | 偏好设置（界面、存储位置等） |
| Services / Hide / Hide Others / Show All | 系统菜单 |
| Quit TotalMix FX / Quit and Keep Windows | 退出（**本 App 需要 TotalMix 在后台运行，别退出**；不想看见它用 Hide） |

### File（文件）
| 条目 | 意思 | 本 App |
| --- | --- | --- |
| New TotalMix Window | 再开一个 TotalMix 窗口 | ⛔ |
| Load Snapshot… / Save Snapshot As… | 从文件读 / 把快照存成文件 | ⛔（调用快照 1–8 ✅） |
| Preload all Snapshots… | 一次读入全部 8 个快照 | ⛔ |
| Load Workspace… / Save Workspace As… | 读取 / 另存“工作区”（整套混音 + 界面，存成文件） | ⛔；本 App 的“场景”可存整套路由与通道条 |
| Workspace Quick Select | 快速切换常用工作区 | ⛔ |
| Open Recent | 最近打开的文件 | ⛔ |
| Close Window / Close All | 关窗口 | ⛔ |

### Function（功能）
| 条目 | 意思 |
| --- | --- |
| Mixer View / Matrix View | 调音台视图 / 矩阵视图 |
| Toggle Mixer Window / Toggle Matrix Window | 打开或关闭这两个窗口 |

### Options（选项）
| 条目 | 意思 | 本 App |
| --- | --- | --- |
| Enable MIDI Control | 允许 MIDI 控制 TotalMix | ⛔ |
| Submix linked to MIDI Controller | MIDI 控制器切子混音时界面跟着切 | ⛔ |
| **Enable OSC Control** | 允许 OSC 控制——**本 App 靠它工作，必须勾上** | 设置页有说明 |
| Submix linked to OSC Controller | OSC 切子混音时界面跟着切（Global OSC 下要**关闭**，即 Follow Submix） | 设置页有说明 |
| Mixer Settings… | 设置窗口：混音、MIDI、OSC、Aux Devices 等页（OSC 端口在这里设） | 设置页有说明 |
| Channel Layout… | 隐藏 / 显示通道、布局预设（隐藏的通道 Global OSC 也收不到） | 布局预设调用 🔜 可做（协议有 `/layout/load`） |
| ARC & Key Command Settings… | ARC 遥控器与快捷键 | ⛔ |
| Reset Mix ▸ | 一键重置（**会清掉现有混音，慎用**）：Straight playback, mix to Main Out（回放直通并混到主输出）、Straight playback（只直通）、Clear all submixes（清空全部子混音）、Set output volumes（重设输出音量）、Clear all channel effects / w/o Room EQ（清效果，可保留 Room EQ）、Reset channel names（恢复通道名）、Set all channels mono / stereo（全部单声道 / 立体声）、Set inputs mono / outputs stereo（输入单声道、输出立体声）、Total Reset / w/o Room EQ（全部重置） | ⛔ |
| Operational Mode… | 工作模式（设备相关） | ⛔ |
| Offline Device Setup… | 设备没接时也能编辑它的配置 | ⛔ |
| Network Remote Settings… | 网络遥控（iPad 等）设置 | ⛔ |
| Always on Top | 窗口总在最前 | ⛔ |
| Prevent Sleep | 运行时阻止 Mac 睡眠 | ⛔ |
| Store current State into Device ▸ | 把当前状态存进设备（脱机时用） | ⛔ |

### Window（窗口）
| 条目 | 意思 |
| --- | --- |
| Set Scale to ▸ | 界面缩放（100%、135%、180%、200%） |
| Toggle Old-New Design | 新旧两种界面外观切换 |
| Hide Control Strip | 隐藏右侧控制条 |
| Minimize / Zoom / Fill / Center / 全屏 / 标签页相关 | 系统窗口操作 |
| 最底下“RME TotalMix FX: MADIface XT (序列号) - disconnected” | 当前窗口对应的设备与连接状态（本机 XT 未接时显示 disconnected） |

### Help（帮助）
| 条目 | 意思 |
| --- | --- |
| TotalMix FX Help | 打开自带帮助（英文，本图例的主要出处） |

---

## 4. 一次性设置（只在 TotalMix 里做一次）

1. Options → 勾 **Enable OSC Control**；
2. Options → **Mixer Settings…** → OSC 页：选一个空闲的 Controller，勾 In Use；Port (incoming) 7011、Port (outgoing) 9011、Remote Host 127.0.0.1；Compatibility 选 **Global OSC**；关闭 Follow Submix；想看电平勾 **Send Level Data**；
3. 其余日常操作都可以在本 App 里完成（见上表 ✅）。
