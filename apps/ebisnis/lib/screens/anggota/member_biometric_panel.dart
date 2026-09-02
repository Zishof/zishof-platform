import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/biometric_capture_bridge.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';

const _fingerprintSlots = <_BiometricSlot>[
  _BiometricSlot('JEMPOL_KANAN', 'Jempol kanan', Icons.fingerprint),
  _BiometricSlot('TELUNJUK_KANAN', 'Telunjuk kanan', Icons.fingerprint),
  _BiometricSlot('JEMPOL_KIRI', 'Jempol kiri', Icons.fingerprint),
  _BiometricSlot('TELUNJUK_KIRI', 'Telunjuk kiri', Icons.fingerprint),
  _BiometricSlot('JARI_CADANGAN', 'Jari cadangan', Icons.fingerprint),
];

const _faceSlots = <_BiometricSlot>[
  _BiometricSlot(
      'WAJAH_DEPAN_1', 'Wajah depan 1', Icons.face_retouching_natural),
  _BiometricSlot(
      'WAJAH_DEPAN_2', 'Wajah depan 2', Icons.face_retouching_natural),
  _BiometricSlot(
      'WAJAH_KIRI', 'Wajah sisi kiri', Icons.face_retouching_natural),
  _BiometricSlot(
      'WAJAH_KANAN', 'Wajah sisi kanan', Icons.face_retouching_natural),
  _BiometricSlot(
      'WAJAH_CADANGAN', 'Wajah cadangan', Icons.face_retouching_natural),
];

/// Pengelolaan 5 sidik jari dan 5 sampel wajah Member.
///
/// Cache lokal hanya memuat metadata slot. Template biometrik mentah langsung
/// dikirim ke endpoint terenkripsi dan tidak pernah ditulis ke SQLite/log/UI.
class MemberBiometricPanel extends StatefulWidget {
  const MemberBiometricPanel({
    super.key,
    required this.targetUserId,
    required this.memberName,
  });

  final String targetUserId;
  final String memberName;

  @override
  State<MemberBiometricPanel> createState() => _MemberBiometricPanelState();
}

class _MemberBiometricPanelState extends State<MemberBiometricPanel> {
  final _bridge = PosBiometricCaptureBridge();
  final Map<String, Map<String, dynamic>> _active = {};
  Map<String, dynamic> _deviceCapabilities = const {};
  Map<String, dynamic> _serverCapabilities = const {};
  String? _busySlot;
  String? _error;
  bool _loading = true;

  String get _cacheKey => 'secure:biometric-metadata:${widget.targetUserId}';

