# 路线图与已完成的重点修复

> 状态：active ｜ 最后核对：2026-11-19 @ de5e8bc

> 从根 README 移出（#298）。开放工作以
> [GitHub issue 列表](https://github.com/BrainEno/flutter-blog/issues) 为准；本页记录
> 已经落地的阶段，不维护开放 issue 的实时状态。

按 [issue 列表](https://github.com/BrainEno/flutter-blog/issues) 的优先级：

- **P2 已落地**：Markdown 正文与编辑预览（#17）、阅读历史与有限数据导出（#22）、
  工程清理与图标配置修复（#25）、README/文档（#26）、中文文案与日期/阅读
  时长与中英双语本地化、无障碍适配（#24，仅剩真机读屏与视觉人工验收，见
  [无障碍说明](accessibility.md)）、分享（#21 出站 + `nowave://` 入站）、
  评论（#19）、作者主页与关注（#20）
- **P2 进行中/延后**：分享的通用链接/App Links（#21，等 web origin 部署
  `assetlinks.json` 与 `apple-app-site-association` 才可验证）、
  离线发布队列（#23 客户端 outbox 已实现，封面媒体幂等与孤儿清理仍待服务端，
  见 [后端差距](backend-gaps.md)）、举报屏蔽（#18）、
  架构收敛的后续拆分（#107 的依赖规则、存储端口去 UI 类型、
  会话时序单元与 Isar 移除已完成；`nowave_api_client` 等仍有拆分空间）
- **P0/P1 已关闭**：#4 工具链升级、#7 schema 版本管理、#8 离线缓存语义

开放工作按 [GitHub issue 列表](https://github.com/BrainEno/flutter-blog/issues) 的优先级处理。
举报与屏蔽仍依赖 no-wave 侧提供迁移、服务和 REST 接口；在这些门槛完成前，客户端不能
只增加一个入口来伪造安全闭环。其当前边界见
[no-wave ADR 0026](https://github.com/BrainEno/no-wave/blob/bbe9d198208cc9f4267e18e3a4ddcc88b2ad535a/docs/architecture/decisions/0026-moderation-reports-and-appeals.md)。


## 已完成的重点修复

草稿按后端、账号和文章隔离及快照安全清理（#14、#79）、Feed 分页与刷新竞态（#13）、
点赞并发与离线行为（#9）、异常契约统一（#12）、iOS 发布流水线（#6）、
点赞离线假成功（#3）、Supabase → no-wave 后端迁移、删除与回收站（G1）、
Markdown 正文（#17）、阅读历史与导出（#22）、Isar 依赖及其一次性导入器的彻底
移除（#107，见 [SQLite 存储](sqlite-storage.md)）、深链入站与分享（#21）、
中文文案统一与无障碍扫描（#24）、无调用方代码与 `build_runner` 的清理（2026-11，
见 [docs/code-audit.md](code-audit.md)）等。
