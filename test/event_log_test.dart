import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/event_log.dart';

void main() {
  setUp(() => EventLog.instance.clear());

  test('records entries and exports them oldest-first', () {
    EventLog.instance.add('first');
    EventLog.instance.add('second', level: EventLevel.warn);
    final out = EventLog.instance.export(header: 'LanLink diagnostics');
    expect(out, contains('LanLink diagnostics'));
    expect(out.indexOf('first'), lessThan(out.indexOf('second')));
    expect(out, contains('WARN'));
  });

  test('ring buffer caps at maxEntries, dropping the oldest', () {
    for (var i = 0; i < EventLog.maxEntries + 25; i++) {
      EventLog.instance.add('line $i');
    }
    final entries = EventLog.instance.entries;
    expect(entries.length, EventLog.maxEntries);
    expect(entries.first.message, 'line 25');
    expect(entries.last.message, 'line ${EventLog.maxEntries + 24}');
  });

  test('clear empties the buffer', () {
    EventLog.instance.add('x');
    EventLog.instance.clear();
    expect(EventLog.instance.entries, isEmpty);
    expect(EventLog.instance.export(), isEmpty);
  });
}
