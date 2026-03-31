import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:safevoice/audio_service.dart';
import 'package:safevoice/siren_service.dart';

class SafetyTimerPage extends StatefulWidget {
  const SafetyTimerPage({super.key});

  @override
  State<SafetyTimerPage> createState() => _SafetyTimerPageState();
}

class _SafetyTimerPageState extends State<SafetyTimerPage> {
  Timer? _timer;
  int _totalSeconds = 900; // 15 Dakika varsayılan
  int _remainingSeconds = 0;
  bool _isTimerRunning = false;
  String _enteredPin = "";
  String _realPin = "1234"; // Varsayılan değer
  final String _fakePin = "0000"; // Sahte şifren (Gizli alarm gönderir)
  final AudioService _audioService = AudioService();
  final SirenService _sirenService = SirenService.instance;
  Position? _lastTrackedPosition;
  String? _trackingError;
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _loadUserPin();
  }

  Future<void> _loadUserPin() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final data =
          await supabase
              .from('profiles')
              .select('pin_code')
              .eq('id', userId)
              .maybeSingle();

      if (data != null &&
          data['pin_code'] != null &&
          data['pin_code'].toString().isNotEmpty) {
        setState(() {
          _realPin = data['pin_code'].toString();
        });
      }
    } catch (e) {
      if (kDebugMode) print("PIN yüklenirken hata: $e");
    }
  }

  void _checkPin(String enteredPin, Function setModalState) {
    if (enteredPin == _realPin) {
      // 1. Durum: Her şey yolunda
      _stopTimer();
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // Paneli kapat
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Güvendesiniz. İyi akşamlar!"),
          backgroundColor: Colors.green,
        ),
      );
    } else if (enteredPin == _fakePin) {
      // 2. Durum: ZORLA DURDURMA (Ajan Modu!)
      _sendSilentEmergencyAlert(); // Gizli alarmı gönder
      _stopTimerSilent(); // Uygulama durmuş gibi görünsün
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Saldırganın şüphelenmemesi için "normal" bir mesaj gösterelim
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Takip başarıyla sonlandırıldı."),
          backgroundColor: Colors.grey,
        ),
      );
    } else {
      // 3. Durum: Yanlış şifre
      if (mounted) {
        setModalState(() {
          _enteredPin = ""; // PIN'i sıfırla
        });
      }
    }
  }

  // GİZLİ ALARM FONKSİYONU
  Future<void> _sendSilentEmergencyAlert() async {
    try {
      final position =
          _lastTrackedPosition != null
              ? _lastTrackedPosition!
              : await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                ),
              );
      final supabase = Supabase.instance.client;

      await supabase.from('alerts').insert({
        'status':
            'DURESS_CODE_TRIGGERED', // Admin panelinde "Tehdit Altında!" diye yanıp sönecek
        'alert_type': 'DURESS_CODE', // Yeni alan: Sahte şifre alarmı
        'message': 'Kullanıcı zorla durdurma şifresi girdi! ACİL MÜDAHALE!',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'user_id': supabase.auth.currentUser?.id,
      });
      _sirenService.playIfEnabled();
      if (kDebugMode) print("Sessiz alarm başarıyla gönderildi!");
    } catch (e) {
      if (kDebugMode) print("Sessiz alarm gönderilirken hata: $e");
    }
  }

  void _startTimer(int minutes) {
    setState(() {
      _totalSeconds = minutes * 60;
      _remainingSeconds = _totalSeconds;
      _isTimerRunning = true;
      _trackingError = null;
    });
    _startLocationTracking();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        if (mounted) setState(() => _remainingSeconds--);
      } else {
        _onTimerExpired();
      }
    });
  }

  void _showPinDialog() {
    _enteredPin = ""; // PIN'i her açılışta sıfırla
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setModalState) => Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "GÜVENLİK ŞİFRESİ",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Takibi durdurmak için 4 haneli şifreni gir.",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 20),
                      // PIN Noktaları
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          4,
                          (index) => Container(
                            margin: const EdgeInsets.all(8),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  _enteredPin.length > index
                                      ? Colors.green
                                      : Colors.grey[300],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Numaratör
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 1.5,
                            ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          if (index == 9) return const SizedBox();
                          if (index == 11) {
                            return IconButton(
                              icon: const Icon(Icons.backspace_outlined),
                              onPressed: () {
                                if (mounted) {
                                  setModalState(() {
                                    if (_enteredPin.isNotEmpty) {
                                      _enteredPin = _enteredPin.substring(
                                        0,
                                        _enteredPin.length - 1,
                                      );
                                    }
                                  });
                                }
                              },
                            );
                          }
                          String val =
                              index == 10 ? "0" : (index + 1).toString();
                          return TextButton(
                            onPressed: () {
                              if (mounted) {
                                setModalState(() {
                                  if (_enteredPin.length < 4) {
                                    _enteredPin += val;
                                  }
                                  if (_enteredPin.length == 4) {
                                    _checkPin(_enteredPin, setModalState);
                                  }
                                });
                              }
                            },
                            child: Text(
                              val,
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
          ),
    ).then((_) {
      if (mounted) _enteredPin = "";
    }); // Modal kapanınca PIN sıfırla
  }

  void _stopTimer() {
    _timer?.cancel();
    _stopLocationTracking();
    if (mounted) setState(() => _isTimerRunning = false);
  }

  void _stopTimerSilent() {
    _timer?.cancel();
    _stopLocationTracking();
    if (mounted) setState(() => _isTimerRunning = false);
  }

  void _onTimerExpired() async {
    _timer?.cancel();
    _stopLocationTracking();
    if (mounted) setState(() => _isTimerRunning = false);

    try {
      final position =
          _lastTrackedPosition != null
              ? _lastTrackedPosition!
              : await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                ),
              );
      final supabase = Supabase.instance.client;

      final data =
          await supabase.from('alerts').insert({
            'status': 'EXPIRED',
            'alert_type': 'TIMER_EXPIRED',
            'message': 'Zamanlayıcı süresi doldu ve kullanıcı onaylamadı!',
            'latitude': position.latitude,
            'longitude': position.longitude,
            'user_id': supabase.auth.currentUser?.id,
          }).select();

      if (data.isNotEmpty) {
        final incidentId = data[0]['id'].toString();
        _audioService.startEmergencyRecord(incidentId);
        _sirenService.playIfEnabled();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Süre doldu! Acil durum alarmı gönderildi."),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print("Zaman aşımı alarmında hata: $e");
    }
  }

  void _startLocationTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) print("Konum servisleri devre dışı");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (kDebugMode) print("Konum izni reddedildi");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) print("Konum izni kalıcı olarak reddedildi");
        return;
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        (Position position) {
          if (mounted) {
            setState(() {
              _lastTrackedPosition = position;
              _trackingError = null;
            });
          }
        },
        onError: (e) {
          if (kDebugMode) print("Konum takip hatası: $e");
          if (mounted) {
            setState(() {
              _trackingError = "Konum takip hatası";
            });
          }
        },
      );
    } catch (e) {
      if (kDebugMode) print("Konum takip başlatılırken hata: $e");
      if (mounted) {
        setState(() {
          _trackingError = "Konum takip başlatılamadı";
        });
      }
    }
  }

  void _stopLocationTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopLocationTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double progress = _totalSeconds > 0 ? _remainingSeconds / _totalSeconds : 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "Beni Takip Et",
          style: GoogleFonts.poppins(color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Center(
        child:
            _isTimerRunning ? _buildActiveTimer(progress) : _buildSetupView(),
      ),
    );
  }

  Widget _buildSetupView() {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.timer_outlined, size: 100, color: Colors.orange),
          const SizedBox(height: 20),
          Text(
            "Zamanlay\u0131c\u0131y\u0131 Ba\u015flat",
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
            child: Text(
              "Belirledi\u011fin s\u00fcre i\u00e7inde 'G\u00fcvendeyim' demezsen otomatik alarm g\u00f6nderilir.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 30),
          // Hızlı Seçim Chip'leri
          Wrap(
            spacing: 15,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children:
                [5, 10, 15, 30, 45, 60]
                    .map(
                      (m) => ActionChip(
                        label: Text("$m dk"),
                        onPressed: () => _startTimer(m),
                        backgroundColor: Colors.orange.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        labelStyle: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 40),
          // Güvenlik Hatırlatıcısı
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 30),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    "Takibi durdururken profilinde belirledi\u011fin 4 haneli PIN kodunu kullanmal\u0131s\u0131n.",
                    style: TextStyle(color: Colors.blue[800], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildActiveTimer(double progress) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 250,
              height: 250,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 12,
                backgroundColor: Colors.grey[200],
                color: Colors.orange,
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "${(_remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}",
                  style: GoogleFonts.poppins(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text("Kalan Süre", style: TextStyle(color: Colors.grey)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 60),
        ElevatedButton(
          onPressed: _showPinDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size(250, 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: Text(
            "GÜVENDEYİM",
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (_trackingError != null) ...[
          const SizedBox(height: 16),
          Text(_trackingError!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}
