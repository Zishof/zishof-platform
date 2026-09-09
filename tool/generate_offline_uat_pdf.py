from __future__ import annotations

import io
import math
from pathlib import Path

from PIL import Image, ImageChops
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph, Table, TableStyle

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "pos" / "uat-offline-20260909"
OUT = OUT_DIR / "Manual-UAT-Offline-Local-First-POS-v1.34.32.pdf"
SCREEN = OUT_DIR / "screenshots"
PHOTO_ROOT = Path(
    r"C:\opt\Claude-Workspace\.codex-remote-attachments\01a0681c-4812-7ed3-924d-fd88131bedd1\3b12b33f-8f44-4b64-a30e-6c8ca06397ac"
)

PAGE = landscape(A4)
W, H = PAGE
NAVY = colors.HexColor("#0F1E33")
BLUE = colors.HexColor("#1677D2")
CYAN = colors.HexColor("#0E7490")
GREEN = colors.HexColor("#15803D")
AMBER = colors.HexColor("#D97706")
RED = colors.HexColor("#C62828")
INK = colors.HexColor("#162033")
MUTED = colors.HexColor("#5E6F89")
PALE = colors.HexColor("#F3F6FA")


def register_fonts() -> None:
    candidates = [
        Path(r"C:\Windows\Fonts\arial.ttf"),
        Path(r"C:\Windows\Fonts\segoeui.ttf"),
    ]
    bolds = [
        Path(r"C:\Windows\Fonts\arialbd.ttf"),
        Path(r"C:\Windows\Fonts\segoeuib.ttf"),
    ]
    regular = next((p for p in candidates if p.exists()), None)
    bold = next((p for p in bolds if p.exists()), None)
    if regular and bold:
        pdfmetrics.registerFont(TTFont("UI", str(regular)))
        pdfmetrics.registerFont(TTFont("UI-Bold", str(bold)))


register_fonts()
FONT = "UI" if "UI" in pdfmetrics.getRegisteredFontNames() else "Helvetica"
BOLD = "UI-Bold" if "UI-Bold" in pdfmetrics.getRegisteredFontNames() else "Helvetica-Bold"

styles = getSampleStyleSheet()
BODY = ParagraphStyle(
    "body", parent=styles["BodyText"], fontName=FONT, fontSize=10.3,
    leading=14.3, textColor=INK, spaceAfter=6,
)
SMALL = ParagraphStyle(
    "small", parent=BODY, fontSize=8.8, leading=11.6, textColor=MUTED,
)
CALLOUT = ParagraphStyle(
    "callout", parent=BODY, fontSize=9.0, leading=11.5, leftIndent=0,
)


def footer(c: canvas.Canvas, page_no: int) -> None:
    c.setStrokeColor(colors.HexColor("#DCE3EC"))
    c.line(34, 24, W - 34, 24)
    c.setFont(FONT, 7.5)
    c.setFillColor(MUTED)
    c.drawString(36, 12, "eBisnis POS • UAT Offline & Local-First • 9 September 2026")
    c.drawRightString(W - 36, 12, f"v1.34.32 • Halaman {page_no}")


