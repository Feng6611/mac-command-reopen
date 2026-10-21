# Command Reopen 事件表

状态：**已实现（1.5.2，App Store 版）**，2026-10-21。PostHog `mac-app` 项目（528691）的 token 已写入本地忽略配置；Release App Store 才发送，Debug 始终不发送。没有 token 时 Kit 不初始化 SDK、零请求。决定见 `DecisionLog.md` D-012；
组件和锁死的隐私配置见 `../../KikiAnalyticsKit/Docs/Design.md`。只有 App Store 版带 PostHog 传输；Direct / Community 版链接 Kit 但用 `.none`，不发送任何数据。

## 要回答的问题

| # | 问题 | 指标 | 用到的事件 |
| --- | --- | --- | --- |
| Q1 | 装上之后有没有真正用起来？ | 激活率：7 天内至少 2 个价值日 | `app first opened` → `onboarding *` → `value day` |
| Q2 | 留下来的人还在受益吗？ | 每周受益用户（WBU）、按价值日算的 D1 / D7 / D30 | `value day` |
| Q3 | 试用结束时（新安装 2 天，1.5.2 之前的安装 14 天），谁付费、谁走了？ | 到期前/后购买率，按使用量分桶 | `trial ended`、`paywall *`、`purchase result`、RevenueCat 事件 |
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
| `onboarding completed` | 点 Get Started 并关闭 paywall sheet（`finished`，每装一次），或窗口被关闭（`closed`，每次） | 每装一次 | `outcome`（`finished` / `closed`）、`last_step`、`launch_at_login`（bool） |
| `value day` | 见上面的定义（`ActivationMonitor` → `ReopenStatsStore`） | 每天一次 | `value_bucket`（累计成功重开次数分桶）；Kit 自动附加 `active_day_index`、`days_since_first_open` |

### 付费

| 事件 | 触发点 | 频率 | 属性 |
| --- | --- | --- | --- |
| `trial ended` | 本地试用第一次被判定为到期（`CommandAccessModel`） | 每装一次 | `active_days`（int，试用期内的价值日数）、`value_bucket`、`winback_eligible`（bool，`TrialReceipt` 能否成立） |
| `paywall viewed` | paywall sheet 新建一次会话 | 每会话 | `session_id`、`source`（`onboarding` / `trial_usage` / `trial_expired` / `status_bar_upgrade` / `settings_about`） |
| `paywall action` | 用户点了按钮，流程开始之前 | 每次 | `session_id`、`action`（`purchase` / `restore` / `close`）、`plan`（`lifetime` / `winback_lifetime`，仅 purchase） |
| `purchase result` | 购买或恢复流程结束 | 每次 | `session_id`、`result`（`success` / `cancelled` / `pending` / `failed`）、`error_category`（`network` / `unavailable` / `not_allowed` / `no_active_purchase` / `other`，不带原文；paywall 里不带 `plan`） |
| `winback offer shown` | `TrialExitOfferView` 第一次出现（`winbackOfferFirstShownAt` 被写入时） | 每装一次 | `value_bucket` |
| `winback offer action` | 卡片上的选择，或从 Settings 行重新打开 | 每次 | `action`（`purchase` / `free_build` / `dismiss` / `reopened`）、`days_left` |

`trial` 是 Kiki 的本地时间试用，RevenueCat 看不到，所以 `trial ended` 必须由客户端发。
实际收入只看 RevenueCat → PostHog 的服务端事件；`purchase result` 只用来看漏斗。

### 使用习惯与流失信号

| 事件 | 触发点 | 频率 | 属性 |
| --- | --- | --- | --- |
| `reopen toggled` | 菜单栏或设置里切换"启用 Command Reopen" | 每次 | `enabled`（bool）；不区分入口 |
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

- 老用户判断（`isExistingUser`）：onboarding 已完成，或首次 analytics 初始化前已有试用开始时间，就记 `analytics_rollout`。
- `RevenueCatConfiguration(postHogUserID: analytics.installationID.uuidString)`。
- 每个触发点都在 App 的 `CommandReopenAnalytics` 门面里有一个带业务含义的方法；视图不直接拼事件。
- 单测用 `RecordingAnalyticsTransport` 断言：演示不产生 `value day`；同一天第二次重开不再发；
  任何事件属性里都不出现被重开 App 的 bundle ID 或名字。

