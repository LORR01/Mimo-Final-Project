import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'data/services.dart';
import 'data/agent_client.dart';
import 'state/mimo_store.dart';
import 'ui/mimo_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const demo = bool.fromEnvironment('MIMO_DEMO');
  final store = MimoStore(
    repository: PreferencesRepository(),
    liveMode: !demo,
    configuredGateway: kIsWeb && Uri.base.scheme == 'https'
        ? Uri.base.origin
        : const String.fromEnvironment('MIMO_AGENT_URL'),
    discovery: demo ? const MockDeviceDiscovery() : AgentClient(),
  );
  await store.initialize();
  runApp(MimoApp(store: store));
  if (!demo) {
    const configured = String.fromEnvironment('MIMO_AGENT_URL');
    final endpoint = kIsWeb && Uri.base.scheme == 'https'
        ? Uri.base.origin
        : store.gatewayUrl.isNotEmpty
        ? store.gatewayUrl
        : configured;
    if (endpoint.isNotEmpty) {
      store.gatewayUrl = endpoint;
      unawaited(store.connectAgent(endpoint));
    }
  }
}
