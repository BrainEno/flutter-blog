# 文档索引

> 状态：active ｜ 最后核对：2026-11-19 @ de5e8bc

以当前源码和 GitHub issue/PR 状态为准。审计文件固定在所列快照，不是自动更新
的部署或生产验收报告；未合并 PR 不代表主线功能。根 [README](../README.md)
只做入口（#298）：功能摘要、快速开始和本索引的链接；被移出的细则都在下面能找到。

## 入门与本地开发

- [功能清单（详细版）](features.md)：根 README 功能表每一行的完整边界说明。
- [本地开发](local-development.md)：初始配置、Windows/macOS 一键脚本、明文 HTTP、
  手动命令与依赖升级。
- [本地启动排障](troubleshooting.md)：版本不符、Pub 哈希错误、白屏、「无法连接到网络」
  与后端未启动时的表现。

## 日常使用、隐私与发布

- [个人安装 IPA / APK](mobile-packages.md)：GitHub Actions、AltStore 重签、
  Android 签名、权限和真机检查。不要提供 Apple ID 或签名凭据给聊天。
- [发布流程](releasing.md)：应用身份（`com.nodeman24.nowave`）、版本
  （`0.2.0+1`）、许可证、签名和发布门禁。
- [隐私政策草案](privacy-policy-draft.md)：未发布；正式政策仍需运营主体审阅。
- [无障碍](accessibility.md)：语义、键盘、字体缩放和仍需真机验收的边界。
- [朗读功能](read-aloud.md)：操作、平台语音和设备/隐私边界。
- [密码恢复](password-recovery.md)：匿名恢复接口、邮件链接及客户端处理范围。

## 账户、文章与本地数据

- [账户邮箱](account-email.md)：`PUT /me/email` 的当前密码、单飞写、结果未知；
  邮箱验证的发信、`MAIL_DISABLED`、确认码与「不验证也能用」的边界。
- [语言版本](article-editions.md)：文章各语言版本的寻址、写入、缓存和旧部署降级。
- [评论线程](comments.md)：顶级评论 cursor 分页、嵌套回复、加载重试、旧部署保护与
  后端迁移要求。
- [私信](messages.md)：会话与消息游标、幂等键、显式已读和旧部署降级。
- [通知收件箱](notifications.md)：按需 cursor 翻页、无推送与轮询、账号围栏、已读语义。
- [首页最新分页](latest-feed-cursor.md)：游标、旧部署回退和密集边界。
- [精选书架的编辑端策展](featured-curation.md)：整份替换的写入、三态角色、
  回退顺序不可分辨带来的界面义务，以及锁住它的守卫测试。
- [分类目录的编辑端维护](taxonomy-maintenance.md)：只吃 `zh-CN` 的写侧、只有
  一页的目录、一个布尔收据给措辞划的上限，以及不给服务端替它补理由的界面。
- [离线书库](offline-library.md)：有界本地全文搜索、backend/语言隔离、清空范围与
  存储估算。
- [发布队列](publish-queue.md)：离线/失败后的安全重试、幂等键、账号与后端隔离和
  已知限制。
- [SQLite 存储](sqlite-storage.md)：schema 版本、迁移、Isar 移除与降级限制。
- [未归属旧草稿](unclaimed-drafts.md)：保留、只读导出范围和降级风险。
- [分享与深链](deep-links.md)：出站分享 payload、`nowave://` 入站与通用链接的验收边界。
- [会话生命周期](session-lifecycle.md)：refresh 单飞、账号 fence、花费策略与改动守则。

## 架构、编辑器与后端集成

- [架构与约定](architecture.md)：目录分层、数据流、正文模型、Failure 契约、本地存储、
  首页离线范围与图片/媒体约定；依赖注入模块在 `lib/di/`。

- [冷启动与墨色幕布](startup.md)：`main` 之后不再 await 的启动顺序、幕布时序与
  原生静态启动图的边界。
- [界面设计系统](design-system.md)：色板与间距 token、共用组件目录、无障碍契约。
- [编辑器收敛路线图](editor-architecture-roadmap.md)：唯一的传统编辑器、Markdown 与
  no-wave blocks 的互转、条件并发，以及本地块编辑原型的移除。
- [no-wave 传输层](nowave-transport.md)：URL 组合、响应信封映射与 401 重放决策。
- [后端差距摘要](backend-gaps.md)：客户端视角的当前差距与服务端待办。
- [no-wave API 差距](nowave-api-gap-audit.md)：指定审计快照的已接入与未接入能力。
- [API 连通性证据](api-connectivity-evidence.md)：探测、诊断和网络验证的证据边界。
- [API 重定向策略](api-redirect-policy.md)：HTTP 重定向的安全边界与客户端行为。
- [Supabase 到 no-wave 的迁移](supabase-to-nowave-migration.md)：历史迁移背景；
  旧快照的接口结论以较新的 API 差距审计和当前源码为准。
- [Notion 内容源评估](notion-content-source-assessment.md)：直接 Notion 数据库内容源
  的未实现评估；编辑器的 Notion bundle 导入/导出属于已接入的独立能力，行为说明见
  [功能清单](features.md)「Notion 导入 / 导出」，范围摘要见根 README「Notion 的范围」。

## 工程与质量门禁

- [Agent 开发流程](agent-development.md) 和 [AGENTS.md](../AGENTS.md)：工程约束、
  验证与 PR 证据；会话平台若限定工作分支，应遵守该更高优先级的约束。
- [CI 可观测性](ci-observability.md)：失败证据与构建诊断。
- [人设巡检与 AI 真机测试员](agent-testers.md)：mobile-agent-testers 式的 6 人设 ×
  17 界面巡检（布局、点击区域、名称、对比度、截断、漏翻），以及手动跑真机代理的步骤。
- [路线图](roadmap.md)：已落地阶段与重点修复（开放工作以 issue 列表为准）。
- [代码健壮性审查](code-audit.md)：指定基线的已修复项与剩余风险。
- [未引用资源来源](assets-source/README.md)：保留在仓库、但不再随应用打包的历史图片。

## 已归档快照

归档资料保留当时的审计证据和结论，不应被当作当前功能、issue 或部署状态。

- [2026-11-02 全面代码审查](archive/comprehensive-code-review-2026-11-02.md)
- [2026-11-05 Issue 勘误与完成度核对](archive/issue-errata-2026-11-05.md)