## 待定

- Direct / Community 版是否埋点；如果埋，没有 paywall，只发激活、价值和使用习惯这几组。
- `onboarding step viewed` 是否值得保留：只有 4 步，可以用 `last_step` 代替。
- `value_bucket` 用累计次数还是近 7 天次数：累计更简单，近 7 天更能看出流失前的下降。

## 触发 paywall 的入口与 `source`

| `source` | 入口 |
| --- | --- |
| `onboarding` | 引导最后一步点 Get Started，paywall 作为 sheet 出现在引导窗口上（Pro 用户跳过） |
| `trial_usage` | 试用超过 3 天后，当天第 10 次成功恢复 |
| `trial_expired` | 试用结束后的启动 / 状态变化，或 Cmd+Tab 每日提示 |
| `status_bar_upgrade` | 菜单栏「Upgrade to Pro…」 |
| `settings_about` | 设置 › 关于 里的入口（默认值） |

## 接入与配置

- token：`Config/LocalSecrets.xcconfig` 的 `KIKI_POSTHOG_PROJECT_TOKEN`（`phc_` 开头，公开 token）；
  `KIKI_POSTHOG_HOST` 留空走默认 host。Release 的 App Store 构建缺 token 会在构建阶段失败（`scripts/check_posthog_config.sh`）。
- 收入：RevenueCat 的 PostHog 集成使用 KikiCommerceKit `0.5.1` 的 `postHogUserID`。
  `AppComposition` 将 `analytics.installationID.uuidString` 经 `CommandAccessModel` 传入 provider；
  只设置 `$posthogUserId` 属性，不更改 RevenueCat 的 `app_user_id`。
- 老用户首次打开按 `first_open_kind = analytics_rollout` 计，不计入新安装。

## 2026-10-21 接入验证

- PostHog 项目：沿用 `mac-app`（528691），与网站项目分开。
- 依赖：远端精确版本 KikiAnalyticsKit `0.1.1`（`5d40929`），不再使用本地路径。
- token：已写入被忽略的 `Config/LocalSecrets.xcconfig`，不提交 token。
- Debug：无论是否配置 token，都使用 `.none`。
- 启动：在试用创建之前初始化 analytics，确保新安装不会被试用标记误判为老用户；退出时 flush。
- 项目侧 IP 丢弃：负责人开启后，工具回读 `anonymize_ips = true`。
- 真实传输：2026-10-21 20:43:46（Asia/Shanghai）回读到 Release 应用的 `Application Installed`；
  `app_id=command_reopen`、`app_version=1.5.2`、`build_number=37`、`distribution_channel=app_store`、
  `$geoip_disable=true`、`$is_identified=false`。这条是 SDK 生命周期事件，不作新安装转化口径。
- 验证：远端精确依赖下 103 项单元测试、MAS Release 和 Direct Release 构建通过；
  Kit 离线测试 Debug 30 项、Release 31 项通过。
- RevenueCat 收入对接：已在项目 `4a77b4bf` 保存 PostHog 集成，US、生产 token、默认 `rc_*` 购买事件、毛收入。
  Sandbox key 留空；不发送订阅者自定义属性，不开启 RevenueCat Paywalls/Web Funnel 事件。
- Commerce：精确 `0.5.1`（`cbe6794`），仅包含身份属性接入；main 的新 paywall API 不在这个 tag 内。
- 收入端到端验证：未做真实购买；Kit 的离线 SDK spy 覆盖配置后仅设置一次身份属性，真实交易交付待下一笔购买确认。

## ASC 隐私标签（2026-10-21 已发布回读）

| 数据 | 用途 | 身份关联 | 追踪 |
| --- | --- | --- | --- |
| Device ID | Analytics | 否 | 否 |
| Product Interaction | Analytics | 否 | 否 |
| Purchase History | App Functionality、Analytics | 否 | 否 |

匿名 RevenueCat 用户不绑定姓名、邮箱或 Apple ID；安装 UUID 只用于 App 与收入事件对齐。
公开隐私政策已于 2026-10-21 同步部署并线上回读：`https://commandreopen.com/privacy/`（站点源码 `c7978a7`）。
