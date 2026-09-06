import 'package:finance/models/family_member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initials', () {
    String of(String name) => FamilyMember(id: 'm', name: name).initials;

    test('two words give two letters, one word gives one', () {
      expect(of('Abdul Moiz'), 'AM');
      expect(of('Muhammad Abdul Moiz'), 'MA');
      // A lone letter cannot tell Abba from Ammi, so one word gives two.
      expect(of('Abba'), 'Ab');
      expect(of('Ammi'), 'Am');
      expect(of('Hamza'), 'Ha');
      expect(of('X'), 'X');
    });

    test('extra spaces and empty names do not crash it', () {
      expect(of('  Ammi  '), 'Am');
      expect(of('Abdul   Moiz'), 'AM');
      expect(of(' '), '?');
    });

    test('non-latin names keep their own letters', () {
      expect(of('عبدالمعز'), 'عب');
    });
  });

  group('serialisation', () {
    test('a member survives a round trip', () {
      final original = FamilyMember(
        id: 'm1',
        name: 'Abba',
        createdAt: DateTime(2026, 9, 1, 10, 30),
      );
      final copy = FamilyMember.fromJson(original.toJson())!;
      expect(copy.id, 'm1');
      expect(copy.name, 'Abba');
      expect(copy.createdAt, DateTime(2026, 9, 1, 10, 30));
    });

    test('rows without an id or a name are dropped, not guessed at', () {
      expect(FamilyMember.fromJson({'name': 'No id'}), isNull);
      expect(FamilyMember.fromJson({'id': 'm1'}), isNull);
      expect(FamilyMember.fromJson({'id': 'm1', 'name': '   '}), isNull);
    });

    test('renaming keeps the id and the created time', () {
      final original = FamilyMember(
        id: 'm1',
        name: 'Abba',
        createdAt: DateTime(2026, 9, 1),
      );
      final renamed = original.copyWith(name: 'Papa');
      expect(renamed.id, 'm1');
      expect(renamed.name, 'Papa');
      expect(renamed.createdAt, original.createdAt);
    });
  });

  group('member spend', () {
    test('a real person reads by name, an empty slot reads as Not set', () {
      final abba = FamilyMember(id: 'm1', name: 'Abba');
      const assigned = MemberSpend(member: null, total: 100, count: 1);
      expect(assigned.unassigned, isTrue);
      expect(assigned.name, 'Not set');
      expect(assigned.initials, '—');

      final theirs = MemberSpend(member: abba, total: 100, count: 1);
      expect(theirs.unassigned, isFalse);
      expect(theirs.name, 'Abba');
      expect(theirs.initials, 'Ab');
    });

    test('share is of the grand total, and zero cannot divide', () {
      const row = MemberSpend(member: null, total: 250, count: 2);
      expect(row.shareOf(1000), 0.25);
      expect(row.shareOf(0), 0);
      expect(row.shareOf(-5), 0);
    });
  });
}
