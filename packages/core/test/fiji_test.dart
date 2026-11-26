import 'package:offroad_core/fiji.dart';
import 'package:test/test.dart';

void main() {
  test('Fiji coverage wraps at Taveuni and includes Rotuma', () {
    expect(FijiStarter.covers(-16.8, 179.95), isTrue);
    expect(FijiStarter.covers(-16.8, -179.95), isTrue);
    expect(FijiStarter.covers(-16.8, 180.05), isTrue);
    expect(FijiStarter.covers(-12.5, 177.1), isTrue);
    expect(FijiStarter.covers(-17, 0), isFalse);
    expect(FijiStarter.covers(17, 179), isFalse);
  });
}
