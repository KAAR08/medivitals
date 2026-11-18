// Plays the real alarm on a device:  flutter test integration_test -d windows
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:medivitallink/src/features/alarm/alarm_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the alarm sound plays, loops and stops', (tester) async {
    final alarm = AudioAlarmPlayer();
    final states = <PlayerState>[];
    final sub = alarm.states.listen(states.add);

    await alarm.start();
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(states, contains(PlayerState.playing));
    final early = await alarm.position();
    expect(early, isNotNull);
    expect(early!.inMilliseconds, greaterThan(2000), reason: 'audio is advancing');

    // The file is 6.4 s; looping brings the position back to the start.
    await Future<void>.delayed(const Duration(seconds: 5));
    final later = await alarm.position();
    expect(later!.inMilliseconds, lessThan(early.inMilliseconds), reason: 'it loops');
    expect(states.last, PlayerState.playing);

    await alarm.stop();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(states.last, PlayerState.stopped);
    await sub.cancel();
  });
}
