import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Presentation, PresentationFile } from "@oai/artifact-tool";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT = path.join(ROOT, "docs/pos-apotik-emedik/uat-v1.34.23");
const RENDER = path.join(OUT, "rendered-pptx-api");
const DATA = JSON.parse(await fs.readFile(path.join(OUT, "presentation-data.json"), "utf8"));

const W = 1280;
const H = 720;
const C = {
  navy: "#0B1F33", blue: "#075985", teal: "#0F766E", green: "#15803D",
  amber: "#B45309", red: "#B91C1C", ink: "#172033", muted: "#526273",
  light: "#F4F7FA", mid: "#D9E5EC", white: "#FFFFFF", paleBlue: "#EAF3F8",
  paleGreen: "#DCFCE7", paleAmber: "#FFF7ED", paleRed: "#FEE2E2", purple: "#7C3AED",
};

async function bytes(file) {
  const b = await fs.readFile(file);
  return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
}

function addShape(slide, x, y, w, h, fill = C.white, line = C.mid, radius = "rounded-xl") {
  return slide.shapes.add({
    geometry: radius ? "roundRect" : "rect",
    position: { left: x, top: y, width: w, height: h },
    fill,
    line: { style: "solid", fill: line, width: 1 },
    ...(radius ? { borderRadius: radius } : {}),
  });
}

function addText(slide, text, x, y, w, h, size = 20, color = C.ink, bold = false, align = "left") {
  const box = slide.shapes.add({
    geometry: "textbox",
    position: { left: x, top: y, width: w, height: h },
    fill: "none",
    line: { style: "solid", fill: "none", width: 0 },
  });
  box.text = text;
  box.text.style = { fontSize: size, color, bold, alignment: align, fontFamily: "Aptos" };
  return box;
}

function chrome(slide, eyebrow, title, number) {
  slide.background.fill = C.light;
  addText(slide, eyebrow.toUpperCase(), 64, 34, 760, 24, 13, C.teal, true);
  addText(slide, title, 64, 67, 1120, 54, 36, C.navy, true);
  addText(slide, `POS APOTIK • v1.34.23 • ${String(number).padStart(2, "0")}`, 64, 683, 1090, 20, 12, "#64748B", false);
  addText(slide, String(number), 1170, 678, 48, 24, 13, C.blue, true, "right");
}

function statusColors(status) {
  if (status.includes("BLOCKED") && !status.startsWith("PASS")) return [C.paleRed, C.red];
  if (status.includes("BLOCKED") || status.includes("defect") || status.includes("perlu")) {
    return [C.paleAmber, C.amber];
  }
  return [C.paleGreen, C.green];
}

function notes(slide, body, sources = []) {
  const block = `${body}\n\n[Sources]\n${sources.map((s) => `- ${s}`).join("\n")}\n[/Sources]`;
  slide.speakerNotes.textFrame.setText(block);
}

function addMetric(slide, x, y, w, value, label, color) {
  addShape(slide, x, y, w, 116, C.white, C.mid, "rounded-2xl");
  addText(slide, value, x + 18, y + 16, w - 36, 45, 34, color, true);
  addText(slide, label, x + 18, y + 67, w - 36, 35, 16, C.muted, false);
}

const deck = Presentation.create({ slideSize: { width: W, height: H } });
let slideNo = 0;

