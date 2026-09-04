import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Presentation, PresentationFile } from "@oai/artifact-tool";

const TMP_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(TMP_DIR, "../..");
const OUT = path.join(ROOT, "docs/pos-apotik-emedik/uat-v1.34.24");
const RENDER = path.join(OUT, "rendered-pptx");
const DATA = JSON.parse(await fs.readFile(path.join(OUT, "presentation-data.json"), "utf8"));
const SUMMARY = JSON.parse(await fs.readFile(path.join(OUT, "screenshots/uat-summary.json"), "utf8"));
const PROCUREMENT = JSON.parse(await fs.readFile(path.join(OUT, "screenshots/procurement-summary.json"), "utf8"));
const JOURNAL = JSON.parse(await fs.readFile(path.join(OUT, "screenshots/vendor-journal-summary.json"), "utf8"));
const FINANCIAL = JSON.parse(await fs.readFile(path.join(OUT, "screenshots/financial-report-summary.json"), "utf8"));

const W = 1280;
const H = 720;
const C = {
  deep: "#123524", green: "#166534", accent: "#16A34A", teal: "#0F766E",
  ink: "#172033", muted: "#526273", light: "#F0FDF4", mid: "#BBF7D0",
  white: "#FFFFFF", amber: "#B45309", paleAmber: "#FFF7ED",
  paleGreen: "#DCFCE7", paleTeal: "#ECFDF5", red: "#B91C1C",
};

async function bytes(file) {
  const buffer = await fs.readFile(file);
  return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
}

function addShape(slide, x, y, width, height, fill = C.white, line = C.mid, radius = "rounded-xl", name) {
  return slide.shapes.add({
    geometry: radius ? "roundRect" : "rect",
    name,
    position: { left: x, top: y, width, height },
    fill,
    line: { style: "solid", fill: line, width: 1 },
    ...(radius ? { borderRadius: radius } : {}),
  });
}

function addText(slide, text, x, y, width, height, size = 18, color = C.ink, bold = false, alignment = "left", name) {
  const shape = slide.shapes.add({
    geometry: "textbox",
    name,
    position: { left: x, top: y, width, height },
    fill: "none",
    line: { style: "solid", fill: "none", width: 0 },
  });
  shape.text = text;
  shape.text.style = { fontSize: size, color, bold, alignment, fontFamily: "Aptos" };
  return shape;
}

function addNode(slide, text, x, y, width, height, fill, line, name, size = 16) {
  const node = addShape(slide, x, y, width, height, fill, line, "rounded-lg", name);
  node.text = text;
  node.text.style = { fontSize: size, color: C.ink, bold: true, alignment: "center", fontFamily: "Aptos" };
  return node;
}

function connect(slide, from, to, fromSide, toSide, color = C.teal) {
  return slide.shapes.connect(from, to, {
    kind: "straight", fromSide, toSide,
    line: { style: "solid", fill: color, width: 2 },
    head: { type: "arrow", width: "sm", length: "sm" },
  });
}

function chrome(slide, eyebrow, title, number) {
  slide.background.fill = C.light;
  addText(slide, eyebrow.toUpperCase(), 64, 30, 800, 24, 13, C.green, true, "left", `eyebrow-${number}`);
  addText(slide, title, 64, 64, 1120, 52, 35, C.deep, true, "left", `title-${number}`);
  addText(slide, `APOTIK | v1.34.24 | ${String(number).padStart(2, "0")}`, 64, 684, 1030, 18, 12, C.muted, false);
  addText(slide, String(number), 1168, 680, 48, 22, 13, C.green, true, "right");
}

function notes(slide, body, sources = []) {
  slide.speakerNotes.textFrame.setText(`${body}\n\n[Sources]\n${sources.map((source) => `- ${source}`).join("\n")}\n[/Sources]`);
}

function shorten(text, max = 260) {
  if (text.length <= max) return text;
  const cut = text.slice(0, max - 1);
  return `${cut.slice(0, cut.lastIndexOf(" "))}…`;
}

function metric(slide, x, y, value, label, color) {
  addShape(slide, x, y, 252, 118, C.white, C.mid, "rounded-2xl");
  addText(slide, `${value}`, x + 18, y + 16, 216, 45, 34, color, true);
  addText(slide, label, x + 18, y + 70, 216, 30, 16, C.muted, false);
}

const deck = Presentation.create({ slideSize: { width: W, height: H } });
let slideNo = 0;

