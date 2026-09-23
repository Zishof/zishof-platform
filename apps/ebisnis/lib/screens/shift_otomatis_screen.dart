import 'package:flutter/material.dart';
import '../services/pengaturan_shift_otomatis.dart';

class ShiftOtomatisScreen extends StatefulWidget {
  const ShiftOtomatisScreen({super.key});
  @override
  State<ShiftOtomatisScreen> createState() => _ShiftOtomatisScreenState();
}

class _ShiftOtomatisScreenState extends State<ShiftOtomatisScreen> {
  bool buka = false;
  bool tutup = false;
  TimeOfDay jam = const TimeOfDay(hour: 22, minute: 0);
  final modal = TextEditingController(text: '0');
  bool memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    await PengaturanShiftOtomatis.instance.muat();
    final p = PengaturanShiftOtomatis.instance;
    final bagian = p.jamTutup.split(':');
    if (!mounted) return;
    setState(() {
      buka = p.bukaOtomatis;
      tutup = p.ingatkanTutupOtomatis;
      modal.text = p.modalAwal.toStringAsFixed(0);
      jam = TimeOfDay(
        hour: int.tryParse(bagian.first) ?? 22,
        minute: bagian.length > 1 ? int.tryParse(bagian[1]) ?? 0 : 0,
      );
      memuat = false;
    });
  }

  @override
  void dispose() {
    modal.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    final nilai = double.tryParse(modal.text.replaceAll(',', '.'));
    if (nilai == null || nilai < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Modal awal harus berupa angka nol atau lebih.')));
      return;
    }
    final teksJam =
        '${jam.hour.toString().padLeft(2, '0')}:${jam.minute.toString().padLeft(2, '0')}';
    await PengaturanShiftOtomatis.instance.simpan(
      bukaOtomatis: buka,
      modalAwal: nilai,
      ingatkanTutupOtomatis: tutup,
      jamTutup: teksJam,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pengaturan shift otomatis disimpan.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Otomasi Shift Kasir')),
        body: memuat
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(24), children: [
                SwitchListTile(
                  title: const Text('Buka shift otomatis'),
                  subtitle: const Text(
                      'Saat POS dibuka dan belum ada sesi aktif, sistem membuka kas memakai modal awal di bawah.'),
                  value: buka,
                  onChanged: (v) => setState(() => buka = v),
                ),
                TextField(
                  controller: modal,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Modal awal otomatis',
                    prefixText: 'Rp ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Mulai penutupan shift otomatis'),
                  subtitle: const Text(
                      'Pada jam yang dipilih, dialog hitung kas dan rekonsiliasi dibuka otomatis. Kasir tetap wajib mengisi uang fisik.'),
                  value: tutup,
                  onChanged: (v) => setState(() => tutup = v),
                ),
                ListTile(
                  title: const Text('Jam penutupan'),
                  subtitle: Text(jam.format(context)),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final hasil = await showTimePicker(
                        context: context, initialTime: jam);
                    if (hasil != null) setState(() => jam = hasil);
                  },
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _simpan,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Simpan Pengaturan Shift'),
                ),
              ]),
      );
}