// 1 — Editorial cover.
{
  const slide = deck.slides.add();
  slideNo += 1;
  slide.background.fill = C.navy;
  addText(slide, "UAT END-TO-END • DATA REAL SERVER DEMO", 72, 64, 800, 28, 14, "#67E8F9", true);
  addText(slide, "POS Apotik\nv1.34.23", 72, 142, 520, 150, 54, C.white, true);
  addText(slide, "Penjualan, racikan, procure-to-pay, stok, kedaluwarsa, akuntansi, dan laporan", 72, 320, 520, 105, 24, "#CBD5E1", false);
  addShape(slide, 690, 96, 492, 476, "#102C46", "#25627E", "rounded-3xl");
  addText(slide, "KEPUTUSAN", 730, 136, 380, 24, 14, "#67E8F9", true);
  addText(slide, "LULUS\nBERSYARAT", 730, 184, 390, 110, 42, C.white, true);
  addText(slide, "Layak untuk UAT/pilot terkontrol. Signing produksi, katalog volume, antrean live, dan rekonsiliasi laporan masih menjadi exit criterion.", 730, 325, 390, 150, 21, "#DCE8F0", false);
  addText(slide, "4 September 2026 • demo.ecampus.id/ecampus", 72, 648, 1030, 24, 16, "#94A3B8", false);
  notes(slide,
    "Presentasi ini merangkum UAT end-to-end POS Apotik v1.34.23 pada server demo. Keputusan LULUS BERSYARAT sengaja membedakan transaksi yang benar-benar tersimpan, tampilan yang berhasil dirender, dan integrasi yang masih diblokir backend. Rilis berisi APK Android dan installer Windows EXE langsung, bukan ZIP. Artefak masih untuk UAT atau pilot terkontrol sampai keystore Android dan sertifikat Authenticode tersedia.",
    ["https://demo.ecampus.id/ecampus/", "docs/pos-apotik-emedik/uat-v1.34.23/document-manifest.json"]);
}

// 2 — Executive metrics.
{
  const slide = deck.slides.add();
  slideNo += 1;
  chrome(slide, "Ringkasan eksekutif", "Volume yang benar-benar dijalankan", slideNo);
  addMetric(slide, 64, 155, 260, "300", "transaksi penjualan", C.blue);
  addMetric(slide, 348, 155, 260, "100 × 5", "dokumen P2P per tahap", C.teal);
  addMetric(slide, 632, 155, 260, "100", "jurnal vendor posted", C.green);
  addMetric(slide, 916, 155, 260, "6", "laporan keuangan render", C.purple);
  addShape(slide, 64, 310, 1112, 310, C.white, C.mid, "rounded-2xl");
  addText(slide, "Yang lulus", 92, 338, 320, 34, 24, C.green, true);
  addText(slide, "• 100 obat jadi\n• 100 obat racik\n• 100 gabungan\n• 100 PR–PO–BAST–tagihan–bayar\n• 100 jurnal vendor diposting", 92, 388, 450, 190, 20, C.ink, false);
  addText(slide, "Exit criterion produksi", 630, 338, 420, 34, 24, C.red, true);
  addText(slide, "• Seed katalog ≥100 item\n• Endpoint antrean live\n• Laporan penjualan berisi data\n• Saldo awal/posting otomatis stabil\n• APK dan EXE ditandatangani resmi", 630, 388, 475, 190, 20, C.ink, false);
  notes(slide,
    "Angka pada slide berasal dari ringkasan mesin UAT. Tenant demo digunakan bersama, sehingga angka total dashboard dapat lebih besar daripada data yang dibuat run ini. Kelulusan dihitung melalui prefix rilis dan kunci idempoten. Tiga ratus transaksi penjualan terdiri dari seratus obat jadi, seratus racikan, dan seratus gabungan. Rangkaian procure-to-pay dibuat seratus kali pada setiap tahap. Seratus pembayaran vendor ditelusuri ke jurnal yang dibuat, diposting, dan dibaca ulang. Enam halaman laporan keuangan berhasil dirender, tetapi keberhasilan render belum berarti validasi angka lulus.",
    ["docs/pos-apotik-emedik/uat-v1.34.23/screenshots/uat-summary.json", "docs/pos-apotik-emedik/uat-v1.34.23/screenshots/procurement-summary.json", "docs/pos-apotik-emedik/uat-v1.34.23/screenshots/vendor-journal-summary.json"]);
}

