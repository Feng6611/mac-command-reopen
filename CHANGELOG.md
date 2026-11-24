# Changelog / 更新日志

## 1.5.5 — 2026-11-24

GitHub build only; the Mac App Store version stays on 1.5.4. / 仅 GitHub 版；Mac App Store 版仍为 1.5.4。

### English

- GitHub build: now includes every 1.5.4 change.
- GitHub build: optional Advanced Window Restore in Settings › Advanced. With Accessibility allowed, Command Reopen restores minimized windows itself.
- GitHub build: now sends anonymous usage stats, like the Mac App Store version. No app names or window titles; PRIVACY.md lists what is sent.
- About in the GitHub build: one Mac App Store button for support, and the footer says when Accessibility is requested and that usage stats are sent.

### 中文

- GitHub 版：包含 1.5.4 的全部改动。
- GitHub 版：新增可选的高级窗口恢复（设置 › 高级）。允许辅助功能后，由 Command Reopen 自己还原最小化的窗口。
- GitHub 版：开始发送匿名使用统计，与 Mac App Store 版相同；不含 App 名称和窗口标题，PRIVACY.md 列明发送内容。
- GitHub 版的“关于”：支持只保留一个 Mac App Store 按钮；底部说明何时请求辅助功能权限，以及会发送使用统计。

## 1.5.4 — 2026-11-17

### English

- The first time Command Reopen restores a window, a short note at the top right says so. Until then, closing an app's last window shows a tip that Cmd+Tab brings it back, on at most two days.
- The menu bar's Statistics item shows the restore count from the first restore.
- Fixed: before the free trial started, Cmd+Tab did not restore windows and could open a purchase sheet saying the trial had ended. Cmd+Tab now works, and the first restore starts the trial.
- Analytics: each real restore attempt reports success, failure or unknown; cancelled purchases and restores are now reported. No app names or window titles are sent.

### 中文

- Command Reopen 第一次帮你还原窗口时，右上角会有一条简短提示。在那之前，关掉某个 App 的最后一个窗口时会提示用 Cmd+Tab 找回，最多出现两天。
- 菜单栏的“统计”从第一次还原起就显示次数。
- 修复：免费试用开始前，Cmd+Tab 不会还原窗口，还可能弹出“试用已结束”的购买页。现在 Cmd+Tab 照常工作，第一次还原时开始试用。
- 分析：每次实际还原都会上报成功、失败或未知；取消购买和取消恢复也会上报。不发送 App 名称或窗口标题。

## 1.5.3 — 2026-10-26

### English

- New installs get a 7-day free trial instead of 2. The tutorial now ends on its own step where you start it, with buying Lifetime as the other option. The trial no longer starts in the background at first launch; closing the tutorial early still starts it.
- Fixed: closing the purchase sheet at the end of the tutorial did nothing, so the tutorial could not be finished.
- The purchase sheet during a trial shows the days left as a status line instead of a countdown headline, and the only plan no longer carries a "Best Value" badge.
- New: Brazilian Portuguese interface.

### 中文

- 新安装的免费试用从 2 天延长到 7 天。引导最后一步改为单独的试用页：在这里开始免费试用，也可以直接买断终身版。试用不再在首次启动时自动开始；中途关闭引导也会开始试用。
- 修复：引导结尾的购买页点关闭没有反应，导致无法完成引导。
- 试用期间的购买页把剩余天数放在副标题里作为状态显示，不再用倒计时标题；唯一的方案不再标注“Best Value”。
- 新增巴西葡萄牙语界面。

## 1.5.2 — 2026-10-20

### English

- New installs get a 2-day free trial instead of 14. Installs that already had a trial keep their 14 days.
- Finishing the tutorial now ends on the purchase sheet. During a trial older than 3 days, the sheet also appears once a day, at that day's 10th restored window.
- The Mac App Store version now sends anonymous product analytics (no app names, window titles or personal data). The privacy policy lists what is sent; the GitHub build sends nothing.
- Yearly is no longer sold. Lifetime is the only plan on the purchase sheet; existing yearly subscribers keep their access until the period ends.
- The purchase sheet opened from Settings › About leads with your own figures again — windows restored during the trial and the app they came back in most — and its title states where the trial stands: days left, ends today, or ended. A 1.4.2 packaging change had dropped those figures, leaving a subtitle that referred to them.
- Pro owners opening the same row now see what they own, until when, and how many windows it has restored, instead of the purchase options.
- The one-time review request now shows only after a purchase or when you open Statistics, states how many windows Command Reopen has brought back, and is never shown once a trial has ended. Launch-time requests are left to the standard App Store prompt.

### 中文

- 新安装的免费试用从 14 天缩短为 2 天；已经有过试用的安装仍按 14 天计算。
- 完成引导后直接显示购买页；试用超过 3 天后，每天恢复窗口满 10 次时再显示一次。
- Mac App Store 版新增匿名产品分析（不含 App 名称、窗口标题和个人信息），隐私政策已列明；GitHub 版不上传任何数据。
- 不再销售年付方案，购买页只保留买断。已订阅年付的用户可继续使用到当前周期结束。
- 从「设置 › 关于」打开的购买页重新以你自己的数据开头——试用期内恢复的窗口数和恢复最多的 App；标题直接说明试用状态：还剩几天、今天结束或已结束。1.4.2 的打包改动曾让这组数据消失，只留下指代它的副标题。
- 已购买 Pro 的用户点开同一行时，看到的是所购方案、到期时间和累计恢复的窗口数，而不再是购买选项。
- 一次性评分请求只在购买完成或打开统计页时出现，会说明 Command Reopen 已帮你找回多少窗口；试用结束后不再请求评分。启动时的请求改由 App Store 标准弹窗处理。

## 1.5.1 — 2026-09-15

### English

- Added **Show Menu Bar Icon** in Settings › General. Turn it off to run Command Reopen with no menu bar presence; it keeps working in the background, and launching the app again opens Settings. A login launch never opens a window.
- Onboarding no longer turns on Launch at Login for you. The switch waits for you to choose, and the final step is worded to match.
- The minimize step plays the native Dock animation again.
- The final step names where to find the app in the menu bar, and its button reads Get Started.

### 中文

- 在「设置 › 通用」中新增 **显示菜单栏图标**。关闭后 Command Reopen 不再显示菜单栏图标，继续在后台运行；再次启动 App 即可打开设置。登录时自动启动不会弹出窗口。
- 引导流程不再自动开启「登录时打开」：改由你自行选择，最后一步文案据此调整。
- 最小化步骤恢复播放原生程序坞动画。
- 最后一步说明 App 在菜单栏的位置，按钮文案改为「开始使用」。

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
