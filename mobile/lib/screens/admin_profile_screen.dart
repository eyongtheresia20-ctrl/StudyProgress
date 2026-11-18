import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/study_provider.dart';

class AdminProfileScreen extends StatelessWidget {
  const AdminProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isFr = context.watch<StudyProvider>().languageCode == 'fr';
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(
          isFr ? 'Profil Administrateur' : 'Admin Profile',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: const AdminProfileBody(),
    );
  }
}

class AdminProfileBody extends StatefulWidget {
  const AdminProfileBody({super.key});

  @override
  State<AdminProfileBody> createState() => _AdminProfileBodyState();
}

class _AdminProfileBodyState extends State<AdminProfileBody> {
  static const Color _deepNavy = Color(0xFF13346B);
  static const Color _primaryBlue = Color(0xFF2563EB);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<StudyProvider>().user;
    _nameCtrl = TextEditingController(text: user?.fullName ?? '');
    _emailCtrl = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(StudyProvider provider) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _statusMessage = null;
      _isError = false;
    });

    try {
      await provider.updateAccountProfile(
        fullName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        currentPassword:
            _newPwCtrl.text.isNotEmpty ? _currentPwCtrl.text : null,
        newPassword: _newPwCtrl.text.isNotEmpty ? _newPwCtrl.text : null,
      );
      if (!mounted) return;
      _currentPwCtrl.clear();
      _newPwCtrl.clear();
      _confirmPwCtrl.clear();
      setState(() {
        _statusMessage = provider.languageCode == 'fr'
            ? 'Profil administrateur mis à jour.'
            : 'Admin profile updated successfully.';
        _isError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString().replaceFirst('Exception: ', '');
        _isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();
    final isFr = provider.languageCode == 'fr';
    final name = provider.user?.fullName ?? 'Admin';
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'A';

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFFDBEAFE),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _primaryBlue,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isFr ? 'Compte administrateur' : 'Administrator account',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _deepNavy,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isFr ? 'Informations du compte' : 'Account Information',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: _fieldDecoration(
                    isFr ? 'Nom complet' : 'Full Name',
                    Icons.person_outline,
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? (isFr ? 'Nom invalide' : 'Enter a valid name')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _fieldDecoration('Email', Icons.email_outlined),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? (isFr ? 'Email invalide' : 'Enter a valid email')
                      : null,
                ),
                const SizedBox(height: 20),
                Text(
                  isFr
                      ? 'Changer le mot de passe (optionnel)'
                      : 'Change Password (optional)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _currentPwCtrl,
                  obscureText: _obscureCurrent,
                  decoration: _fieldDecoration(
                    isFr ? 'Mot de passe actuel' : 'Current Password',
                    Icons.lock_outline,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureCurrent
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                  ),
                  validator: (v) {
                    if (_newPwCtrl.text.isNotEmpty &&
                        (v == null || v.isEmpty)) {
                      return isFr
                          ? 'Entrez votre mot de passe actuel'
                          : 'Enter your current password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newPwCtrl,
                  obscureText: _obscureNew,
                  decoration: _fieldDecoration(
                    isFr ? 'Nouveau mot de passe' : 'New Password',
                    Icons.lock_reset_outlined,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.length < 6) {
                      return isFr
                          ? 'Au moins 6 caractères'
                          : 'Minimum 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPwCtrl,
                  obscureText: _obscureConfirm,
                  decoration: _fieldDecoration(
                    isFr
                        ? 'Confirmer le nouveau mot de passe'
                        : 'Confirm New Password',
                    Icons.lock_reset_outlined,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (_newPwCtrl.text.isNotEmpty && v != _newPwCtrl.text) {
                      return isFr
                          ? 'Les mots de passe ne correspondent pas'
                          : 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isError
                          ? const Color(0xFFFEE2E2)
                          : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(
                        color: _isError
                            ? const Color(0xFF991B1B)
                            : const Color(0xFF166534),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: provider.isLoading ? null : () => _save(provider),
                  style: FilledButton.styleFrom(
                    backgroundColor: _deepNavy,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: provider.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isFr ? 'Enregistrer' : 'Save Changes',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: provider.logout,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
            side: const BorderSide(color: Color(0xFFFCA5A5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.logout),
          label: Text(isFr ? 'Déconnexion' : 'Sign Out'),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _deepNavy, width: 1.5),
      ),
    );
  }
}
