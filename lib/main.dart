import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:safevoice/login_page.dart';
import 'package:safevoice/safety_timer_page.dart';
import 'package:safevoice/settings_page.dart';
import 'package:safevoice/voice_service.dart';
import 'package:safevoice/audio_service.dart';
import 'package:safevoice/database_service.dart';
import 'package:safevoice/siren_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase baglantisini baslatiyoruz
  await Supabase.initialize(
    url: 'https://ibwcrgpqawwckixwprvd.supabase.co',
    anonKey: 'sb_publishable_nmUhM-6aRKxey-tKMC1zXg_KrIr-uwy',
  );

  runApp(const SafeVoiceApp());
}

class SafeVoiceApp extends StatelessWidget {
  const SafeVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SafeVoice',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
        useMaterial3: true,
        textTheme: GoogleFonts.robotoTextTheme(Theme.of(context).textTheme),
      ),
      home: session == null ? const LoginPage() : const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VoiceService _voiceService = VoiceService();
  final AudioService _audioService = AudioService();
  final SirenService _sirenService = SirenService.instance;
  final Battery _battery = Battery(); // Battery sinifi artik dogru tanimli
  final DatabaseService _databaseService = DatabaseService();

  bool _isListening = false;
  String _currentKeyword = "elma";
  String _securityStatus = "KONTROL ED\u0130L\u0130YOR...";
  Color _statusColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _loadKeyword();
    _startEmergencySystem();
    _setupBatteryListener();
    _checkSecurityScore();
  }

  // Kritik Pil Seviyesi Takibi (%5 Alti)
  void _setupBatteryListener() {
    _battery.onBatteryStateChanged.listen((BatteryState state) async {
      final level = await _battery.batteryLevel;
      if (level <= 5 && state != BatteryState.charging) {
        triggerEmergency('LOW_BATTERY');
      }
    });
  }

  // Guvenlik Durumu ve PIN Kontrolu
  Future<void> _checkSecurityScore() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final profile =
          await Supabase.instance.client
              .from('profiles')
              .select('pin_code')
              .eq('id', user.id)
              .maybeSingle();

      final List<dynamic> contacts = await Supabase.instance.client
          .from('emergency_contacts')
          .select()
          .eq('user_id', user.id);

      if (mounted) {
        setState(() {
          if (contacts.isEmpty) {
            _securityStatus =
                "AC\u0130L DURUM K\u0130\u015e\u0130S\u0130 EKS\u0130K!";
            _statusColor = Colors.orange;
          } else if (profile == null || profile['pin_code'] == '1234') {
            _securityStatus = "PIN KODUNU DE\u011e\u0130\u015eT\u0130R!";
            _statusColor = Colors.orange;
          } else {
            _securityStatus = "S\u0130STEM AKT\u0130F / TAM KORUMA";
            _statusColor = Colors.green;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _securityStatus =
              "S\u0130STEM AKT\u0130F / G\u00dcVENDES\u0130N\u0130Z";
          _statusColor = Colors.green;
        });
      }
    }
  }

  Future<void> _loadKeyword() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currentKeyword = prefs.getString('emergency_keyword') ?? 'elma';
      });
    }
  }

  Future<void> _startEmergencySystem() async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      await _voiceService.initVosk();
      if (mounted) setState(() => _isListening = true);
    }
  }

  Future<void> triggerEmergency(String type) async {
    final alert = await _databaseService.sendAlert(
      type: type,
      message:
          type == 'VOICE_TRIGGER'
              ? 'Kullan\u0131c\u0131 acil durum kelimesini s\u00f6yledi!'
              : 'Kritik uyar\u0131 (Pil/Zamanlay\u0131c\u0131)!',
    );

    if (alert != null) {
      final incidentId = alert['id'].toString();
      _audioService.recordAndUpload(incidentId); // Otomatik ses kaydi
      _sirenService.playIfEnabled();
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _voiceService.stop();
    } else {
      await _voiceService.start();
    }
    if (mounted) setState(() => _isListening = !_isListening);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
          tooltip: 'Çıkış Yap',
          onPressed: () async {
            try {
              await Supabase.instance.client.auth.signOut();

              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Çıkış yapılırken hata oluştu: $e"),
                  ),
                );
              }
            }
          },
        ),
        title: Text(
          "SafeVoice",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.black),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color:
                    _isListening
                        ? Colors.red.withAlpha(25)
                        : _statusColor.withAlpha(25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isListening ? Icons.record_voice_over : Icons.shield,
                    color: _isListening ? Colors.red : _statusColor,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isListening
                        ? "D\u0130NL\u0130YOR (Anahtar: $_currentKeyword)"
                        : _securityStatus,
                    style: TextStyle(
                      color: _isListening ? Colors.red : _statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
            Center(
              child: GestureDetector(
                onTap: _toggleListening,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening ? Colors.red : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(25),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    size: 70,
                    color: _isListening ? Colors.white : Colors.red,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Column(
                  children: [
                    _buildMenuAction(
                      icon: FontAwesomeIcons.clock,
                      color: Colors.orange,
                      title: "Zamanlay\u0131c\u0131",
                      subtitle: "Beni takip et modunu ba\u015flat",
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SafetyTimerPage(),
                            ),
                          ),
                    ),
                    const Divider(height: 1),
                    _buildMenuAction(
                      icon: FontAwesomeIcons.gear,
                      color: Colors.blue,
                      title: "Ayarlar",
                      subtitle: "G\u00fcvenlik ayarlar\u0131n\u0131 y\u00f6net",
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SettingsPage(),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuAction({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withAlpha(25),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}
