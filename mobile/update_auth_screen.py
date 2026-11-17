with open('mobile/lib/screens/auth_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read().replace('\r\n', '\n')

# 1. Update text fields with explicit style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600)
old_name_field = """            TextFormField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration('e.g. Jean-Paul Mbah'),"""

new_name_field = """            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600),
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration('e.g. Jean-Paul Mbah'),"""
text = text.replace(old_name_field, new_name_field)

old_email_field = """          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration('student@kivora.cm'),"""

new_email_field = """          TextFormField(
            controller: _emailCtrl,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration('student@kivora.cm'),"""
text = text.replace(old_email_field, new_email_field)

old_pw_field = """          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            textInputAction:
                _isRegisterMode ? TextInputAction.next : TextInputAction.done,
            onFieldSubmitted: _isRegisterMode ? null : (_) => _submit(provider),
            decoration: _inputDecoration('Enter your password').copyWith("""

new_pw_field = """          TextFormField(
            controller: _passwordCtrl,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600),
            obscureText: _obscurePassword,
            textInputAction:
                _isRegisterMode ? TextInputAction.next : TextInputAction.done,
            onFieldSubmitted: _isRegisterMode ? null : (_) => _submit(provider),
            decoration: _inputDecoration('Enter your password').copyWith("""
text = text.replace(old_pw_field, new_pw_field)

old_cpw_field = """            TextFormField(
              controller: _confirmPasswordCtrl,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(provider),
              decoration: _inputDecoration('Re-enter your password').copyWith("""

new_cpw_field = """            TextFormField(
              controller: _confirmPasswordCtrl,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600),
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(provider),
              decoration: _inputDecoration('Re-enter your password').copyWith("""
text = text.replace(old_cpw_field, new_cpw_field)

# 2. Update labels to high contrast Color(0xFF0F172A)
text = text.replace("color: Color(0xFF334155)", "color: Color(0xFF0F172A)")

# 3. Update FilledButton styling to have pure white text
old_button = """          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: provider.isLoading ? null : () => _submit(provider),
              style: FilledButton.styleFrom(
                backgroundColor: _plumPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: provider.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isRegisterMode ? 'Create Account' : 'Login',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),"""

new_button = """          SizedBox(
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
          ),"""
assert old_button in text, "old_button not found"
text = text.replace(old_button, new_button)

# 4. Update _inputDecoration to high contrast
old_input_dec = """  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF8F7FC),
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2DCF2), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _plumPrimary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.6),
      ),
    );
  }"""

new_input_dec = """  InputDecoration _inputDecoration(String hint) {
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
  }"""
assert old_input_dec in text, "old_input_dec not found"
text = text.replace(old_input_dec, new_input_dec)

# 5. Quick server switch buttons & friendly error message in auth_screen.dart
old_error_box = """          if (_localError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _localError!,
                style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
              ),
            ),
          ],"""

new_error_box = """          if (_localError != null) ...[
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
                  if (_localError!.contains('Connection') || _localError!.contains('127.0.0.1')) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDBEAFE),
                            foregroundColor: const Color(0xFF1E40AF),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          onPressed: () async {
                            await provider.setApiBaseUrl('http://192.168.1.148:8000');
                            setState(() => _localError = null);
                            _submit(provider);
                          },
                          child: const Text('📶 Switch to Wi-Fi (192.168.1.148)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],"""
assert old_error_box in text, "old_error_box not found"
text = text.replace(old_error_box, new_error_box)

# 6. Add Quick Server Chips at the bottom of the card
old_api_link = """          Center(
            child: InkWell(
              onTap: () => _showServerSettingsDialog(context, provider),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.settings_ethernet,
                        size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 5),
                    Text(
                      'API: ${provider.apiBaseUrl}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),"""

new_api_link = """          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () => _showServerSettingsDialog(context, provider),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_tethering, size: 14, color: Color(0xFF1E40AF)),
                      const SizedBox(width: 6),
                      Text(
                        'API: ${provider.apiBaseUrl}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A), fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 12, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: provider.apiBaseUrl.contains('192.168.1.148') ? const Color(0xFFDCFCE7) : Colors.white,
                      label: Text('📶 Wi-Fi 192.168.1.148', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: provider.apiBaseUrl.contains('192.168.1.148') ? const Color(0xFF15803D) : const Color(0xFF334155))),
                      onPressed: () => provider.setApiBaseUrl('http://192.168.1.148:8000'),
                    ),
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: provider.apiBaseUrl.contains('127.0.0.1') ? const Color(0xFFDCFCE7) : Colors.white,
                      label: Text('🔌 USB localhost', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: provider.apiBaseUrl.contains('127.0.0.1') ? const Color(0xFF15803D) : const Color(0xFF334155))),
                      onPressed: () => provider.setApiBaseUrl('http://127.0.0.1:8000'),
                    ),
                  ],
                ),
              ],
            ),
          ),"""
assert old_api_link in text, "old_api_link not found"
text = text.replace(old_api_link, new_api_link)

with open('mobile/lib/screens/auth_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print("Updated auth_screen.dart successfully!")

