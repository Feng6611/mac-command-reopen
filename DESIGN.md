# Command Reopen — Design System

## 三条铁律

1. **Native-first**：默认 Form / GroupBox / LabeledContent / 系统按钮。  
   自定义必须说明"系统 API 不够用的原因"。
2. **Rule of 3**：同一个值或模式出现 ≥ 3 次才进 `DesignSystem.swift`。
3. **零和**：加一个 token / modifier / 组件，必须删一个等价或过时的。

---

## Token 预算（上限）

| 类别 | 上限 | 当前 |
|------|------|------|
| Spacing | ≤ 7 | 8（含 xxxl，边缘） |
| Radius | ≤ 3 | 3（control / card / modal） |
| Typography 自定义 | ≤ 8 | 8 |
| Color 自定义 | ≤ 7 | 7 |
| Card modifier | 1 | 1（dsCard，settingsCard 是 alias） |

---

## Radius 语义

| Token | 值 | 用途 |
|-------|----|------|
| `DS.Radius.control` | 6 pt | 按钮、输入框、小胶囊 |
| `DS.Radius.card` | 10 pt | 卡片、Group 表面 |
| `DS.Radius.modal` | 14 pt | Onboarding、大弹层 |

---

## Typography 使用准则

优先使用系统文字样式：`.headline` / `.body` / `.callout` / `.caption`。  
只在系统样式不足时使用 `DS.Typography.*`：

| Token | 用途 |
|-------|------|
| `displayHero` | Stats 519 大数字 |
| `metricValue` | MetricTile 数值 |
| `headlineMedium` | Paywall / Support 卡片标题 |
| `headlineSmall` | 价格数字 |
| `bodyMedium` | 表单 row 主文字 |
| `captionMedium` | 元数据标签 |
| `micro` / `microSemibold` | 胶囊标签、注释 |

---

## Surface 分类

| Surface | 控件 | 备注 |
|---------|------|------|
| Form Section | 系统 `Form { Section {} }` | 不加自定义背景/边框 |
| 统计 / Pro 卡片 | `GroupBox` | native macOS 表面 |
| Marketing 卡片（Paywall hero） | `.dsCard()` | 唯一自定义卡片 |
| 控件背景（MetricTile 等） | `.thinMaterial` + border overlay | 轻填充 + 边框 |

---

## 禁止

- 在 Form Section 里加自定义背景/边框
- `.link` 按钮加 `systemImage`
- 给已有 DS token 创建同义 alias
- 绕过 DS 直接写 `Font.system(size: X)` 而不先检查是否有对应 token
- 新增超出预算的 token（必须先删一个）

---

## 新增 Token 流程

1. 确认该值在 ≥ 3 个不同位置以相同语义使用
2. 检查 token 预算，如已达上限则先删除一个不再需要的
3. 在 `DesignSystem.swift` 里对应 enum 中添加，并在本文件更新表格
4. 提交时在 commit message 里说明原因
