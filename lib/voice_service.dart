import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

import 'audio_service.dart';
import 'database_service.dart';

class VoiceService {
  static final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  final AudioService _audioService = AudioService();
  final DatabaseService _databaseService = DatabaseService();

  Future<String> get _keyword async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('emergency_keyword') ?? 'elma';
  }

  Future<void> initVosk() async {
    try {
      final statuses =
          await [Permission.microphone, Permission.location].request();

      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        if (kDebugMode) print('Mikrofon izni reddedildi!');
        return;
      }

      final modelLoader = ModelLoader();
      final modelPath = await modelLoader.loadFromAssets(
        'assets/models/vosk-model-small-tr-0.3.zip',
      );

      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );
      _speechService = await _vosk.initSpeechService(_recognizer!);

      _speechService!.onPartial().listen((partial) async {
        await _handleResult(partial.toString(), isPartial: true);
      });

      _speechService!.onResult().listen((result) async {
        await _handleResult(result.toString(), isPartial: false);
      });

      await _speechService!.start();
    } catch (e) {
      if (kDebugMode) print('Vosk hatasi: $e');
    }
  }

  Future<void> _handleResult(String raw, {required bool isPartial}) async {
    try {
      final currentKeyword = await _keyword;
      final text = raw.toLowerCase();

      if (kDebugMode) {
        final source = isPartial ? 'Ham' : 'Tam';
        print(
          'Duyulan ($source): $raw | Ayiklanan: $text | Dinlenen: $currentKeyword',
        );
      }

      if (text.contains(currentKeyword.toLowerCase())) {
        await _onKeywordDetected();
      }
    } catch (e) {
      if (kDebugMode) print('Ses sonucu islenirken hata: $e');
    }
  }

  Future<void> _onKeywordDetected() async {
    if (kDebugMode) print('!!! ANAHTAR KELIME YAKALANDI !!!');

    try {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 1000);
      }
    } catch (e) {
      if (kDebugMode) print('Titresim hatasi: $e');
    }

    try {
      final alert = await _databaseService.sendAlert(
        type: 'HELP_NEEDED',
        message: 'Kullanici acil durum kelimesini soyledi!',
      );

      if (alert != null) {
        final incidentId = alert['id'].toString();
        _audioService.recordAndUpload(incidentId);
      }

      if (kDebugMode) print('Acil durum sinyali ve ses kaydi baslatildi!');
    } catch (e) {
      if (kDebugMode) print('Sinyal gonderme hatasi: $e');
    }
  }

  Future<void> stop() async {
    await _speechService?.stop();
    if (kDebugMode) print('Dinleme durduruldu.');
  }

  Future<void> start() async {
    await _speechService?.start();
    if (kDebugMode) print('Dinleme baslatildi.');
  }
}
