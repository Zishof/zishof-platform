import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/apotik_status_pill.dart';
import 'apotik_pos_state.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// <h3>Panel keranjang POS Apotik (§10 ApotikCartPanel).</h3>
///
/// Menutup temuan audit: panel lama besar tetapi kosong informasi. Sekarang
/// setiap baris menampilkan quantity stepper, batch terpilih, badge risiko
/// (LASA/terkendali), dan **pagar bayar dengan alasan yang terbaca** —
/// tombol bayar tidak sekadar mati tanpa penjelasan.
class ApotikCartPanel extends StatelessWidget {
  final ApotikPosController pos;
  final void Function(int indeks, double qty) onUbahQty;
  final void Function(int indeks) onHapus;
  final void Function(int indeks)? onPilihBatch;
  final VoidCallback? onBayar;
  final VoidCallback? onTahan;
  final VoidCallback? onLanjutkan;
  final String judul;
  final String ringkasanLabel;
  final String? ringkasanNilai;
  final String labelAksi;
  final IconData ikonAksi;
  final String judulPagar;
  final String petunjukKosong;

  const ApotikCartPanel({
    super.key,
    required this.pos,
    required this.onUbahQty,
    required this.onHapus,
    this.onPilihBatch,
    this.onBayar,
    this.onTahan,
    this.onLanjutkan,
    this.judul = 'Keranjang',
    this.ringkasanLabel = 'Total',
    this.ringkasanNilai,
    this.labelAksi = 'Bayar',
    this.ikonAksi = Icons.payments_outlined,
    this.judulPagar = 'Pembayaran ditahan',
    this.petunjukKosong =
        'Cari obat di katalog, atau pilih resep untuk menebus obat pasien.',
  });

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    final pagar = pos.pagarBayar();
    return ApotikResponsive(
      builder: (context, layout) {
        return Container(
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(left: BorderSide(color: t.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _judul(t),
              Divider(height: 1, color: t.border),
              Expanded(
                child: pos.keranjang.isEmpty
                    ? ApotikEmptyState(
                        ikon: Icons.shopping_cart_outlined,
                        judul: 'Keranjang kosong',
                        petunjuk: petunjukKosong,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: pos.keranjang.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: t.border),
                        itemBuilder: (context, i) =>
                            _baris(context, t, i, pos.keranjang[i]),
                      ),
              ),
              Divider(height: 1, color: t.border),
              _ringkasanDanAksi(context, t, pagar, layout),
            ],
          ),
        );
      },
    );
  }

  Widget _judul(ApotikDesignTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(children: [
        Icon(Icons.shopping_cart_outlined, size: 17, color: t.primary),
        const SizedBox(width: 8),
        // Expanded menggantikan Spacer: pada skala teks besar judul + pill
        // status melebihi lebar panel.
        Expanded(
          child: Text(judul,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary)),
        ),
        if (pos.status == ApotikStatusTransaksi.held)
          const ApotikStatusPill(
              teks: 'Ditahan',
              nada: ApotikStatusNada.peringatan,
              ikon: Icons.pause_circle_outline,
              penjelasan: 'Transaksi ditahan — lanjutkan untuk membayar',
              rapat: true)
        else
          Text('${pos.keranjang.length} item',
              style: TextStyle(fontSize: 12, color: t.textSecondary)),
      ]),
    );
  }

  Widget _baris(BuildContext context, ApotikDesignTokens t, int i,
      ApotikBarisKeranjang b) {
    final batchKurang = !b.batchLengkap;
    final bolehPilihBatch = onPilihBatch != null && !b.racikan && !b.produksi;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(b.nama,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: b.lasa ? FontWeight.w800 : FontWeight.w600,
                        color: t.textPrimary)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Hapus ${b.nama}',
                icon: Icon(Icons.close, size: 16, color: t.textSecondary),
                onPressed: () => onHapus(i),
              ),
            ],
          ),
          if (b.lasa || b.terkendali)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                if (b.lasa) ApotikStatusPill.lasa(),
                if (b.terkendali) ApotikStatusPill.terkendali(),
              ]),
            ),
          Row(children: [
            _stepper(t, i, b),
            const SizedBox(width: 10),
            Expanded(
              child: Text('× ${_rp.format(b.harga)}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.textSecondary)),
            ),
            const SizedBox(width: 6),
            Text(_rp.format(b.subtotal),
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary)),
          ]),
          if (b.batch.isNotEmpty || bolehPilihBatch) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: bolehPilihBatch ? () => onPilihBatch!(i) : null,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 13,
                      color: batchKurang ? t.warning : t.textSecondary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      b.batch.isEmpty
                          ? 'Batch: otomatis FEFO (server memilih)'
                          : 'Batch: ${b.batch.length} lot • '
                              '${b.qtyBatchTeralokasi.toStringAsFixed(0)}/${b.qty.toStringAsFixed(0)} unit',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: batchKurang ? t.warning : t.textSecondary),
                    ),
                  ),
                  if (bolehPilihBatch)
                    Icon(Icons.chevron_right, size: 15, color: t.textSecondary),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Quantity stepper dengan target sentuh memadai (§8) — pengganti input
  /// teks kecil yang sulit dipakai di layar sentuh apotek.
  Widget _stepper(ApotikDesignTokens t, int i, ApotikBarisKeranjang b) {
    Widget tombol(IconData ikon, VoidCallback? aksi, String tip) {
      return Semantics(
        button: true,
        label: tip,
        child: InkWell(
          onTap: aksi,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(ikon,
                size: 16, color: aksi == null ? t.border : t.textPrimary),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
        border: Border.all(color: t.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        tombol(Icons.remove, () => onUbahQty(i, b.qty - 1),
            'Kurangi jumlah ${b.nama}'),
        Container(
          constraints: const BoxConstraints(minWidth: 34),
          alignment: Alignment.center,
          child: Text(b.qty.toStringAsFixed(b.qty % 1 == 0 ? 0 : 2),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary)),
        ),
        tombol(Icons.add, () => onUbahQty(i, b.qty + 1),
            'Tambah jumlah ${b.nama}'),
      ]),
    );
  }

  Widget _ringkasanDanAksi(BuildContext context, ApotikDesignTokens t,
      ApotikPagarBayar pagar, ApotikLayout layout) {
    final sedangProses = pos.status.sedangProses;
    final ditahan = pos.status == ApotikStatusTransaksi.held;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap, bukan Row: pada skala teks aksesibilitas nominalnya lebih
          // lebar dari panel dan angka uang tidak boleh dipotong -- ia turun
          // ke baris sendiri.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(ringkasanLabel,
                  style: TextStyle(fontSize: 13, color: t.textSecondary)),
              Text(ringkasanNilai ?? _rp.format(pos.total),
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary)),
            ],
          ),
          // Pesan penahan server ditampilkan APA ADANYA (perilaku existing).
          if (pos.pesanPenahan != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.danger.withValues(alpha: 0.3)),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.error_outline, size: 15, color: t.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(pos.pesanPenahan!,
                      style: TextStyle(fontSize: 11.5, color: t.textPrimary)),
                ),
              ]),
            ),
          ],
          // Alasan pagar: kasir tahu APA yang harus dilengkapi, bukan sekadar
          // menemukan tombol bayar berwarna abu-abu.
          if (!pagar.boleh && pos.keranjang.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.warning.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.gpp_maybe_outlined, size: 15, color: t.warning),
                    const SizedBox(width: 6),
                    Text(judulPagar,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.warningText)),
                  ]),
                  const SizedBox(height: 4),
                  for (final a in pagar.alasan)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('• $a',
                          style:
                              TextStyle(fontSize: 11.5, color: t.textPrimary)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (pos.keranjang.isNotEmpty)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      sedangProses ? null : (ditahan ? onLanjutkan : onTahan),
                  icon: Icon(
                      ditahan
                          ? Icons.play_circle_outline
                          : Icons.pause_circle_outline,
                      size: 17),
                  label: Text(ditahan ? 'Lanjutkan' : 'Tahan'),
                ),
              ),
            if (pos.keranjang.isNotEmpty) const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: ApotikBreakpoints.targetSentuhMinimum,
                child: FilledButton.icon(
                  // Terkunci saat proses berjalan (anti double-submit) DAN
                  // saat pagar belum lolos.
                  onPressed: (pagar.boleh && !sedangProses && !ditahan)
                      ? onBayar
                      : null,
                  icon: sedangProses
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(ikonAksi, size: 18),
                  label: Text(sedangProses ? 'Memproses…' : labelAksi),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
