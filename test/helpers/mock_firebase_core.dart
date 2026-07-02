// ⚠️ NOT CURRENTLY USED — kept only as a note of what NOT to do.
//
// This mocks the firebase_core init channel enough to make
// `Firebase.initializeApp()` succeed in a test, which sounds useful but is
// actually dangerous on its own: once `Firebase.apps.isNotEmpty` is true,
// any code that gates real Firestore/Auth calls on "is Firebase ready"
// (e.g. ReactionWheelNotifier, various sync providers) will actually attempt
// those calls against a fake, non-existent project — and Firestore/Auth SDK
// calls tend to hang or retry for a long time rather than fail fast when
// there's no real backend, unlike an unmocked platform channel (which throws
// MissingPluginException immediately).
//
// This caused a 7+ minute test hang in `test/app/app_routing_test.dart`
// (the "StackAndFlowApp bootstrap..." test) — DO NOT reuse this helper for
// any widget that reaches `StackAndFlowApp.build()` (or any other widget
// that watches Firestore-backed providers) without ALSO mocking/overriding
// every downstream Firestore/Auth call it triggers. That is a much bigger
// undertaking than this file alone provides — do it deliberately, not by
// wiring this in and hoping.
//
// If you do want full Firebase mocking for a widget test later, override
// each Firebase-touching Riverpod provider explicitly (as
// `test/app/app_routing_test.dart`'s `_routingOverrides` already does for
// `authProfileSyncProvider` / `cardStyleFirestoreSyncProvider`) rather than
// trying to make the real Firebase SDKs believe they're live.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void mockFirebaseCoreChannel() {
  const channel = MethodChannel('plugins.flutter.io/firebase_core');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    switch (call.method) {
      case 'Firebase#initializeCore':
        return [_fakeApp];
      case 'Firebase#initializeApp':
        return _fakeApp;
      default:
        return null;
    }
  });
}

const Map<String, Object?> _fakeApp = {
  'name': '[DEFAULT]',
  'options': {
    'apiKey': 'fake-api-key',
    'appId': '1:1234567890:android:abcdef1234567890',
    'messagingSenderId': '1234567890',
    'projectId': 'last-cards-test',
  },
  'pluginConstants': <String, Object?>{},
};
