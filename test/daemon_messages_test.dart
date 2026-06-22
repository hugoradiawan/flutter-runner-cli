import 'package:frun/src/data/models/daemon_messages.dart';
import 'package:test/test.dart';

void main() {
  test('FlutterDevice.fromJson reads the standard fields', () {
    final d = FlutterDevice.fromJson(<String, Object?>{
      'id': 'emulator-5554',
      'name': 'Pixel 7',
      'platform': 'android-arm64',
      'category': 'mobile',
      'platformType': 'android',
      'ephemeral': true,
      'emulator': true,
      'emulatorId': 'Pixel_7_API_34',
    });
    expect(d.id, 'emulator-5554');
    expect(d.name, 'Pixel 7');
    expect(d.platform, 'android-arm64');
    expect(d.emulator, isTrue);
    expect(d.emulatorId, 'Pixel_7_API_34');
  });

  test('FlutterDevice.fromJson tolerates missing fields', () {
    final d = FlutterDevice.fromJson(const <String, Object?>{});
    expect(d.id, '<unknown>');
    expect(d.name, '<unknown>');
    expect(d.emulator, isFalse);
    expect(d.ephemeral, isTrue);
  });

  test('FlutterEmulator.fromJson falls back to id when name missing', () {
    final e = FlutterEmulator.fromJson(const <String, Object?>{
      'id': 'Pixel_7',
      'platformType': 'android',
    });
    expect(e.id, 'Pixel_7');
    expect(e.name, 'Pixel_7');
  });
}

