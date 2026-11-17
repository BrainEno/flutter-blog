# Local structured body transfer

The local editor can prepare a versioned, body-only clipboard copy. It is an
interchange between compatible app versions, not an article backup or a server
API. The copy excludes metadata, recovery history, in-progress text buffers,
image files and account/edition identity. Image URLs are references only.
Clipboard contents may be read, retained or synced by the operating system and
other apps; copying cannot be undone or recalled by the app.

Import reads only after an explicit action. It rejects unsupported envelopes,
noncanonical encodings, invalid documents and values beyond the bound. This is
format validation, not authentication, provenance or a checksum: a valid copy
can contain intentional changes from any source. Users must verify both source
and destination. Comparison is structural, not a rendered Markdown diff.

The whole-body option replaces the local body only after preview and explicit
confirmation. Alternatively, selected modified blocks shared by ID can be
previewed and replaced atomically. The latter preserves current order, version,
and all unselected blocks; additions, deletions and moves are not inferred.
Incompatible selected blocks fail together. Both modes preserve local metadata,
create a session history entry and use the existing local CAS writer. A queued
edit is not a durable save and may fail or conflict. Neither mode publishes or
writes structured content remotely.

A body change, account fence invalidation or route closure discards the active
preview. Confirmation and async results are rechecked against the captured body
and history generation. An already-started platform clipboard call or worker
cannot be cancelled; its late result is ignored after invalidation. Native
workers use Flutter `compute`; on web computation runs on the event loop.
The codec is bounded and strictly accepts the app's canonical ASCII JSON,
including escaped UTF-16 code units. Hand-editing or reformatting a copy may
make it noncanonical and is deliberately rejected. This is not a general JSON
importer and does not promise future schema compatibility.