// 3 — Decision map.
{
  const slide = deck.slides.add();
  slideNo += 1;
  chrome(slide, "Status UAT", "PASS tidak sama dengan siap produksi", slideNo);
  const rows = [
    ["Penjualan", "300/300", "PASS", C.green],
    ["Procure-to-pay", "100/tahap", "PASS bersyarat", C.amber],
    ["Stok master", "2 item", "BLOCKED volume", C.red],
    ["Antrean pasien", "komponen", "BLOCKED backend", C.red],
    ["Akuntansi", "100 posted", "PASS vendor", C.green],
    ["Laporan", "6 render", "BLOCKED angka", C.amber],
  ];
  addText(slide, "AREA", 82, 154, 270, 28, 16, C.muted, true);
  addText(slide, "BUKTI", 474, 154, 190, 28, 16, C.muted, true);
  addText(slide, "KEPUTUSAN", 758, 154, 330, 28, 16, C.muted, true);
  rows.forEach((r, i) => {
    const y = 194 + i * 72;
    addShape(slide, 64, y, 1112, 58, i % 2 ? "#F8FAFC" : C.white, C.mid, "rounded-lg");
    addText(slide, r[0], 82, y + 15, 340, 30, 19, C.ink, true);
    addText(slide, r[1], 474, y + 15, 210, 30, 19, C.blue, true);
    addText(slide, r[2], 758, y + 15, 330, 30, 19, r[3], true);
  });
  notes(slide,
    "Matriks ini adalah kontrol anti-overclaim. PASS transaksi berarti transaksi berhasil disimpan dan diperiksa ulang. PASS komponen berarti tampilan atau widget berjalan dengan data terkontrol, tetapi backend live mungkin belum ada. BLOCKED menunjukkan prasyarat yang belum tersedia. PASS render laporan hanya membuktikan halaman dapat dibuka tanpa error fatal; validasi angka membutuhkan rekonsiliasi dengan dokumen sumber, periode, dan klasifikasi akun. Dengan definisi ini, pemilik proses dapat memberi sign-off terpisah untuk fungsi, integrasi, data, keamanan, dan deployment.",
    ["docs/pos-apotik-emedik/uat-v1.34.23/Laporan-UAT-dan-Manual-POS-Apotik-v1.34.23.docx"]);
}

// Nine scenario pairs: screenshot evidence + editable diagrams.
for (const item of DATA) {
  {
    const slide = deck.slides.add();
    slideNo += 1;
    chrome(slide, `Bukti ${item.index}`, item.title, slideNo);
    addShape(slide, 64, 142, 760, 450, C.white, C.mid, "rounded-2xl");
    slide.images.add({
      blob: await bytes(path.resolve(ROOT, item.screenshot)), contentType: "image/png", alt: item.caption,
      fit: "contain", geometry: "roundRect", borderRadius: "rounded-xl",
      position: { left: 78, top: 156, width: 732, height: 422 },
    });
    const [fill, color] = statusColors(item.status);
    addShape(slide, 850, 142, 326, 104, fill, color, "rounded-xl");
    addText(slide, "STATUS", 872, 158, 280, 20, 13, color, true);
    addText(slide, item.status, 872, 184, 280, 52, 16, color, true);
    addShape(slide, 850, 260, 326, 332, C.white, C.mid, "rounded-2xl");
    addText(slide, "HASIL AKTUAL", 872, 282, 270, 24, 14, C.teal, true);
    addText(slide, item.observation, 872, 318, 274, 210, 16, C.ink, false);
    addText(slide, `Narasi lengkap: ${item.narrativeWordCount} kata`, 872, 550, 274, 24, 14, C.muted, true);
    notes(slide, `${item.narrative.join("\n\n")}\n\nKriteria penerimaan: ${item.acceptance}`,
      ["https://demo.ecampus.id/ecampus/", item.screenshot.replaceAll("\\", "/"), "docs/pos-apotik-emedik/uat-v1.34.23/presentation-data.json"]);
  }

  {
    const slide = deck.slides.add();
    slideNo += 1;
    chrome(slide, `Diagram ${item.index}`, `${item.title}: peran, alur, dan data`, slideNo);
    const panels = [64, 440, 816];
    for (const x of panels) addShape(slide, x, 145, 344, 486, C.white, C.mid, "rounded-2xl");
    addText(slide, "USE CASE", 86, 166, 300, 26, 17, C.blue, true);
    addText(slide, `${item.actors[0]} → ${item.usecases[0]}\n${item.actors[1]} → ${item.usecases[1]}\n${item.actors[2]} → ${item.usecases[2]}\n${item.actors[3]} → ${item.usecases[3]}`, 86, 215, 296, 300, 16, C.ink, false);
    addShape(slide, 88, 524, 296, 78, C.paleBlue, C.blue, "rounded-lg");
    addText(slide, "RBAC + segregasi tugas", 104, 548, 264, 28, 17, C.blue, true, "center");

    addText(slide, "FLOWCHART", 462, 166, 300, 26, 17, C.teal, true);
    item.flow.forEach((step, i) => {
      const y = 211 + i * 60;
      addShape(slide, 462, y, 300, 43, i === item.flow.length - 1 ? C.paleGreen : "#F8FAFC", i === item.flow.length - 1 ? C.green : C.teal, "rounded-lg");
      addText(slide, `${i + 1}. ${step}`, 476, y + 11, 272, 23, 16, C.ink, i === item.flow.length - 1);
      if (i < item.flow.length - 1) addText(slide, "↓", 596, y + 42, 28, 19, 16, C.teal, true, "center");
    });

    addText(slide, "ERD / DATA FLOW", 838, 166, 300, 26, 17, C.purple, true);
    item.entities.forEach((entity, i) => {
      const y = 211 + i * 69;
      addShape(slide, 838, y, 300, 50, i === 0 ? "#EDE9FE" : "#F8FAFC", C.purple, "rounded-lg");
      addText(slide, entity.replace("\n", " • "), 852, y + 13, 272, 25, 16, C.ink, i === 0, "center");
      if (i < item.entities.length - 1) addText(slide, "↕ 1..n", 944, y + 48, 90, 20, 14, C.purple, true, "center");
    });
    addText(slide, item.gate, 838, 566, 300, 48, 15, C.amber, true, "center");
    notes(slide,
      `Diagram ini melengkapi bukti ${item.index}. Use case menunjukkan aktor dan tanggung jawab utama. Flowchart memperlihatkan urutan kontrol. ERD/data flow adalah model konseptual, bukan klaim nama tabel fisik. Gate yang tercantum harus dipenuhi sebelum skenario dapat diberi sign-off. Kontrol rinci: ${item.controls}. Kriteria penerimaan: ${item.acceptance}.`,
      ["docs/pos-apotik-emedik/uat-v1.34.23/presentation-data.json"]);
  }
}

