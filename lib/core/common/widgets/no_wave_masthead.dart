import 'package:flutter/material.dart';

/// Compact native version of no-wave's two-face wordmark.
class NoWaveMasthead extends StatelessWidget {
  const NoWaveMasthead({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: 'No Wave',
      header: true,
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            style: TextStyle(color: color, fontSize: 22, height: 1),
            children: const [
              TextSpan(
                text: 'No ',
                style: TextStyle(
                  fontFamily: 'InterTight',
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: 'Wave',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
