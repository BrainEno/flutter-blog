# Local structured recovery review

> 状态：active ｜ 最后核对：2026-11-16 @ 7fc34ce

The local structured editor now includes a **Review local changes** surface. It
is deliberately a read-only explanation of a recovery, not a second editing or
publishing path.

## What it compares

The review compares two exact, immutable local document snapshots held by the
same fenced `LocalStructuredSession`:

- the original base saved with the local recovery; and
- the body currently held by that local recovery.

It matches blocks by their validated IDs, reports additions, removals, moves and
field changes separately, and retains the distinction between an absent optional
field and an explicit value. A surviving block can be both moved and modified.
Formatted runs, links, image alt/caption and unknown future fields are compared
structurally; the reviewer never flattens them to Markdown or text.

The page is available at the recovery decision, before the author chooses to
resume or discard a saved recovery. After adoption, the editor's separate body
snapshot comparator can additionally show the session-open remote read; this
recovery-decision page remains intentionally local-only. It performs no
database writes, does not discard anything, and has no publish, queue or
network dependency.

## Server-state boundary

The screen also explains the result of the session's original edition read when
one exists. That is contextual information only: it never performs a new
request, asserts that the server is current, rebases, or merges either side.
When that read was unavailable, outside the author-list window, malformed or
incomplete, the screen says that only local snapshots are being compared.

A recovery with different base/body document versions is refused rather than
being converted or guessed.

## Fence and lifecycle behavior

A review route receives a one-shot pair of exact snapshot references. It
continues to display them only while the session remains on that exact base/body
pair in its allowed local phases. A local body replacement, conflict transition
without the pair, route/session closure, account replacement, token loss or
generation change clears the snapshots immediately and replaces the page with a
safe stale-state message. It never reuses a later body as a new comparison base.

Like the rest of structured recovery, this protects local account and storage
boundaries only. It is not cross-device concurrency protection, does not verify
the deployed backend, and does not make unsaved in-memory edits durable.