// Risks.
{
  const slide = deck.slides.add();
  slideNo += 1;
  chrome(slide, "Risiko", "Delapan temuan yang menahan produksi", slideNo);
  const risks = [
    ["P0", "Katalog", "hanya 2 item", C.red], ["P0", "Antrean", "endpoint belum deploy", C.red],
    ["P0", "Laporan jual", "success / 0 rows", C.red], ["P0", "Signing", "APK debug + EXE unsigned", C.red],
    ["P0", "Saldo awal", "respons parse error", C.amber], ["P0", "Posting", "preview tertentu kosong", C.amber],
    ["P1", "Filter bayar", "marker mengembalikan 0", C.amber], ["P2", "Layout", "overflow 34 px", C.blue],
  ];
  risks.forEach((risk, i) => {
    const col = i % 2; const row = Math.floor(i / 2);
    const x = 64 + col * 564; const y = 150 + row * 116;
    addShape(slide, x, y, 536, 94, C.white, C.mid, "rounded-xl");
    addShape(slide, x + 16, y + 18, 64, 58, risk[3] === C.red ? C.paleRed : risk[3] === C.amber ? C.paleAmber : C.paleBlue, risk[3], "rounded-lg");
    addText(slide, risk[0], x + 28, y + 36, 40, 24, 17, risk[3], true, "center");
    addText(slide, risk[1], x + 98, y + 18, 380, 25, 19, C.ink, true);
    addText(slide, risk[2], x + 98, y + 50, 400, 24, 17, C.muted, false);
  });
  notes(slide,
    "Temuan P0 adalah exit criterion sebelum produksi, bukan sekadar catatan kosmetik. Release GitHub tetap dapat dipublikasikan sebagai UAT/pilot agar stakeholder dapat menguji klien dan dokumen, tetapi deployment produksi harus menunggu data master, endpoint, laporan, jalur akuntansi, dan signing resmi. Overflow tampilan diprioritaskan lebih rendah karena tidak merusak transaksi, namun tetap harus diretest pada resolusi umum.",
    ["docs/pos-apotik-emedik/uat-v1.34.23/Laporan-UAT-dan-Manual-POS-Apotik-v1.34.23.docx"]);
}

