import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:i_am_astudent/database/db_helper.dart';

import '../constants/api_constants.dart';
import 'secure_session_service.dart';
import '../utils/connectivity_util.dart';

enum SyncState { idle, syncing, synced, offline, error }

class SyncStatus {
  const SyncStatus(this.state, {this.message, this.lastSyncedAt});

  final SyncState state;
  final String? message;
  final DateTime? lastSyncedAt;
}

/// Pushes locally queued records when a network connection becomes available.
/// The backend must treat record IDs as idempotency keys.
class SyncService {
  SyncService({http.Client? client}) : _client = client ?? http.Client();

  static final SyncService instance = SyncService();
  static const _tables = [
    'users',
    'quizzes',
    'questions',
    'user_scores',
    'offline_pdfs',
    'offline_textbooks',
  ];

  final http.Client _client;
  final ValueNotifier<SyncStatus> status = ValueNotifier(
    const SyncStatus(SyncState.idle),
  );
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Future<void>? _syncInProgress;
  String? _activeEmail;
  bool _started = false;

  Future<void> start({required String email}) async {
    if (_started) return;
    _activeEmail = email.trim().toLowerCase();
    _started = true;
    _subscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        if (results.any((result) => result != ConnectivityResult.none)) {
          unawaited(
            syncPending().catchError((Object error) {
              debugPrint('Automatic cloud sync failed: $error');
            }),
          );
        } else {
          status.value = const SyncStatus(
            SyncState.offline,
            message: 'Offline. Changes are saved on this device.',
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        status.value = SyncStatus(
          SyncState.error,
          message: 'Connectivity monitoring failed: $error',
        );
      },
    );
    try {
      if (await ConnectivityUtil.hasNetworkConnection()) {
        await syncPending();
      } else {
        status.value = const SyncStatus(
          SyncState.offline,
          message: 'Offline. Changes are saved on this device.',
        );
      }
    } catch (error) {
      status.value = SyncStatus(
        SyncState.error,
        message: 'Sync could not start. Local data is retained. $error',
      );
      rethrow;
    }
  }

  Future<void> syncPending() async {
    final active = _syncInProgress;
    if (active != null) return active;
    final future = _performSync();
    _syncInProgress = future;
    try {
      await future;
    } finally {
      if (identical(_syncInProgress, future)) _syncInProgress = null;
    }
  }

  Future<void> _performSync() async {
    if (!await ConnectivityUtil.hasNetworkConnection()) {
      status.value = const SyncStatus(
        SyncState.offline,
        message: 'Offline. Changes are saved on this device.',
      );
      return;
    }
    if (ApiConstants.apiBaseUrl.trim().isEmpty) {
      status.value = const SyncStatus(
        SyncState.offline,
        message: 'Cloud sync is not configured. Changes remain saved in the local database.',
      );
      return;
    }
    status.value = const SyncStatus(SyncState.syncing);
    try {
      final baseUrl = ApiConstants.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
      for (final table in _tables) {
        final records = await DbHelper.instance.getPendingRecords(table);
        if (records.isNotEmpty) {
          final response = await _client
              .post(
                Uri.parse('$baseUrl/sync/$table'),
                headers: await _requestHeaders(),
                body: jsonEncode({'records': records}),
              )
              .timeout(const Duration(seconds: 30));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw http.ClientException(
              'Sync of $table failed (${response.statusCode}): ${response.body}',
            );
          }
          await DbHelper.instance.markRecordsSynced(
            table,
            records.map((record) => record['id']! as String).toList(),
          );
        }

        final deletions = await DbHelper.instance.getPendingDeletions(table);
        if (deletions.isNotEmpty) {
          final response = await _client
              .post(
                Uri.parse('$baseUrl/sync/$table/delete'),
                headers: await _requestHeaders(),
                body: jsonEncode({
                  'records': deletions
                      .map((deletion) => {'id': deletion['record_id']})
                      .toList(),
                }),
              )
              .timeout(const Duration(seconds: 30));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw http.ClientException(
              'Deletion sync for $table failed (${response.statusCode}): '
              '${response.body}',
            );
          }
          await DbHelper.instance.markDeletionsSynced(
            deletions.map((deletion) => deletion['id']! as String).toList(),
          );
        }

        final cursor = await DbHelper.instance.getSetting('sync_cursor_$table');
        final pullUri = Uri.parse(
          '$baseUrl/sync/$table',
        ).replace(queryParameters: cursor == null ? null : {'cursor': cursor});
        final response = await _client
            .get(pullUri, headers: await _requestHeaders())
            .timeout(const Duration(seconds: 30));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw http.ClientException(
            'Download of $table failed (${response.statusCode}): '
            '${response.body}',
          );
        }
        final decoded = jsonDecode(response.body);
        final cloudRecords = decoded is List
            ? decoded
            : decoded is Map<String, dynamic>
            ? decoded['records']
            : null;
        if (cloudRecords is! List ||
            cloudRecords.any((record) => record is! Map<String, dynamic>)) {
          throw FormatException(
            'Cloud response for $table must contain a records array.',
          );
        }
        await DbHelper.instance.mergeSyncedRecords(
          table,
          cloudRecords.cast<Map<String, Object?>>(),
        );
        final nextCursor = decoded is Map<String, dynamic>
            ? decoded['next_cursor'] ?? decoded['nextCursor']
            : null;
        if (nextCursor is String && nextCursor.isNotEmpty) {
          await DbHelper.instance.saveSetting('sync_cursor_$table', nextCursor);
        }
      }
      status.value = SyncStatus(
        SyncState.synced,
        message: 'All pending data is synced.',
        lastSyncedAt: DateTime.now(),
      );
    } catch (error) {
      status.value = SyncStatus(
        SyncState.error,
        message: 'Sync failed. Your local data is retained. $error',
      );
      rethrow;
    }
  }

  Future<void> sendFeedback({
    required String email,
    required String message,
  }) async {
    if (ApiConstants.apiBaseUrl.trim().isEmpty) {
      throw StateError(
        'Feedback service is not configured. Set SAAMEP_API_BASE_URL.',
      );
    }
    final response = await _client
        .post(
          Uri.parse(
            '${ApiConstants.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}'
            '/support/feedback',
          ),
          headers: await _requestHeaders(),
          body: jsonEncode({'email': email, 'message': message}),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Feedback submission failed (${response.statusCode}).',
      );
    }
  }

  Future<Map<String, String>> _requestHeaders() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final email = _activeEmail;
    final token = email == null
        ? null
        : await SecureSessionService.instance.getAccessToken(email: email);
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
    _activeEmail = null;
    status.value = const SyncStatus(SyncState.idle);
  }
}
