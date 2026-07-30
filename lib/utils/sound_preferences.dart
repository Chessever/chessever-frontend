enum SoundTheme {
  standard('Standard', 'standard'),
  lichess('Lichess', 'standard'),
  piano('Piano', 'piano'),
  nes('NES', 'nes'),
  sfx('SFX', 'sfx'),
  futuristic('Futuristic', 'futuristic'),
  lisp('Lisp', 'lisp');

  const SoundTheme(this.label, this.assetDirectory);

  final String label;
  final String assetDirectory;

  static SoundTheme fromIndex(int index) {
    if (index < 0 || index >= SoundTheme.values.length) {
      return SoundTheme.standard;
    }
    return SoundTheme.values[index];
  }
}

const double kDefaultSoundVolume = 0.7;
