# Changelog / 更新日志

## 1.5.0 — 2026-08-25

### English

- Removed product analytics and PostHog from every distribution.
- Kept the Direct edition free and feature-complete, without RevenueCat, trials, purchases, or upgrade flows.
- Added a two-day 20% lifetime win-back offer after an expired trial; it is shown only after meaningful use and is separate from the regular paywall.
- Refined Settings layout, window sizing, shortcuts, Login Items guidance, purchase-status refresh, Advanced Settings, excluded-app controls, win-back copy, and review-request copy.
- Paywall plan cards and Developer Testing controls now update immediately when the in-app language changes.
- Removed the About-page feedback-form promotion; existing support contacts remain available.

### 中文

- 移除所有发行渠道中的产品分析与 PostHog。
- 直装版保持免费且功能完整，不包含 RevenueCat、试用、购买或升级流程。
- 试用过期后新增两天有效期的终身版八折挽回优惠；仅在用户已有实际使用后展示，且不与常规购买页混合。
- 优化设置页布局、窗口尺寸、快捷键、登录项指引、购买状态刷新、高级设置、排除应用、挽回优惠和评分请求文案。
- 购买页方案卡片和“开发者测试”控件会立即跟随应用内语言切换更新。
- 移除 About 页中的反馈表单推广；原有支持联系方式仍可使用。

## 1.4.1 — 2026-08-06

### English

- Extended the automatic free trial from two days to fourteen days; existing trials retain their original start date.
- Fixed App Store analytics configuration and added an archive gate for missing analytics configuration.

### 中文

- 自动免费试用从两天延长到十四天；已有试用保留原始开始日期。
- 修复 App Store 分析配置，并为缺少分析配置的归档添加校验门禁。

## 2026-07-27

### English

- Added Simplified Chinese and in-app language selection.
- Localized Statistics, onboarding, About, purchase errors, date labels, and menu copy that previously ignored the selected language.
- Removed stale localization keys and made localization tests independent of the developer’s system language.

### 中文

- 新增简体中文和应用内语言选择。
- 为此前忽略所选语言的统计页、引导页、About、购买错误、日期标签和菜单文案补齐本地化。
- 移除过时的本地化键，并让本地化测试不再依赖开发者的系统语言。

## 2026-07-21

### English

- Excluded helper-like processes from reopen detection and statistics, and removed their existing records through a one-time migration.
- Reverted the menu-bar pulse experiment; it does not ship.

### 中文

- 辅助进程不再触发窗口恢复或写入统计；已有记录会通过一次性迁移移除。
- 撤回菜单栏图标闪动实验；该功能不随版本发布。

## 2026-07-14

### English

- Production builds resolved Kiki_mackit 0.8.0 and KikiCommerceKit 0.1.0 from public tags.
- Kept KikiCommerceTesting in the test target only.

### 中文

- 生产构建从公开 tag 解析 Kiki_mackit 0.8.0 和 KikiCommerceKit 0.1.0。
- KikiCommerceTesting 仅链接到测试 target。
