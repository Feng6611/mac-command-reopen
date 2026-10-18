# Command Reopen 事件表（草案）

状态：**草案，待确认，未实现**。2026-10-18。决定见 `DecisionLog.md` D-012；
组件和锁死的隐私配置见 `../../KikiAnalyticsKit/Docs/Design.md`。首期只覆盖 App Store 版（`#if APPSTORE`），
Direct / Community 版是否埋点待定。

## 要回答的问题

| # | 问题 | 指标 | 用到的事件 |
| --- | --- | --- | --- |
| Q1 | 装上之后有没有真正用起来？ | 激活率：7 天内至少 2 个价值日 | `app first opened` → `onboarding *` → `value day` |
| Q2 | 留下来的人还在受益吗？ | 每周受益用户（WBU）、按价值日算的 D1 / D7 / D30 | `value day` |
| Q3 | 14 天试用结束时，谁付费、谁走了？ | 到期前/后购买率，按使用量分桶 | `trial ended`、`paywall *`、`purchase result`、RevenueCat 事件 |
| Q4 | 哪个 paywall 入口在起作用？ | 各 source 的展示 → 点购买 → 成功 | `paywall viewed` / `paywall action` / `purchase result` |
| Q5 | 挽留卡（D-003 / D-010）值不值？ | 卡片出现率、九折购买率、去免费版的比例 | `winback offer *` |
| Q6 | 用户在什么情况下关掉它？ | 关闭自动重开的比例、关之前用了多久 | `reopen toggled` |

**北极星指标：每周受益用户（WBU）**，即本周至少有 1 个价值日的安装数。启动次数和打开设置都不算价值。

## 价值日的定义

当天第一次**真实**的成功重开：`ReopenStatsStore.recordSuccessfulReopen` 返回 `true` 之后。
不算的情况：onboarding 里的 Minimize 演示、helper 进程（已被 `HelperProcessFilter` 过滤）、打开失败的 reopen。

## 事件表

`entitlement_state`（`trial` / `expired` / `pro`）通过 Kit 的 `context` 附在每个事件上。Kit 自动附加的公共属性、
`app first opened` 和 SDK 生命周期事件不再列出。

### 激活与价值

| 事件 | 触发点 | 频率 | 属性 |
| --- | --- | --- | --- |
| `onboarding started` | `OnboardingWindowController` 首次展示 | 每会话 | `session_id` |
| `onboarding step viewed` | 每一步出现 | 每会话每步 | `session_id`、`step`（`welcome` / `try_minimize` / `success` / `finish`） |
| `onboarding demo succeeded` | 演示里真的 Cmd+Tab 回来了（`OnboardingTryMinimizeModel` 成功） | 每装一次 | `duration_ms`（从 started 起） |
| `onboarding completed` | coordinator 完成或窗口被关闭 | 每装一次 | `outcome`（`finished` / `closed`）、`last_step`、`launch_at_login`（bool） |
| `value day` | 见上面的定义（`ActivationMonitor` → `ReopenStatsStore`） | 每天一次 | `value_bucket`（累计成功重开次数分桶）；Kit 自动附加 `active_day_index`、`days_since_first_open` |

### 付费

| 事件 | 触发点 | 频率 | 属性 |
| --- | --- | --- | --- |
| `trial ended` | 本地 14 天试用第一次被判定为到期（`AppAccessController`） | 每装一次 | `active_days`（int，试用期内的价值日数）、`value_bucket`、`winback_eligible`（bool，`TrialReceipt` 能否成立） |
| `paywall viewed` | paywall sheet 新建一次会话 | 每会话 | `session_id`、`source`（`status_bar_upgrade` / `settings_about` / `trial_expired` / `winback_row`） |
| `paywall action` | 用户点了按钮，流程开始之前 | 每次 | `session_id`、`action`（`purchase` / `restore` / `close`）、`plan`（`yearly` / `lifetime`，仅 purchase） |
| `purchase result` | 购买或恢复流程结束 | 每次 | `session_id`、`result`（`success` / `cancelled` / `pending` / `failed`）、`plan`、`error_category`（Commerce 的错误枚举，不带原文） |
| `winback offer shown` | `TrialExitOfferView` 第一次出现（`winbackOfferFirstShownAt` 被写入时） | 每装一次 | `value_bucket` |
| `winback offer action` | 卡片上的选择，或从 Settings 行重新打开 | 每次 | `action`（`purchase` / `free_build` / `dismiss` / `reopened`）、`days_left` |

