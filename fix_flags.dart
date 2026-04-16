import 'dart:io';

void main() {
  var dir = Directory('lib');
  var files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  
  for (var file in files) {
    var content = file.readAsStringSync();
    if (content.contains('CountryFlag.fromCountryCode(')) {
      String original = content;

      // Extremely simple regex: just find width: x, height: y, shape: z inside CountryFlag.fromCountryCode(...)
      // Let's do it using a loop and a custom parser.
      var regex = RegExp(r'CountryFlag\.fromCountryCode\s*\((.*?)\)', dotAll: true);
      
      content = content.replaceAllMapped(regex, (match) {
        String inside = match[1]!;
        
        // Parse out the country code (it's the first positional argument, usually everything before the first named argument)
        // Let's assume the country code doesn't contain comma.
        int firstComma = inside.indexOf(',');
        if (firstComma == -1) return match[0]!; // No other arguments
        
        String countryCode = inside.substring(0, firstComma).trim();
        String rest = inside.substring(firstComma + 1).trim();
        
        // If it already has "theme:", don't touch it
        if (rest.contains('theme:')) return match[0]!;
        
        // Create an ImageTheme
        // Extract width, height, shape from `rest`
        String newRest = rest;
        // Since we are just wrapping all existing properties (width, height, shape) into `theme: ImageTheme(...)`,
        // and we know those are the ONLY arguments passed in our codebase...
        // Let's just wrap `rest` in `theme: const ImageTheme(...)`? 
        // No, some might have `width: 20.w, height: 14.h`, some might have `shape: const RoundedRectangle(12)`.
        // Let's just replace the whole `rest` with `theme: ImageTheme($rest)` 
        // Wait, if `rest` has `shape:`, it will be `theme: ImageTheme(..., shape: ...)`. This is perfect!
        // Are there any other arguments in `rest`? No, we only ever used width, height, shape.
        return 'CountryFlag.fromCountryCode(\n$countryCode,\n  theme: ImageTheme($rest),\n)';
      });
      
      if (content != original) {
        file.writeAsStringSync(content);
        print('Updated ${file.path}');
      }
    }
  }
}
