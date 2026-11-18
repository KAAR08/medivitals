import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medivitallink/main.dart';
import 'package:medivitallink/src/features/alarm/alarm_controller.dart';
import 'package:medivitallink/src/core/navigation/app_router.dart';
import 'package:medivitallink/src/core/navigation/app_routes.dart';
import 'package:medivitallink/src/data/services/mock_data.dart';

// These tests run the whole app against the mock backend (the default).

Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// The alarm's audio plugin doesn't exist in tests.
class SilentAlarmPlayer implements AlarmPlayer {
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

Future<void> startApp(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [alarmPlayerProvider.overrideWithValue(SilentAlarmPlayer())],
    child: const MedVitalsLinkApp(),
  ));
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// Unmounts the app so providers dispose their streams and timers.
Future<void> stopApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await pumpFor(tester, const Duration(seconds: 2));
}

Future<void> tapAndWait(WidgetTester tester, Finder finder,
    [Duration wait = const Duration(milliseconds: 500)]) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpFor(tester, wait);
}

/// Taps a tab in the bottom navigation bar.
Future<void> tapTab(WidgetTester tester, String label) => tapAndWait(
      tester,
      find.descendant(
          of: find.byType(NavigationBar), matching: find.text(label)),
      const Duration(seconds: 1),
    );

GoRouterHelper router(WidgetTester tester) => GoRouterHelper(
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp))));

