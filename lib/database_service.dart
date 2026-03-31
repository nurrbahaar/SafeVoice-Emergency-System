import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> sendAlert({
    required String type,
    required String message,
  }) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final response =
          await _supabase
              .from('alerts')
              .insert({
                'latitude': position.latitude,
                'longitude': position.longitude,
                'status': type,
                'message': message,
                'created_at': DateTime.now().toIso8601String(),
                'user_id': _supabase.auth.currentUser?.id,
              })
              .select()
              .single();

      return response;
    } catch (e) {
      debugPrint('Alert gonderme hatasi: $e');
      return null;
    }
  }
}
