// Base repository interface providing common database access patterns
// All repositories inherit from this to ensure consistent error handling

import 'package:sqflite/sqflite.dart';
import '../services/database_service.dart';

/// Result type for repository operations - encapsulates success/failure
sealed class Result<T> {
  const Result();

  /// Check if the operation was successful
  bool get isSuccess => this is Success<T>;

  /// Check if the operation failed
  bool get isFailure => this is Failure<T>;

  /// Get the data if success, otherwise null
  T? get dataOrNull => switch (this) {
        Success<T>(data: final d) => d,
        Failure<T>() => null,
      };

  /// Get the error message if failure, otherwise null
  String? get errorMessage => switch (this) {
        Success<T>() => null,
        Failure<T>(message: final m) => m,
      };

  /// Transform the data if success
  Result<R> map<R>(R Function(T data) mapper) => switch (this) {
        Success<T>(data: final d) => Success(mapper(d)),
        Failure<T>(message: final m, error: final e) => Failure(m, e),
      };

  /// Handle both success and failure cases
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(String message, Object? error) onFailure,
  }) =>
      switch (this) {
        Success<T>(data: final d) => onSuccess(d),
        Failure<T>(message: final m, error: final e) => onFailure(m, e),
      };

  /// Get data or default value
  T getOrElse(T defaultValue) => switch (this) {
        Success<T>(data: final d) => d,
        Failure<T>() => defaultValue,
      };

  /// Get data or throw exception
  T getOrThrow() => switch (this) {
        Success<T>(data: final d) => d,
        Failure<T>(message: final m, error: final e) =>
          throw RepositoryException(m, e),
      };
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);

  @override
  String toString() => 'Success($data)';
}

class Failure<T> extends Result<T> {
  final String message;
  final Object? error;
  const Failure(this.message, [this.error]);

  @override
  String toString() => 'Failure: $message';
}

/// Exception thrown when repository operations fail
class RepositoryException implements Exception {
  final String message;
  final Object? cause;

  const RepositoryException(this.message, [this.cause]);

  @override
  String toString() => 'RepositoryException: $message';
}

/// Base repository with common database access
abstract class BaseRepository {
  /// Get the database instance
  Future<Database> get database async => DatabaseService.instance.database;

  /// Execute a database operation safely with error handling
  Future<Result<T>> safeExecute<T>(Future<T> Function() operation) async {
    try {
      final result = await operation();
      return Success(result);
    } catch (e) {
      return Failure(e.toString(), e);
    }
  }

  /// Execute a database transaction safely
  Future<Result<T>> safeTransaction<T>(
    Future<T> Function(Transaction txn) operation,
  ) async {
    try {
      final db = await database;
      final result = await db.transaction((txn) async {
        return await operation(txn);
      });
      return Success(result);
    } catch (e) {
      return Failure(e.toString(), e);
    }
  }
}
