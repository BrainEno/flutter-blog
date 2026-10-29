import 'package:flutter/material.dart';

enum DraftRecoveryChoice { restore, discard, keepCurrent }

/// Asks before replacing the editor's current contents with a local draft.
Future<DraftRecoveryChoice?> showDraftRecoveryDialog(
  BuildContext context, {
  required bool isOlderThanPublished,
}) {
  return showDialog<DraftRecoveryChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('发现草稿'),
      content: Text(
        isOlderThanPublished
            ? '此草稿比已发布文章旧。恢复草稿会替换当前编辑内容。'
            : '恢复草稿会替换当前编辑内容。请选择如何处理。',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, DraftRecoveryChoice.keepCurrent),
          child: const Text('继续当前内容'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, DraftRecoveryChoice.discard),
          child: const Text('丢弃草稿'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, DraftRecoveryChoice.restore),
          child: const Text('恢复草稿'),
        ),
      ],
    ),
  );
}
