import '../models/category.dart';
import '../models/energy.dart';
import '../models/local_time.dart';

/// Time zone used until the user picks another.
const String defaultTimeZone = 'Europe/Paris';

/// The editable starter categories.
List<Category> defaultCategories() => List.unmodifiable([
  const Category(
    id: 'reading',
    name: 'Reading',
    color: '#2E7D32',
    weeklyTargetMin: 8 * 60,
    defaultEnergy: Energy.medium,
    defaultDurationMin: 45,
  ),
  Category(
    id: 'research',
    name: 'Research',
    color: '#1565C0',
    weeklyTargetMin: 15 * 60,
    defaultEnergy: Energy.high,
    defaultDurationMin: 90,
    preferredWindow: TimeWindow(const LocalTime(9, 0), const LocalTime(12, 0)),
  ),
  const Category(
    id: 'writing',
    name: 'Writing/Blog',
    color: '#6A1B9A',
    weeklyTargetMin: 2 * 60,
    defaultEnergy: Energy.high,
    defaultDurationMin: 60,
  ),
  const Category(
    id: 'news',
    name: 'News/Veille',
    color: '#EF6C00',
    weeklyTargetMin: 60,
    defaultEnergy: Energy.low,
    defaultDurationMin: 20,
  ),
  const Category(
    id: 'teaching',
    name: 'Teaching',
    color: '#c6b328',
    // Teaching time is driven by the timetable, not a target.
    weeklyTargetMin: 0,
    defaultEnergy: Energy.medium,
    defaultDurationMin: 60,
  ),
  const Category(
    id: 'admin',
    name: 'Admin',
    color: '#546E7A',
    weeklyTargetMin: 60,
    defaultEnergy: Energy.low,
    defaultDurationMin: 30,
  ),
]);
