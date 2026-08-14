// Copyright 2026 Lóránd Somogyi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// The one place duration rendering lives.
///
/// CLAUDE.md is explicit: dates, times and durations are the reporting
/// feature's core output and must go through `intl`, never a hand-built
/// string — `1.5 h`, `1,5 óra` and `1,5 Std.` all differ by more than the
/// decimal mark. Neither function here actually varies by locale today (every
/// shipped language reads a colon-joined clock the same way), but the padding
/// goes through [NumberFormat] with an explicit locale rather than
/// `padLeft`, so a future locale with its own digit set — Arabic-Indic
/// numerals, for instance — is handled by construction instead of by
/// remembering to revisit this file.
///
/// Every screen that renders a duration or a running timer should reuse
/// these two functions rather than formatting its own.
library;

import 'package:intl/intl.dart';

/// Formats [duration] as `H:MM` — the compact form used for entry durations
/// and day totals in the timer and reports screens.
///
/// The hour is *not* zero-padded (`0:45`, not `00:45`): this is an elapsed
/// duration, not a clock time, and a leading zero on it reads as a clock.
/// A negative duration (clock skew, or a not-yet-stopped entry compared
/// against a stale "now") clamps to zero rather than printing a minus sign
/// nobody asked for.
String formatDuration(Duration duration, String localeName) {
  final d = duration.isNegative ? Duration.zero : duration;
  final minutes = NumberFormat('00', localeName).format(d.inMinutes % 60);
  return '${d.inHours}:$minutes';
}

/// Formats [duration] as `HH:MM:SS` — the running-timer readout, both on the
/// idle `00:00:00` placeholder and the ticking display once a timer starts.
///
/// Unlike [formatDuration], the hour *is* zero-padded to match the fixed-width
/// stopwatch look the design calls for (`01:24:36`, not `1:24:36`); minutes
/// and seconds always were. Every field goes through the same tabular-figure
/// treatment, so the digits never jitter width as they change.
String formatTimer(Duration duration, String localeName) {
  final d = duration.isNegative ? Duration.zero : duration;
  final nf = NumberFormat('00', localeName);
  final hours = nf.format(d.inHours);
  final minutes = nf.format(d.inMinutes % 60);
  final seconds = nf.format(d.inSeconds % 60);
  return '$hours:$minutes:$seconds';
}