  PosBiometricReadiness get _readiness => PosBiometricReadiness(
        device: _deviceCapabilities,
        server: _serverCapabilities,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final cached = await CoreDb.instance.ambilCacheReferensi(_cacheKey);
    if (cached != null) {
      try {
        _applyRows(jsonDecode(cached) as List);
      } catch (_) {}
    }
    try {
      final deviceCapability = await _bridge.capabilities();
      final serverCapability =
          await ApiClient.instance.aksi('biometrik_kemampuan');
      final result = await ApiClient.instance.aksi('biometrik_daftar', {
        'target_user_id': widget.targetUserId,
      });
      final rows = result['data'] is List ? result['data'] as List : const [];
      await CoreDb.instance.simpanCacheReferensi(_cacheKey, jsonEncode(rows));
      if (!mounted) return;
      setState(() {
        _deviceCapabilities = deviceCapability;
        _serverCapabilities = serverCapability;
        _error = null;
      });
      _applyRows(rows);
    } catch (error) {
      if (mounted && _active.isEmpty) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyRows(List rows) {
    if (!mounted) return;
    final active = <String, Map<String, dynamic>>{};
    for (final value in rows) {
      if (value is! Map || value['active'] != true) continue;
      final row = Map<String, dynamic>.from(value);
      final key = '${row['modality']}:${row['position']}';
      active.putIfAbsent(key, () => row);
    }
    setState(() {
      _active
        ..clear()
        ..addAll(active);
    });
  }

  Future<bool> _confirmConsent(_BiometricSlot slot, String modality) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Persetujuan perekaman biometrik'),
            content: Text(
              'Pastikan ${widget.memberName} atau wali yang sah telah menyetujui '
              'perekaman ${modality == 'FINGERPRINT' ? 'sidik jari' : 'wajah'} '
              'untuk slot ${slot.label}. Template akan dienkripsi di server dan '
              'tidak dapat diunduh dari aplikasi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Persetujuan sudah diperoleh'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _capture(_BiometricSlot slot, String modality) async {
    if (!_readiness.enrollmentReady(modality)) {
      setState(() => _error = _readiness.reason(modality, enrollment: true));
      return;
    }
    if (!await _confirmConsent(slot, modality)) return;
    final key = '$modality:${slot.code}';
    setState(() {
      _busySlot = key;
      _error = null;
    });
    try {
      final sample = await _bridge.capture(modality);
      // ONLINE-ONLY: pendaftaran biometrik adalah kredensial, dan sidik jarinya
      // baru saja diambil dari perangkat. Mengantrekannya menahan data biometrik
      // di penyimpanan lokal, sekaligus membuat pengguna mengira pendaftarannya
      // sudah sah padahal server belum pernah menerimanya.
      final result = await ApiClient.instance.aksi('biometrik_simpan', {
        'target_user_id': widget.targetUserId,
        'modality': modality,
        'position': slot.code,
        'template_format': sample.templateFormat,
        'template_base64': sample.templateBase64,
        'provider': sample.provider,
        if (sample.livenessScore != null)
          'liveness_score': sample.livenessScore,
        if (sample.qualityScore != null) 'quality': sample.qualityScore,
        if (sample.qualityScore == null && sample.livenessScore != null)
          'quality': (sample.livenessScore! * 100).round(),
        'consent': true,
        'clientMutationId':
            'bio-${widget.targetUserId}-${slot.code}-${DateTime.now().microsecondsSinceEpoch}',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${slot.label} berhasil disimpan terenkripsi.'
            '${result['warning'] == null ? '' : ' ${result['warning']}'}'),
      ));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  Future<void> _revoke(_BiometricSlot slot, String modality) async {
    final key = '$modality:${slot.code}';
    final row = _active[key];
    final id = row?['id'];
    if (id == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Nonaktifkan biometrik?'),
            content: Text(
                '${slot.label} tidak lagi dapat dipakai untuk verifikasi.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Nonaktifkan')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _busySlot = key);
    try {
      await ApiClient.instance.aksi('biometrik_nonaktifkan', {
        'credential_id': id,
        'target_user_id': widget.targetUserId,
        'clientMutationId':
            'bio-revoke-${widget.targetUserId}-$id-${DateTime.now().microsecondsSinceEpoch}',
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fpReady = _readiness.enrollmentReady('FINGERPRINT');
    final faceReady = _readiness.enrollmentReady('FACE');
    final fpMatcherReady = _readiness.matcherReady('FINGERPRINT');
    final faceMatcherReady = _readiness.matcherReady('FACE');
    return AppFormSection(
      judul: 'Biometrik Member',
      deskripsi:
          'Maksimal 5 sidik jari dan 5 sampel wajah. Template disimpan terenkripsi di server; cache lokal hanya menyimpan status slot.',
      aksiJudul: IconButton(
        tooltip: 'Muat ulang status biometrik',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
      children: [
        if (!fpReady || !faceReady)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Perekaman belum sepenuhnya siap. '
              '${!fpReady ? 'Fingerprint: ${_readiness.reason('FINGERPRINT', enrollment: true)} ' : ''}'
              '${!faceReady ? 'Wajah: ${_readiness.reason('FACE', enrollment: true)}' : ''} '
              'Slot tetap tampil, tetapi Rekam dinonaktifkan agar tidak ada '
              'template palsu atau data yang tidak dapat diverifikasi.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if ((fpReady && !fpMatcherReady) ||
            (faceReady && !faceMatcherReady)) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Perekaman dapat dilakukan, tetapi verifikasi belum aktif untuk '
              '${[
                if (fpReady && !fpMatcherReady) 'fingerprint',
                if (faceReady && !faceMatcherReady) 'wajah',
              ].join(' dan ')} karena matcher server belum siap. '
              'Data boleh direkam untuk persiapan, namun kasir tetap menolak '
              'transaksi yang mewajibkan modalitas tersebut.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        if (_loading) const LinearProgressIndicator(),
        const SizedBox(height: 10),
        _diagnosticCard(),
        const SizedBox(height: 14),
        _slotGroup('Sidik jari', 'FINGERPRINT', _fingerprintSlots),
        const SizedBox(height: 16),
        _slotGroup('Pengenalan wajah', 'FACE', _faceSlots),
      ],
    );
  }

  Widget _diagnosticCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        initiallyExpanded: !_readiness.verificationReady('FINGERPRINT') ||
            !_readiness.verificationReady('FACE'),
        leading: const Icon(Icons.health_and_safety_outlined),
        title: const Text('Diagnostik kesiapan biometrik'),
        subtitle: const Text(
          'Perangkat, enkripsi, matcher, dan hak akses diperiksa terpisah.',
          style: TextStyle(fontSize: 11),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: [
          _diagnosticGroup('Fingerprint', 'FINGERPRINT'),
          const Divider(height: 22),
          _diagnosticGroup('Pengenalan wajah', 'FACE'),
        ],
      ),
    );
  }

  Widget _diagnosticGroup(String title, String modality) {
    final items = _readiness.diagnostics(modality);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.ready ? Icons.check_circle : Icons.cancel,
                  size: 17,
                  color: item.ready ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(item.detail,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryOf(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _slotGroup(String title, String modality, List<_BiometricSlot> slots) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final slot in slots) _slotCard(slot, modality)],
        ),
      ],
    );
  }

