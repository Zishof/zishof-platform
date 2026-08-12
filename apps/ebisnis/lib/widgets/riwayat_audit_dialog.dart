import 'package:flutter/material.dart';

import '../api_client.dart';

/// Dialog "Riwayat Audit" per record (paritas aksi legacy di seluruh layar
/// master) -- membaca snapshot revisi Envers via `si_audit_history`.
/// [entity]: supplier|customer|sales|piutang|penerimaan|order|spj (whitelist
/// server); [id]: id record. Menampilkan 25 revisi terakhir (terbaru dulu)
/// beserta nilai skalar tiap revisi.
Future<void> tampilkanRiwayatAudit(
    BuildContext context, String entity, Object id, String judul) {
  return showDialog(
    context: context,
    builder: (_) => _RiwayatAuditDialog(entity: entity, id: id, judul: judul),
  );
}

class _RiwayatAuditDialog extends StatefulWidget {
  final String entity;
  final Object id;
  final String judul;
  const _RiwayatAuditDialog(
      {required this.entity, required this.id, required this.judul});

  @override
  State<_RiwayatAuditDialog> createState() => _RiwayatAuditDialogState();
}

class _RiwayatAuditDialogState extends State<_RiwayatAuditDialog> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final hasil = await ApiClient.instance.aksi('si_audit_history', {
        'entity': widget.entity,
        'id': widget.id,
      });
      if (!mounted) return;
      setState(() {
        _rows = ((hasil['rows'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _total = (hasil['totalRevisi'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Riwayat Audit — ${widget.judul}'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: _error != null
            ? Center(child: Text(_error!, textAlign: TextAlign.center))
            : _rows == null
                ? const Center(child: CircularProgressIndicator())
                : _rows!.isEmpty
                    ? const Center(child: Text('Belum ada revisi tercatat.'))
                    : ListView(children: [
                        Text('$_total revisi total (25 terakhir ditampilkan)',
                            style: const TextStyle(fontSize: 11)),
                        const SizedBox(height: 6),
                        for (final r in _rows!)
                          ExpansionTile(
                            dense: true,
                            title: Text(
                                'Revisi ${r['revisi']} — ${r['waktu']}',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                            children: [
                              for (final k
                                  in (Map<String, dynamic>.from(
                                          (r['nilai'] as Map?) ?? {}))
                                      .entries)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 1),
                                  child: Row(children: [
                                    Expanded(
                                        child: Text(k.key,
                                            style: const TextStyle(
                                                fontSize: 11.5))),
                                    Expanded(
                                        child: Text('${k.value}',
                                            style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight:
                                                    FontWeight.w600))),
                                  ]),
                                ),
                            ],
                          ),
                      ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup')),
      ],
    );
  }
}
