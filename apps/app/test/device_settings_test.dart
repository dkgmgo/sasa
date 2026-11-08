import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/src/device_settings.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('forceCalDav defaults to false and persists', () async {
    final s = PrefsDeviceSettings();
    expect(await s.forceCalDav(), isFalse);
    await s.setForceCalDav(true);
    expect(await PrefsDeviceSettings().forceCalDav(), isTrue);
  });

  test('MemoryDeviceSettings', () async {
    final s = MemoryDeviceSettings(forceCalDav: true);
    expect(await s.forceCalDav(), isTrue);
    await s.setForceCalDav(false);
    expect(await s.forceCalDav(), isFalse);
  });
}
