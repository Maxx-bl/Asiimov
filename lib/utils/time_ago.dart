import 'package:easy_localization/easy_localization.dart';

String _pad2(int n) => n.toString().padLeft(2, '0');

/// Formats a past [dateTime] relative to now.
///
/// Under 24h: granular relative time ("il y a 30 secondes", "1 hour ago"...).
/// 1 to 3 days: "il y a 1/2/3 jour(s)".
/// Beyond 3 days: an absolute dd/MM/yy date.
String formatTimeAgo(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);

  if (diff.inDays > 3) {
    final year = (dateTime.year % 100);
    return '${_pad2(dateTime.day)}/${_pad2(dateTime.month)}/${_pad2(year)}';
  }

  if (diff.inDays >= 1) {
    final days = diff.inDays;
    return (days == 1 ? 'time_ago_day' : 'time_ago_days').tr(args: ['$days']);
  }

  if (diff.inHours >= 1) {
    final hours = diff.inHours;
    return (hours == 1 ? 'time_ago_hour' : 'time_ago_hours')
        .tr(args: ['$hours']);
  }

  if (diff.inMinutes >= 1) {
    final minutes = diff.inMinutes;
    return (minutes == 1 ? 'time_ago_minute' : 'time_ago_minutes')
        .tr(args: ['$minutes']);
  }

  final seconds = diff.inSeconds < 0 ? 0 : diff.inSeconds;
  return (seconds == 1 ? 'time_ago_second' : 'time_ago_seconds')
      .tr(args: ['$seconds']);
}