// Cover - custom green visual direction for the Apotik variant.
{
  const slide = deck.slides.add();
  slideNo += 1;
  slide.background.fill = C.deep;
  addText(slide, "UAT LIVE SERVER DEMO", 72, 70, 760, 28, 15, "#86EFAC", true);
  addText(slide, "Apotik", 72, 142, 520, 78, 54, C.white, true);
  addText(slide, "UAT End-to-End &\nPanduan Pengguna", 72, 230, 580, 118, 38, C.white, true);
  addText(slide, "Penjualan, racikan, persediaan, layar pasien, pengadaan, akuntansi, dan laporan", 72, 380, 560, 100, 22, "#D1FAE5", false);
  addShape(slide, 740, 112, 426, 412, "#1B4D35", "#4ADE80", "rounded-3xl");
  addText(slide, "HASIL", 782, 156, 310, 24, 14, "#86EFAC", true);
  addText(slide, "LULUS UAT", 782, 204, 330, 60, 40, C.white, true);
  addText(slide, "Backend dan volume data diverifikasi. APK produksi tetap menunggu keystore pemilik.", 782, 304, 320, 118, 21, "#D1FAE5", false);
  addText(slide, "4 September 2026 | demo.ecampus.id/ecampus", 72, 648, 1040, 24, 16, "#A7F3D0", false);
  notes(slide,
    "Presentasi ini menyampaikan hasil UAT Apotik v1.34.24 untuk pemilik proses, apoteker, procurement, keuangan, auditor, dan tim teknologi. Bukti berasal dari server demo, ringkasan mesin, dan tangkapan layar 1920 x 1080. Data obat, resep, pasien, dan transaksi adalah sample/UAT. Satu-satunya pengecualian distribusi adalah APK belum memakai keystore produksi.",
    ["https://demo.ecampus.id/ecampus/", "docs/pos-apotik-emedik/uat-v1.34.24/screenshots/uat-summary.json"]);
}

{
  const slide = deck.slides.add();
  slideNo += 1;
  chrome(slide, "Ringkasan", "Volume UAT telah memenuhi target utama", slideNo);
  metric(slide, 64, 155, SUMMARY.katalogItemTotal ?? 0, "item katalog", C.green);
  metric(slide, 342, 155, SUMMARY.bahanRacikanTerverifikasi ?? SUMMARY.bahanRacikanTotal ?? 0, "bahan racikan", C.teal);
  metric(slide, 620, 155, SUMMARY.resepSiapJualTerverifikasi ?? SUMMARY.resepSiapJualTotal ?? 0, "resep siap jual", C.accent);
  metric(slide, 898, 155, SUMMARY.totalTransaksiPenjualanLulus ?? 0, "transaksi lulus", C.deep);
  addText(slide, "Cakupan yang diverifikasi", 64, 334, 420, 34, 24, C.green, true);
  addText(slide,
    "• Obat jadi, racikan, dan gabungan\n• Batch, FEFO, stok, dan kedaluwarsa\n• Layar kedua dengan identitas tersamar\n• PR, PO, BAST, tagihan, dan pembayaran\n• Jurnal, posting, dan laporan keuangan",
    64, 385, 520, 200, 20, C.ink, false);
  addText(slide, "Batas distribusi", 682, 334, 360, 34, 24, C.amber, true);
  addShape(slide, 682, 382, 494, 172, C.paleAmber, C.amber, "rounded-2xl");
  addText(slide, "APK masih debug-signed. Gunakan untuk UAT/pilot perangkat terkontrol sampai keystore resmi tersedia.", 714, 421, 430, 98, 20, C.ink, true, "center");
  notes(slide,
    `Ringkasan mesin mencatat ${SUMMARY.katalogItemTotal ?? 0} item katalog, ${SUMMARY.bahanRacikanTerverifikasi ?? SUMMARY.bahanRacikanTotal ?? 0} bahan racikan, ${SUMMARY.resepSiapJualTerverifikasi ?? SUMMARY.resepSiapJualTotal ?? 0} resep siap jual, dan ${SUMMARY.totalTransaksiPenjualanLulus ?? 0} transaksi lulus. Procure-to-pay diperiksa 100 record per tahap, sedangkan ${FINANCIAL.sumberJurnalTerpostingTerverifikasi ?? 0} jurnal sample menjadi sumber laporan keuangan non-kosong.`,
    ["docs/pos-apotik-emedik/uat-v1.34.24/screenshots/uat-summary.json", "docs/pos-apotik-emedik/uat-v1.34.24/screenshots/procurement-summary.json", "docs/pos-apotik-emedik/uat-v1.34.24/screenshots/vendor-journal-summary.json", "docs/pos-apotik-emedik/uat-v1.34.24/screenshots/financial-report-summary.json"]);
}

