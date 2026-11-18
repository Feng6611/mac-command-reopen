# Command Reopen 事件表

当前设计覆盖至 **1.5.4（本地实现，待发布）**。1.5.2 / 1.5.3 的历史事件版本见飞书埋点设计表。生产 Release 分发（App Store 及 Release Direct 归档）在配置 token 后发送；Debug 始终使用 `.none`。事件与参数统一定义在 `CommandReopenAnalytics.swift`；PostHog 传输封装在 KikiAnalyticsKit。本文不表示生产数据已验证。

## 安装到付费的分析口径

- 首次打开：`app first opened`，按 `first_open_kind` 分开新安装与埋点上线前的已有安装。无法逐用户识别下载后从未打开的人。
- 激活：首次 `reopen result` 且 `result=success`，衡量实际重开后观察到窗口；引导演示和开始试用都不算激活。
- 使用留存：按安装 ID 汇总成功事件的时间，以首次打开或首次成功为 cohort，计算 D1 / D2 / D3 和后续使用留存。按固定分析时区的自然日计算；完整 24 小时窗口另按事件时间计算。无事件只表示未观测到成功使用，不能认定卸载。
- 转化：串联 `trial started`、带来源的 `paywall viewed` / `paywall action`、`purchase result`；实际付费和收入以 RevenueCat 服务端交易为准，恢复购买单列。
- 试用 cohort 按试用长度与版本分开，只有观察窗口完整的安装才进入对应转化率分母；不能只用客户端实际发出 `trial ended` 的人作为到期分母。

## 重开结果

1.5.4 起停发 `value day`，删除尚未发布的 `daily summary`。替换为 **`reopen result`，每次实际发出的重开尝试恰好一个最终结果，不采样、不限每日数量**。已有窗口、功能关闭、排除应用、helper、引导演示或去抖提前返回均不属于实际指令，不上报结果。

原生打开回调无错误（Direct 为 AX 返回 restored）后，立即及约 0.3 / 1 / 2 秒复用 `WindowInspector` 检查目标 PID：非透明、layer 0、宽高至少 32 的屏幕窗口。看到任意一个即成功，一次尝试不会按窗口数量重复计数。成功使用和本机次数共用 Executor 的确认分支；菜单显示和试用用量逻辑继续使用 `ReopenStatsStore.onReopenRecorded`。

| 参数 | 类型 | 含义 | 起始版本 |
| --- | --- | --- | --- |
| `result` | enum | `success` / `failed` / `unknown` | 1.5.4 |
| `reason` | enum | 判定原因，见下表 | 1.5.4 |
| `duration_ms` | int | 发出指令至最终结果的单调时钟耗时，毫秒，≥ 0 | 1.5.4 |
| `daily_attempt_index` | int | 当天第几次实际重开尝试，从 1 起；持久化跨重启，本地自然日重置；不限量 | 1.5.4 |

| reason | result | 判定 |
| --- | --- | --- |
| `window_observed` | success | 请求被接受后检测到目标进程的合格屏幕窗口 |
| `no_window_observed` | failed | 四轮检查均可用，但观察期内均没有窗口 |
| `request_error` | failed | 系统打开回调返回错误；不上传错误原文 |
| `inspection_unavailable` | unknown | 没有确认窗口，且至少一轮无法读取窗口列表，或观察被取消 |
| `process_unavailable` | unknown | 缺少目标 PID，或回调应用与请求目标不符 |
| `superseded` | unknown | 同一应用的新请求替代了尚未结案的旧尝试 |
| `request_timeout` | unknown | 从发出指令起 5 秒仍未结案，包括系统回调未到或太迟 |

重复回调、超时后的晚到回调不会再次计数或上报。一次失败不触发额外重开。进程被杀或离线仍可能丢失事件，客户端埋点不保证送达。只读取现有 CG 窗口信息，不新增权限请求。

“有窗口”不代表窗口置顶、用户已经看到、恢复了原窗口或全部窗口，也不能证明窗口由本次指令产生。B 的已有窗口被 A 遮挡时，前置检查通常会跳过重开；同一应用只要有任意一个合格窗口即认为有窗口，不追踪具体窗口。慢于观察期的窗口可能漏计。已有本地历史次数保留，1.5.4 前后口径不可直接混算。成功率按已观测到的 success / (success + failed) 计算，unknown 比例另列。

## 公共参数

Kit 附加安装 `distinct_id`、`app_id`、`app_version`、`build_number`、`distribution_channel`、`os_version`、`app_locale`、`schema_version`。
App 业务事件附加 `entitlement_state`（`not_started` / `trial` / `expired` / `pro` / `unrestricted`）；1.5.4 起已知时附加 `trial_day`、`trial_duration_days`（2 / 7 / 14）、`days_since_download`。后者来自签名 AppTransaction 原始购买日期，不提供跨设备安装身份。
`active_day_index` 和 `days_since_first_open` 仍由 Kit 仅为按日事件附加；停发价值日后，本 App 只在 `reopen opportunity` 上使用，不能将其视为成功使用日。

