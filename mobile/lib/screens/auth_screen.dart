import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/study_provider.dart';
import '../widgets/app_logo.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isRegisterMode = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _localError;

  static const Color _plumPrimary = Color(0xFF26145E);
  static const Color _goldAccent = Color(0xFFD99B26);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(StudyProvider provider) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _localError = null);

    try {
      if (!_isRegisterMode) {
        await provider.login(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      } else {
        await provider.register(
          fullName: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          role: 'student',
        );
      }
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceFirst('Exception: ', '');
      String msg = raw;
      if (raw.contains('TimeoutException') ||
          raw.contains('SocketException') ||
          raw.contains('Connection refused') ||
          raw.contains('ClientException') ||
          raw.contains('Server unreachable')) {
        msg = provider.languageCode == 'fr'
            ? 'Impossible de joindre le serveur. Veuillez vérifier la connexion.'
            : 'Unable to connect to the server. Please check your connection.';
      }
      setState(() {
        _localError = msg;
      });
    }
  }


  void _showServerConfigSheet(BuildContext context, StudyProvider provider) {
    final urlCtrl = TextEditingController(text: provider.apiBaseUrl);
    bool isTesting = false;
    bool? testSuccess;
    String? testMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isFr = provider.languageCode == 'fr';
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.dns_rounded, color: _plumPrimary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isFr ? 'Configuration du Serveur' : 'Server Configuration',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  isFr
                      ? 'Choisissez une adresse ou saisissez l\'URL du serveur :'
                      : 'Choose an address or type your backend server URL:',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.cloud_outlined, size: 16),
                      label: const Text('4G / Internet (Cloudflare)'),
                      onPressed: () {
                        setSheetState(() {
                          urlCtrl.text = 'https://whilst-endorsed-hampshire-out.trycloudflare.com';
                          testSuccess = null;
                        });
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.wifi, size: 16),
                      label: const Text('Wi-Fi Bureau (192.168.10.233)'),
                      onPressed: () {
                        setSheetState(() {
                          urlCtrl.text = 'http://192.168.10.233:8000';
                          testSuccess = null;
                        });
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.usb, size: 16),
                      label: const Text('USB / ADB (127.0.0.1)'),
                      onPressed: () {
                        setSheetState(() {
                          urlCtrl.text = 'http://127.0.0.1:8000';
                          testSuccess = null;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: isFr ? 'URL du serveur backend' : 'Backend Server URL',
                    prefixIcon: const Icon(Icons.link_rounded),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (testMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: testSuccess == true
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: testSuccess == true
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFFCA5A5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          testSuccess == true
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 16,
                          color: testSuccess == true
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB91C1C),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            testMessage!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: testSuccess == true
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: isTesting
                            ? null
                            : () async {
                                setSheetState(() {
                                  isTesting = true;
                                  testMessage = null;
                                });
                                final ok = await provider.testConnection(urlCtrl.text);
                                setSheetState(() {
                                  isTesting = false;
                                  testSuccess = ok;
                                  testMessage = ok
                                      ? (isFr
                                          ? 'Serveur en ligne et joignable !'
                                          : 'Server is online and reachable!')
                                      : (isFr
                                          ? 'Impossible de joindre ce serveur.'
                                          : 'Cannot reach this server.');
                                });
                              },
                        icon: isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.network_check_rounded, size: 18),
                        label: Text(isFr ? 'Tester' : 'Test'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _plumPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final target = urlCtrl.text.trim();
                          if (target.isEmpty) return;
                          await provider.setApiBaseUrl(target);
                          if (ctx.mounted) Navigator.pop(ctx);
                          setState(() => _localError = null);
                          if (!mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                isFr
                                    ? 'Serveur mis à jour : $target'
                                    : 'Server updated: $target',
                              ),
                            ),
                          );
                        },
                        child: Text(
                          isFr ? 'Enregistrer & Utiliser' : 'Save & Use',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();

    return Scaffold(
      body: Stack(
        children: [
          // Soft airy pearl-lavender canvas matching Option 4's white/plum/gold palette
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFAF9FE),
                  Color(0xFFF3EFFB),
                  Color(0xFFEDE7F8),
                ],
              ),
            ),
          ),
          // Subtle ambient gold & lavender glows
          Positioned(
            top: -110,
            right: -90,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFDE68A).withAlpha(95),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -90,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFDDD6FE).withAlpha(115),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 30,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFE7E1F5),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _plumPrimary.withAlpha(20),
                          blurRadius: 34,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: _buildForm(provider),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(StudyProvider provider) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.settings_ethernet_rounded, color: Color(0xFF64748B), size: 20),
              tooltip: 'Server Settings',
              onPressed: () => _showServerConfigSheet(context, provider),
            ),
          ),
          const Center(
            child: KivoraLogo(size: 62, showTitle: true),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 44,
              height: 3,
              decoration: BoxDecoration(
                color: _goldAccent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _isRegisterMode ? 'Create Account' : 'Welcome Back',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E105A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isRegisterMode
                ? 'Join our community and unlock your potential.'
                : 'Sign in to continue your learning journey.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 22),
          if (_isRegisterMode) ...[
            const Text(
              'Full Name',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600),
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration('e.g. Jean-Paul Mbah'),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Enter your full name'
                  : null,
            ),
            const SizedBox(height: 14),
          ],
          const Text(
            'Email',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailCtrl,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration('student@kivora.cm'),
            validator: (v) => (v == null || !v.contains('@'))
                ? 'Enter a valid email address'
                : null,
          ),
          const SizedBox(height: 14),
          const Text(
            'Password',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordCtrl,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600),
            obscureText: _obscurePassword,
            textInputAction:
                _isRegisterMode ? TextInputAction.next : TextInputAction.done,
            onFieldSubmitted: _isRegisterMode ? null : (_) => _submit(provider),
            decoration: _inputDecoration('Enter your password').copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF64748B),
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) => (v == null || v.length < 6)
                ? 'Password must be at least 6 characters'
                : null,
          ),
          if (_isRegisterMode) ...[
            const SizedBox(height: 14),
            const Text(
              'Confirm Password',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _confirmPasswordCtrl,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600),
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(provider),
              decoration: _inputDecoration('Re-enter your password').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: const Color(0xFF64748B),
                  ),
                  onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'Please confirm your password';
                }
                if (v != _passwordCtrl.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: _plumPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      onChanged: (v) =>
                          setState(() => _rememberMe = v ?? true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Remember me',
                    style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                  ),
                ],
              ),
              if (!_isRegisterMode)
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Contact your school administrator to reset your password.',
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(
                      fontSize: 13,
                      color: _plumPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (_localError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFB91C1C), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _localError!,
                          style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        foregroundColor: const Color(0xFFB91C1C),
                      ),
                      onPressed: () => _showServerConfigSheet(context, provider),
                      icon: const Icon(Icons.settings_ethernet_rounded, size: 16),
                      label: Text(
                        provider.languageCode == 'fr' ? 'Changer de serveur' : 'Change Server',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: provider.isLoading ? null : () => _submit(provider),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E1B4B),
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: provider.isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _isRegisterMode ? 'Create Account' : 'Login',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isRegisterMode
                    ? 'Already have an account? '
                    : 'Not registered yet? ',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _isRegisterMode = !_isRegisterMode;
                  _confirmPasswordCtrl.clear();
                  _localError = null;
                }),
                child: Text(
                  _isRegisterMode ? 'Login' : 'Create an Account',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _plumPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1E1B4B), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
      ),
    );
  }
}
