# 文档索引

以当前源码和 GitHub issue/PR 状态为准。审计文件固定在所列快照，不是自动更新
的部署或生产验收报告；未合并 PR 不代表主线功能。根 [README](../README.md)
说明当前运行、配置和主要功能。

## 日常使用与发布

- [个人安装 IPA / APK](mobile-packages.md)：GitHub Actions、AltStore 重签、
  Android 签名、权限和真机检查。不要提供 Apple ID 或签名凭据给聊天。
- [发布流程](releasing.md)：应用身份（`com.nodeman24.nowave`）、版本
  （`0.2.0+1`）、许可证、签名和发布门禁。
- [朗读功能](read-aloud.md)：操作、平台语音和设备/隐私边界。
- [隐私政策草案](privacy-policy-draft.md)：未发布；正式政策仍需运营主体审阅。

## 数据、兼容性与故障排查

- [未归属旧草稿](unclaimed-drafts.md)：保留、只读导出范围和降级风险。
- [SQLite 存储](sqlite-storage.md)：schema 版本、迁移、Isar 移除与降级限制。
- [发布队列](publish-queue.md)：离线/失败后的安全重试、幂等键、账号与后端隔离和
  已知限制。
- [通知收件箱](notifications.md)：进页面读一次、无推送与轮询、账号围栏、已读语义、
  服务端无分页的限制。
- [私信](messages.md)：会话与消息游标、幂等键（建会话与发送）、显式已读、参与者名字
  解析与「暂不提供私信」的旧部署降级。
- [账户邮箱](account-email.md)：`PUT /me/email` 的当前密码、单飞写、结果未知与
  「不验证也能用」的边界。
- [会话生命周期](session-lifecycle.md)：refresh 单飞、账号 fence、花费策略与改动守则。
- [no-wave 传输层](nowave-transport.md)：URL 组合、响应信封映射与 401 重放决策。
- [首页最新分页](latest-feed-cursor.md)：游标、旧部署回退和密集边界。
- [CI 可观测性](ci-observability.md)：失败证据与构建诊断。

## 开发与审计快照

- [no-wave API 差距](nowave-api-gap-audit.md)：记录审计 SHA、已接入与未接入能力。
- [Supabase 到 no-wave 的迁移](supabase-to-nowave-migration.md)：历史迁移背景；
  旧快照的接口结论以较新的 API 差距审计和当前源码为准。
- [代码健壮性审查](code-audit.md)：指定基线的已修复项与剩余风险。
- [Agent 开发流程](agent-development.md) 和 [AGENTS.md](../AGENTS.md)：工程约束、
  验证与 PR 证据；会话平台若限定工作分支，应遵守该更高优先级的约束。
