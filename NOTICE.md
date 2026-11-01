# Notices

## MIT motion-source attribution

HushKey adapts the MIT-licensed macOS motion experiment [Subvox](https://github.com/joeblau/subvox), copyright Joe Blau (2026). Adapted areas include headphone motion capture, motion features, DTW template classification, calibration/segmentation, evaluation, session recording, and parts of the SwiftUI workflow. The original MIT license and copyright notice are retained in [LICENSE](LICENSE). HushKey-specific changes are copyright HushKey contributors (2026).

The upstream source was reviewed from commit `591d028` (2026-10-30). HushKey uses the public Core Motion API; it does not access an AirPods speech accelerometer or inward-facing microphone.

Apple references reviewed: [headphone motion API](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager) and [headphone motion sample](https://developer.apple.com/documentation/CoreMotion/getting-motion-activity-data-from-headphones).
