import 'dart:io';

import 'package:belog/core/l10n/l10n.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Platform spinner with a localized screen-reader status.
class Loader extends StatelessWidget {
  const Loader({super.key, this.semanticLabel});

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: semanticLabel ?? context.l10n.loading,
        liveRegion: true,
        child: ExcludeSemantics(
          child: Platform.isAndroid
              ? const CircularProgressIndicator()
              : const CupertinoActivityIndicator(),
        ),
      ),
    );
  }
}
