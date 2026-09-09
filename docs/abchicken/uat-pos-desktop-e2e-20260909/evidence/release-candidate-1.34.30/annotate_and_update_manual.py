from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(__file__).resolve().parent
DOCX = ROOT / "User-Manual-dan-UAT-E2E-AB-Chicken-POS-Desktop-2026-09-09.docx"
ANNOTATED = EVIDENCE / "annotated"
MARKER = "Lampiran A — Regresi Kandidat Rilis v1.34.30"


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
        Path("C:/Windows/Fonts/calibrib.ttf" if bold else "C:/Windows/Fonts/calibri.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def annotate(source: Path, target: Path, callouts: list[tuple[int, tuple[int, int, int, int], str]]) -> None:
    image = Image.open(source).convert("RGB")
    # Flutter integration screenshots are stored on a larger black canvas. Crop that
    # padding so the operational screen remains legible when placed in the manual.
    content_box = image.getbbox()
    if content_box:
        image = image.crop((0, 0, content_box[2], content_box[3]))
    draw = ImageDraw.Draw(image)
    number_font = font(35)
    label_font = font(27)
    for number, box, label in callouts:
        x1, y1, x2, y2 = box
        draw.rounded_rectangle(box, radius=12, outline="#e31b23", width=8)
        circle_x = max(20, x1 - 24)
        circle_y = max(20, y1 - 24)
        draw.ellipse((circle_x - 26, circle_y - 26, circle_x + 26, circle_y + 26), fill="#e31b23")
        text = str(number)
        bounds = draw.textbbox((0, 0), text, font=number_font)
        draw.text(
            (circle_x - (bounds[2] - bounds[0]) / 2, circle_y - (bounds[3] - bounds[1]) / 2 - 3),
            text,
            fill="white",
            font=number_font,
        )
        label_bounds = draw.textbbox((0, 0), label, font=label_font)
        label_width = label_bounds[2] - label_bounds[0] + 32
        label_height = label_bounds[3] - label_bounds[1] + 22
        label_x = min(max(12, x1 + 20), image.width - label_width - 12)
        label_y = max(12, y1 - label_height - 12)
        draw.rounded_rectangle(
            (label_x, label_y, label_x + label_width, label_y + label_height),
            radius=8,
            fill="#e31b23",
        )
        draw.text((label_x + 16, label_y + 8), label, fill="white", font=label_font)
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, quality=95)


def set_cell_shading(cell, fill: str) -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), fill)
    tc_pr.append(shd)


def format_table(table) -> None:
    table.style = "Table Grid"
    table.autofit = False
    for index, cell in enumerate(table.rows[0].cells):
        set_cell_shading(cell, "17365D")
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        for paragraph in cell.paragraphs:
            for run in paragraph.runs:
                run.font.bold = True
                run.font.color.rgb = RGBColor(255, 255, 255)
                run.font.size = Pt(8)
    for row in table.rows[1:]:
        for cell in row.cells:
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            for paragraph in cell.paragraphs:
                for run in paragraph.runs:
                    run.font.size = Pt(8)


def add_heading(document: Document, title: str) -> None:
    paragraph = document.add_paragraph()
    paragraph.style = document.styles["Heading 1"]
    run = paragraph.add_run(title)
    run.font.color.rgb = RGBColor(37, 117, 178)


def add_body(document: Document, text: str) -> None:
    paragraph = document.add_paragraph(text)
    paragraph.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    paragraph.paragraph_format.space_after = Pt(5)
    paragraph.paragraph_format.line_spacing = 1.05
    for run in paragraph.runs:
        run.font.size = Pt(9)


def add_picture_page(document: Document, title: str, image_path: Path, caption: str, explanation: str) -> None:
    document.add_page_break()
    add_heading(document, title)
    paragraph = document.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.add_run().add_picture(str(image_path), width=Inches(9.55))
    caption_paragraph = document.add_paragraph(caption)
    caption_paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for run in caption_paragraph.runs:
        run.font.italic = True
        run.font.size = Pt(8)
        run.font.color.rgb = RGBColor(89, 100, 117)
    add_body(document, explanation)


