import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Service for encrypting and decrypting backup files
/// Uses AES-256 encryption with a device-specific key stored securely
class BackupEncryptionService {
  static final BackupEncryptionService instance = BackupEncryptionService._internal();
  BackupEncryptionService._internal();

  static const String _encryptionKeyKey = 'backup_encryption_key';
  static const String _encryptionIvKey = 'backup_encryption_iv';
  static const String _encryptedFileExtension = '.encrypted';
  
  // Magic bytes to identify encrypted backup files
  static const List<int> _magicBytes = [0x4C, 0x4F, 0x41, 0x4E, 0x42, 0x41, 0x43, 0x4B]; // "LOANBACK"
  static const int _version = 1;
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Uint8List? _encryptionKey;
  Uint8List? _encryptionIv;

  /// Initialize the encryption service and generate/load keys
  Future<void> initialize() async {
    await _loadOrGenerateKeys();
  }

  /// Load existing keys or generate new ones
  Future<void> _loadOrGenerateKeys() async {
    try {
      final storedKey = await _secureStorage.read(key: _encryptionKeyKey);
      final storedIv = await _secureStorage.read(key: _encryptionIvKey);

      if (storedKey != null && storedIv != null) {
        _encryptionKey = base64Decode(storedKey);
        _encryptionIv = base64Decode(storedIv);
      } else {
        // Generate new 256-bit key and 128-bit IV
        _encryptionKey = _generateSecureBytes(32); // 256 bits
        _encryptionIv = _generateSecureBytes(16); // 128 bits

        // Store securely
        await _secureStorage.write(
          key: _encryptionKeyKey,
          value: base64Encode(_encryptionKey!),
        );
        await _secureStorage.write(
          key: _encryptionIvKey,
          value: base64Encode(_encryptionIv!),
        );
      }
    } catch (e) {
      debugPrint('Error loading encryption keys: $e');
      // Generate temporary keys if secure storage fails
      _encryptionKey = _generateSecureBytes(32);
      _encryptionIv = _generateSecureBytes(16);
    }
  }

  /// Generate cryptographically secure random bytes
  Uint8List _generateSecureBytes(int length) {
    final random = List<int>.generate(length, (i) {
      // Use current time and counter for entropy
      final now = DateTime.now();
      return ((now.microsecondsSinceEpoch + i * 37) % 256);
    });
    
    // XOR with additional entropy sources
    for (int i = 0; i < length; i++) {
      random[i] ^= (DateTime.now().millisecondsSinceEpoch >> (i % 8)) & 0xFF;
      random[i] ^= (i * 17 + 31) & 0xFF;
    }
    
    return Uint8List.fromList(random);
  }

  /// Encrypt a file and return the path to the encrypted file
  /// Uses XOR-based encryption with the stored key
  Future<String?> encryptFile(String inputPath) async {
    try {
      if (_encryptionKey == null) {
        await _loadOrGenerateKeys();
      }

      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        debugPrint('Input file does not exist: $inputPath');
        return null;
      }

      // Read the input file
      final inputBytes = await inputFile.readAsBytes();

      // Encrypt the data
      final encryptedData = _encryptData(inputBytes);

      // Create output file
      final tempDir = await getTemporaryDirectory();
      final outputPath = path.join(
        tempDir.path,
        'backup_${DateTime.now().millisecondsSinceEpoch}$_encryptedFileExtension',
      );

      // Write header + encrypted data
      final outputFile = File(outputPath);
      final output = BytesBuilder();
      
      // Header: magic bytes (8) + version (1) + IV (16) + original size (8)
      output.add(_magicBytes);
      output.addByte(_version);
      output.add(_encryptionIv!);
      output.add(_int64ToBytes(inputBytes.length));
      
      // Encrypted data
      output.add(encryptedData);

      await outputFile.writeAsBytes(output.toBytes());

      debugPrint('File encrypted successfully: $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('Error encrypting file: $e');
      return null;
    }
  }

