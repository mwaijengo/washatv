/// Tanzanian Shilling (TZS) display helpers for the admin dashboard.

String _thousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  if (n < 0) return '-$b';
  return b.toString();
}

/// Full amount, e.g. `TSh 25,000` (shillings are whole numbers in UI).
String fmtTzs(num amount) {
  return 'TSh ${_thousands(amount.round())}';
}

/// Short form for chart axes (values are in TSh).
String fmtTzsAxis(num v) {
  if (v >= 1e6) {
    final x = v / 1e6;
    return x == x.roundToDouble() ? '${x.toInt()}M' : '${x.toStringAsFixed(1)}M';
  }
  if (v >= 1e3) {
    final x = v / 1e3;
    return x == x.roundToDouble() ? '${x.toInt()}k' : '${x.toStringAsFixed(1)}k';
  }
  return v.toInt().toString();
}