## 事件表

### 引导与使用

| 事件 | 触发点 | 频率 | 参数 |
| --- | --- | --- | --- |
| `app first opened` | Kit 首次初始化 | 每安装一次 | `first_open_kind` |
| `onboarding started` | 引导开始 | 每会话 | `session_id` |
| `onboarding step viewed` | 步骤出现 | 每会话每步 | `session_id`、`step` |
| `onboarding demo succeeded` | 引导演示成功 | 每安装一次 | `duration_ms` |
| `onboarding completed` | 完成或关闭引导 | finished 每安装一次；closed 每次 | `session_id`、`outcome`、`last_step`、`launch_at_login`、`duration_ms`、`demo_succeeded` |
| `reopen result` | 实际重开尝试结案 | 每次一次，不限量 | `result`、`reason`、`duration_ms`、`daily_attempt_index` |
| `reopen hint shown` | 首次成功提示，或首次成功前关掉最后一个窗口时的用法提示 | 首次成功一次；用法提示最多 2 天、每天 1 次 | `kind`（`first_success` / `return_tip`），不含 App 名称 |
| `reopen opportunity` | 通过前置过滤且未检测到窗口 | 每本地日一次 | 无业务参数；Kit 附加日序 |
| `app quit` | 菜单栏 Quit | 每次 | `install_day` |

### 试用与付费

| 事件 | 触发点 | 频率 | 参数 |
| --- | --- | --- | --- |
| `trial started` | 本地试用实际开始；引导外首次真实重开也会开始（I-007） | 每安装一次 | `trigger`（含 `first_reopen`）、`trial_duration_days`、`minutes_since_first_open` |
| `trial ended` | 本地首次观察到期 | 每安装一次 | `active_days`、`value_bucket`、`winback_eligible` |
| `paywall viewed` | 付费页首次出现 | 每付费页会话 | `session_id`、`source`、`trigger`、`prices_available` |
| `paywall action` | 购买/恢复进度开始，或开始试用/关闭 | 每次；close 每会话最多一次 | `session_id`、`action`、`plan`、`ms_since_view`、`prices_available` |
| `purchase result` | 购买或恢复流程结束 | 每次 | `session_id`（页外发起可缺失）、`operation`、`result`、`plan`、`error_category` |
| `winback offer shown` | 挽留优惠首次出现 | 每安装一次 | `value_bucket` |
| `winback offer action` | 购买、免费版、关闭或重开卡片 | 每次 | `action`、`days_left` |

同一付费页的 viewed / action / purchase result 共用 `session_id`；挽留卡片页外购买不带此 ID。同页多次购买尝试共用会话，当前没有逐次 `attempt_id`。不增加加载结果事件，保留展示及动作时的 `prices_available`；其含义是至少一个在售方案可用。`purchase result` 只诊断客户端流程，`pending` 不能当付款成功，restore 不能算新增付费。

### 设置与评分

| 事件 | 频率 | 参数 |
| --- | --- | --- |
| `reopen toggled` | 每次 | `enabled` |
| `setting changed` | 每次 | `setting`、`enabled` 或 `language` |
| `excluded apps changed` | 每次 | `count_bucket`，不含排除内容 |
| `review prompt shown` | 每次 | `kind` |
| `review prompt action` | 每次 | `action` |

SDK 自动生命周期事件为 `Application Installed` / `Application Updated` / `Application Opened` / `Application Backgrounded`，不是业务激活证据。

## 永不采集

目标 App 的名称、bundle ID、URL、窗口标题、按 App 关联的激活历史与统计、排除列表内容、自由文本、错误原文和文件路径均不上传。本机 `ReopenStatsStore` 的 App 维度数据不进入事件；重开结果只有无目标身份的结果枚举、耗时与当日序号。

## 验证

使用 `RecordingAnalyticsTransport` 验证超过每日 10 次仍全部发送，每个事件字段固定且不含目标身份。Executor 测试覆盖成功窗口、延迟窗口、无窗口、窗口列表不可用、系统错误、重复及晚到回调、被后续请求替代、超时与跨日序号。Debug 模式及未配置 token 的构建无网络传输；生产 PostHog 回读另行验证。

## 接入与配置

- token：`Config/LocalSecrets.xcconfig` 的 `KIKI_POSTHOG_PROJECT_TOKEN`（`phc_` 开头，公开 token）；
  `KIKI_POSTHOG_HOST` 留空走默认 host。Release 的 App Store 构建缺 token 会在构建阶段失败（`scripts/check_posthog_config.sh`）；Release Direct 归档要求配置 token，普通本地源码构建可省略。
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
