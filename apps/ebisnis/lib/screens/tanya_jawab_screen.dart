import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bantuan_content.dart';
import 'bantuan_kontekstual.dart';

class PertanyaanJawaban {
  final String pertanyaan;
  final String jawaban;
  const PertanyaanJawaban(this.pertanyaan, this.jawaban);
}

/// Tanya-jawab kontekstual. Materi umum memakai narasi bantuan terpusat sehingga
/// seluruh menu memperoleh jawaban lengkap, konsisten, offline, dan >2.000 kata.
List<PertanyaanJawaban> tanyaJawabUntukMenu(
    String menuId, String judulHalaman) {
  final spesifikasi = spesifikasiBantuanMenu[menuId];
  final judul = spesifikasi?.judul ?? judulHalaman;
  final tujuan = spesifikasi?.tujuan ??
      'menjalankan pekerjaan pada halaman ini secara benar dan dapat ditelusuri';
  final objek = spesifikasi?.objekUtama ?? 'data pada halaman ini';
  final hasil = spesifikasi?.hasilAkhir ?? 'data tersimpan dengan benar';
  final alur = spesifikasi?.workflow.join(' → ') ??
      'Pilih konteks → Cari data → Verifikasi → Isi → Tinjau → Simpan';

  return <PertanyaanJawaban>[
    PertanyaanJawaban(
      'Apa tujuan halaman $judul dan kapan saya menggunakannya?',
      'Halaman $judul digunakan untuk $tujuan. Objek utama yang dikelola adalah '
          '$objek. Gunakan halaman ini hanya ketika pekerjaan dan dokumen sumber '
          'sudah jelas. Hasil yang diharapkan ialah $hasil. Sebelum mulai, periksa '
          'akun, toko, perangkat, periode, status koneksi, dan hak akses agar data '
          'tidak masuk ke konteks yang salah.',
    ),
    PertanyaanJawaban(
      'Bagaimana urutan kerja yang disarankan pada halaman $judul?',
      'Urutan ringkasnya adalah $alur. Kerjakan berurutan dan jangan melompati '
          'pemeriksaan identitas, jumlah, tanggal, nilai, status, serta akibat '
          'perubahan. Tekan tombol simpan atau proses satu kali, tunggu jawaban '
          'aplikasi, kemudian periksa riwayat atau tabel hasil. Bila hasil belum '
          'jelas, jangan membuat dokumen pengganti sebelum transaksi pertama '
          'dipastikan gagal.',
    ),
    PertanyaanJawaban(
      'Apa yang harus saya periksa sebelum menyimpan perubahan di $judul?',
      'Periksa bahwa $objek yang dipilih benar, semua kolom wajib terisi dari '
          'sumber yang sah, angka dan satuan sesuai, serta toko dan tanggal benar. '
          'Baca peringatan sampai selesai. Untuk tindakan bernilai besar, '
          'pembatalan, perubahan master, atau pengecualian, mintalah pemeriksaan '
          'supervisor. Setelah berhasil, pastikan $hasil dan simpan nomor '
          'referensinya bila diperlukan.',
    ),
    ...panduanOperasionalUmum.map(
      (bagian) => PertanyaanJawaban(
        'Bagaimana ketentuan ${bagian.judul.toLowerCase()} pada halaman $judul?',
        bagian.isi,
      ),
    ),
  ];
}

int jumlahKataTanyaJawab(List<PertanyaanJawaban> daftar) => daftar
    .expand((item) => [item.pertanyaan, item.jawaban])
    .join(' ')
    .trim()
    .split(RegExp(r'\s+'))
    .where((kata) => kata.isNotEmpty)
    .length;

class TanyaJawabScreen extends StatefulWidget {
  final String menuId;
  final String menuJudul;
  const TanyaJawabScreen({
    super.key,
    required this.menuId,
    required this.menuJudul,
  });

  @override
  State<TanyaJawabScreen> createState() => _TanyaJawabScreenState();
}

class _TanyaJawabScreenState extends State<TanyaJawabScreen> {
  final _cari = TextEditingController();
  String _kata = '';

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semua = tanyaJawabUntukMenu(widget.menuId, widget.menuJudul);
    final kata = _kata.toLowerCase().trim();
    final tampil = kata.isEmpty
        ? semua
        : semua
            .where((item) => '${item.pertanyaan} ${item.jawaban}'
                .toLowerCase()
                .contains(kata))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(title: Text('Tanya Jawab — ${widget.menuJudul}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                color: AppColors.primary.withValues(alpha: .08),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pertanyaan yang sering diajukan',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary)),
                      const SizedBox(height: 6),
                      Text(
                        'Jawaban mengikuti halaman ${widget.menuJudul}, tersedia '
                        'tanpa internet, dan ditulis untuk pengguna nonteknis. '
                        '${semua.length} pertanyaan · '
                        '${jumlahKataTanyaJawab(semua)} kata.',
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _cari,
                        onChanged: (nilai) => setState(() => _kata = nilai),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Cari pertanyaan atau jawaban',
                          hintText:
                              'Contoh: gagal simpan, hak akses, stok, sesi kas',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (tampil.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Pertanyaan tidak ditemukan. Coba kata yang lebih singkat.'),
                  ),
                )
              else
                ...tampil.asMap().entries.map(
                      (entry) => Card(
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            child: Text('${entry.key + 1}'),
                          ),
                          title: Text(entry.value.pertanyaan,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: SelectableText(entry.value.jawaban,
                                  textAlign: TextAlign.justify,
                                  style: const TextStyle(height: 1.65)),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