{
  const slide = deck.slides.add();
  slideNo += 1;
  chrome(slide, "Alur end-to-end", "Transaksi tetap dapat ditelusuri sampai laporan", slideNo);
  const labels = ["Master & batch", "Resep / permintaan", "Penjualan / P2P", "Jurnal posted", "Laporan & audit"];
  const nodes = labels.map((label, index) => addNode(slide, label, 64 + index * 226, 245, 182, 104,
    index === 4 ? C.paleGreen : C.white, index === 4 ? C.green : C.teal, `e2e-${index}`, 18));
  for (let index = 0; index < nodes.length - 1; index += 1) connect(slide, nodes[index], nodes[index + 1], "right", "left");
  addShape(slide, 64, 440, 1086, 118, C.paleGreen, C.green, "rounded-2xl");
  addText(slide, "Prinsip audit: setiap angka laporan harus dapat kembali ke jurnal, dokumen sumber, detail item, batch, dan pengguna yang melakukan tindakan.", 98, 475, 1020, 58, 21, C.deep, true, "center");
  notes(slide,
    "Diagram ini menunjukkan rantai audit utama. Data master dan batch menjadi dasar resep atau permintaan. Penjualan dan procure-to-pay menghasilkan dokumen sumber. Transaksi yang lolos validasi dipetakan ke jurnal posted, lalu dilaporkan. Hubungan tersebut diuji melalui kode idempoten, referensi dokumen, dan pembacaan ulang hasil.",
    ["docs/pos-apotik-emedik/uat-v1.34.24/Laporan-UAT-dan-Panduan-Apotik-v1.34.24.docx"]);
}

for (const item of DATA) {
  {
    const slide = deck.slides.add();
    slideNo += 1;
    chrome(slide, `Bukti ${item.index}`, item.title, slideNo);
    addShape(slide, 64, 142, 770, 474, C.white, C.mid, "rounded-2xl");
    slide.images.add({
      blob: await bytes(path.resolve(ROOT, item.screenshot)),
      contentType: "image/png",
      alt: item.title,
      fit: "contain",
      geometry: "roundRect",
      borderRadius: "rounded-xl",
      position: { left: 78, top: 156, width: 742, height: 446 },
    });
    addText(slide, "YANG DIBUKTIKAN", 866, 162, 280, 24, 14, C.green, true);
    addText(slide, shorten(item.paragraphs[0], 310), 866, 205, 290, 186, 17, C.ink, false);
    addShape(slide, 850, 424, 326, 168, C.paleGreen, C.green, "rounded-xl");
    addText(slide, "KONTROL UTAMA", 876, 448, 270, 24, 14, C.green, true);
    addText(slide, shorten(item.controls, 210), 876, 486, 270, 76, 16, C.deep, true);
    notes(slide,
      `${item.paragraphs.join("\n\n")}\n\nKriteria penerimaan: ${item.acceptance}`,
      ["https://demo.ecampus.id/ecampus/", item.screenshot, "docs/pos-apotik-emedik/uat-v1.34.24/presentation-data.json"]);
  }

  {
    const slide = deck.slides.add();
    slideNo += 1;
    chrome(slide, `Diagram ${item.index}`, `${item.title}: peran, proses, dan data`, slideNo);
    const panelXs = [52, 428, 804];
    for (const x of panelXs) addShape(slide, x, 140, 344, 506, C.white, C.mid, "rounded-2xl");

    addText(slide, "USE CASE", 76, 160, 290, 26, 18, C.green, true);
    const actorNodes = [];
    const caseNodes = [];
    for (let index = 0; index < 4; index += 1) {
      const y = 205 + index * 93;
      actorNodes.push(addNode(slide, item.actors[index], 70, y, 110, 58, C.paleGreen, C.green, `actor-${item.index}-${index}`, 15));
      caseNodes.push(addNode(slide, item.usecases[index], 228, y, 144, 58, C.white, C.teal, `case-${item.index}-${index}`, 15));
    }
    for (let index = 0; index < 4; index += 1) connect(slide, actorNodes[index], caseNodes[index], "right", "left");

    addText(slide, "FLOWCHART", 452, 160, 290, 26, 18, C.teal, true);
    const flowNodes = [];
    for (let index = 0; index < 6; index += 1) {
      const y = 202 + index * 68;
      flowNodes.push(addNode(slide, `${index + 1}. ${item.flow[index]}`, 452, y, 296, 46,
        index === 5 ? C.paleGreen : C.white, index === 5 ? C.green : C.teal,
        `flow-${item.index}-${index}`, 15));
    }
    for (let index = 0; index < 5; index += 1) connect(slide, flowNodes[index], flowNodes[index + 1], "bottom", "top");

    addText(slide, "ERD / ALIRAN DATA", 828, 160, 290, 26, 18, C.deep, true);
    const entityNodes = [];
    for (let index = 0; index < 5; index += 1) {
      const y = 202 + index * 75;
      entityNodes.push(addNode(slide, item.entities[index].replace("\n", " • "), 828, y, 296, 50,
        index === 4 ? C.paleAmber : C.paleTeal, index === 4 ? C.amber : C.green,
        `entity-${item.index}-${index}`, 15));
    }
    for (let index = 0; index < 4; index += 1) connect(slide, entityNodes[index], entityNodes[index + 1], "bottom", "top", C.green);
    addText(slide, shorten(item.gate, 150), 824, 585, 304, 50, 15, C.amber, true, "center");
    notes(slide,
      `Use case memperlihatkan aktor dan tanggung jawab pada ${item.title}. Flowchart menampilkan urutan kerja yang harus dijalankan. ERD/aliran data memperlihatkan keterhubungan konseptual antardata; nama tabel fisik dapat berbeda. ${item.gate} Kriteria penerimaan: ${item.acceptance}`,
      ["docs/pos-apotik-emedik/uat-v1.34.24/presentation-data.json"]);
  }
}