  Widget _slotCard(_BiometricSlot slot, String modality) {
    final key = '$modality:${slot.code}';
    final row = _active[key];
    final active = row != null;
    final busy = _busySlot == key;
    final ready = _readiness.enrollmentReady(modality);
    return Container(
      width: 210,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(
            color: active ? AppColors.primary : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(slot.icon,
                size: 20, color: active ? AppColors.primary : Colors.grey),
            const SizedBox(width: 7),
            Expanded(
                child: Text(slot.label,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Icon(active ? Icons.verified : Icons.radio_button_unchecked,
                size: 18, color: active ? Colors.green : Colors.grey),
          ]),
          const SizedBox(height: 6),
          Text(
            active
                ? 'Terdaftar · ${row['provider'] ?? 'provider'} · rev ${row['template_revision'] ?? '-'}'
                : 'Belum direkam',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busySlot == null && ready
                    ? () => _capture(slot, modality)
                    : null,
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(active ? Icons.replay : Icons.fiber_manual_record,
                        size: 15),
                label: Text(active ? 'Rekam ulang' : 'Rekam'),
              ),
            ),
            if (!ready)
              Tooltip(
                message: _readiness.reason(modality, enrollment: true),
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child:
                      Icon(Icons.info_outline, size: 18, color: Colors.amber),
                ),
              ),
            if (active)
              IconButton(
                tooltip: 'Nonaktifkan slot',
                onPressed:
                    _busySlot == null ? () => _revoke(slot, modality) : null,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
          ]),
        ],
      ),
    );
  }
}

class _BiometricSlot {
  const _BiometricSlot(this.code, this.label, this.icon);
  final String code;
  final String label;
  final IconData icon;
}
