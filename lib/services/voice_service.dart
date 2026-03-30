import 'package:vosk_flutter/vosk_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
// import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_service.dart';
import 'database_service.dart';

class VoiceService {
  final VoskFlutterPlugin vosk = VoskFlutterPlugin.instance();
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
      // 1. Ýzinleri Al
      Map<Permission, PermissionStatus> statuses =
          await [Permission.microphone, Permission.location].request();

      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        if (kDebugMode) print("Mikrofon izni reddedildi!");
        return;
      }

      final modelLoader = ModelLoader();
      final modelPath = await modelLoader.loadFromAssets(
        'assets/models/vosk-model-small-tr-0.3.zip',
      );

      _model = await vosk.createModel(modelPath);

      _recognizer = await vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );

      _speechService = await vosk.initSpeechService(_recognizer!);

      _speechService!.onPartial().listen((partial) async {
        try {
          final currentKeyword = await _keyword;
          String text = partial.toString().toLowerCase();

          if (kDebugMode) {
            print(
              "Duyulan (Ham): $partial | Ayýklanan: $text | Dinlenen: $currentKeyword",
            );
          }

          if (text.contains(currentKeyword.toLowerCase())) {
            _onKeywordDetected();
          }
        } catch (e) {
          if (kDebugMode) print("Partial iþleme hatasý: $e");
        }
      });

      _speechService!.onResult().listen((result) async {
        try {
          final currentKeyword = await _keyword;
          String text = result.toString().toLowerCase();

          if (kDebugMode) {
            print(
              "Duyulan (Tam): $result | Ayýklanan: $text | Dinlenen: $currentKeyword",
            );
          }

          if (text.contains(currentKeyword.toLowerCase())) {
            _onKeywordDetected();
          }
        } catch (e) {
          if (kDebugMode) print("Result iþleme hatasý: $e");
        }
      });

      await _speechService!.start();
    } catch (e) {
      if (kDebugMode) {
        print("Vosk Hatasý: $e");
      }
    }
  }

  Future<void> _onKeywordDetected() async {
    if (kDebugMode) {
      print("!!! ANAHTAR KELÝME YAKALANDI !!!");
    }

    // Titreþim ekleyelim (Geri Bildirim)
    try {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 1000); // 1 saniye güçlü titreþim
      }
    } catch (e) {
      if (kDebugMode) print("Titreþim hatasý: $e");
    }

    try {
      // 1. DatabaseService üzerinden Alarm ve Ses Kaydý "Zincirleme Reaksiyonu"nu baþlat
      final alert = await _databaseService.sendAlert(
        type: 'HELP_NEEDED',
        message: 'Kullanýcý acil durum kelimesini söyledi!',
      );

      if (alert != null) {
        final incidentId = alert['id'].toString();
        // Arka planda baþlasýn, UI'ý bloklamasýn
        _audioService.recordAndUpload(incidentId);
      }

      if (kDebugMode) {
        print("Acil durum sinyali ve ses kaydý baþlatýldý!");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Sinyal gönderme hatasý: $e");
      }
    }
  }

  Future<void> stop() async {
    await _speechService?.stop();
    if (kDebugMode) print("Dinleme durduruldu.");
  }

  Future<void> start() async {
    await _speechService?.start();
    if (kDebugMode) print("Dinleme baþlatýldý.");
  }
}