class GoRouterHelper {
  GoRouterHelper(this._container);
  final ProviderContainer _container;
  void go(String location) => _container.read(appRouterProvider).go(location);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('cold start without a session leaves the splash for login',
      (tester) async {
    await startApp(tester);

    expect(find.text('Sign In'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('doctor signs in, opens a patient, then logs out',
      (tester) async {
    await startApp(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'), 'dr@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'secret1');
    await tapAndWait(tester, find.text('Doctor'));
    await tapAndWait(tester, find.text('Sign In'), const Duration(seconds: 2));

    expect(find.widgetWithText(AppBar, 'Patients'), findsOneWidget);
    expect(find.text('Jane Smith'), findsOneWidget);

    await tapAndWait(
        tester, find.text('Jane Smith'), const Duration(seconds: 2));
    expect(find.text('Live Metrics'), findsOneWidget);
    expect(find.byTooltip('Message patient'), findsOneWidget);

    await tester.pageBack();
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tapTab(tester, 'Account');
    await tester.scrollUntilVisible(find.text('Logout').hitTestable(), 200,
        scrollable: find.byType(Scrollable).last);
    await tapAndWait(tester, find.text('Logout'), const Duration(seconds: 2));

    expect(find.text('Sign In'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets('login error shows the backend message', (tester) async {
    await startApp(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'),
        'invalid@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'secret1');
    await tapAndWait(tester, find.text('Sign In'), const Duration(seconds: 2));

    expect(find.text('Email or password is incorrect'), findsOneWidget);
    await stopApp(tester);
  });

  testWidgets(
      'stored patient session is restored, role guard holds, chat works',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'medivitallink.access_token': 'mock-access.$kJohnId.1',
      'medivitallink.refresh_token': 'mock-refresh.$kJohnId',
      'medivitallink.user': jsonEncode(mockPatient.toJson()),
    });
    await startApp(tester);
    await pumpFor(tester, const Duration(seconds: 1));

    expect(find.text('Live Metrics'), findsOneWidget);

    // Patients may not open the doctor's monitor.
    router(tester).go(AppRoutes.doctorMonitor);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.widgetWithText(AppBar, 'Patients'), findsNothing);
    expect(find.text('Live Metrics'), findsOneWidget);

    // Messages → conversation with the doctor → send.
    await tapTab(tester, 'Messages');
    await tapAndWait(
        tester, find.text(mockDoctor.name), const Duration(seconds: 1));
    expect(find.text('Good morning John. How are you feeling today?'),
        findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Feeling great today');
    await tester.pump(); // enables the send button
    await tapAndWait(
        tester, find.byIcon(Icons.send_rounded), const Duration(seconds: 6));
    // A sent bubble (Text), not the input field (EditableText), which is now empty.
    expect(
        find.byWidgetPredicate(
            (w) => w is Text && w.data == 'Feeling great today'),
        findsOneWidget);
    expect(
        find.byIcon(Icons.done_all_rounded), findsWidgets); // marked delivered
    expect(find.text(mockAutoReplies.first),
        findsOneWidget); // the doctor "replied"

    await stopApp(tester);
  });

  testWidgets('deep link while signed out returns there after login',
      (tester) async {
    await startApp(tester);
    router(tester).go(AppRoutes.chatDetailPath('conv-001'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Sign In'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'),
        'john@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'secret1');
    await tapAndWait(tester, find.text('Sign In'), const Duration(seconds: 3));

    expect(find.text('Good morning John. How are you feeling today?'),
        findsOneWidget);
    await stopApp(tester);
  });

  testWidgets(
      'callback request: nurse calls back, then refers and dispatches an ambulance',
      (tester) async {
    // Tall enough for every case card: Jane's simulated decline follows the
    // clock, so on some runs her case is in the queue above John's.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({
      'medivitallink.access_token': 'mock-access.$kJohnId.1',
      'medivitallink.refresh_token': 'mock-refresh.$kJohnId',
      'medivitallink.user': jsonEncode(mockPatient.toJson()),
    });
    await startApp(tester);
    await pumpFor(tester, const Duration(seconds: 1));

    // Patient: health banner is shown, one tap raises the request. Patients
    // can't ring the nurses directly: they ask, and the nurse calls back.
    expect(find.text('Stable'), findsOneWidget);
    expect(find.text('Call a nurse now'), findsNothing);
    await tapAndWait(
        tester, find.text('Request a callback'), const Duration(seconds: 2));
    expect(find.text('Callback requested'), findsOneWidget);

    // The (simulated) triage nurse calls back; the patient answers.
    await pumpFor(tester, const Duration(seconds: 8));
    expect(find.text('Incoming call'), findsOneWidget);
    expect(find.text('Triage nurse'), findsOneWidget);
    await tapAndWait(tester, find.text('Answer'), const Duration(seconds: 2));
    expect(find.textContaining(RegExp(r'^00:0\d$')), findsOneWidget); // talking
    await tapAndWait(tester, find.text('End'));
    expect(find.textContaining('Call ended'), findsOneWidget);
    await pumpFor(tester, const Duration(seconds: 3)); // closes by itself
    expect(find.text('A nurse is handling your case'), findsOneWidget);

    // Sign out, sign in as the nurse.
    await tapTab(tester, 'Account');
    await tester.scrollUntilVisible(find.text('Logout').hitTestable(), 200,
        scrollable: find.byType(Scrollable).last);
    await tapAndWait(tester, find.text('Logout'), const Duration(seconds: 2));
    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'),
        'grace@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'secret1');
    await tapAndWait(tester, find.text('Nurse'));
    await tapAndWait(tester, find.text('Sign In'), const Duration(seconds: 3));

    // Nurse: John's case is in the queue with the call on record.
    expect(find.widgetWithText(AppBar, 'Triage queue'), findsOneWidget);
    Finder johnCard() => find
        .ancestor(of: find.text('John Doe'), matching: find.byType(Column))
        .first;
    expect(
        find.descendant(
            of: johnCard(), matching: find.textContaining('Being handled')),
        findsOneWidget);
    expect(
        find.descendant(
            of: johnCard(), matching: find.textContaining('Last call: voice')),
        findsOneWidget);

    // She calls John (simulated answer), then refers him to a doctor.
    await tapAndWait(tester,
        find.descendant(of: johnCard(), matching: find.text('Call patient')));
    expect(find.text('Calling…'), findsOneWidget);
    await pumpFor(tester, const Duration(seconds: 4));
    expect(find.text('John Doe'), findsWidgets);
    expect(find.text('Heart rate'), findsOneWidget,
        reason: 'live vitals during the call');
    await tapAndWait(tester, find.text('End'));
    expect(find.text('What happens next?'), findsOneWidget);
    await tapAndWait(tester, find.text('Refer to doctor'));
    await tapAndWait(
        tester, find.widgetWithText(ElevatedButton, 'Refer to doctor'));
    expect(find.text('Say why you are referring the patient.'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField), 'Chest tightness, needs review');
    await tapAndWait(
        tester,
        find.widgetWithText(ElevatedButton, 'Refer to doctor'),
        const Duration(seconds: 2));
    expect(find.text('What happens next?'), findsNothing);
    expect(
        find.descendant(
            of: johnCard(),
            matching: find.textContaining('Referred to a doctor')),
        findsOneWidget);
    expect(find.text('“Chest tightness, needs review”'), findsOneWidget);

    // Things get worse: ambulance, from the queue without another call.
    await tapAndWait(tester,
        find.descendant(of: johnCard(), matching: find.text('Outcome')));
    await tapAndWait(tester, find.text('Dispatch ambulance'));
    expect(find.textContaining('no real ambulance is sent'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Suspected MI, at home');
    await tapAndWait(
        tester,
        find.widgetWithText(ElevatedButton, 'Dispatch ambulance'),
        const Duration(seconds: 2));
    expect(
        find.descendant(
            of: johnCard(),
            matching: find.textContaining('Ambulance dispatched')),
        findsOneWidget);

    await stopApp(tester);
  });
}
