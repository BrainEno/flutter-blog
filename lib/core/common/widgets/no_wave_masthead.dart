import 'package:belog/core/common/widgets/no_wave_wordmark.dart';
import 'package:flutter/material.dart';

/// Compact native version of no-wave's two-face wordmark, sized for an app bar.
///
/// The mark itself lives in [NoWaveWordmark]; this wrapper exists only to add
/// the header semantics the app bar context needs.
class NoWaveMasthead extends StatelessWidget {
  const NoWaveMasthead({super.key});

  @override
  Widget build(BuildContext context) {
    return const Semantics(
      label: 'No Wave',
      header: true,
      child: ExcludeSemantics(child: NoWaveWordmark()),
    );
  }
}
