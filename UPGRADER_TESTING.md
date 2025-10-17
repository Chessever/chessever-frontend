# Testing the Upgrader Dialog

## 🔍 How to See the Dialog During Development

The upgrader package checks the App Store/Play Store for a newer version. Here are the ways to test it:

### Option 1: Using `debugDisplayAlways` (Requires Valid App Store Listing)

**Current Status:** Enabled in [lib/widgets/custom_upgrade_alert.dart:53](lib/widgets/custom_upgrade_alert.dart#L53)

This will show the dialog if:
- Your app is listed on App Store/Play Store
- The version in the store is higher than your current app version in `pubspec.yaml`

**Current app version:** `5.3.0+91` (from pubspec.yaml)

### Option 2: Test with Lower Version Number (Recommended for Testing UI)

1. Open `pubspec.yaml`
2. Temporarily change the version to something lower, like:
   ```yaml
   version: 1.0.0+1
   ```
3. Run the app
4. The dialog should appear if there's a higher version in the store

### Option 3: Force Show Dialog with Mock Data (Best for UI Testing)

If you want to see the dialog immediately without relying on the store, you can temporarily modify the widget:

**Add this to [lib/widgets/custom_upgrade_alert.dart](lib/widgets/custom_upgrade_alert.dart):**

```dart
@override
Widget build(BuildContext context) {
  // TEMPORARY: Show dialog immediately for testing
  if (kDebugMode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTestDialog(context);
    });
  }

  // ... rest of existing code
}

// Add this method temporarily for testing
void _showTestDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => Theme(
      data: Theme.of(context).copyWith(
        dialogTheme: DialogThemeData(
          backgroundColor: kPopUpColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.sp),
          ),
          titleTextStyle: AppTypography.textXlBold.copyWith(
            color: kWhiteColor,
          ),
          contentTextStyle: AppTypography.textSmRegular.copyWith(
            color: kWhiteColor70,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kWhiteColor,
            padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 24.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.sp),
            ),
            textStyle: AppTypography.textMdMedium,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryColor,
            foregroundColor: kWhiteColor,
            padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 24.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.sp),
            ),
            textStyle: AppTypography.textMdBold,
            elevation: 0,
          ),
        ),
      ),
      child: AlertDialog(
        title: Text('Update Available'),
        content: Text('A new version of ChessEver is available. Update now to get the latest features and improvements.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Skip This Version'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Remind Me Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Update Now'),
          ),
        ],
      ),
    ),
  );
}
```

### Option 4: Check Console Logs

With `debugLogging: true` enabled, you'll see console output like:

```
upgrader: instantiated
upgrader: loading version info
upgrader: version info: {...}
upgrader: blocked: false
upgrader: shouldDisplayUpgrade: true/false
```

This helps you understand if the upgrader is working and why it might not show.

## 📱 What You Should See

When the dialog appears, it will show:
- ✅ Dark background (`kPopUpColor` - #111111)
- ✅ White top bar indicator
- ✅ Blue circular icon with update symbol
- ✅ "Update Available" title in white, bold
- ✅ Description text in white with 70% opacity
- ✅ Three buttons:
  1. **"Update Now"** - Blue primary button
  2. **"Remind Me Later"** - Outlined button
  3. **"Skip This Version"** - Text only button

## 🚀 For Production

**IMPORTANT:** Before releasing to production:

1. Set `debugDisplayAlways: false` in [lib/widgets/custom_upgrade_alert.dart](lib/widgets/custom_upgrade_alert.dart)
2. Remove the `Upgrader.clearSavedSettings()` call from [lib/main.dart](lib/main.dart)
3. Set a reasonable `durationUntilAlertAgain` (currently 1 day)

## 🔧 Current Configuration

- **Debug mode:** Shows always + clears settings on restart
- **Check frequency:** Once per day
- **Shows "Later" button:** Yes
- **Shows "Ignore" button:** Yes
- **Shows release notes:** No

## 📝 Troubleshooting

**Dialog not showing?**

1. Check console logs for `upgrader:` messages
2. Verify your app is on App Store/Play Store
3. Ensure store version > current version in pubspec.yaml
4. Try Option 2 or 3 above to force show the dialog

**Need to reset the dialog?**

The app already clears settings on each debug run via:
```dart
if (kDebugMode) {
  await Upgrader.clearSavedSettings();
}
```

This means each time you hot restart in debug mode, the upgrader state is reset.