// Release assets.
{
  const slide = deck.slides.add();
  slideNo += 1;
  chrome(slide, "Distribusi", "Aset GitHub Release v1.34.23", slideNo);
  addShape(slide, 64, 150, 532, 360, C.white, C.mid, "rounded-2xl");
  addText(slide, "ANDROID", 92, 182, 300, 26, 15, C.teal, true);
  addText(slide, "APK", 92, 230, 300, 55, 42, C.navy, true);
  addText(slide, "POS-Apotik-v1.34.23-Android.apk", 92, 305, 450, 35, 20, C.ink, true);
  addText(slide, "Debug-signed sampai keystore pemilik tersedia. Gunakan untuk UAT/pilot, bukan upgrade produksi.", 92, 365, 450, 100, 18, C.muted, false);
  addShape(slide, 644, 150, 532, 360, C.white, C.mid, "rounded-2xl");
  addText(slide, "WINDOWS", 672, 182, 300, 26, 15, C.blue, true);
  addText(slide, "SETUP.EXE", 672, 230, 400, 55, 42, C.navy, true);
  addText(slide, "POS-Apotik-v1.34.23-Windows-Setup.exe", 672, 305, 450, 60, 20, C.ink, true);
  addText(slide, "Installer langsung—tidak ada ZIP. Jendela utama otomatis maximized. Authenticode menunggu sertifikat resmi.", 672, 378, 450, 100, 18, C.muted, false);
  addShape(slide, 64, 540, 1112, 82, C.paleBlue, C.blue, "rounded-xl");
  addText(slide, "Word • PDF • PPTX • Release notes • SHA256SUMS", 92, 566, 1056, 30, 22, C.blue, true, "center");
  notes(slide,
    "Aset Windows dipublikasikan sebagai installer EXE langsung sesuai permintaan, bukan ZIP. Installer memuat executable varian Apotik dan dependensi runtime. Startup desktop dimaksimalkan pada work area monitor sehingga halaman kasir dan screenshot menggunakan area layar seluas mungkin tanpa exclusive fullscreen. APK dan EXE harus diverifikasi menggunakan SHA-256. Karena credential signing produksi belum tersedia, release diberi batasan UAT/pilot secara eksplisit.",
    ["apps/ebisnis/installer/apotik.iss", "apps/ebisnis/windows/runner/win32_window.cpp", "apps/ebisnis/pubspec.yaml"]);
}

// Retest/rollout.
{
  const slide = deck.slides.add();
  slideNo += 1;
  chrome(slide, "Go-live", "Urutan aman dari UAT ke produksi", slideNo);
  const steps = [
    ["1", "Deploy backend", "endpoint antrean, seed katalog, laporan"],
    ["2", "Provision data", "≥100 item lintas kategori + batch"],
    ["3", "Retest integrasi", "300 jual + 100 P2P + 100 jurnal"],
    ["4", "Rekonsiliasi", "stok, vendor, buku besar, laporan"],
    ["5", "Signing", "keystore Android + Authenticode Windows"],
    ["6", "Pilot & monitor", "rollback bila kontrol kritis gagal"],
  ];
  steps.forEach((step, i) => {
    const x = 64 + i * 188;
    addShape(slide, x, 190, 164, 300, i === 5 ? C.paleGreen : C.white, i === 5 ? C.green : C.mid, "rounded-2xl");
    addShape(slide, x + 48, 220, 68, 68, i === 5 ? C.green : C.blue, i === 5 ? C.green : C.blue, "rounded-2xl");
    addText(slide, step[0], x + 66, 236, 32, 30, 24, C.white, true, "center");
    addText(slide, step[1], x + 14, 320, 136, 50, 19, C.navy, true, "center");
    addText(slide, step[2], x + 14, 390, 136, 80, 16, C.muted, false, "center");
    if (i < 5) addText(slide, "→", x + 166, 318, 22, 32, 24, C.teal, true, "center");
  });
  addShape(slide, 64, 530, 1104, 90, C.paleRed, C.red, "rounded-xl");
  addText(slide, "Rollback bila stok tidak terlacak, batch ED dapat dijual, privasi bocor, pembayaran tanpa sumber, jurnal tidak seimbang, atau laporan material berbeda.", 92, 554, 1048, 48, 18, C.red, true, "center");
  notes(slide,
    "Urutan rollout menjaga agar klien tidak mendahului backend dan data master. Setelah backend dipasang, provisioning harus idempoten. Retest menggunakan prefix baru agar dapat dipisahkan dari data UAT sebelumnya. Rekonsiliasi dilakukan oleh owner proses, bukan hanya tim teknis. Signing adalah gate terpisah. Pilot dimulai setelah sign-off, dengan rollback trigger yang disepakati sebelum deployment. Rollback klien memakai artefak rilis sebelumnya; rollback data/backend memakai backup serta reversal yang disetujui dan tidak menghapus audit trail.",
    ["docs/pos-apotik-emedik/uat-v1.34.23/Laporan-UAT-dan-Manual-POS-Apotik-v1.34.23.docx"]);
}

