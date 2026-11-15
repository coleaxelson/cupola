/// A whole count with a comma between its thousands: `1,284`.
///
/// For a figure a person reads and compares (`Select all 1,284`), never for one
/// that is parsed back. Plain digits under a thousand, so `34` stays `34`.
String formatCount(int count) {
  final digits = count.abs().toString();
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return count < 0 ? '-$grouped' : '$grouped';
}