`trial` 是 Kiki 的本地时间试用，RevenueCat 看不到，所以 `trial ended` 必须由客户端发。
实际收入只看 RevenueCat → PostHog 的服务端事件；`purchase result` 只用来看漏斗。

### 使用习惯与流失信号

| 事件 | 触发点 | 频率 | 属性 |
| --- | --- | --- | --- |
| `reopen toggled` | 菜单栏或设置里切换"启用 Command Reopen" | 每次 | `enabled`（bool）、`surface`（`status_bar` / `settings`） |
| `setting changed` | 设置里改了开关或选项 | 每次 | `setting`（`launch_at_login` / `show_menu_bar_icon` / `return_focus` / `language`）、`enabled`（bool，开关类）或 `language`（App 支持的语言枚举） |
| `excluded apps changed` | 排除列表增删 | 每次 | `count_bucket`（只有数量分桶，不带任何 App） |
| `review prompt shown` | `ReviewPromptPolicy` 实际展示或请求 | 每次 | `kind`（`custom` / `system_request`） |
| `review prompt action` | 自定义评分卡上的选择 | 每次 | `action`（`review` / `not_now`） |

Advanced Mode 的三个开关只在 Direct 版存在，App Store 版不采。

## 看板

1. **Activation**：`app first opened`（`fresh_install`）→ `onboarding demo succeeded` → `onboarding completed`（`finished`）
   → 7 天内 `value day` 的 `active_day_index` ≥ 2。
2. **Retention**：WBU 周趋势；以首个 `value day` 为起点的 D1 / D7 / D30 留存。
3. **Trial outcome**：`trial ended` 按 `value_bucket` 拆分 → 之后 7 天内的 `purchase result`（`success`）或
   RevenueCat initial purchase；再对比试用期内已经购买的人。
4. **Paywall**：按 `source` 的 viewed → action(purchase) → result(success)。
5. **Win-back**：`trial ended`（`winback_eligible`）→ `winback offer shown` → `winback offer action` 的分布。
6. **Health**：`reopen toggled`（`enabled = false`）占活跃安装的比例，以及关闭前的 `active_day_index`。

## 永不采集

被重开的 App 的名字、bundle ID、URL、窗口标题；激活历史和按 App 的统计；排除列表的内容；
自由文本、错误原文、文件路径。`ReopenStatsStore` 里的 App 维度数据一律不进事件，只有总数分桶。

## 实现要点

- 老用户判断（`isExistingUser`）：`ReopenStatsStore` 已有记录，或 onboarding 已完成，就记 `analytics_rollout`。
- `RevenueCatConfiguration(postHogUserID: analytics.installationID.uuidString)`。
- 每个触发点都在 App 的 `CommandReopenAnalytics` 门面里有一个带业务含义的方法；视图不直接拼事件。
- 单测用 `RecordingAnalyticsTransport` 断言：演示不产生 `value day`；同一天第二次重开不再发；
  任何事件属性里都不出现被重开 App 的 bundle ID 或名字。

## 待定

- Direct / Community 版是否埋点；如果埋，没有 paywall，只发激活、价值和使用习惯这几组。
- `onboarding step viewed` 是否值得保留：只有 4 步，可以用 `last_step` 代替。
- `value_bucket` 用累计次数还是近 7 天次数：累计更简单，近 7 天更能看出流失前的下降。