// Sign-off.
{
  const slide = deck.slides.add();
  slideNo += 1;
  chrome(slide, "Keputusan", "Sign-off lintas pemilik proses", slideNo);
  const owners = ["Owner Apotik", "Apoteker PJ", "Procurement", "Keuangan/Akuntansi", "IT/DevOps", "Keamanan/Privasi"];
  owners.forEach((owner, i) => {
    const col = i % 3; const row = Math.floor(i / 3);
    const x = 64 + col * 376; const y = 160 + row * 190;
    addShape(slide, x, y, 344, 154, C.white, C.mid, "rounded-2xl");
    addText(slide, owner, x + 22, y + 22, 300, 28, 19, C.navy, true);
    addText(slide, "Keputusan: __________________", x + 22, y + 72, 300, 24, 16, C.muted, false);
    addText(slide, "Tanggal / paraf: _____________", x + 22, y + 108, 300, 24, 16, C.muted, false);
  });
  addShape(slide, 64, 565, 1096, 58, C.paleAmber, C.amber, "rounded-xl");
  addText(slide, "Status saat rilis: UAT/PILOT • produksi menunggu seluruh P0 ditutup dan signing resmi", 92, 582, 1040, 26, 19, C.amber, true, "center");
  notes(slide,
    "Sign-off dipisahkan agar keputusan farmasi, pengadaan, keuangan, akuntansi, teknologi, keamanan, dan privasi tidak diwakili satu pihak. Setiap owner meninjau bukti, temuan, exit criterion, dan risiko di wilayahnya. Status UAT/pilot tidak boleh diubah menjadi produksi hanya karena installer tersedia di GitHub. Produksi membutuhkan seluruh P0 tertutup, build ditandatangani, dan rollback plan disetujui.",
    ["docs/pos-apotik-emedik/uat-v1.34.23/Laporan-UAT-dan-Manual-POS-Apotik-v1.34.23.docx"]);
}

await fs.mkdir(RENDER, { recursive: true });
for (const [index, slide] of deck.slides.items.entries()) {
  const stem = `slide-${String(index + 1).padStart(2, "0")}`;
  const png = await deck.export({ slide, format: "png", scale: 1 });
  await fs.writeFile(path.join(RENDER, `${stem}.png`), new Uint8Array(await png.arrayBuffer()));
  const layout = await slide.export({ format: "layout" });
  await fs.writeFile(path.join(RENDER, `${stem}.layout.json`), await layout.text());
}
const montage = await deck.export({ format: "webp", montage: true, scale: 1 });
await fs.writeFile(path.join(RENDER, "deck-montage.webp"), new Uint8Array(await montage.arrayBuffer()));
const pptx = await PresentationFile.exportPptx(deck);
const outPath = path.join(OUT, "Presentasi-UAT-POS-Apotik-v1.34.23.pptx");
await pptx.save(outPath);
console.log(`${outPath}\nSLIDES=${deck.slides.items.length}`);
