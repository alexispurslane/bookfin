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
