# App Icon Setup

## Instructions to Change App Icon

1. **Save your green "G" logo image** as `app_icon.png` in this folder (`assets/icons/`)
   - Image should be at least 1024x1024 pixels for best quality
   - Use PNG format with transparent background (recommended)
   - Square aspect ratio (1:1)

2. **Run the following commands** in your terminal:
   ```bash
   flutter pub get
   dart run flutter_launcher_icons
   ```

3. **Rebuild your app**:
   ```bash
   flutter clean
   flutter build apk
   ```

## Icon Requirements
- Minimum size: 512x512 pixels
- Recommended size: 1024x1024 pixels
- Format: PNG
- Square aspect ratio

The flutter_launcher_icons package will automatically generate all required sizes for:
- Android (mipmap folders)
- iOS (AppIcon.appiconset)