def page_title(c: canvas.Canvas, title: str, subtitle: str = "") -> None:
    c.setFillColor(NAVY)
    c.rect(0, H - 52, W, 52, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont(BOLD, 18)
    c.drawString(34, H - 33, title)
    if subtitle:
        c.setFont(FONT, 8.5)
        c.setFillColor(colors.HexColor("#D8E8F7"))
        c.drawRightString(W - 34, H - 31, subtitle)


def paragraph(c: canvas.Canvas, text: str, x: float, y_top: float,
              width: float, style=BODY) -> float:
    p = Paragraph(text, style)
    _, ph = p.wrap(width, H)
    p.drawOn(c, x, y_top - ph)
    return y_top - ph


def bullet_block(c: canvas.Canvas, items: list[str], x: float, y: float,
                 width: float, style=BODY) -> float:
    for item in items:
        y = paragraph(c, f"• {item}", x, y, width, style) - 2
    return y


def next_page(c: canvas.Canvas, page_no: int) -> int:
    footer(c, page_no)
    c.showPage()
    return page_no + 1


def cropped_image(path: Path) -> tuple[ImageReader, int, int]:
    im = Image.open(path).convert("RGB")
    if path.parent == SCREEN:
        # Screenshot test memakai kanvas 2560×1392 agar elemen tidak pernah
        # terpotong. Untuk dokumen, ambil area kerja di kiri dan buang ruang
        # kosong kanan/bawah supaya teks tetap besar serta mudah dibaca.
        right = min(im.width, 1200)
        probe = im.crop((20, 0, right, im.height - 40))
        sample_x = min(probe.width - 30, 980)
        sample_y = min(probe.height - 60, 980)
        background = Image.new("RGB", probe.size, probe.getpixel((sample_x, sample_y)))
        content = ImageChops.difference(probe, background).convert("L")
        content_box = content.point(lambda p: 255 if p > 14 else 0).getbbox()
        bottom = min(im.height, 760, (content_box[3] + 28) if content_box else 760)
        im = im.crop((0, 0, right, bottom))
    # Hilangkan hanya bingkai hitam murni dari screenshot runner Windows.
    bg = Image.new("RGB", im.size, (0, 0, 0))
    diff = ImageChops.difference(im, bg).convert("L")
    bbox = diff.point(lambda p: 255 if p > 12 else 0).getbbox()
    if bbox:
        left, top, right, bottom = bbox
        if left > 20 or top > 20 or right < im.width - 20 or bottom < im.height - 20:
            im = im.crop(bbox)
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    buf.seek(0)
    return ImageReader(buf), im.width, im.height


def annotated_image_page(c: canvas.Canvas, page_no: int, title: str,
                         image_path: Path, callouts: list[tuple[float, float, str]],
                         intro: str) -> int:
    page_title(c, title, "Bukti visual beranotasi")
    y = paragraph(c, intro, 36, H - 68, W - 72, SMALL)
    img, iw, ih = cropped_image(image_path)
    image_top = y - 8
    notes_h = 92
    max_h = image_top - notes_h - 34
    max_w = W - 72
    scale = min(max_w / iw, max_h / ih)
    dw, dh = iw * scale, ih * scale
    x0 = (W - dw) / 2
    y0 = notes_h + 30
    c.setFillColor(colors.white)
    c.roundRect(x0 - 4, y0 - 4, dw + 8, dh + 8, 5, fill=1, stroke=0)
    c.drawImage(img, x0, y0, dw, dh, preserveAspectRatio=True, mask="auto")
    for i, (xf, yf, _) in enumerate(callouts, start=1):
        px = x0 + xf * dw
        py = y0 + (1 - yf) * dh
        c.setLineWidth(2.2)
        c.setStrokeColor(RED)
        c.circle(px, py, 13, fill=0, stroke=1)
        c.setFillColor(RED)
        c.circle(px, py, 9, fill=1, stroke=0)
        c.setFillColor(colors.white)
        c.setFont(BOLD, 8)
        c.drawCentredString(px, py - 3, str(i))
    col_w = (W - 84) / 2
    for i, (_, _, text) in enumerate(callouts):
        col = i % 2
        row = i // 2
        xx = 42 + col * col_w
        yy = 104 - row * 30
        c.setFillColor(RED)
        c.circle(xx + 8, yy - 5, 7, fill=1, stroke=0)
        c.setFillColor(colors.white)
        c.setFont(BOLD, 7)
        c.drawCentredString(xx + 8, yy - 7.5, str(i + 1))
        paragraph(c, text, xx + 20, yy + 3, col_w - 26, CALLOUT)
    return next_page(c, page_no)


def box(c: canvas.Canvas, x: float, y: float, w: float, h: float,
        title: str, note: str, color=BLUE) -> None:
    c.setFillColor(colors.white)
    c.setStrokeColor(color)
    c.setLineWidth(1.4)
    c.roundRect(x, y, w, h, 8, fill=1, stroke=1)
    c.setFillColor(color)
    c.setFont(BOLD, 10)
    c.drawString(x + 10, y + h - 18, title)
    paragraph(c, note, x + 10, y + h - 26, w - 20, SMALL)


def arrow(c: canvas.Canvas, x1: float, y1: float, x2: float, y2: float,
          label: str = "") -> None:
    c.setStrokeColor(MUTED)
    c.setFillColor(MUTED)
    c.setLineWidth(1.4)
    c.line(x1, y1, x2, y2)
    angle = math.atan2(y2 - y1, x2 - x1)
    for delta in (-0.52, 0.52):
        c.line(x2, y2, x2 - 8 * math.cos(angle + delta),
               y2 - 8 * math.sin(angle + delta))
    if label:
        c.setFont(FONT, 7.4)
        c.drawCentredString((x1 + x2) / 2, y1 + 5, label)


def poly_arrow(c: canvas.Canvas, points: list[tuple[float, float]],
               label: str = "", label_at: tuple[float, float] | None = None) -> None:
    """Garis siku-siku dengan kepala panah pada segmen terakhir."""
    c.setStrokeColor(MUTED)
    c.setFillColor(MUTED)
    c.setLineWidth(1.4)
    path = c.beginPath()
    path.moveTo(*points[0])
    for point in points[1:]:
        path.lineTo(*point)
    c.drawPath(path, fill=0, stroke=1)
    (x1, y1), (x2, y2) = points[-2], points[-1]
    angle = math.atan2(y2 - y1, x2 - x1)
    for delta in (-0.52, 0.52):
        c.line(x2, y2, x2 - 8 * math.cos(angle + delta),
               y2 - 8 * math.sin(angle + delta))
    if label:
        lx, ly = label_at or ((x1 + x2) / 2, (y1 + y2) / 2)
        c.setFillColor(MUTED)
        c.setFont(FONT, 7.4)
        c.drawCentredString(lx, ly + 4, label)


def build() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUT), pagesize=PAGE, pageCompression=1)
    c.setTitle("Manual dan Hasil UAT Offline Local-First POS v1.34.32")
    c.setAuthor("Tim eBisnis / Zishof")
    page_no = 1

    # Cover
    c.setFillColor(NAVY)
    c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColor(BLUE)
    c.rect(0, 0, 18, H, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont(BOLD, 30)
    c.drawString(58, H - 140, "Manual & Hasil UAT Offline")
    c.setFont(BOLD, 20)
    c.drawString(58, H - 177, "POS Kantin • Apotek • Sales • Akuntansi")
    c.setFont(FONT, 12)
    c.setFillColor(colors.HexColor("#CFE3F5"))
    c.drawString(58, H - 210, "Perbaikan transaksi pending, local-first, posting, dan laporan")
    c.setFillColor(colors.HexColor("#163251"))
    c.roundRect(58, 135, W - 116, 175, 12, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont(BOLD, 14)
    c.drawString(82, 278, "HASIL")
    c.setFont(BOLD, 25)
    c.setFillColor(colors.HexColor("#6EE7B7"))
    c.drawString(82, 238, "LULUS — 845/845 tes otomatis")
    c.setFont(FONT, 11)
    c.setFillColor(colors.white)
    c.drawString(82, 208, "1/1 skenario visual Windows • 4 screenshot • endpoint produksi kembali JSON")
    c.drawString(82, 184, "Versi kandidat: 1.34.32+195 • 9 September 2026")
    page_no = next_page(c, page_no)

    # Ringkasan
    page_title(c, "1. Ringkasan keputusan", "UAT berbasis risiko")
    y = H - 78
    y = paragraph(c,
        "Perbaikan ini menutup dua jenis kegagalan yang sebelumnya terlihat sama di kasir, padahal penanganannya berbeda. Gangguan jaringan seperti HTTP 522 harus tetap dapat dicoba ulang. Sebaliknya, penolakan bisnis—misalnya saldo member tidak cukup—harus dihentikan, ditandai <b>Perlu koreksi</b>, dan tidak dikirim berulang tanpa perubahan data.",
        36, y, W - 72)
    data = [
        ["Area", "Perilaku yang diverifikasi", "Hasil"],
        ["Kantin", "Tunai/manual diantre lokal; Voucher/saldo/PIN menunggu ACK", "LULUS"],
        ["Apotek", "Katalog, batch, metode, dan laporan cache-first; transaksi final tervalidasi server", "LULUS"],
        ["Sales & CRUD", "Mutasi queueable memakai ID sementara dan outbox idempoten", "LULUS"],
        ["Akuntansi", "Draf dapat lokal; posting/closing final hanya setelah ACK", "LULUS"],
        ["Laporan", "Snapshot lokal bertimestamp; tanpa cache muncul penjelasan + Detail", "LULUS"],
        ["Regresi", "Seluruh suite Flutter", "845/845"],
    ]
    t = Table(data, colWidths=[115, 500, 110], repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), NAVY), ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), BOLD), ("FONTNAME", (0, 1), (-1, -1), FONT),
        ("FONTSIZE", (0, 0), (-1, -1), 8.5), ("LEADING", (0, 0), (-1, -1), 11),
        ("GRID", (0, 0), (-1, -1), .5, colors.HexColor("#CBD5E1")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"), ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, PALE]),
        ("TEXTCOLOR", (2, 1), (2, -1), GREEN), ("FONTNAME", (2, 1), (2, -1), BOLD),
        ("LEFTPADDING", (0, 0), (-1, -1), 7), ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 7), ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    _, th = t.wrap(W - 72, H)
    t.drawOn(c, 36, y - th - 8)
    paragraph(c,
        "<b>Makna LULUS:</b> aplikasi mengikuti kontrak keselamatan local-first. Istilah ini bukan izin untuk menganggap otorisasi saldo, obat terkendali, posting jurnal, atau closing sebagai sukses ketika server belum memberi jawaban.",
        36, y - th - 28, W - 72, BODY)
    page_no = next_page(c, page_no)

    # Root cause
    page_title(c, "2. Analisis insiden AB20909202600019", "Akar masalah & koreksi")
    y = H - 78
    y = paragraph(c,
        "Server menolak transaksi Voucher Pejuang Rp149.500 karena saldo SAHRUL ARIFIN hanya Rp3.160. Penolakan tersebut benar dan tidak boleh dilemahkan. Masalah berada pada klasifikasi klien lama: pesan server lama tidak membawa kode kesalahan, sehingga dianggap gangguan sementara dan otomatis dicoba ulang sembilan kali.",
        36, y, W - 72)
    box(c, 40, 300, 170, 125, "1 • Server menolak", "Saldo aktual lebih kecil daripada nilai transaksi. Tidak ada jurnal atau pengurangan saldo yang boleh dibentuk.", RED)
    box(c, 245, 300, 170, 125, "2 • Klien mengira sementara", "Pesan tanpa kode masuk jalur retry. Koneksi pulih tidak akan mengubah saldo.", AMBER)
    box(c, 450, 300, 170, 125, "3 • v1.34.32 memarkir", "Pesan saldo/limit/metode diklasifikasi sebagai penolakan permanen: status Perlu koreksi.", BLUE)
    box(c, 655, 300, 145, 125, "4 • Operator memilih", "Topup resmi, koreksi member, atau ganti ke pembayaran lokal yang benar-benar diterima.", GREEN)
    arrow(c, 210, 362, 245, 362)
    arrow(c, 415, 362, 450, 362)
    arrow(c, 620, 362, 655, 362)
    y = 275
    y = bullet_block(c, [
        "Kode transaksi, waktu, toko, kasir, item, harga, dan total tidak diubah ketika metode dikoreksi.",
        "Split payment lama dihapus hanya pada alur koreksi metode yang dipilih operator, sehingga satu transaksi tidak memiliki dua interpretasi pembayaran.",
        "HTTP 522/5xx tetap berada di jalur retry. Teks 'saldo' yang kebetulan muncul pada badan respons gateway tidak salah diklasifikasikan sebagai penolakan bisnis.",
        "Transaksi yang sudah tersinkron tidak dapat diubah melalui jalur lokal ini; koreksi final harus memakai prosedur server yang berwenang.",
    ], 48, y, W - 96)
    page_no = next_page(c, page_no)

    page_no = annotated_image_page(c, page_no,
        "3. Bukti awal — status sinkronisasi transaksi",
        PHOTO_ROOT / "1-Photo-1.jpg",
        [(0.71, 0.56, "Label merah menandai transaksi masih menunggu dan belum boleh dianggap final."),
         (0.72, 0.70, "Label hijau membuktikan transaksi lain sudah memperoleh ACK server."),
         (0.91, 0.49, "Menu aksi membuka rincian tanpa menghapus jejak transaksi lokal.")],
        "Foto lapangan sebelum perbaikan memperlihatkan transaksi Voucher Pejuang berdampingan dengan transaksi yang sudah tersinkron. Anotasi membedakan status operasional yang harus dibaca kasir.")

    page_no = annotated_image_page(c, page_no,
        "4. Bukti awal — alasan penolakan saldo",
        PHOTO_ROOT / "2-Photo-2.jpg",
        [(0.34, 0.19, "Kode transaksi yang sama menjadi kunci idempotensi dan penelusuran."),
         (0.32, 0.30, "Status PENDING lama disertai sembilan percobaan; v1.34.32 mengubahnya menjadi Perlu koreksi."),
         (0.45, 0.69, "Alasan saldo harus ditindaklanjuti lewat topup/koreksi, bukan menekan kirim berulang.")],
        "Rincian lapangan menunjukkan penyebab bisnis yang tegas. Server tidak sedang gagal: ia melindungi saldo pusat dari pemotongan melebihi saldo tersedia.")

    page_no = annotated_image_page(c, page_no,
        "5. Hasil perbaikan — panduan operator",
        SCREEN / "01-transaksi-perlu-koreksi.png",
        [(0.20, 0.11, "Judul menegaskan transaksi belum selesai dan membutuhkan tindakan."),
         (0.36, 0.29, "Langkah koreksi menyebut kode, member, saldo, dan pilihan pembayaran yang aman."),
         (0.19, 0.51, "Informasi Teknis tetap tertutup agar kasir tidak dibebani detail implementasi.")],
        "Panel produksi memisahkan bahasa operasional dari data teknis. Kasir memperoleh langkah yang dapat dilakukan tanpa membaca stack trace.")

    page_no = annotated_image_page(c, page_no,
        "6. Hasil perbaikan — Detail teknis",
        SCREEN / "02-detail-teknis-dibuka.png",
        [(0.25, 0.22, "Pesan utama tetap sama ketika detail dibuka."),
         (0.53, 0.61, "Kode referensi, action, status, dan alasan server dapat disalin untuk admin."),
         (0.14, 0.65, "Tombol salin mengurangi salah ketik saat eskalasi ke tim teknis.")],
        "Tombol Informasi Teknis memenuhi kebutuhan dukungan tanpa menampilkan detail sensitif secara permanen. Password tidak pernah dimasukkan ke bukti.")

    page_no = annotated_image_page(c, page_no,
        "7. Laporan offline — snapshot bertimestamp",
        SCREEN / "03-laporan-salinan-lokal.png",
        [(0.44, 0.23, "Banner menyebut waktu terakhir data diperbarui dan meminta muat ulang setelah online."),
         (0.31, 0.48, "Status Perlu koreksi dibedakan dari Tersinkron."),
         (0.68, 0.48, "Metode pembayaran tetap terlihat untuk rekonsiliasi operator.")],
        "Laporan yang pernah dimuat tidak menjadi halaman kosong saat koneksi putus. Snapshot tetap berguna, tetapi tidak boleh dibaca sebagai angka real-time.")

    page_no = annotated_image_page(c, page_no,
        "8. Matriks layanan offline",
        SCREEN / "04-matriks-batas-offline.png",
        [(0.30, 0.28, "Pagar keselamatan menjelaskan mengapa beberapa aksi tetap menunggu server."),
         (0.37, 0.48, "Setiap modul memiliki status offline yang eksplisit, bukan klaim seragam."),
         (0.69, 0.82, "Draf jurnal dipisahkan dari posting final dan laporan resmi.")],
        "Matriks ini menjadi panduan singkat bagi pengguna dan reviewer UAT. Local-first diterapkan sesuai risiko domain, bukan sekadar mengubah semua kegagalan menjadi sukses lokal.")

    # Flowchart
    page_title(c, "9. Flowchart transaksi Kantin yang aman", "Alur keputusan tanpa panah overlap")
    box(c, 40, 420, 160, 82, "A. Pilih metode", "Tunai/manual, Voucher/saldo, PIN, biometrik, atau hutang.", BLUE)
    box(c, 245, 420, 170, 82, "B. Otorisasi pusat?", "Dibaca dari master metode, bukan nama tampilan.", AMBER)
    box(c, 470, 455, 155, 70, "C1. Ya — minta ACK", "Server memeriksa saldo, limit, identitas, dan toko.", RED)
    box(c, 470, 340, 155, 70, "C2. Simpan lokal", "Payload lengkap dan kode idempoten masuk outbox.", GREEN)
    box(c, 670, 420, 135, 90, "D. Respons server", "Sukses, 522/5xx, atau penolakan bisnis.", CYAN)
    box(c, 55, 130, 180, 82, "E1. Gangguan", "Pending; retry dengan backoff. Keranjang tidak hilang.", AMBER)
    box(c, 330, 130, 180, 82, "E2. Ditolak", "Perlu koreksi; retry otomatis dihentikan.", RED)
    box(c, 605, 130, 170, 82, "E3. Diterima", "Tersinkron; baru masuk proses jurnal server.", GREEN)
    arrow(c, 200, 461, 245, 461, "validasi")
    poly_arrow(c, [(415, 466), (445, 466), (445, 490), (470, 490)], "ya", (447, 492))
    poly_arrow(c, [(415, 450), (445, 450), (445, 375), (470, 375)], "tidak", (447, 382))
    arrow(c, 625, 490, 670, 472, "otorisasi")
    poly_arrow(c, [(625, 375), (648, 375), (648, 438), (670, 438)], "saat online", (648, 403))
    poly_arrow(c, [(737, 420), (737, 285), (145, 285), (145, 212)], "522/5xx", (145, 250))
    poly_arrow(c, [(737, 420), (737, 272), (420, 272), (420, 212)], "ditolak", (420, 244))
    poly_arrow(c, [(737, 420), (737, 250), (690, 250), (690, 212)], "sukses", (690, 231))
    paragraph(c, "Semua konektor mengikuti jalur siku-siku dan berhenti pada tepi kotak. Tidak ada panah yang melintasi teks atau menutupi simpul keputusan.", 55, 103, 720, SMALL)
    page_no = next_page(c, page_no)

    # ERD / data flow
    page_title(c, "10. Aliran data & ERD ringkas", "Identitas, outbox, jurnal, laporan")
    entities = [
        (55, 390, "Transaksi Lokal", "kode_unik (PK)\npayload_json\nstatus\njumlah_retry"),
        (330, 390, "Metode Pembayaran", "id (PK)\nmanual\nmemotong_deposit\nmasuk_hutang"),
        (605, 390, "Member", "id (PK)\nsaldo\nlimit\naturan PIN"),
        (55, 210, "Transaksi Server", "id (PK)\nkode_unik (UK)\nstatus final\ntotal"),
        (330, 210, "Jurnal", "referensi transaksi\ndebet\nkredit\nstatus posting"),
        (605, 210, "Laporan Cache", "kunci filter\nsnapshot\ndisimpan_pada\nsumber periode"),
    ]
    for x, y, title, note in entities:
        box(c, x, y, 175, 110, title, note, BLUE if y > 300 else GREEN)
    arrow(c, 230, 445, 330, 445, "N:1")
    arrow(c, 505, 445, 605, 445, "butuh bila saldo")
    arrow(c, 142, 390, 142, 320, "sinkron idempoten")
    arrow(c, 230, 265, 330, 265, "1:N setelah final")
    arrow(c, 505, 265, 605, 265, "agregasi terposting")
    paragraph(c,
        "<b>Aturan kunci:</b> kode_unik mencegah duplikasi ketika jaringan putus setelah server sebenarnya menerima transaksi. Laporan cache tidak membaca transaksi pending sebagai jurnal final; snapshot hanya berasal dari respons laporan server yang lengkap.",
        55, 178, 720, BODY)
    page_no = next_page(c, page_no)

    # Operational sections
    for title, intro, items in [
        ("11. UAT Kantin POS",
         "Skenario Kantin memverifikasi pembayaran lokal yang aman serta penolakan saldo pada server. Perbaikan berlaku pada kode bersama seluruh varian Desktop/Android.",
         ["Tunai/manual: payload disimpan di SQLite, kode idempoten dibuat sekali, lalu dikirim di latar belakang.",
          "Voucher/saldo/PIN/biometrik: pembayaran tidak boleh selesai hanya berdasarkan cache; ACK server wajib.",
          "Gangguan 522: pesan ramah tampil, detail teknis dapat disalin, dan transaksi tidak digandakan.",
          "Saldo tidak cukup: status berubah menjadi Perlu koreksi, retry otomatis berhenti, operator mendapat langkah topup/ganti metode.",
          "Koreksi metode hanya menawarkan metode manual, nonhutang, tanpa PIN, dan tidak memotong saldo."]),
        ("12. UAT POS Apotek",
         "Apotek memiliki risiko tambahan: FEFO, kedaluwarsa, resep, stok batch, dan register obat terkendali. Karena itu offline penuh tidak boleh menghilangkan validasi keselamatan.",
         ["Pencarian obat, racikan, produksi, metode pembayaran, dan batch memakai salinan lokal yang dipisah per varian, tenant, pengguna, toko, serta kata kunci.",
          "Jika server putus, hasil cache tetap dapat dipakai untuk menyiapkan keranjang; kegagalan menampilkan Detail teknis.",
          "Pembayaran final tetap menunggu validasi server. Keranjang tidak dibersihkan ketika permintaan gagal.",
          "Register obat terkendali dan risiko kedaluwarsa tidak pernah direka dari cache kosong.",
          "Tiga laporan Apotek memakai snapshot bertimestamp; tanpa snapshot, aplikasi menjelaskan cara memuatnya."]),
        ("13. UAT Sales & CRUD",
         "CRUD yang aman ditunda mengikuti pola local-first bersama. Pengguna dapat melanjutkan pekerjaan tanpa menunggu server, dan konflik tetap dapat diaudit.",
         ["Create/Update/Delete queueable: validasi lokal, simpan data dan outbox, tampilkan status lokal, lalu sinkronkan.",
          "ID sementara tidak boleh masuk ke API yang mensyaratkan ID final; relasi anak ditukar atomik setelah induk diterima.",
          "Penghapusan lokal bersifat soft dan dapat dipulihkan selama perintah belum diterima server.",
          "Approval, pembatalan final, dan tindakan yang membalik stok/jurnal tetap online-only.",
          "Seluruh form yang gagal mempertahankan isian sehingga operator tidak mengulang data dari awal."]),
        ("14. UAT Jurnal, posting, dan laporan",
         "Akuntansi membedakan draf kerja dengan fakta buku besar. Offline membantu menyiapkan dan membaca, tetapi tidak boleh menerbitkan laporan resmi dari transaksi yang belum final.",
         ["Jurnal Umum dapat mempertahankan draf; setiap baris hanya boleh mengisi satu sisi Debet atau Kredit.",
          "Posting dan closing final menunggu server karena memerlukan akun aktif, periode terbuka, hak akses, nomor, dan keseimbangan global.",
          "Laporan generik dan Apotek membaca snapshot lokal terlebih dahulu serta menampilkan waktu pembaruan.",
          "Tanpa cache, pesan menyebut bahwa server diperlukan dan transaksi pending belum masuk angka resmi.",
          "Tombol Detail membuka jejak teknis; pesan utama tetap mudah dipahami pengguna nonteknis."]),
    ]:
        page_title(c, title, "Langkah & kriteria penerimaan")
        y = paragraph(c, intro, 42, H - 82, W - 84, BODY) - 8
        y = bullet_block(c, items, 56, y, W - 112, BODY)
        c.setFillColor(colors.HexColor("#E8F7EE"))
        c.roundRect(50, 85, W - 100, 58, 8, fill=1, stroke=0)
        c.setFillColor(GREEN)
        c.setFont(BOLD, 12)
        c.drawString(68, 119, "Kriteria penerimaan: LULUS")
        c.setFont(FONT, 9)
        c.setFillColor(INK)
        c.drawString(68, 98, "Data tidak hilang, status tidak menyesatkan, retry tidak menggandakan transaksi, dan aksi berisiko tetap fail-closed.")
        page_no = next_page(c, page_no)

    # Test evidence
    page_title(c, "15. Bukti pengujian & prosedur reproduksi", "Dapat diulang oleh tim UAT")
    y = H - 82
    y = paragraph(c,
        "Pengujian dilakukan pada source yang sama dengan kandidat rilis. Suite otomatis mencakup model, database SQLite, outbox, widget, kontrak API, hak akses, kanal pembaruan varian, laporan, Apotek, Sales, Keuangan, dan Akuntansi.",
        42, y, W - 84)
    test_data = [
        ["Pengujian", "Hasil", "Bukti"],
        ["Flutter unit/widget/contract", "845 lulus • 0 gagal", "flutter test --no-pub"],
        ["Core database", "2 lulus • 0 gagal", "payload koreksi + audit waktu"],
        ["Visual Windows", "1 lulus • 0 gagal", "4 PNG, 2560×1392; area kerja dipotong proporsional"],
        ["Endpoint eBisnis", "HTTP 401 JSON tanpa token", "server hidup; respons ±1.014 ms"],
        ["Endpoint Nahl", "HTTP 401 JSON tanpa token", "server hidup; respons ±554 ms"],
        ["Login demo eBisnis", "success; token tersedia", "respons ±743 ms; token tidak dicetak"],
    ]
    t = Table(test_data, colWidths=[235, 210, 300])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), NAVY), ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), BOLD), ("FONTNAME", (0, 1), (-1, -1), FONT),
        ("FONTSIZE", (0, 0), (-1, -1), 9), ("GRID", (0, 0), (-1, -1), .5, colors.HexColor("#CBD5E1")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, PALE]),
        ("LEFTPADDING", (0, 0), (-1, -1), 7), ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7), ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    _, th = t.wrap(W - 84, H)
    t.drawOn(c, 42, y - th - 10)
    y = y - th - 28
    paragraph(c,
        "<b>Reproduksi offline:</b> sinkronkan master sekali, putuskan jaringan, buat transaksi Tunai/manual, pastikan status Menunggu dan data tetap ada setelah aplikasi dibuka ulang. Sambungkan kembali dan pastikan kode yang sama menjadi Tersinkron. Untuk Voucher/saldo, pastikan tombol tidak menyatakan sukses sebelum ACK. Untuk laporan, pastikan snapshot bertimestamp tampil atau pesan tanpa-cache menyediakan Detail.",
        42, y, W - 84, BODY)
    page_no = next_page(c, page_no)

    # Deploy and operator response
    page_title(c, "16. Catatan deploy & tindak lanjut", "Pemisahan klien dan server")
    y = H - 82
    y = paragraph(c,
        "Perbaikan insiden saldo berada pada POS Desktop/Android dan tidak memerlukan deploy server. Pagar server yang menolak saldo tidak cukup harus dipertahankan. Server dapat ditingkatkan kemudian agar selalu mengirim kode bisnis terstruktur, namun klien v1.34.32 telah kompatibel dengan pesan server lama.",
        42, y, W - 84)
    y = bullet_block(c, [
        "Jangan membuat transaksi pengganti untuk kode pending yang sama; lakukan koreksi pada transaksi tersebut.",
        "Jangan mengubah Voucher menjadi Tunai kecuali uang tunai benar-benar telah diterima dan operator mencentang konfirmasi.",
        "Sesudah koneksi kembali, buka Riwayat Sinkronisasi, periksa Perlu koreksi, lalu kirim satu kali setelah penyebab diperbaiki.",
        "Jika laporan berbeda, samakan tenant, toko, satuan kerja, periode, dan status posting; transaksi pending memang belum termasuk.",
        "Lampirkan Informasi Teknis ketika eskalasi. Jangan mengirim password atau token sesi.",
    ], 56, y - 8, W - 112)
    c.setFillColor(NAVY)
    c.roundRect(52, 95, W - 104, 84, 10, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont(BOLD, 14)
    c.drawString(72, 145, "Kesimpulan")
    c.setFont(FONT, 10)
    c.drawString(72, 121, "Kandidat v1.34.32 memenuhi UAT otomatis 100% dan memperbaiki retry transaksi saldo tanpa melemahkan integritas server.")
    c.drawString(72, 104, "Offline dipakai untuk kesinambungan kerja; otorisasi pusat dan posting final tetap menunggu ACK yang sah.")
    footer(c, page_no)
    c.save()


if __name__ == "__main__":
    build()
    print(OUT)
