"""Bangkitkan ikon aplikasi eCanteen.

Tanda gerai: kanopi bergelombang di atas, cangkir/tas belanja di bawah, pada
latar biru primer aplikasi. Digambar terprogram supaya semua ukuran berasal
dari satu sumber dan mudah dibangkitkan ulang bila branding berubah.

Keluaran:
  - assets/icon/ecanteen-icon.png          (1024, sumber)
  - assets/icon/ecanteen-foreground.png    (1024, transparan, utk adaptive)
  - android/.../mipmap-*/ic_launcher.png   (semua densitas)
  - windows/runner/resources/app_icon.ico
"""

import os
import sys

from PIL import Image, ImageDraw

BIRU = (27, 111, 227, 255)
PUTIH = (255, 255, 255, 255)
KUNING = (255, 199, 64, 255)

S = 1024


def gambar_lambang(d, u):
    """Kanopi + tas belanja. Semua koordinat pecahan dari sisi `u`."""

    def x(v):
        return v * u

    def y(v):
        return v * u

    # ── Kanopi ────────────────────────────────────────────────────────────
    kiri, kanan = 0.215, 0.785
    atas = 0.245
    tinggi = 0.105
    d.rounded_rectangle(
        [x(kiri), y(atas), x(kanan), y(atas + tinggi)],
        radius=x(0.026),
        fill=PUTIH,
    )
    # Gelombang bawah kanopi: setengah lingkaran berselang-seling.
    gigi = 5
    lebar = (kanan - kiri) / gigi
    for i in range(gigi):
        x0 = kiri + i * lebar
        d.pieslice(
            [x(x0), y(atas + tinggi - lebar / 2),
             x(x0 + lebar), y(atas + tinggi + lebar / 2)],
            start=0, end=180,
            fill=KUNING if i % 2 else PUTIH,
        )

    # ── Tas belanja ───────────────────────────────────────────────────────
    # Pegangan digambar LEBIH DULU supaya badan tas menutupi ujungnya, jadi
    # tidak ada garis yang menggantung di dalam badan tas.
    tas_kiri, tas_kanan = 0.325, 0.675
    tas_atas, tas_bawah = 0.585, 0.815

    tebal = x(0.030)
    d.arc(
        [x(0.408), y(0.505), x(0.592), y(0.665)],
        start=180, end=360,
        fill=PUTIH, width=int(tebal),
    )

    d.rounded_rectangle(
        [x(tas_kiri), y(tas_atas), x(tas_kanan), y(tas_bawah)],
        radius=x(0.040),
        fill=PUTIH,
    )
    # Garis aksen pada badan tas (senada latar supaya terbaca sbg lipatan).
    d.rounded_rectangle(
        [x(0.392), y(0.688), x(0.608), y(0.718)],
        radius=x(0.015),
        fill=BIRU,
    )


def buat_sumber(dengan_latar=True):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if dengan_latar:
        # Satu warna rata: gradasi/dua nada menimbulkan jahitan yang terlihat
        # pada sudut membulat.
        d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=BIRU)
    gambar_lambang(d, S)
    return img


def main():
    akar = sys.argv[1] if len(sys.argv) > 1 else "."
    dir_aset = os.path.join(akar, "assets", "icon")
    os.makedirs(dir_aset, exist_ok=True)

    sumber = buat_sumber(dengan_latar=True)
    sumber.save(os.path.join(dir_aset, "ecanteen-icon.png"))

    depan = buat_sumber(dengan_latar=False)
    depan.save(os.path.join(dir_aset, "ecanteen-foreground.png"))

    densitas = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    dasar_res = os.path.join(akar, "android", "app", "src", "main", "res")
    for folder, px in densitas.items():
        tujuan = os.path.join(dasar_res, folder)
        os.makedirs(tujuan, exist_ok=True)
        sumber.resize((px, px), Image.LANCZOS).save(
            os.path.join(tujuan, "ic_launcher.png"))

    ico = os.path.join(akar, "windows", "runner", "resources", "app_icon.ico")
    os.makedirs(os.path.dirname(ico), exist_ok=True)
    sumber.save(ico, sizes=[(256, 256), (128, 128), (64, 64),
                            (48, 48), (32, 32), (16, 16)])

    print("ikon dibangkitkan di", akar)


if __name__ == "__main__":
    main()
