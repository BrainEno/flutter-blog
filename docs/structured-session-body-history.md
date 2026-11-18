# Local structured body history

> 状态：active | 分类基线：`7fc34ce`（仅文档分类，非逐项事实核验）

This feature is a session-only safety aid, not a backup or remote version
history. It applies only to the local structured body editor after explicit
recovery adoption (or initial remote adoption). It neither reads the server
again nor publishes, enqueues, rebases, deletes, or changes metadata.

## Operations

- Each accepted, structurally different body edit adds one immutable checkpoint.
  Exact no-ops do not create a checkpoint or a storage write. Undo/redo and
  choosing another checkpoint restore a complete body, including IDs, block
  order, formatting and optional fields. The current metadata is kept.
- Undo/redo are immediately queued through the same serialized local CAS
  writer as other body edits. Choosing a checkpoint opens a comparison from
  the current body to the selected snapshot and requires confirmation before
  queuing. Redo remains available until a new body edit creates a branch.
- One historical block can be restored in place, or multiple shared modified
  block contents can be selected together and previewed before application.
  Each selected block is replaced in full, including type, inline runs and
  optional fields. Current order and all unselected blocks remain unchanged.
  Added or removed blocks cannot be chosen: the tool never guesses insertion
  positions, performs a merge, or changes order. A selected-block restore is
  one new body edit, so it removes any later redo steps.
- The mixed result is validated as a whole before admission. Invalid format,
  incompatible versions, missing IDs and the existing size limits fail closed
  without a partial body or a write.

## Durability, lifetime, and boundaries

The timeline holds at most 25 body snapshots and a 3,000,000 serialized UTF-16
unit budget; oldest snapshots are evicted first. These are bounds on checkpoint
count and serialized size, not a guarantee about actual VM heap consumption.
An individual validated document can be retained by itself if a different
budget is configured smaller than that document. Previewing and validating a
batch makes temporary copies and has additional cost. Selection comparison is
bounded by the existing 200-block document limit.

History is never written to SQLite. It is cleared on account/generation
invalidation or session close, and it does not cross restart or the handoff to
plain/rich text input. The most recently *successfully saved* recovery remains
subject to existing recovery and CAS behavior. A queued undo or restore is not
durable until local saving completes. Failures or CAS conflicts stop further
history edits and leave the unsaved body visible; retry applies only to ordinary
storage failure, not conflict. A write admitted before account change may
finish only under its original key. Snapshots already handed to consumers
cannot be revoked, so routes clear their references and hide content when the
body, account or session changes; stale confirmation is independently fenced.

This is not cross-device concurrency protection or a safe server-side write
protocol. Manual testing on real devices, with IMEs and screen readers, remains
separate from unit, widget, and CI build checks.
