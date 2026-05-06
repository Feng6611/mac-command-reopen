# Command Reopen — Claude 协作规则

## 必读

修改任何 UI 文件前先读 `DESIGN.md`。

---

## UI 改动的铁规

1. **Native-first**：默认 Form / GroupBox / LabeledContent / 系统按钮。  
   自定义必须在 PR/commit message 里说明"系统 API 不够用的原因"。
2. **Rule of 3**：同一个值或模式出现 ≥ 3 次才进 `DesignSystem.swift`。
3. **零和**：加一个 token / modifier / 组件，必须删一个等价或过时的。

---

## Token 总数预算（上限）

- Spacing: ≤ 7
- Radius: ≤ 3
- Typography 自定义: ≤ 8（其余用系统字体 `.headline` / `.body` / `.callout` / `.caption`）
- Color 自定义: ≤ 7
- Card modifier: 1（`dsCard`），`settingsCard` 是它的 alias

---

## 禁止

- 在 Form Section 里加自定义背景/边框
- `.link` 按钮加 `systemImage`
- 给已有 DS token 创建同义 alias
- 绕过 DS 写 `Font.system(size: X)` 而不先看有没有对应 token
- 不经过 Rule of 3 就新增 token

---

## 不涉及的文件（不改动）

`state/`、`services/`、`system/`、`app/` 里的逻辑文件。  
UI 修改范围：`ComTab/views/` 和 `ComTab/shared/DesignSystem.swift`。

---

## 调试工具

`ComTab/shared/DesignCatalog.swift`（仅 DEBUG）：打开 Xcode Preview 可一览所有组件的 Light / Dark 效果。