def main() -> None:
    ANNOTATED.mkdir(parents=True, exist_ok=True)
    summary_before = ANNOTATED / "01-ringkasan-data-settle-beranotasi.png"
    summary_after = ANNOTATED / "02-ringkasan-setelah-siklus-beranotasi.png"
    journal_last = ANNOTATED / "03-jurnal-halaman-terakhir-beranotasi.png"

    annotate(
        EVIDENCE / "data" / "00-ringkasan-data-settle.png",
        summary_before,
        [
            (1, (195, 145, 1895, 210), "Pastikan seluruh gate lulus"),
            (2, (195, 210, 1895, 340), "Periksa volume data pilot"),
            (3, (195, 340, 1895, 975), "Semua kontrol harus hijau"),
        ],
    )
    annotate(
        EVIDENCE / "action" / "10-ringkasan-setelah-siklus.png",
        summary_after,
        [
            (1, (195, 145, 1895, 210), "Gate tetap lulus setelah transaksi"),
            (2, (670, 210, 1040, 340), "Jurnal bertambah menjadi 312"),
            (3, (195, 340, 1895, 975), "Tidak ada integritas yang gagal"),
        ],
    )
    annotate(
        EVIDENCE / "reports" / "20-keseluruhan-jurnal-halaman-terakhir.png",
        journal_last,
        [
            (1, (12, 300, 1908, 520), "Telusuri jurnal sampai baris terakhir"),
            (2, (12, 520, 1908, 590), "Debit dan kredit harus sama"),
            (3, (12, 590, 1908, 650), "608 baris • halaman 44 dari 44"),
        ],
    )

    document = Document(DOCX)
    # Recreate the addendum on reruns while preserving the original 74-page manual.
    body = document._element.body
    marker_element = next(
        (paragraph._element for paragraph in document.paragraphs if MARKER in paragraph.text),
        None,
    )
    if marker_element is not None:
        marker_index = list(body).index(marker_element)
        if marker_index > 0 and list(body)[marker_index - 1].xpath(".//w:br[@w:type='page']"):
            marker_index -= 1
        for element in list(body)[marker_index:]:
            if element.tag != qn("w:sectPr"):
                body.remove(element)

    for section in document.sections:
        for paragraph in section.footer.paragraphs:
            for run in paragraph.runs:
                run.text = run.text.replace("Versi 1.34.27 build 190", "Versi 1.34.30 build 193")

    document.add_page_break()
    add_heading(document, MARKER)
    add_body(
        document,
        "Lampiran ini merekam pengujian regresi terhadap build yang akan dipublikasikan. Data historis pada "
        "bagian utama manual tetap dipertahankan sebagai bukti UAT awal. Kandidat 1.34.30 build 193 kemudian "
        "menjalankan ulang kontrak aplikasi, pemeriksaan volume, seluruh transisi status, posting jurnal, serta "
        "enam laporan akuntansi melalui POS Desktop. Aplikasi Web tidak dipakai untuk melakukan transaksi.",
    )

    gate_rows = [
        ("Analisis statis", "Berkas varian dan updater", "LULUS"),
        ("Kontrak aplikasi", "23 pengujian", "LULUS 23/23"),
        ("Isolasi kanal", "7 pengujian updater", "LULUS 7/7"),
        ("Data settle", "13 layar; daftar utama ≥50 record", "LULUS 13/13"),
        ("Aksi E2E", "Pesanan sampai POS dan kembali ke stok", "LULUS 10/10"),
        ("Laporan", "Jurnal, Buku Besar, NS, LR, Neraca, Arus Kas", "LULUS 6/6"),
    ]
    table = document.add_table(rows=1, cols=3)
    table.rows[0].cells[0].text = "Gate"
    table.rows[0].cells[1].text = "Cakupan"
    table.rows[0].cells[2].text = "Hasil"
    for gate, scope, result in gate_rows:
        cells = table.add_row().cells
        cells[0].text = gate
        cells[1].text = scope
        cells[2].text = result
    format_table(table)

    document.add_paragraph()
    add_body(
        document,
        "Dokumen representatif yang diproses adalah UAT-AB-REQ-0006, UAT-AB-PR-0008, UAT-AB-PO-0008, "
        "UAT-AB-BAST-0008, UAT-AB-INV-0009, UAT-AB-PAY-0009, UAT-AB-PROD-0009, UAT-AB-SHP-0009, "
        "UAT-AB-CLM-0009, dan UAT-AB-POS-00016. Posting BAST, tagihan, pembayaran, produksi, pengiriman, "
        "dan penjualan membentuk jurnal 307 sampai 312.",
    )

    add_picture_page(
        document,
        "Data pilot sebelum transaksi kandidat rilis",
        summary_before,
        "Gambar 37  Volume data dan gate integritas kandidat rilis",
        "Kotak 1 menunjukkan gerbang kelulusan global. Kotak 2 merangkum 50 resep, 100 bahan baku, 120 "
        "penjualan POS, serta 170 record pada proses pengadaan, produksi, dan pengiriman. Kotak 3 menjadi "
        "kontrol sebelum operator memilih dokumen DRAFT: semua indikator harus hijau sehingga transaksi tidak "
        "dipaksakan pada data yang belum lengkap.",
    )
    add_picture_page(
        document,
        "Integritas setelah seluruh siklus operasional",
        summary_after,
        "Gambar 38  Ringkasan sesudah pesanan, pengadaan, produksi, pengiriman, dan POS",
        "Setelah sepuluh aksi selesai, indikator pada kotak 1 tetap lulus. Kotak 2 memperlihatkan jurnal "
        "terposting bertambah dari 306 menjadi 312 dan jurnal POS menjadi 52. Kotak 3 memastikan penambahan "
        "tersebut tidak merusak BOM, relasi akun, keseimbangan jurnal, maupun syarat minimum volume. Ini "
        "membuktikan siklus dapat diulang mulai dari permintaan bahan outlet berikutnya.",
    )
    add_picture_page(
        document,
        "Keseluruhan Jurnal sampai halaman terakhir",
        journal_last,
        "Gambar 39  Bukti 608 baris jurnal, total seimbang, dan halaman 44 dari 44",
        "Kotak 1 menampilkan pasangan jurnal pengiriman terakhir yang dapat ditelusuri melalui nomor dokumen. "
        "Kotak 2 menunjukkan total debit dan kredit masing-masing Rp1.445.585.902,50. Kotak 3 membuktikan "
        "pemeriksaan telah mencapai halaman 44 dari 44 dengan 608 baris; laporan tidak dinilai hanya dari "
        "halaman pertama dan tidak ada total yang tertutup oleh scroll.",
    )

    document.add_page_break()
    add_heading(document, "Catatan kesiapan produksi dan kanal pembaruan")
    add_body(
        document,
        "Saldo awal kas dan bank data pilot belum dimuat. Arus Kas tetap lulus dalam aspek perhitungan dan "
        "keterlacakan, tetapi dapat memperlihatkan saldo akhir negatif. Administrator wajib memasukkan saldo "
        "awal yang telah disetujui sebelum tenant dipakai untuk pembukuan produksi.",
    )
    add_body(
        document,
        "Varian AB Chicken memakai kanal pembaruan dengan prefix tag abchicken- dan kata kunci aset "
        "abchicken. Rilis tidak menggunakan tag global v*, tidak melakukan fallback ke aset varian lain, dan "
        "dipublikasikan sebagai prerelease khusus agar pembaruan eBisnis, AlBahjah, Nahl, serta varian lain tidak "
        "ikut berubah.",
    )
    document.save(DOCX)


if __name__ == "__main__":
    main()
