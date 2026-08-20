import 'package:flutter/material.dart';

import '../services/server_config.dart';

/// Ubah alamat server. Pengguna boleh menempel URL utuh -- host dan context
/// path dipisahkan otomatis.
class PengaturanServerScreen extends StatefulWidget {
  const PengaturanServerScreen({super.key});

  @override
  State<PengaturanServerScreen> createState() => _PengaturanServerScreenState();
}

class _PengaturanServerScreenState extends State<PengaturanServerScreen> {
  late final TextEditingController _host =
      TextEditingController(text: ServerConfig.instance.host);
  late final TextEditingController _context =
      TextEditingController(text: ServerConfig.instance.contextPath);
  late bool _https = ServerConfig.instance.https;

  @override
  void dispose() {
    _host.dispose();
    _context.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    await ServerConfig.instance.simpan(
      host: _host.text,
      contextPath: _context.text,
      https: _https,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final pratinjau = () {
      final h = ServerConfig.bersihkanHost(_host.text);
      final c = ServerConfig.bersihkanContextPath(_context.text);
      return '${_https ? 'https' : 'http'}://$h${c.isEmpty ? '' : '/$c'}/Api';
    }();

    return Scaffold(
      appBar: AppBar(title: const Text('Alamat Server')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: 'Host',
              hintText: 'kantinpcu.ecampus.id',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _context,
            decoration: const InputDecoration(
              labelText: 'Context path',
              hintText: 'petra',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gunakan HTTPS'),
            value: _https,
            onChanged: (v) => setState(() => _https = v),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Alamat yang akan dipakai',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                SelectableText(pratinjau,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _simpan, child: const Text('Simpan')),
        ],
      ),
    );
  }
}
