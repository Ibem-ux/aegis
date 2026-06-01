import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:dio/dio.dart';

const uploadTaskKey = 'aegis.upload.task';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == uploadTaskKey && inputData != null) {
      try {
        final filePath = inputData['filePath'] as String;
        final uploadUrl = inputData['uploadUrl'] as String;
        
        final file = File(filePath);
        if (!await file.exists()) {
          return true; // File doesn't exist, ignore task
        }

        final fileBytes = await file.readAsBytes();

        final dio = Dio();
        await dio.put<dynamic>(
          uploadUrl,
          data: fileBytes,
          options: Options(
            headers: {
              Headers.contentLengthHeader: fileBytes.length,
            },
          ),
        );

        // Delete temporary file after successful upload
        await file.delete();
        
        return true;
      } catch (e) {
        // Return false to allow retry
        return false;
      }
    }
    return true;
  });
}

class UploadQueueManager {
  static final UploadQueueManager _instance = UploadQueueManager._internal();
  factory UploadQueueManager() => _instance;
  UploadQueueManager._internal();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    _initialized = true;
  }

  Future<void> enqueueUpload({
    required String filePath,
    required String uploadUrl,
  }) async {
    if (kIsWeb) return; // Workmanager not supported on web

    await Workmanager().registerOneOffTask(
      'upload_task_${DateTime.now().millisecondsSinceEpoch}',
      uploadTaskKey,
      inputData: {
        'filePath': filePath,
        'uploadUrl': uploadUrl,
      },
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 10),
    );
  }
}
