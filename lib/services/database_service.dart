import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class DatabaseService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> sendAlert({
    required String type,
    required String message,
  }) async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
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
      print("Alert gönderme hatasý: $e");
      return null;
    }
  }
}
