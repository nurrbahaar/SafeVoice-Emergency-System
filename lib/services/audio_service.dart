import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class AudioService {
  final _record = AudioRecorder();

  Future<void> recordAndUpload(String incidentId) async {
    try {
      // 1. Mikrofon izni kontrolü
      final hasPermission = await _record.hasPermission();
      if (!hasPermission) return;

      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$incidentId.m4a';

      // 2. Kaydý Baþlat
      await _record.start(const RecordConfig(), path: path);

      // 3. 15 saniye sonra otomatik durdur
      await Future.delayed(const Duration(seconds: 15));

      final finalPath = await _record.stop();
      if (finalPath != null) {
        // 4. Supabase Storage'a yükle
        final file = File(finalPath);
        if (await file.exists()) {
          await Supabase.instance.client.storage
              .from('incidents_audio')
              .upload('$incidentId.m4a', file);
        }
      }
    } catch (e) {
      print('AudioService hata: $e');
    }
  }

  Future<void> startEmergencyRecord(String incidentId) async {
    await recordAndUpload(incidentId);
  }
}
