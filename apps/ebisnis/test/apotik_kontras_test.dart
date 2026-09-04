import 'dart:math' as math;

import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Luminansi relatif WCAG 2.1 (§ relative luminance).
double _luminansi(Color c) {
  double kanal(double v) {
    final s = v; // sudah 0..1
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * kanal(c.r) + 0.7152 * kanal(c.g) + 0.0722 * kanal(c.b);
}

/// Rasio kontras WCAG antara dua warna solid.
double kontras(Color a, Color b) {
  final la = _luminansi(a);
  final lb = _luminansi(b);
  final tinggi = math.max(la, lb);
  final rendah = math.min(la, lb);
  return (tinggi + 0.05) / (rendah + 0.05);
}

/// Warna semu-transparan di atas latar solid, sebagaimana benar-benar terlihat.
Color _diAtas(Color depan, Color latar) => Color.alphaBlend(depan, latar);

void main() {
  // Ambang WCAG 2.1 AA: 4,5:1 untuk teks normal, 3:1 untuk teks besar dan
  // untuk komponen grafis (ikon, garis tepi).
  const ambangTeks = 4.5;
  const ambangGrafis = 3.0;

  for (final (namaTema, t) in <(String, ApotikDesignTokens)>[
    ('light', ApotikDesignTokens.light),
    ('dark', ApotikDesignTokens.dark),
  ]) {
    group('Kontras token apotik — $namaTema', () {
      final latar = <String, Color>{
        'surface': t.surface,
        'surfaceMuted': t.surfaceMuted,
      };

      test('warna teks utama & sekunder lolos ambang teks', () {
        latar.forEach((namaLatar, bg) {
          expect(kontras(t.textPrimary, bg), greaterThanOrEqualTo(ambangTeks),
              reason: 'textPrimary di atas $namaLatar');
          expect(kontras(t.textSecondary, bg), greaterThanOrEqualTo(ambangTeks),
              reason: 'textSecondary di atas $namaLatar');
        });
      });

      test('varian TEKS status lolos ambang teks', () {
        final teksStatus = <String, Color>{
          'successText': t.successText,
          'warningText': t.warningText,
          'dangerText': t.dangerText,
          'info': t.info,
          'clinicalPurple': t.clinicalPurple,
          'primary': t.primary,
        };
        latar.forEach((namaLatar, bg) {
          teksStatus.forEach((nama, warna) {
            expect(kontras(warna, bg), greaterThanOrEqualTo(ambangTeks),
                reason: '$nama di atas $namaLatar');
          });
        });
      });

      test('warna status penuh lolos ambang GRAFIS (ikon & garis tepi)', () {
        final grafis = <String, Color>{
          'success': t.success,
          'warning': t.warning,
          'danger': t.danger,
          'info': t.info,
        };
        latar.forEach((namaLatar, bg) {
          grafis.forEach((nama, warna) {
            expect(kontras(warna, bg), greaterThanOrEqualTo(ambangGrafis),
                reason: '$nama sebagai ikon di atas $namaLatar');
          });
        });
      });

      test('label pill tetap terbaca di atas latar tipisnya sendiri', () {
        // ApotikStatusPill melukis latar warna status dengan alpha 0,10 di
        // atas surface, lalu menulis label dengan varian teks di atasnya.
        final pasangan = <String, (Color, Color)>{
          'sukses': (t.successText, t.success),
          'peringatan': (t.warningText, t.warning),
          'bahaya': (t.dangerText, t.danger),
        };
        pasangan.forEach((nama, p) {
          // Pill dipakai di dalam kartu (surface) maupun langsung di atas
          // latar halaman (surfaceMuted) -- keduanya harus lolos.
          latar.forEach((namaLatar, bg) {
            final latarPill = _diAtas(p.$2.withValues(alpha: 0.10), bg);
            expect(kontras(p.$1, latarPill), greaterThanOrEqualTo(ambangTeks),
                reason: 'label pill $nama di atas $namaLatar');
          });
        });
      });
    });
  }

  test('varian teks BEDA dari warna status penuh pada tema terang', () {
    // Kalau seseorang menyamakannya lagi, kontras label pill kembali jatuh ke
    // 3,0-3,3:1 -- test ini menjelaskan kenapa keduanya sengaja terpisah.
    const t = ApotikDesignTokens.light;
    expect(t.successText, isNot(t.success));
    expect(t.warningText, isNot(t.warning));
    expect(t.dangerText, isNot(t.danger));
  });
}
