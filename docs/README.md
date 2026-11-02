# 文档索引

以当前源码和 GitHub issue/PR 状态为准。审计文件固定在所列快照，不是自动更新
的部署或生产验收报告；未合并 PR 不代表主线功能。根 [README](../README.md)
说明当前运行、配置和主要功能。

## 日常使用与发布

- [个人安装 IPA / APK](mobile-packages.md)：GitHub Actions、AltStore 重签、
  Android 签名、权限和真机检查。不要提供 Apple ID 或签名凭据给聊天。
- [发布流程](releasing.md)：版本、签名和发布门禁。
- [朗读功能](read-aloud.md)：操作、平台语音和设备/隐私边界。
- [隐私政策草案](privacy-policy-draft.md)：未发布；正式政策仍需运营主体审阅。

## 数据、兼容性与故障排查

- [未归属旧草稿](unclaimed-drafts.md)：保留、只读导出范围和降级风险。
- [Isar 到 SQLite](isar-to-sqlite-migration.md)：旧数据迁移与回退限制。
- [首页最新分页](latest-feed-cursor.md)：游标、旧部署回退和密集边界。
- [CI 可观测性](ci-observability.md)：失败证据与构建诊断。

## 开发与审计快照

- [no-wave API 差距](nowave-api-gap-audit.md)：记录审计 SHA、已接入与未接入能力。
- [Supabase 到 no-wave 的迁移](supabase-to-nowave-migration.md)：历史迁移背景；
  旧快照的接口结论以较新的 API 差距审计和当前源码为准。
- [代码健壮性审查](code-audit.md)：指定基线的已修复项与剩余风险。
- [全面代码审查（2026-11-02）](full-code-review-2026-11-02.md)：基于 `5c0ef3a`
  的规模、架构、API 清单、多维评分、15 个待办 Issue（含可直接预填充的正文）与
  开放 Issue 可关闭性评估；同名 `.html` 是带一键创建/关闭按钮的交互版本，
  待 Issue 全部创建后可删。
- [Agent 开发流程](agent-development.md) 和 [AGENTS.md](../AGENTS.md)：工程约束、
  验证与 PR 证据；会话平台若限定工作分支，应遵守该更高优先级的约束。
