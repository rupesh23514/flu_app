package com.example.flu_app

import android.media.AudioManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.os.PowerManager
import android.app.KeyguardManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "flu_app/audio_mode"
    private val SERVICE_CHANNEL = "flu_app/foreground_service"
    private val ALARM_CHANNEL = "flu_app/alarm_player"
    private val LOCK_SCREEN_CHANNEL = "flu_app/lock_screen"
    private val OEM_CHANNEL = "flu_app/oem_settings"
    
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Audio mode channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getRingerMode") {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val ringerMode = audioManager.ringerMode
                // 0 = RINGER_MODE_SILENT, 1 = RINGER_MODE_VIBRATE, 2 = RINGER_MODE_NORMAL
                result.success(ringerMode)
            } else {
                result.notImplemented()
            }
        }
        
        // 🔐 Lock Screen Channel - Check if device is locked
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCK_SCREEN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeviceLocked" -> {
                    try {
                        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                        val isLocked = keyguardManager.isKeyguardLocked
                        android.util.Log.d("LockScreen", "🔐 Device locked: $isLocked")
                        result.success(isLocked)
                    } catch (e: Exception) {
                        android.util.Log.e("LockScreen", "Error checking lock state: ${e.message}")
                        result.error("LOCK_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 🏆 Alarm Player Channel - Uses ALARM stream (bypasses silent/vibrate mode)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playAlarmSound" -> {
                    try {
                        val volume = call.argument<Double>("volume") ?: 1.0
                        playAlarmThroughAlarmStream(volume.toFloat())
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ALARM_ERROR", e.message, null)
                    }
                }
                "stopAlarmSound" -> {
                    try {
                        stopAlarmPlayer()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ALARM_ERROR", e.message, null)
                    }
                }
                "vibrateAlarm" -> {
                    try {
                        vibrateForAlarm()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VIBRATE_ERROR", e.message, null)
                    }
                }
                "stopVibrate" -> {
                    try {
                        stopVibration()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VIBRATE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // Foreground service channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    try {
                        AlarmForegroundService.startService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        AlarmForegroundService.stopService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER.lowercase())
                }
                else -> result.notImplemented()
            }
        }
        
        // OEM Settings Channel - Programmatically open device-specific settings
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OEM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAutoStartSettings" -> {
                    val opened = openAutoStartSettings()
                    result.success(opened)
                }
                "openBatterySettings" -> {
                    val opened = openBatterySettings()
                    result.success(opened)
                }
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }
                "requestIgnoreBatteryOptimization" -> {
                    val requested = requestIgnoreBatteryOptimization()
                    result.success(requested)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    /**
     * 🏆 LEGENDARY: Play alarm through ALARM audio stream
     * This bypasses silent mode and plays even when phone is muted
     */
    private fun playAlarmThroughAlarmStream(volume: Float) {
        stopAlarmPlayer() // Stop any existing playback
        
        try {
            mediaPlayer = MediaPlayer().apply {
                // Use ALARM stream which bypasses silent mode
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                
                // Try to load custom alarm sound from raw resources
                try {
                    val resId = resources.getIdentifier("alarm_sound", "raw", packageName)
                    if (resId != 0) {
                        val afd = resources.openRawResourceFd(resId)
                        setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                        afd.close()
                    } else {
                        // Fallback to system alarm sound
                        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        setDataSource(this@MainActivity, alarmUri)
                    }
                } catch (e: Exception) {
                    // Fallback to system alarm sound
                    val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    setDataSource(this@MainActivity, alarmUri)
                }
                
                isLooping = true
                setVolume(volume, volume)
                
                // Use async prepare to avoid blocking UI thread (prevents ANR)
                setOnPreparedListener { mp ->
                    mp.start()
                    android.util.Log.d("AlarmPlayer", "🔔 Alarm sound playing through ALARM stream (bypasses silent mode)")
                }
                setOnErrorListener { _, what, extra ->
                    android.util.Log.e("AlarmPlayer", "MediaPlayer error: what=$what extra=$extra")
                    true
                }
                prepareAsync()
            }
        } catch (e: Exception) {
            android.util.Log.e("AlarmPlayer", "Error playing alarm: ${e.message}")
        }
    }
    
    private fun stopAlarmPlayer() {
        try {
            mediaPlayer?.apply {
                if (isPlaying) {
                    stop()
                }
                release()
            }
            mediaPlayer = null
            android.util.Log.d("AlarmPlayer", "🔕 Alarm sound stopped")
        } catch (e: Exception) {
            android.util.Log.e("AlarmPlayer", "Error stopping alarm: ${e.message}")
        }
    }
    
    /**
     * Vibrate pattern for alarm - works even in silent mode
     */
    private fun vibrateForAlarm() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        
        // Vibration pattern: wait 0ms, vibrate 500ms, wait 200ms, vibrate 500ms, repeat
        val pattern = longArrayOf(0, 500, 200, 500, 200, 500, 200, 500)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0)) // 0 = repeat from start
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, 0)
        }
        
        android.util.Log.d("AlarmPlayer", "📳 Alarm vibration started")
    }
    
    private fun stopVibration() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        
        vibrator.cancel()
        android.util.Log.d("AlarmPlayer", "📳 Alarm vibration stopped")
    }
    
    /**
     * Open device-specific autostart settings
     * Supports Vivo, Xiaomi, Oppo, Huawei, Samsung, and other OEMs
     */
    private fun openAutoStartSettings(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        android.util.Log.d("OemSettings", "📱 Opening autostart for manufacturer: $manufacturer")
        
        val intents = mutableListOf<Intent>()
        
        when {
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> {
                // Vivo/iQOO specific intents
                intents.add(Intent().setComponent(ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                )))
                intents.add(Intent().setComponent(ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"
                )))
                intents.add(Intent().setComponent(ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.PurviewTabActivity"
                )))
                intents.add(Intent().setComponent(ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                )))
                // i Manager autostart
                intents.add(Intent().setComponent(ComponentName(
                    "com.vivo.abe",
                    "com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity"
                )))
            }
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") || manufacturer.contains("poco") -> {
                intents.add(Intent().setComponent(ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )))
                intents.add(Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT))
            }
            manufacturer.contains("oppo") || manufacturer.contains("realme") -> {
                intents.add(Intent().setComponent(ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )))
                intents.add(Intent().setComponent(ComponentName(
                    "com.oppo.safe",
                    "com.oppo.safe.permission.startup.StartupAppListActivity"
                )))
                intents.add(Intent().setComponent(ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.startupapp.StartupAppListActivity"
                )))
            }
            manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
                intents.add(Intent().setComponent(ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                )))
                intents.add(Intent().setComponent(ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity"
                )))
                intents.add(Intent().setComponent(ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity"
                )))
            }
            manufacturer.contains("samsung") -> {
                intents.add(Intent().setComponent(ComponentName(
                    "com.samsung.android.lool",
                    "com.samsung.android.sm.ui.battery.BatteryActivity"
                )))
                intents.add(Intent().setComponent(ComponentName(
                    "com.samsung.android.sm",
                    "com.samsung.android.sm.ui.battery.BatteryActivity"
                )))
            }
            manufacturer.contains("asus") -> {
                intents.add(Intent().setComponent(ComponentName(
                    "com.asus.mobilemanager",
                    "com.asus.mobilemanager.autostart.AutoStartActivity"
                )))
                intents.add(Intent().setComponent(ComponentName(
                    "com.asus.mobilemanager",
                    "com.asus.mobilemanager.entry.FunctionActivity"
                )))
            }
            manufacturer.contains("oneplus") -> {
                intents.add(Intent().setComponent(ComponentName(
                    "com.oneplus.security",
                    "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
                )))
            }
        }
        
        // Try each intent
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                android.util.Log.d("OemSettings", "✅ Successfully opened: ${intent.component}")
                return true
            } catch (e: Exception) {
                android.util.Log.d("OemSettings", "⚠️ Intent failed: ${intent.component}")
            }
        }
        
        // Fallback: Open app settings
        android.util.Log.d("OemSettings", "⚠️ No OEM autostart found, opening app settings")
        openAppSettings()
        return false
    }
    
    /**
     * Open battery optimization settings
     */
    private fun openBatterySettings(): Boolean {
        try {
            // First try: Request ignore battery optimizations (shows popup)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val packageName = packageName
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    return true
                }
            }
            
            // Already ignoring, open battery settings
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return true
        } catch (e: Exception) {
            android.util.Log.e("OemSettings", "Error opening battery settings: ${e.message}")
            // Fallback to general battery settings
            try {
                val intent = Intent(Intent.ACTION_POWER_USAGE_SUMMARY).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return true
            } catch (e2: Exception) {
                return false
            }
        }
    }
    
    /**
     * Open app-specific settings
     */
    private fun openAppSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.e("OemSettings", "Error opening app settings: ${e.message}")
        }
    }
    
    /**
     * Request to ignore battery optimization (shows system dialog)
     */
    private fun requestIgnoreBatteryOptimization(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    return true
                }
                return false // Already ignoring
            } catch (e: Exception) {
                android.util.Log.e("OemSettings", "Error requesting battery optimization: ${e.message}")
                return false
            }
        }
        return false
    }
    
    override fun onDestroy() {
        stopAlarmPlayer()
        stopVibration()  // Fix: Stop vibration to prevent hardware resource leak
        super.onDestroy()
    }
}
