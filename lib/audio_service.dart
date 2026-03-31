import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AudioService {
  final _record = AudioRecorder();

  Future<void> recordAndUpload(String incidentId) async {
    try {
      final hasPermission = await _record.hasPermission();
      if (!hasPermission) return;

      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$incidentId.m4a';

      await _record.start(const RecordConfig(), path: path);
      await Future.delayed(const Duration(seconds: 15));

      final finalPath = await _record.stop();
      if (finalPath != null) {
        final file = File(finalPath);
        if (await file.exists()) {
          await Supabase.instance.client.storage
              .from('incidents_audio')
              .upload('$incidentId.m4a', file);
        }
      }
    } catch (e) {
      debugPrint('AudioService hata: $e');
    }
  }

  Future<void> startEmergencyRecord(String incidentId) async {
    await recordAndUpload(incidentId);
  }
}
