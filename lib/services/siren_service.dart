import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SirenService {
  SirenService._();

  static final SirenService instance = SirenService._();

  static const String _prefKey = 'is_siren_enabled';

  final AudioPlayer _player = AudioPlayer();
  Timer? _autoStopTimer;
  Uint8List? _sirenBytes;
  bool _isPlaying = false;

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final localValue = prefs.getBool(_prefKey);

    // If user already toggled locally, trust it and avoid extra network calls.
    if (localValue != null) {
      return localValue;
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return false;

      final data =
          await Supabase.instance.client
              .from('profiles')
              .select('is_siren_enabled')
              .eq('id', userId)
              .maybeSingle();

      final enabled = data?['is_siren_enabled'] == true;
      await prefs.setBool(_prefKey, enabled);
      return enabled;
    } catch (_) {
      return false;
    }
  }

  Future<void> playIfEnabled({
    Duration autoStopAfter = const Duration(seconds: 20),
  }) async {
    final enabled = await isEnabled();
    if (!enabled) return;

    await play(autoStopAfter: autoStopAfter);
  }

  Future<void> play({
    Duration autoStopAfter = const Duration(seconds: 20),
  }) async {
    if (_isPlaying) return;

    _isPlaying = true;

    try {
      _sirenBytes ??= _buildSirenWavBytes();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(BytesSource(_sirenBytes!));

      _autoStopTimer?.cancel();
      _autoStopTimer = Timer(autoStopAfter, () {
        stop();
      });
    } catch (_) {
      _isPlaying = false;
    }
  }

  Future<void> stop() async {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    _isPlaying = false;
    await _player.stop();
  }

  Uint8List _buildSirenWavBytes() {
    const int sampleRate = 22050;
    const double seconds = 2.0;
    final int sampleCount = (sampleRate * seconds).toInt();

    final int dataLength = sampleCount * 2;
    final buffer = ByteData(44 + dataLength);

    void writeAscii(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        buffer.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    buffer.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little); // PCM chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM format
    buffer.setUint16(22, 1, Endian.little); // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buffer.setUint16(32, 2, Endian.little); // block align
    buffer.setUint16(34, 16, Endian.little); // bits per sample
    writeAscii(36, 'data');
    buffer.setUint32(40, dataLength, Endian.little);

    final int16 = Int16List.view(buffer.buffer, 44, sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;

      // 0.25s aralýklarla iki frekans arasýnda geçiþ yapan klasik siren tonu.
      final bool highTone = ((t / 0.25).floor() % 2) == 0;
      final freq = highTone ? 820.0 : 1280.0;
      final sample = math.sin(2 * math.pi * freq * t) * 0.65;
      int16[i] = (sample * 32767).toInt();
    }

    return buffer.buffer.asUint8List();
  }
}
