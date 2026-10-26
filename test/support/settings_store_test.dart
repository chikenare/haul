import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const defaults = HaulSettings(merge: true, wifiOnly: true);
  const store = HaulSettingsStore(key: 'k', defaults: defaults);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the defaults until something is stored', () async {
    expect(await store.load(), defaults);
  });

  test('the controller saves every change, and loads what was saved', () async {
    final settings = store.controller();
    expect(settings.value, defaults);
    settings.update(
      (s) => s.copyWith(destination: const HaulDestination.app()),
    );
    await Future<void>.delayed(Duration.zero);

    final again = store.controller();
    await store.loadInto(again);
    expect(again.value.destination, const HaulDestination.app());
    expect(again.value.merge, isTrue);
  });

  test('what cannot be read is the defaults', () async {
    SharedPreferences.setMockInitialValues({'k': '{not json'});
    expect(await store.load(), defaults);
  });
}
