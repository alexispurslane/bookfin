import 'dart:math';

import 'package:flutter/material.dart';

/// A place in a recording as a clock reads it: "05:00" under an hour, and
/// "1:05:00" from an hour on. Negative times read as "00:00".
String audioTime(int milliseconds) {
  final seconds = max(0, milliseconds) ~/ 1000;
  final minutes = seconds ~/ 60;
  return '${minutes ~/ 60 > 0 ? '${minutes ~/ 60}:' : ''}${(minutes % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// A length of time to the nearest minute, for example "9 h 44 m", or "12 m"
/// under one hour.
String duration(int milliseconds) {
  final minutes = (milliseconds / 60000).round();
  return minutes < 60 ? '$minutes m' : '${minutes ~/ 60} h ${minutes % 60} m';
}

/// An estimate of a reading time, rounded to a step that reads at a glance
/// and does not change on every page: to the minute under 10 minutes, to 5
/// minutes under an hour, and to 10 minutes from an hour on. Under half a
/// minute it is zero. A rounded estimate stays as it is.
Duration roundEstimate(Duration time) {
  final minutes = time.inMilliseconds / Duration.millisecondsPerMinute;
  int to(int step) => (minutes / step).round() * step;
  final rounded = minutes < 9.5
      ? to(1)
      : to(5) < 60
      ? to(5)
      : to(10);
  return Duration(minutes: rounded);
}

/// An estimate of a reading time as [roundEstimate] rounds it, for example
/// "less than 1 min", "6 min", "1 h 20 min" or "3 h". It differs from
/// [duration], which shows a measured time to the minute.
String estimatedTime(Duration time) {
  final minutes = roundEstimate(time).inMinutes;
  if (minutes == 0) return 'less than 1 min';
  if (minutes < 60) return '$minutes min';
  final hours = '${minutes ~/ 60} h';
  return minutes % 60 == 0 ? hours : '$hours ${minutes % 60} min';
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// For example "Today", "Yesterday", "Tuesday", or "12 Oct", in local time.
String listenedWhen(DateTime at, DateTime now) {
  final local = at.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = (today.difference(day).inHours / 24).round();
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return _weekdays[local.weekday - 1];
  return '${local.day} ${_months[local.month - 1]}'
      '${local.year == now.year ? '' : ' ${local.year}'}';
}

/// A moment as its day and its local time of day, for example
/// "Today, 2:07 PM" or "12 Oct, 14:07", in the format of the app's locale.
String dayAndTime(BuildContext context, DateTime at) =>
    '${listenedWhen(at, DateTime.now())}, ${timeOfDay(context, at)}';

/// The local time of day of a moment, for example "2:07 PM" or "14:07", in
/// the format of the app's locale.
String timeOfDay(BuildContext context, DateTime at) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(at.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