{
  const slide = deck.slides.add();
  slideNo += 1;
  chrome(slide, "Kontrol rilis", "Semua gerbang ditutup kecuali signing APK produksi", slideNo);
  const checks = [
    ["Backend", "endpoint dan provisioning aktif"],
    ["Data", "katalog, bahan, resep, antrean"],
    ["Transaksi", "obat jadi, racikan, gabungan"],
    ["P2P", "PR sampai pembayaran vendor"],
    ["Akuntansi", "jurnal posted dan laporan"],
    ["Distribusi", "APK debug-signed; EXE installer"],
  ];
  checks.forEach((entry, index) => {
    const row = Math.floor(index / 2);
    const col = index % 2;
    const x = 64 + col * 560;
    const y = 156 + row * 144;
    addShape(slide, x, y, 528, 112, index === 5 ? C.paleAmber : C.white, index === 5 ? C.amber : C.mid, "rounded-xl");
    addText(slide, index === 5 ? "PENGECUALIAN" : "PASS", x + 22, y + 22, 140, 24, 14, index === 5 ? C.amber : C.green, true);
    addText(slide, entry[0], x + 168, y + 20, 320, 26, 20, C.deep, true);
    addText(slide, entry[1], x + 168, y + 56, 320, 28, 17, C.muted, false);
  });
  notes(slide,
    "Gerbang backend, volume data, transaksi, procure-to-pay, akuntansi, laporan, dan visual telah diperiksa. APK tetap menggunakan sertifikat debug karena keystore produksi belum diberikan. Pengecualian ini harus terlihat pada release notes dan tidak boleh ditafsirkan sebagai izin distribusi store atau penggantian instalasi produksi.",
    ["docs/pos-apotik-emedik/uat-v1.34.24/RELEASE_NOTES.md"]);
}

{
  const slide = deck.slides.add();
  slideNo += 1;
  chrome(slide, "Sign-off", "Keputusan tetap dimiliki oleh pemilik proses", slideNo);
  const owners = ["Owner Apotik", "Apoteker PJ", "Procurement", "Keuangan/Akuntansi", "IT/DevOps", "Keamanan/Privasi"];
  owners.forEach((owner, index) => {
    const col = index % 3;
    const row = Math.floor(index / 3);
    const x = 64 + col * 374;
    const y = 158 + row * 188;
    addShape(slide, x, y, 342, 150, C.white, C.mid, "rounded-2xl");
    addText(slide, owner, x + 22, y + 20, 296, 26, 19, C.deep, true);
    addText(slide, "Keputusan: __________________", x + 22, y + 70, 296, 22, 16, C.muted, false);
    addText(slide, "Tanggal/paraf: _______________", x + 22, y + 108, 296, 22, 16, C.muted, false);
  });
  addShape(slide, 64, 560, 1090, 66, C.paleGreen, C.green, "rounded-xl");
  addText(slide, "Rilis UAT/pilot dapat digunakan setelah checksum diverifikasi; produksi menunggu keystore APK resmi.", 94, 580, 1030, 30, 19, C.deep, true, "center");
  notes(slide,
    "Sign-off dipisahkan menurut tanggung jawab. Pemilik Apotik dan apoteker menilai keselamatan serta operasi farmasi; procurement dan keuangan menilai dokumen serta rekonsiliasi; IT/DevOps menilai deployment dan rollback; keamanan menilai privasi layar publik. Ketersediaan installer tidak menggantikan persetujuan para pemilik proses.",
    ["docs/pos-apotik-emedik/uat-v1.34.24/Laporan-UAT-dan-Panduan-Apotik-v1.34.24.docx"]);
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
const outPath = path.join(OUT, "Presentasi-UAT-Apotik-v1.34.24.pptx");
await pptx.save(outPath);
console.log(`${outPath}\nSLIDES=${deck.slides.items.length}`);
