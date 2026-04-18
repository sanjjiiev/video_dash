import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hub_streaming/app.dart';
import 'package:hub_streaming/core/network/api_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // media_kit MUST be initialized before any Player/Video widget is used
  MediaKit.ensureInitialized();

  // Initialize SharedPreferences once at startup and inject via ProviderScope.
  // This satisfies the sharedPreferencesProvider override required by ApiClient.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const HubApp(),
    ),
  );
}
