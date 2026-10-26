# 二次元模式 · Claude 看板娘：出图需求（交给 GPT 出图）

对应设计文档第 5.1.2 节。图出好后放进 `Resources/AnimeClaude/`，文件名照下表（扩展名 png / webp / jpg 都行）。App 会自动换上；缺的那张继续用代码画的替代，不会报错。

## 整体方向

两种气质混在一起：

1. **立绘本身**：用户给的形象。
   - 橙色长发，琥珀色眼睛，神情安静、略带书卷气。
   - 奶白色高领荷叶边长裙，黑色腰封和蝴蝶结，橙色饰带，金色流苏。
   - 裙摆和胸前是放射状的橙色花饰，手里拿着一本深棕色封面的书。
   - 气质是“图书馆里的女仆 / 学者”。
2. **Claude 官方的气质**（参考 claude.dev、Claude Code）：
   - 暖奶油纸色底，陶土橙强调。
   - 复古终端感：等宽字、全大写小标签、方括号快捷键（如 `[D] DEVICES`）、`=====` 下划线。
   - 像素风小元素、点阵纸。
   - 整体干净、克制、留白多，不要赛博霓虹。

**色板**（请严格按这几个色出图）：

| 用途 | 颜色 |
|---|---|
| 奶油底 | #F7F1E8、#FFFBF5 |
| 深色底 | #221A16、#2D231E |
| 陶土橙（主色） | #C15F3C、#D97757 |
| 金（流苏、描边） | #C9A15A |
| 黑饰带 | #1F1A17 |
| 文字棕 | #2A1E17 |

**注意**：
- 要画 Anthropic 或 Claude 的那个像素小螃蟹吉祥物 Clawd，不要出现任何文字或水印。
- 花饰请画成“向日葵 / 雏菊式的放射状花”，和立绘裙子上的一致。

## 要出的图

| 文件名 | 尺寸 | 内容 | 要求 |
|---|---|---|---|
| `maid-left.png` | 1100 × 2000 以内，竖图 | 全身立绘（替换现在用户原图抠出的版本） | **透明背景**，干净抠图；头发缝隙不要留白底；人物居中、脚到底边 |
| `maid-right.png` | 1000 × 1900 以内 | 第二个姿势：低头翻书，或抱着书、朝左侧回眸 | 透明背景；同一角色、同一服装 |
| `palace-day.png` | 1600 × 1000 | 浅色背景：午后的旧图书馆 / 书房。高书架、拱窗、暖阳光斑、桌上摊开的书、一盆向日葵 | 画面偏淡、低对比、中间留空（上面要叠界面）；不要人物 |
| `palace-night.png` | 1600 × 1000 | 深色背景：同一书房的夜晚。台灯暖光、窗外深蓝夜色、书架剪影 | 整体偏暗（#221A16 附近），不要人物 |
| `lace-tile.png` | 120 × 72，可横向无缝平铺 | 卡片顶边：奶白蕾丝 + 一条细橙线 | 透明背景；左右边缘能无缝接上 |
| `trim-tile.png` | 384 × 30，可横向平铺 | 卡片底边：黑色细带 + 金色细线 + 小放射花点缀 | 透明背景；无缝 |
| `corner.png` | 400 × 400 | 侧栏右上角的角花：金色细线卷草 + 一朵小放射花，可以带一点像素风 | 透明背景；装饰只占右上角，其余透明 |
| `face-delighted.png` | 512 × 512 | Q 版头像：开心（读取成功时出现） | 透明背景；只要头和肩；表情夸张一点 |
| `face-sleepy.png` | 512 × 512 | Q 版头像：犯困、趴在书上（连不上 TotalMix 时出现） | 同上 |
| `face-determined.png` | 512 × 512 | Q 版头像：认真、推眼镜或握拳（确认发送时出现） | 同上 |

## 给 GPT 的提示词（可直接复制，按需改）

**立绘（透明背景）**

> Full-body anime character illustration, same character as the reference: long straight orange hair, amber eyes, calm scholarly expression, cream-white high-collar ruffled long dress, black corset belt and black bows, orange sash panels, gold tassels, orange sunflower-like radial flower brooches, holding a dark brown hardcover book. Clean line art, soft cel shading, warm palette (#F7F1E8, #C15F3C, #D97757, #C9A15A, #1F1A17). Transparent background, no text, no logo, no watermark.

**浅色背景**

> Quiet old library study in the afternoon, tall wooden bookshelves, arched windows with warm sunlight patches, an open book on a desk, a small pot of sunflowers. Soft, low-contrast, pale cream tones (#F7F1E8, #FFFBF5) with terracotta accents (#D97757), empty center area for UI overlay, no people, no text, no logo, 16:10.

**深色背景**

> The same library study at night, warm desk lamp glow, deep blue night outside the window, silhouettes of bookshelves, dark warm brown overall (#221A16), subtle gold highlights (#C9A15A), empty center area, no people, no text, no logo, 16:10.

**Q 版表情（三张分别出）**

> Chibi head-and-shoulders portrait of the same orange-haired scholar maid character, [happy and cheerful / sleepy, head resting on an open book / determined, adjusting glasses], thick clean outlines, transparent background, no text, no logo.

**蕾丝 / 花边 / 角花**

> Seamless horizontal border tile, cream lace with a thin terracotta line (#D97757), transparent background, flat vector style, no text.
>
> Seamless horizontal trim tile, thin black ribbon band with a fine gold line (#C9A15A) and tiny radial orange flowers, transparent background, no text.
>
> Corner ornament for the top-right corner, thin gold scrollwork with a small radial orange flower, subtle pixel-art accents, transparent background, decoration only in the top-right, no text.

## 放进来之后

告诉我一声，我会：
- 核对尺寸和透明度。
- 更新 `Resources/AnimeClaude/sources.json`（记出图来源和 sha256）。
- 在设置的署名里补上出图来源。
- 在 App 里看一遍浅色和深色。