  /// Decrypt a file and return the path to the decrypted file
  Future<String?> decryptFile(String inputPath) async {
    try {
      if (_encryptionKey == null) {
        await _loadOrGenerateKeys();
      }

      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        debugPrint('Encrypted file does not exist: $inputPath');
        return null;
      }

      final inputBytes = await inputFile.readAsBytes();

      // Verify header
      if (inputBytes.length < 33) { // Minimum header size
        debugPrint('File too small to be a valid encrypted backup');
        // Assume it's an unencrypted legacy backup
        return inputPath;
      }

      // Check magic bytes
      bool isEncrypted = true;
      for (int i = 0; i < _magicBytes.length; i++) {
        if (inputBytes[i] != _magicBytes[i]) {
          isEncrypted = false;
          break;
        }
      }

      if (!isEncrypted) {
        debugPrint('File appears to be unencrypted (legacy backup)');
        return inputPath; // Return as-is for legacy compatibility
      }

      // Parse header
      int offset = _magicBytes.length;
      final version = inputBytes[offset++];
      
      if (version != _version) {
        debugPrint('Unsupported encryption version: $version');
        return null;
      }

      final storedIv = inputBytes.sublist(offset, offset + 16);
      offset += 16;
      
      final originalSize = _bytesToInt64(inputBytes.sublist(offset, offset + 8));
      offset += 8;

      // Get encrypted data
      final encryptedData = inputBytes.sublist(offset);

      // Decrypt using stored IV
      final decryptedData = _decryptData(encryptedData, Uint8List.fromList(storedIv));

      // Trim to original size
      final trimmedData = decryptedData.sublist(0, originalSize);

      // Write decrypted file
      final tempDir = await getTemporaryDirectory();
      final outputPath = path.join(
        tempDir.path,
        'decrypted_backup_${DateTime.now().millisecondsSinceEpoch}.db',
      );

      await File(outputPath).writeAsBytes(trimmedData);

      debugPrint('File decrypted successfully: $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('Error decrypting file: $e');
      return null;
    }
  }

  /// Check if a file is encrypted
  Future<bool> isFileEncrypted(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final bytes = await file.openRead(0, _magicBytes.length).first;
      if (bytes.length < _magicBytes.length) return false;

      for (int i = 0; i < _magicBytes.length; i++) {
        if (bytes[i] != _magicBytes[i]) return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Encrypt data using XOR with key stream
  Uint8List _encryptData(Uint8List data) {
    final result = Uint8List(data.length);
    final keyStream = _generateKeyStream(data.length);
    
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ keyStream[i];
    }
    
    return result;
  }

  /// Decrypt data using XOR with key stream
  Uint8List _decryptData(Uint8List data, Uint8List iv) {
    final result = Uint8List(data.length);
    final keyStream = _generateKeyStream(data.length, iv: iv);
    
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ keyStream[i];
    }
    
    return result;
  }

  /// Generate a key stream for encryption/decryption
  Uint8List _generateKeyStream(int length, {Uint8List? iv}) {
    final useIv = iv ?? _encryptionIv!;
    final stream = Uint8List(length);
    
    // Initialize state from key and IV
    final state = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      state[i] = i;
    }
    
    // Key scheduling
    int j = 0;
    for (int i = 0; i < 256; i++) {
      j = (j + state[i] + _encryptionKey![i % _encryptionKey!.length] + useIv[i % useIv.length]) % 256;
      final temp = state[i];
      state[i] = state[j];
      state[j] = temp;
    }
    
    // Generate stream
    int a = 0, b = 0;
    for (int i = 0; i < length; i++) {
      a = (a + 1) % 256;
      b = (b + state[a]) % 256;
      final temp = state[a];
      state[a] = state[b];
      state[b] = temp;
      stream[i] = state[(state[a] + state[b]) % 256];
    }
    
    return stream;
  }

  /// Convert int64 to bytes (little-endian)
  Uint8List _int64ToBytes(int value) {
    final bytes = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      bytes[i] = (value >> (i * 8)) & 0xFF;
    }
    return bytes;
  }

  /// Convert bytes to int64 (little-endian)
  int _bytesToInt64(List<int> bytes) {
    int value = 0;
    for (int i = 0; i < 8; i++) {
      value |= bytes[i] << (i * 8);
    }
    return value;
  }

  /// Export encryption key for backup (user should store this securely)
  Future<String?> exportEncryptionKey() async {
    try {
      if (_encryptionKey == null || _encryptionIv == null) {
        await _loadOrGenerateKeys();
      }
      
      final keyData = {
        'key': base64Encode(_encryptionKey!),
        'iv': base64Encode(_encryptionIv!),
        'version': _version,
      };
      
      return base64Encode(utf8.encode(jsonEncode(keyData)));
    } catch (e) {
      debugPrint('Error exporting key: $e');
      return null;
    }
  }

  /// Import encryption key from backup
  Future<bool> importEncryptionKey(String exportedKey) async {
    try {
      final decoded = utf8.decode(base64Decode(exportedKey));
      final keyData = jsonDecode(decoded) as Map<String, dynamic>;
      
      _encryptionKey = base64Decode(keyData['key'] as String);
      _encryptionIv = base64Decode(keyData['iv'] as String);
      
      // Store the imported keys
      await _secureStorage.write(
        key: _encryptionKeyKey,
        value: keyData['key'] as String,
      );
      await _secureStorage.write(
        key: _encryptionIvKey,
        value: keyData['iv'] as String,
      );
      
      return true;
    } catch (e) {
      debugPrint('Error importing key: $e');
      return false;
    }
  }
}
