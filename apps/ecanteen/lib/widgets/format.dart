import 'package:intl/intl.dart';

final _rp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _angka = NumberFormat.decimalPattern('id_ID');

String rupiah(num nilai) => _rp.format(nilai);
String angka(num nilai) => _angka.format(nilai);
