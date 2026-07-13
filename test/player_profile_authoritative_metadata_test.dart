import 'package:chessever2/screens/player_profile/player_profile_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Supabase metadata overrides stale TWIC profile metadata', () async {
    const twicPlayer = PlayerProfileMetadata(
      fideId: 1503014,
      name: 'Stale TWIC Name',
      federation: 'OLD',
      title: 'IM',
      classicalRating: 2701,
      rapidRating: 2702,
      blitzRating: 2703,
      classicalGames: 10,
      rapidGames: 11,
      blitzGames: 12,
      birthday: '1980',
      sex: 'M',
    );
    const supabasePlayer = PlayerProfileMetadata(
      fideId: 1503014,
      name: 'Current Supabase Name',
      federation: 'USA',
      title: 'GM',
      classicalRating: 2837,
      rapidRating: 2777,
      blitzRating: 2811,
      classicalGames: 25,
      rapidGames: 26,
      blitzGames: 27,
      birthday: '1990',
      sex: 'F',
    );
    final profile = resolvePlayerProfileMetadata(
      fallback: twicPlayer,
      authoritative: supabasePlayer,
    );

    expect(profile.name, 'Current Supabase Name');
    expect(profile.title, 'GM');
    expect(profile.federation, 'USA');
    expect(profile.classicalRating, 2837);
    expect(profile.rapidRating, 2777);
    expect(profile.blitzRating, 2811);
    expect(profile.classicalGames, 25);
    expect(profile.rapidGames, 26);
    expect(profile.blitzGames, 27);
    expect(profile.birthday, '1990');
    expect(profile.sex, 'F');
  });

  test('missing Supabase fields preserve usable TWIC metadata', () {
    const twicPlayer = PlayerProfileMetadata(
      fideId: 1503014,
      name: 'TWIC Name',
      federation: 'NOR',
      title: 'GM',
      classicalRating: 2800,
      rapidRating: 2700,
      blitzRating: 2750,
      classicalGames: 10,
      birthday: '1990',
      sex: 'M',
    );
    const partialSupabasePlayer = PlayerProfileMetadata(
      fideId: 1503014,
      name: '  ',
      federation: '',
      classicalRating: 0,
      rapidGames: 0,
    );

    final profile = resolvePlayerProfileMetadata(
      fallback: twicPlayer,
      authoritative: partialSupabasePlayer,
    );

    expect(profile.name, 'TWIC Name');
    expect(profile.federation, 'NOR');
    expect(profile.title, 'GM');
    expect(profile.classicalRating, 2800);
    expect(profile.rapidRating, 2700);
    expect(profile.blitzRating, 2750);
    expect(profile.classicalGames, 10);
    expect(profile.rapidGames, 0);
    expect(profile.birthday, '1990');
    expect(profile.sex, 'M');
  });
}
