# Alarm Sounds

This folder contains alarm sound files for the reminder system.

## Adding Custom Alarm Sounds

1. Add `.mp3` files to this folder
2. Recommended: `alarm_sound.mp3` (default alarm sound)
3. Format: MP3, 44100 Hz, stereo
4. Duration: 3-10 seconds (will loop)

## Default Sound

If no custom sound is provided, the app uses the system default notification sound.

## For Android

To use custom sounds with notifications:
1. Place `.mp3` files in `android/app/src/main/res/raw/`
2. Reference as `RawResourceAndroidNotificationSound('filename')` (without extension)

## Current Setup

The app uses `flutter_local_notifications` with:
- Maximum importance for alarm notifications
- Full-screen intent for urgent alarms
- System default sound as fallback
