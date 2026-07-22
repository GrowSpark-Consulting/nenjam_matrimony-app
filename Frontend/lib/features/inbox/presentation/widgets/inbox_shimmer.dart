import 'package:flutter/material.dart';

import '../../../../core/widgets/feedback/shimmer_widget.dart';

/// Loading placeholder for the conversations list — composed from the
/// shared [NmShimmer] primitives (same compositional style as
/// `NmShimmerProfileCard`) rather than a bespoke shimmer implementation.
class InboxShimmer extends StatelessWidget {
  final int rowCount;

  const InboxShimmer({super.key, this.rowCount = 8});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rowCount,
      itemBuilder: (context, index) => const _InboxShimmerRow(),
    );
  }
}

class _InboxShimmerRow extends StatelessWidget {
  const _InboxShimmerRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NmShimmer.circle(size: 54),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NmShimmer(width: 140, height: 14),
                const SizedBox(height: 8),
                const NmShimmer(width: 90, height: 10),
                const SizedBox(height: 8),
                NmShimmer(width: MediaQuery.of(context).size.width * 0.5, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
