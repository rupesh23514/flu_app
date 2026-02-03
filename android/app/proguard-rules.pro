# Flutter Local Notifications - prevent stripping
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }

# Android Alarm Manager Plus - prevent stripping
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }
-keep class io.flutter.** { *; }

# Keep all notification related classes
-keep class androidx.core.app.NotificationCompat** { *; }
-keep class androidx.core.app.NotificationManagerCompat { *; }

# Keep alarm receivers and services
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver { *; }
-keep class com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver { *; }

# Keep your custom foreground service
-keep class com.example.flu_app.AlarmForegroundService { *; }
-keep class com.example.flu_app.MainActivity { *; }

# Keep R8 from stripping Flutter entry points
-keepattributes *Annotation*
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# Prevent stripping of alarm/notification resources
-keepclassmembers class **.R$* {
    public static <fields>;
}
