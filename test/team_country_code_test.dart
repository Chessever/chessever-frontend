import 'package:chessever2/widgets/team_country_code.dart';
import 'package:chessever2/widgets/team_crest_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveTeamCountryCode', () {
    test('returns ISO2 for known country names', () {
      expect(resolveTeamCountryCode('Norway'), 'NO');
      expect(resolveTeamCountryCode('India'), 'IN');
      expect(resolveTeamCountryCode('  Germany  '), 'DE');
    });

    test('returns ISO2 for federation / ISO codes used as team names', () {
      // Olympiad-style squad labels.
      expect(resolveTeamCountryCode('USA'), 'US');
      expect(resolveTeamCountryCode('usa'), 'US');
      expect(resolveTeamCountryCode('IND'), 'IN');
      expect(resolveTeamCountryCode('US'), 'US');
    });

    test('returns null for club-style non-country names', () {
      expect(resolveTeamCountryCode('ΣΟ ΚΑΒΑΛΑΣ'), isNull);
      expect(resolveTeamCountryCode('Marseille'), isNull);
      expect(
        resolveTeamCountryCode('UGANDA - Sr. Miriam Duggan Primary School'),
        isNull,
      );
      expect(resolveTeamCountryCode('AL RUSTAQ - A'), isNull);
    });

    test('returns null for empty / whitespace', () {
      expect(resolveTeamCountryCode(''), isNull);
      expect(resolveTeamCountryCode('   '), isNull);
    });
  });

  group('TeamCrestAvatar.showsFlagFor', () {
    test('mirrors resolve for country vs club', () {
      expect(TeamCrestAvatar.showsFlagFor('USA'), isTrue);
      expect(TeamCrestAvatar.showsFlagFor('Norway'), isTrue);
      expect(TeamCrestAvatar.showsFlagFor('ΠΑΝΑΘΗΝΑΪΚΟΣ ΑΟ'), isFalse);
    });
  });
}
