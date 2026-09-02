import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/master_offline.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'pengadaan_cetak_util.dart';
import 'pengadaan_dasbor_tab.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/safe_state.dart';
import '../widgets/aksi_baris_menu.dart';

/// Layar "Bayar Pajak" -- tahap penutup rantai Pengadaan POS.
///
/// Mengikuti bentuk layar Pertanggungjawaban Pajak versi ZKoss: satu rekaman
/// setoran mewakili satu jenis pajak, dengan DPP, nilai, NPWP, nama wajib pajak,
/// NTPN, dan tanggal setor sebagai bukti.
///
/// PPh DIPOTONG dari kas yang keluar dan menjadi kewajiban kita kepada negara;
/// PPN dibayarkan kepada vendor sebagai pajak masukan. Keduanya ditampilkan agar
/// petugas melihat gambaran utuh sebelum menyetor.
class PengadaanPajakScreen extends StatefulWidget {
  const PengadaanPajakScreen({super.key});

  @override
  State<PengadaanPajakScreen> createState() => _PengadaanPajakScreenState();
}

class _PengadaanPajakScreenState extends State<PengadaanPajakScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabLuar;
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  late final TabController _tab;
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _terutang = [];
  List<Map<String, dynamic>> _setoran = [];

  /// Kunci gabungan sumber+id, mis. "BAST|12" atau "PEMBAYARAN|7". Pajak kini
  /// datang dari dua sumber sehingga id saja tidak lagi unik.
  final Set<String> _dipilih = {};
  double _totalPph = 0;
  double _totalPpn = 0;

  @override
  void initState() {
    super.initState();
    _tabLuar = TabController(length: 2, vsync: this);
    _tab = TabController(length: 2, vsync: this);
    _muat();
  }

  @override
  void dispose() {
    _tabLuar.dispose();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      // Local-first pada sisi baca: salinan terakhir ditampilkan lebih dulu bila ada,
      // sehingga layar tidak kosong saat sinyal buruk.
      await MasterOffline.daftarCacheDulu(
        'pengadaan_pajak_terutang',
        const {},
        'master:pengadaan_pajak_terutang',
        onData: (res) {
          if (!mounted) return;
          setStateIfMounted(() {
            _terutang = ((res['data'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _totalPph = (res['totalPph'] as num?)?.toDouble() ?? 0;
            _totalPpn = (res['totalPpn'] as num?)?.toDouble() ?? 0;
            _dipilih.removeWhere((k) => !_terutang.any((r) => _kunci(r) == k));
          });
        },
      );
      // Riwayat setoran juga dibaca cache-dulu, sejalan dengan tab Terutang.
      await MasterOffline.daftarCacheDulu(
        'pengadaan_pajak_daftar',
        const {},
        'master:pengadaan_pajak_setoran',
        onData: (res) {
          if (!mounted) return;
          final hakBaru = res['hak'];
          setStateIfMounted(() {
            // Hanya emisi SERVER yang membawa hak; snapshot cache tidak, dan
            // menimpanya dgn peta kosong akan memadamkan tombol tanpa alasan.
            if (hakBaru is Map) {
              _hak = hakBaru.map((k, v) => MapEntry('$k', v == true));
            }
            _setoran = ((res['data'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          });
        },
      );
      if (!mounted) return;
      setStateIfMounted(() => _memuat = false);
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  /// Kunci baris terutang: sumber + id barisnya.
  String _kunci(Map<String, dynamic> r) {
    final sumber = '${r['sumber'] ?? 'PEMBAYARAN'}';
    final id = sumber == 'BAST'
        ? (r['bast_detail_id'] as num?)?.toInt()
        : (r['detail_id'] as num?)?.toInt();
    return '$sumber|${id ?? 0}';
  }

  double _totalDipilih(String kunci) => _terutang
      .where((r) => _dipilih.contains(_kunci(r)))
      .fold(0, (s, r) => s + ((r[kunci] as num?)?.toDouble() ?? 0));

  void _pesan(String teks, {bool sukses = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(teks),
        backgroundColor: sukses ? null : Theme.of(context).colorScheme.error));
  }

  /// Setor pajak atas baris terpilih. NTPN dan tanggal setor WAJIB -- keduanya
  /// adalah bukti bahwa uangnya benar-benar masuk kas negara, dan server menolak
  /// bila kosong, jadi dialog meminta keduanya sekaligus.
  /// Hak per aksi dari peladen (grid CRUD TbmroleAction) -- dipakai MEMADAMKAN
  /// tombol; gerbang sebenarnya tetap pemeriksaan di peladen. Kunci yang tidak
  /// dikirim dianggap BOLEH, sama seperti bawaan peladen.
  Map<String, bool> _hak = const {};

  bool _boleh(String aksi) => _hak[aksi] != false;

  Future<void> _setor(String jenis) async {
    if (_dipilih.isEmpty) {
      _pesan('Centang minimal satu baris pajak.', sukses: false);
      return;
    }
    final nilai = _totalDipilih(jenis == 'PPH' ? 'pph' : 'ppn');
    if (nilai <= 0) {
      _pesan('Baris terpilih tidak memiliki $jenis untuk disetor.',
          sukses: false);
      return;
    }
    final ntpn = TextEditingController();
    final npwp = TextEditingController();
    final namaWp = TextEditingController();
    final keterangan = TextEditingController();
    final tanggal = TextEditingController(
        text: DateFormat('dd-MM-yyyy').format(DateTime.now()));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (c, setLocal) {
        Future<void> pilihTanggal() async {
          final pilih = await showDatePicker(
            context: c,
            initialDate: DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (pilih == null) return;
          setLocal(() => tanggal.text = DateFormat('dd-MM-yyyy').format(pilih));
        }

        return AlertDialog(
          title: Text('Setor $jenis'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      '${_dipilih.length} baris · nilai ${_fmtRp.format(nilai)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ntpn,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'NTPN *',
                      helperText: 'Nomor Transaksi Penerimaan Negara'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tanggal,
                  readOnly: true,
                  onTap: pilihTanggal,
                  decoration: const InputDecoration(
                      labelText: 'Tanggal setor *',
                      suffixIcon: Icon(Icons.event, size: 18)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: npwp,
                  decoration: const InputDecoration(labelText: 'NPWP'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: namaWp,
                  decoration:
                      const InputDecoration(labelText: 'Nama wajib pajak'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: keterangan,
                  decoration: const InputDecoration(labelText: 'Keterangan'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text('Setor $jenis')),
          ],
        );
      }),
    );
    final isi = {
      'ntpn': ntpn.text.trim(),
      'tanggalSetor': tanggal.text.trim(),
      'npwp': npwp.text.trim(),
      'namaWp': namaWp.text.trim(),
      'keterangan': keterangan.text.trim(),
    };
    ntpn.dispose();
    npwp.dispose();
    namaWp.dispose();
    keterangan.dispose();
    tanggal.dispose();
    if (ok != true || !mounted) return;
    if (isi['ntpn']!.isEmpty) {
      _pesan('NTPN wajib diisi sebagai bukti setor.', sukses: false);
      return;
    }
    try {
      // Local-first: bukti setor ditulis ke antrean perangkat dulu.
      final r = await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_pajak_setor',
        cacheKey: 'master:pengadaan_pajak_terutang',
        kunci: 'pengadaan_pajak_setor:${isi['ntpn'] ?? ''}',
        body: {
          'jenis': jenis,
          ...isi,
          // Baris BAST dan baris pembayaran dikirim dengan nama parameter berbeda;
          // server membedakannya dari situ.
          'detail': _dipilih.map((k) {
            final bagian = k.split('|');
            final id = int.tryParse(bagian.length > 1 ? bagian[1] : '') ?? 0;
            return bagian.first == 'BAST'
                ? {'bast_detail_id': id}
                : {'detail_id': id};
          }).toList(),
        },
      );
      if (!mounted) return;
      _pesan(r['offline'] == true
          ? 'Setoran tersimpan di perangkat, akan dikirim otomatis.'
          : 'Setoran ${r['kode'] ?? ''} tercatat: ${_fmtRp.format(r['nilai'] ?? 0)}');
      _dipilih.clear();
      await _muat();
    } catch (e) {
      _pesan('Gagal: $e', sukses: false);
    }
  }

  Future<void> _batal(Map<String, dynamic> row) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Batalkan Setoran'),
        content: Text('Batalkan setoran ${row['kode']} (NTPN ${row['ntpn']})? '
            'Pajaknya kembali menjadi terutang dan dapat disetor ulang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Tidak')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Batalkan')),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      final r = await prosesSimpanMaster(
        context,
        aksi: 'pengadaan_pajak_batal',
        body: {'id': row['id']},
        kunci: 'pengadaan_pajak_batal:${row['id']}',
        cacheKey: 'master:pengadaan_pajak_terutang',
      );
      if (!mounted) return;
      _pesan(r['offline'] == true
          ? 'Pembatalan tersimpan di perangkat, akan dikirim otomatis.'
          : 'Setoran dibatalkan; ${r['barisDilepas'] ?? 0} baris kembali terutang.');
      await _muat();
    } catch (e) {
      _pesan('Gagal: $e', sukses: false);
    }
  }

  Widget _kotak(String label, String nilai) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(nilai, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }

  /// Dua tab pada setiap menu Pengadaan: "Dasbor" (ringkasan angka) dan
  /// "Pajak" (daftar + CRUD). Susunannya sengaja disamakan di keenam
  /// menu supaya berpindah tahap tidak menuntut penyesuaian kebiasaan.
  Widget _bungkusTab(Widget isiData) {
    return Column(children: [
      TabBar(
        controller: _tabLuar,
        tabs: const [
          Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Dasbor'),
          Tab(icon: Icon(Icons.list_alt_outlined, size: 18), text: 'Pajak'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabLuar,
          children: [
            const PengadaanDasborTab(tahap: 'pajak'),
            isiData,
          ],
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.pengadaanPajak,
      judul: 'Bayar Pajak',
      subjudul: 'Setor PPh yang dipotong dan catat PPN dari pembayaran vendor',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(
            onPressed: _muat,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh)),
      ],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
      body: _bungkusTab(Column(children: [
        TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Terutang'),
            Tab(text: 'Riwayat Setoran'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [_tabTerutang(), _tabSetoran()],
          ),
        ),
      ])),
    );
  }

  Widget _tabTerutang() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_galat != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_galat!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
          ]),
        ),
      );
    }
    if (_terutang.isEmpty) {
      return const Center(
        child: Text(
            'Tidak ada pajak terutang.\nPajak muncul di sini setelah pembayaran '
            'vendor disetujui.',
            textAlign: TextAlign.center),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          _kotak('Baris', '${_terutang.length}'),
          _kotak('PPh terutang', _fmtRp.format(_totalPph)),
          _kotak('PPN tercatat', _fmtRp.format(_totalPpn)),
          _kotak('Dipilih', '${_dipilih.length}'),
        ]),
      ),
      Expanded(child: _daftarTerutang()),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Text(
                'Terpilih: PPh ${_fmtRp.format(_totalDipilih('pph'))} · '
                'PPN ${_fmtRp.format(_totalDipilih('ppn'))}',
                style: const TextStyle(fontSize: 12)),
          ),
          // Menyetor pajak MEMBUAT dokumen setoran baru -> hak create.
          OutlinedButton.icon(
              onPressed: _boleh('create') ? () => _setor('PPN') : null,
              icon: const Icon(Icons.receipt_outlined, size: 18),
              label: const Text('Setor PPN')),
          const SizedBox(width: 8),
          FilledButton.icon(
              onPressed: _boleh('create') ? () => _setor('PPH') : null,
              icon: const Icon(Icons.account_balance, size: 18),
              label: const Text('Setor PPh')),
        ]),
      ),
    ]);
  }

  Widget _daftarTerutang() {
    return ListView.builder(
      itemCount: _terutang.length,
      itemBuilder: (_, i) {
        final r = _terutang[i];
        final k = _kunci(r);
        final dariBast = '${r['sumber'] ?? ''}' == 'BAST';
        final namaPajak = '${r['namaPajak'] ?? ''}';
        final barang = '${r['barang'] ?? ''}';
        final belumSah = r['dokumenDisetujui'] == false;
        final rincian = StringBuffer()
          ..write('${r['po'] ?? ''} ${r['termin'] ?? ''}')
          ..write(barang.isEmpty ? '' : ' $barang')
          ..write('  DPP ${_fmtRp.format(r['dpp'] ?? 0)}\n')
          ..write('PPh ${_fmtRp.format(r['pph'] ?? 0)}')
          ..write(namaPajak.isEmpty ? '' : ' ($namaPajak)')
          ..write('  PPN ${_fmtRp.format(r['ppn'] ?? 0)}')
          ..write(belumSah
              ? '\nDokumen belum disetujui - belum dapat disetor'
              : '');
        return CheckboxListTile(
          dense: true,
          value: _dipilih.contains(k),
          onChanged: belumSah
              ? null
              : (v) => setState(() {
                    if (v == true) {
                      _dipilih.add(k);
                    } else {
                      _dipilih.remove(k);
                    }
                  }),
          title: Row(children: [
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: (dariBast ? Colors.indigo : Colors.teal)
                      .withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(dariBast ? 'BAST' : 'BAYAR',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: dariBast
                          ? Colors.indigo.shade800
                          : Colors.teal.shade800)),
            ),
            Expanded(
                child: Text(
                    '${r['dokumen'] ?? r['bayar'] ?? '-'}  ${r['penyedia'] ?? '-'}',
                    overflow: TextOverflow.ellipsis)),
          ]),
          subtitle:
              Text(rincian.toString(), style: const TextStyle(fontSize: 11)),
          isThreeLine: true,
        );
      },
    );
  }

  Widget _tabSetoran() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_setoran.isEmpty) {
      return const Center(child: Text('Belum ada setoran pajak tercatat.'));
    }
    return AppDataTable(
      minWidth: 1080,
      emptyText: 'Belum ada setoran.',
      columns: const [
        AppTableColumn('Kode', flex: 2),
        AppTableColumn('Jenis', flex: 2),
        AppTableColumn('DPP', flex: 2, align: TextAlign.right),
        AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
        AppTableColumn('NTPN', flex: 3),
        AppTableColumn('Tanggal setor', flex: 2),
        AppTableColumn('Aksi', width: 110),
      ],
      rows: _setoran.map(_barisSetoran).toList(),
    );
  }

  AppTableRowData _barisSetoran(Map<String, dynamic> r) {
    final aktif = r['aktif'] == true;
    final jenisPajak = '${r['jenisPajak'] ?? ''}';
    return AppTableRowData(cells: [
      AppTableCell.text('${r['kode'] ?? '-'}', flex: 2),
      AppTableCell.text(
          '${r['jenis'] ?? ''}${jenisPajak.isEmpty ? '' : ' · $jenisPajak'}',
          flex: 2),
      AppTableCell.text(_fmtRp.format(r['dpp'] ?? 0),
          flex: 2, align: TextAlign.right),
      AppTableCell.text(_fmtRp.format(r['nilai'] ?? 0),
          flex: 2, align: TextAlign.right),
      AppTableCell.text('${r['ntpn'] ?? '-'}', flex: 3),
      AppTableCell.text('${r['tanggalSetor'] ?? '-'}', flex: 2),
      AppTableCell(
        width: 110,
        /* Kolomnya tidak seramping layar lain karena penanda "dibatalkan" IKUT
         * tinggal di sini. Tabel setoran pajak tidak punya kolom Status, jadi
         * teks itulah satu-satunya tempat pembatalan terlihat -- meleburnya ke
         * dalam menu akan menghilangkan keterangan itu dari layar. */
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AksiBarisMenu(aksi: [
            // Bukti setor pajak. Templatnya BARU -- versi ZKoss tidak punya dokumen
            // per baris untuk pajak, hanya ekspor daftar.
            AksiBaris(
                ikon: Icons.print_outlined,
                label: 'Cetak bukti setor',
                onTap: () => cetakDokumenPengadaan(context,
                    tahap: 'pajak',
                    id: (r['id'] as num).toInt(),
                    kode: '${r['kode'] ?? ''}')),
            AksiBaris(
                ikon: Icons.undo,
                label: 'Batalkan setoran',
                // Membatalkan setoran = membalik dokumen yang sudah terbit,
                // jadi mengikuti hak delete, bukan create.
                onTap: aktif && _boleh('delete') ? () => _batal(r) : null),
          ]),
          if (!aktif)
            const Text('dibatalkan',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
      ),
    ]);
  }
}
