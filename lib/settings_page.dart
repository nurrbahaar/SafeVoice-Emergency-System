import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:postgrest/postgrest.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  // Kişisel Bilgiler
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Acil Durum
  final _pinController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();

  // Güvenlik
  final _keywordController = TextEditingController();
  bool _isSirenEnabled = false;
  bool _isAutoSmsEnabled = false;
  String _currentKeyword = "elma";
  bool _isLoading = false;
  bool _isSaving = false;

  String _firstNonEmpty(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return '';
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<bool> _upsertProfileFields(
    Map<String, dynamic> fields, {
    String? successMessage,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        _showMessage('Oturum bulunamadı. Tekrar giriş yapın.', isError: true);
        return false;
      }

      setState(() => _isSaving = true);

      await _supabase
          .from('profiles')
          .upsert({'id': userId, ...fields}, onConflict: 'id')
          .select('id')
          .single()
          .timeout(const Duration(seconds: 12));

      if (successMessage != null) {
        _showMessage(successMessage);
      }
      return true;
    } on PostgrestException catch (e) {
      // Some projects use different emergency contact column names.
      // Retry once with fallback names when column-not-found is returned.
      if (e.code == 'PGRST204') {
        final fallbackFields = <String, dynamic>{...fields};
        bool changed = false;

        if (fallbackFields.containsKey('emergency_contact_name')) {
          fallbackFields['emergency_name'] = fallbackFields.remove(
            'emergency_contact_name',
          );
          changed = true;
        }
        if (fallbackFields.containsKey('emergency_contact_phone')) {
          fallbackFields['emergency_phone'] = fallbackFields.remove(
            'emergency_contact_phone',
          );
          changed = true;
        }

        if (changed) {
          return _upsertProfileFields(
            fallbackFields,
            successMessage: successMessage,
          );
        }
      }

      final msg = e.message.toLowerCase();
      final isRls =
          e.code == '42501' ||
          msg.contains('row-level security') ||
          msg.contains('permission denied');

      if (isRls) {
        _showMessage(
          'DB izin hatası (RLS). profiles tablosunda insert/update policy gerekli.',
          isError: true,
        );
      } else {
        _showMessage('Kaydetme hatası: ${e.message}', isError: true);
      }
      return false;
    } catch (e) {
      _showMessage('Kaydetme hatası: $e', isError: true);
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        final data =
            await _supabase
                .from('profiles')
                .select('*')
                .eq('id', userId)
                .maybeSingle();

        if (data != null) {
          setState(() {
            // Kişisel Bilgiler
            _nameController.text = data['full_name']?.split(' ')[0] ?? '';
            _surnameController.text =
                data['full_name']?.split(' ').skip(1).join(' ') ?? '';
            _phoneController.text = data['phone'] ?? '';

            // Acil Durum
            _pinController.text = data['pin_code']?.toString() ?? '';
            _emergencyNameController.text = _firstNonEmpty(data, [
              'emergency_contact_name',
              'emergency_name',
            ]);
            _emergencyPhoneController.text = _firstNonEmpty(data, [
              'emergency_contact_phone',
              'emergency_phone',
            ]);

            // Güvenlik
            _currentKeyword = data['emergency_keyword'] ?? 'elma';
            _keywordController.text = _currentKeyword;
            _isSirenEnabled = data['is_siren_enabled'] ?? false;
            _isAutoSmsEnabled = data['is_auto_sms_enabled'] ?? false;
          });
        }
      }
    } catch (e) {
      debugPrint('Ayarlar yüklenirken hata: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _savePersonalInfo() async {
    final fullName =
        '${_nameController.text} ${_surnameController.text}'.trim();
    final ok = await _upsertProfileFields({
      'full_name': fullName,
      'phone': _phoneController.text.trim(),
    }, successMessage: 'Kişisel bilgiler kaydedildi!');

    if (ok) {
      await _loadAllSettings();
    }
  }

  Future<void> _saveEmergencyContact() async {
    final pin = int.tryParse(_pinController.text.trim());
    if (pin == null) {
      _showMessage('PIN sadece rakamlardan oluşmalı.', isError: true);
      return;
    }

    final ok = await _upsertProfileFields({
      'pin_code': pin,
      'emergency_contact_name': _emergencyNameController.text.trim(),
      'emergency_contact_phone': _emergencyPhoneController.text.trim(),
    }, successMessage: 'Acil durum bilgileri kaydedildi!');

    if (ok) {
      await _loadAllSettings();
    }
  }

  Future<void> _updateKeyword(String value) async {
    if (value.isEmpty) return;
    final cleanValue = value.trim().toLowerCase();

    await _upsertProfileFields({'emergency_keyword': cleanValue});

    setState(() => _currentKeyword = cleanValue);
  }

  Future<void> _toggleSiren(bool value) async {
    await _upsertProfileFields({'is_siren_enabled': value});

    setState(() => _isSirenEnabled = value);
  }

  Future<void> _toggleAutoSms(bool value) async {
    await _upsertProfileFields({'is_auto_sms_enabled': value});

    setState(() => _isAutoSmsEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text(
          "Ayarlar",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Kişisel'),
            Tab(text: 'Acil Durum'),
            Tab(text: 'Güvenlik'),
          ],
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue,
        ),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildPersonalInfoTab(),
                  _buildEmergencyTab(),
                  _buildSecurityTab(),
                ],
              ),
    );
  }

  Widget _buildPersonalInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildTextField('Ad', _nameController, Icons.person),
          const SizedBox(height: 12),
          _buildTextField('Soyad', _surnameController, Icons.person_outline),
          const SizedBox(height: 12),
          _buildTextField(
            'Telefon',
            _phoneController,
            Icons.phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _isSaving ? null : _savePersonalInfo,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              minimumSize: const Size(double.infinity, 50),
            ),
            child:
                _isSaving
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                    : const Text(
                      'Kaydet',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildTextField(
            'PIN Kodu (4 Haneli)',
            _pinController,
            Icons.lock,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            'Acil Durum Kişisi Adı',
            _emergencyNameController,
            Icons.contact_emergency,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            'Acil Durum Kişisi Telefon',
            _emergencyPhoneController,
            Icons.phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _isSaving ? null : _saveEmergencyContact,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              minimumSize: const Size(double.infinity, 50),
            ),
            child:
                _isSaving
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                    : const Text(
                      'Kaydet',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 20),
        _buildSectionHeader("SESLİ KOMUT AYARLARI"),
        _buildSettingsGroup([
          ListTile(
            leading: const Icon(Icons.mic, color: Colors.blue),
            title: const Text("Anahtar Kelime"),
            subtitle: Text("Şu an: \"$_currentKeyword\""),
            trailing: SizedBox(
              width: 120,
              child: TextField(
                controller: _keywordController,
                textAlign: TextAlign.end,
                decoration: const InputDecoration(
                  hintText: "Kelime gir",
                  border: InputBorder.none,
                ),
                onSubmitted: (value) async {
                  await _updateKeyword(value);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Kelime güncellendi!")),
                    );
                  }
                },
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        _buildSectionHeader("GÜVENLİK ÖZELLİKLERİ"),
        _buildSettingsGroup([
          ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
            title: const Text("Tehlike Anında Siren Çalsın"),
            subtitle: const Text("Yüksek sesli uyarı verir"),
            trailing: CupertinoSwitch(
              value: _isSirenEnabled,
              onChanged: _toggleSiren,
              activeColor: Colors.redAccent,
            ),
          ),
          const Divider(height: 1, indent: 60),
          ListTile(
            leading: const Icon(Icons.sms, color: Colors.green),
            title: const Text("Otomatik SMS Gönder"),
            subtitle: const Text("Acil durum kişilerine mesaj atar"),
            trailing: CupertinoSwitch(
              value: _isAutoSmsEnabled,
              onChanged: _toggleAutoSms,
              activeColor: Colors.green,
            ),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.all(30.0),
          child: Text(
            "Ayarlar otomatik olarak kaydedilir.",
            style: TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.blue),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 20, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF8E8E93),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: children),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _keywordController.dispose();
    super.dispose();
  }
}
