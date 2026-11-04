# Unclaimed legacy drafts / 无法确认归属的旧草稿

## English

Before account-scoped drafts were introduced, the local `drafts` table did not
record a backend or an account. There is no reliable way to determine who wrote
those rows. They remain in the SQLite database but are **not** automatically
shown, assigned, deleted, or imported into any account. Pre-SQLite Isar drafts
are no longer imported at all: the Isar reader was removed in #107 and a
leftover `default.isar` is left untouched (see
[sqlite-storage.md](sqlite-storage.md)). This tool only reads rows already in
SQLite; it cannot extract a `default.isar` file on its own.

If you can legally and safely obtain an app-data copy, stop the app first and
back up the entire app-data directory. The SQLite file is `belog.sqlite` in the
application documents directory. Copy it **together with any matching
`belog.sqlite-wal` and `belog.sqlite-shm` sidecars**, without changing their
names, to a private directory. Copies made while the app is running can be
inconsistent. Do not delete the original data or uninstall the app merely to
make a copy. A release build's Android/iOS sandbox may not permit extracting
these files at all; available backup or developer access depends on the device,
build and OS. Uninstalling the app can permanently remove its local data.

On a trusted POSIX machine with Python 3 (Linux, macOS or WSL), run:

```sh
python3 tool/export_unclaimed_drafts.py /private/copy/belog.sqlite /private/copy/unclaimed-drafts.json
```

The SQLite connection is read-only and the new output is created with at most
`0600` permissions, exclusively: an existing file or symlink is never
replaced. The command reports only a row count, not article contents. JSON
contains each legacy row's raw `id`, `blog_id`, `title`, `content`, `tags` and
`updated_at`; it does not parse or normalize `tags`. A BLOB value is represented
as an object with `encoding: "base64"` and `data`. Treat the JSON as sensitive:
keep it private, make your own secure backup and remove temporary copies safely.
Do not commit or upload it to a public service. Export is not account recovery:
a person who knows the data must separately verify its ownership, and there is
no automatic reimport tool.

Do **not** downgrade to a previous app version as a recovery shortcut. Older
versions may again show an unscoped draft to the wrong logged-in account. This
change protects local drafts in the updated app; it cannot revoke text already
exposed by an older version or an already-sent network request.

## 中文

旧版本的本地 `drafts` 表没有记录 API 后端或账号，无法可靠证明每条草稿属于
谁。升级后这些记录仍保存在 SQLite 中，但**不会**自动展示、分配、删除或导入
任何账号。Isar 时代（SQLite 之前）的草稿已经不再导入：Isar 读取器在 #107 中
移除，残留的 `default.isar` 原样保留（见 [sqlite-storage.md](sqlite-storage.md)）。
本工具只能读取已经进入 SQLite 的记录，不能直接提取 `default.isar`。

仅当你能合法、安全地获取应用数据时，先停止应用并备份整个应用数据目录。
SQLite 文件名为应用文档目录下的 `belog.sqlite`；若存在同名
`belog.sqlite-wal`、`belog.sqlite-shm`，必须连同主文件一起复制到私密目录，
且不要更改文件名。运行中的应用数据副本可能不一致。不要为了复制而删除原数据
或卸载应用。正式版 Android/iOS 的应用沙箱可能完全不允许提取这些文件；是否
有备份或开发者访问权限取决于设备、构建和系统。卸载可能永久丢失本地数据。

在可信的 Linux、macOS 或 WSL 环境安装 Python 3 后运行：

```sh
python3 tool/export_unclaimed_drafts.py /private/copy/belog.sqlite /private/copy/unclaimed-drafts.json
```

程序以只读方式打开 SQLite，并使用不宽于 `0600` 的权限独占创建新文件；不会
覆盖已有文件或符号链接。终端仅显示条数，不打印文章内容。JSON 保留旧行的原始
`id`、`blog_id`、`title`、`content`、`tags` 和 `updated_at`，不解析或改写
`tags`；BLOB 以 `encoding: "base64"` 和 `data` 对象表示。导出文件含隐私内容，
应妥善保管、安全备份并清理临时副本，不要提交到 Git 或上传公开服务。导出不等于
账号恢复：必须由了解数据的人自行核实归属，目前没有自动重新导入工具。

不要以降级旧版应用作为恢复捷径：旧版可能再次向错误的登录账号展示未隔离的
草稿。本修复只能保护更新后应用中的本地草稿，无法撤销旧版已经泄露的内容或
已经发出的网络请求。
