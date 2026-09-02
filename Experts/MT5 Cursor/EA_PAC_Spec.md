# Spesifikasi EA: PAC (Pivot and Control) — Auto Detection & Auto Entry

> **CATATAN PENTING:** EA ini TERPISAH dari EA "Panbes" (asisten cutloss/layering yang sudah dipakai live). EA ini punya scope jauh lebih besar: mendeteksi Pivot & Control secara otomatis dari price action, menentukan area entry/exit, dan **mengeksekusi order secara otomatis tanpa approval manual trader**.
>
> **RISIKO:** Karena EA ini mengambil keputusan entry sepenuhnya sendiri (bukan hanya membantu order yang sudah dipasang trader), EA ini WAJIB melalui backtest & forward test ekstensif sebelum dipakai di akun live/uang sungguhan — khususnya untuk memvalidasi akurasi deteksi Pivot & Control otomatis, karena ini adalah bagian paling rawan salah tafsir dari seluruh sistem.
>
> **Beberapa bagian di dokumen ini masih PENDING dan akan dibahas lebih lanjut** — ditandai dengan `[PENDING]`. Jangan mengasumsikan sendiri bagian yang pending; tandai dengan `// TODO: CONFIRM WITH USER` di kode jika implementasi menyentuh bagian itu.

---

## 1. DETEKSI PIVOT

### 1.1 Pivot Buy
1. **Candle acuan** (warna bebas — merah/hijau): syaratnya **Low lebih rendah** dari Low candle sebelumnya.
2. Setelah candle acuan, cari **2 candle hijau** konfirmasi (tidak harus berurutan langsung, boleh diselingi candle merah).
3. **Syarat candle selingan merah** (jika ada): Low-nya **tidak boleh** lebih rendah dari Low candle acuan.
   - **Jika ada candle dengan Low lebih rendah dari candle acuan muncul di tengah proses** → candle tersebut **otomatis menjadi kandidat pivot BARU**. Hitungan 2 candle konfirmasi di-reset dan dimulai ulang dari candle baru ini (rolling/geser acuan, bukan restart scan dari awal chart).
4. **Syarat 2 candle hijau konfirmasi**: Open dari KEDUA candle hijau tersebut harus berada **di atas Close** candle acuan.
5. Jika semua syarat terpenuhi → candle acuan sah menjadi **Pivot Buy**.

**Mode Pivot Ketat** (`InpPivotMode` = Ketat, default): kiri acuan memakai aturan yang sama dengan kanan. Candle hanya jadi kandidat jika **sudah** ada 2 hijau di kirinya (Open di atas Close acuan, boleh diselingi). Mundur dari candle sebelum acuan; jika ketemu Low lebih rendah dari acuan sebelum terkumpul 2 hijau → gagal, bukan kandidat (acuan lama yang terpecah juga dibuang). Kanan tetap 2 hijau seperti di atas. Longgar = hanya konfirmasi kanan (perilaku lama).

### 1.2 Pivot Sell (kebalikan persis dari Pivot Buy)
1. Candle acuan: **High lebih tinggi** dari High candle sebelumnya.
2. Cari 2 candle **merah** konfirmasi (boleh diselingi candle hijau).
3. Candle selingan hijau: High-nya **tidak boleh** lebih tinggi dari High candle acuan. Jika lebih tinggi → jadi kandidat pivot baru, reset hitungan.
4. Open kedua candle merah konfirmasi harus **di bawah Close** candle acuan.
5. Jika terpenuhi → sah menjadi **Pivot Sell**.

Mode Pivot Ketat: 2 merah kiri (Open di bawah Close acuan, boleh diselingi, berhenti jika High lebih tinggi dari acuan) sebelum hitung 2 merah kanan.

---

## 2. DETEKSI CONTROL (ZONA BASE)

Control **bukan** 1 candle Base. Control = **zona Base** (grup RBR/DBD + pengecatan) yang sudah **tersentuh Pivot** di kanannya. Geometri zona yang digambar di chart = geometri yang dipakai untuk overlap, Atap, Lantai, dan pelemahan.

### 2.1 Candle Base (penanda putih)
Candle Base = **1 candle** dengan syarat (tidak peduli tetangga):
```
|Close - Open| ≤ 0.5 × (High - Low)
```
Setiap candle yang lolos mendapat garis putih High–Low. Ini belum zona S&D.

### 2.2 Grup Base / zona RBR dan DBD
Zona S&D = **satu grup** Candle Base berurutan (1 sampai `InpMaxBaseCandles`, default **10**), diapit **leg kiri dan leg kanan**. Leg milik grup, bukan milik tiap candle.

```
[LEG KIRI]  [Base] [Base] … [Base]  [LEG KANAN]
               |←—— rectangle zona ——→|
```

- Candle di dalam grup: Candle Base, warna bebas, nempel (tidak terselingi non-Base).
- **Leg kiri** = candle langsung sebelum Base pertama. **Leg kanan** = candle langsung sesudah Base terakhir (sudah close).
- Impulse: body ≥ 50% dari High–Low (`IMPULSE_BODY_PCT`). Rally = hijau + impulse. Drop = merah + impulse.
- Lebih dari `InpMaxBaseCandles` Candle Base nempel → **bukan** zona (chop).

| Pola | Leg kiri | Leg kanan | Syarat keluar |
|---|---|---|---|
| **RBR** (support) | Rally | Rally | `Close leg kanan > High grup` |
| **DBD** (resisten) | Drop | Drop | `Close leg kanan < Low grup` |

RBD dan DBR **tidak** dipakai. Tinggi zona = Low terendah–High tertinggi seluruh Base di grup (**wick ikut**). Tepi kiri rectangle = Base pertama. Leg kiri/kanan **tidak** masuk kotak.

### 2.3 Pengecatan tepi kanan zona
1. Lewati Base terakhir + leg kanan. Hitungan mulai **Base terakhir + 2**.
2. Support: mulai cat saat ada candle dengan **Close < High zona**.
3. Resisten: mulai cat saat ada candle dengan **Close > Low zona**.
4. Setelah mulai: tiap candle menyumbang **body** (Open–Close) plus **celah Close candle sebelumnya → Open candle ini**, dipotong ke tinggi zona. Wick tidak dihitung.
5. Kotak berhenti di candle pertama yang membuat cat **nyambung** dari Low sampai High zona (toleransi 1 point). Jika belum penuh, tepi kanan = candle terakhir di window scan.

### 2.4 Control = zona + overlap Pivot
Zona di 2.3 sah menjadi **Control** jika ada Pivot **di sebelah kanan Base terakhir grup** (waktu Pivot > waktu Base terakhir) **dan tidak setelah cat zona penuh** (waktu Pivot ≤ tepi kanan kotak / candle penutup cat, inklusif) yang range High–Low-nya (termasuk wick) **overlap** dengan tinggi zona, walau hanya 0.1 pip:

- Zona **support** (mulai RBR) + **Pivot Buy** overlap → Control (calon **Lantai**)
- Zona **resisten** (mulai DBD) + **Pivot Sell** overlap → Control (calon **Atap**)

Overlap: `Pivot.Low ≤ Zona.High` DAN `Pivot.High ≥ Zona.Low`.

Pivot **setelah** candle penutup cat (section 2.3) **fresh**: tidak mengaktifkan Control, tidak menambah sentuhan, tag kuning — meski harganya masih di High–Low zona. Candle penutup cat sendiri masih dihitung. Jika cat belum nutup penuh, overlap tetap dihitung seperti sebelumnya.

Zona tanpa Pivot overlap **bukan** Control Aktif — digambar sebagai **Control Standby**, tidak dipakai Atap/Lantai/order.

Penanda rectangle:
- **Control Standby** — putus-putus, tanpa isi (zona S&D, belum overlap Pivot)
- **Control Aktif** — isi penuh, garis tebal (overlap Pivot, belum lemah)
- **Control Off** — titik-titik, tanpa isi (pernah Control, sekarang lemah)

### 2.5 Aturan Pelemahan Control (zona invalidation)

**Resisten (zona DBD / Control Atap):**
Setelah C3 (leg kanan) Base **terakhir** di grup, jika muncul candle APAPUN yang **body**-nya (bukan wick) mencapai atau melebihi **High zona** → zona dinyatakan **LEMAH**, tidak digunakan lagi sebagai Control untuk validasi PAC baru.

**Support (zona RBR / Control Lantai) — simetris:**
Setelah C3 Base terakhir, jika muncul candle yang body-nya mencapai atau melebihi **Low zona** → zona dinyatakan LEMAH.

**Berlaku surut:** Aturan ini berlaku juga untuk zona yang SUDAH menjadi Control valid (sudah tersentuh Pivot, PAC sudah "terbentuk"). Begitu syarat pelemahan terpenuhi, PAC terkait ditandai tidak valid lagi.

**Efek operasional terhadap order (PENTING):**
- Pelemahan Control dicek **per GRUP**, bukan per order individual.
- **Jika grup TIDAK memiliki satupun order yang sudah terbuka (semua masih pending):** begitu Control grup itu lemah, **SEMUA pending order di grup itu dibatalkan (delete)**.
- **Jika grup SUDAH memiliki minimal 1 order yang terbuka:** aturan pelemahan **TIDAK BERLAKU** untuk grup ini. Semua order (baik yang sudah terbuka maupun yang masih pending) **dibiarkan tetap ada**, grup berjalan normal seperti biasa termasuk reentry.
- Pelemahan Control **TIDAK PERNAH** menutup/membatalkan posisi yang sudah terbuka secara langsung — hanya mempengaruhi pending order, dan hanya jika grup tersebut belum punya posisi terbuka sama sekali.

---

## 3. AREA ENTRY & EXIT (ATAP & LANTAI)

### 3.1 Definisi Atap & Lantai
- **Atap** = garis harga = **High zona** dari Control resisten (mulai DBD, tersentuh Pivot Sell) yang **masih aktif** (belum lemah, sesuai section 2.5).
- **Lantai** = garis harga = **Low zona** dari Control support (mulai RBR, tersentuh Pivot Buy) yang **masih aktif**.

### 3.2 Pemilihan Pasangan Atap-Lantai
EA melakukan scan otomatis terhadap seluruh **Control** aktif di chart (zona 2.3 yang lolos overlap 2.4 dan belum lemah 2.5), lalu menentukan **Atap dan Lantai yang TERDEKAT dari harga pasar saat ini** secara otomatis — tanpa perlu approval manual trader.

### 3.3 Kasus 1: Pasangan Atap-Lantai Ditemukan, Jarak ≤ N Pips (default 300)

Jika jarak antara Atap dan Lantai **tidak lebih dari `InpMaxAreaWidth`** (default 300 pips):

| Elemen | Rumus/Posisi |
|---|---|
| **TP** (sama untuk Buy & Sell) | Titik tengah antara Atap dan Lantai: `(Atap + Lantai) / 2` |
| **Entry Sell 1** | 50% jarak antara Atap dan TP: `Atap - 0.5 × (Atap - TP)` |
| **Entry Buy 1** | 50% jarak antara Lantai dan TP: `Lantai + 0.5 × (TP - Lantai)` |
| **CL Sell** | `Atap + InpCLBuffer pips` (default 10 pips) |
| **CL Buy** | `Lantai - InpCLBuffer pips` (default 10 pips) |
| **SL Sell** | Jarak SL ke CL = `InpSLRatio%` × jarak CL ke TP (default 100%). `SL = CL + rasio × (CL − TP)`. SL di atas CL. |
| **SL Buy** | Sama: `SL = CL − rasio × (TP − CL)`. SL di bawah CL. |
| **Order Layer** (posisi 2, 3, dst) | Diletakkan **antara Entry 1 dan Atap/Lantai** — gunakan logika pembagian proporsional yang sama seperti EA Panbes (jarak dibagi rata sesuai jumlah layer). |
| **TP/SL/CL Layer** | SAMA PERSIS dengan Entry 1 (mengikuti mekanisme flat seperti Panbes). |

**Catatan CL:** Menggunakan metode **CLCC (Cut Loss Close Body Candle)** — sama seperti mekanisme di EA Panbes, BUKAN SL harga biasa. Level CL di atas adalah harga acuan untuk candle close, bukan level SL yang langsung dieksekusi begitu disentuh.

### 3.4 Kasus 2: Pasangan Tidak Ditemukan (hanya ada Atap ATAU Lantai saja)

Jika hanya ditemukan salah satu (Atap saja, atau Lantai saja, tanpa pasangannya dalam jarak wajar):

| Elemen | Rumus/Posisi |
|---|---|
| **TP** | Jarak dari Atap/Lantai ke TP = `InpMaxAreaWidth / 2` (default 300/2 = 150 pips). **Tidak ada parameter terpisah untuk Kasus 2** — nilai ini otomatis diturunkan dari `InpMaxAreaWidth` yang sama dipakai Kasus 1, bukan konfigurasi independen. |
| **Entry Sell 1** | Sama seperti Kasus 1: 50% jarak antara Atap dan TP. |
| **Entry Buy 1** | Sama seperti Kasus 1: 50% jarak antara Lantai dan TP. |
| **CL Sell** | Sama seperti Kasus 1: `Atap + InpCLBuffer pips`. |
| **CL Buy** | Sama seperti Kasus 1: `Lantai - InpCLBuffer pips`. |
| **SL Sell/Buy** | Sama seperti Kasus 1: `InpSLRatio%` × jarak CL ke TP. |
| **Order Layer & TP/SL/CL Layer** | Sama seperti Kasus 1. |

Singkatnya: **seluruh rumus Kasus 2 identik dengan Kasus 1**, satu-satunya perbedaan adalah cara TP ditentukan (titik tengah Atap-Lantai untuk Kasus 1, vs setengah `InpMaxAreaWidth` dari sisi yang ditemukan untuk Kasus 2 — karena tidak ada pasangan untuk dihitung titik tengahnya).

### 3.5 Parameter Input (Default)
```
input int    InpMaxAreaWidth = 300;  // Jarak maksimal Atap-Lantai (pips) untuk Kasus 1.
                                      // Kasus 2 otomatis pakai setengah nilai ini (150) sebagai jarak TP.
input int    InpCLBuffer     = 10;   // Buffer CL dari Atap/Lantai (pips)
input int    InpSLRatio      = 100;  // Rasio (SL−CL) terhadap (CL−TP), persen (default 100%)
```

---

## 4. TIMEFRAME DETEKSI

Timeframe untuk deteksi Pivot & Control **ditentukan oleh trader melalui parameter input EA** (bukan hasil scan otomatis multi-TF, dan bukan dari comment per-order seperti Panbes). Satu nilai TF berlaku global untuk seluruh proses deteksi Pivot, Control, Atap, Lantai di EA ini.

```
input ENUM_TIMEFRAMES InpDetectionTF = PERIOD_M1;  // Timeframe untuk deteksi Pivot & Control
```

---

## 5. FORMAT COMMENT ORDER

**Batas panjang comment MT5 Mobile: 30 karakter** — dikonfirmasi langsung oleh trader melalui uji coba nyata di aplikasi (bukan asumsi dari dokumentasi). Format comment di bawah ini dirancang untuk selalu berada di dalam batas ini, termasuk untuk skenario terpanjang (timeframe 3 karakter seperti M15/M30).

Format: `[P/M][B/S][LayerPosisi]/[TF]/[HargaCL]/[Timestamp]`

Contoh: `PS31/M1/4530.00/260826.143022` (29 karakter, TF 2 digit)
Contoh skenario terpanjang: `PS31/M15/4530.00/260826.143022` (30 karakter, TF 3 digit — PAS di batas maksimal)

| Bagian | Arti |
|---|---|
| `P` atau `M` | **P** = Paired (grup ini berasal dari pasangan Atap-Lantai yang ditemukan, section 3.3). **M** = Mandiri (grup ini dari kasus single-side, section 3.4, hanya ada Atap ATAU Lantai saja). |
| `B` atau `S` (langsung menempel setelah P/M, TANPA pemisah) | Arah: **B** = Buy, **S** = Sell. |
| `LayerPosisi` (langsung menempel setelah B/S, TANPA pemisah) | 2 digit gabung: digit pertama = jumlah total layer, digit kedua = posisi urutan layer ini (sama seperti Panbes, contoh `31` = 3 layer total, posisi 1). Jumlah layer dijamin selalu < 10 (single digit aman). |
| `TF` | Timeframe (mengikuti `InpDetectionTF` yang aktif saat grup ini dibuat). Bisa 2 karakter (M1, M5, H1) atau 3 karakter (M15, M30) — format comment WAJIB tetap valid untuk kedua kemungkinan panjang ini. |
| `HargaCL` | Harga level Cut Loss Close Candle untuk grup/arah ini. |
| `Timestamp` | **Menggantikan KodeGrup angka urut.** Format `YYMMDD.HHMMSS` (2 digit tahun, bulan, tanggal, jam, menit, detik — presisi hingga DETIK, tanpa centisecond). Contoh `260826.143022` = 26 Agustus 2026, jam 14:30:22. Diambil **SEKALI** saat EA memutuskan sebuah pasangan Atap-Lantai (atau kasus Mandiri) valid untuk di-generate, **SEBELUM** proses pengiriman order dimulai — lalu dipakai ulang (bukan digenerate ulang) untuk SEMUA order dalam pasangan itu (baik sisi Sell maupun Buy, semua layer). Ini menghindari resiko timestamp berbeda antar order akibat jeda proses `OrderSend()` yang berurutan. Risiko collision antar PASANGAN BERBEDA yang kebetulan diproses EA pada detik yang identik dianggap dapat diabaikan, karena EA memproses pasangan secara sekuensial (satu per satu), sehingga dua pasangan berbeda praktis tidak mungkin selesai diproses pada detik yang sama persis. |

**Contoh — 1 pasangan Atap-Lantai (timestamp `260826.143022`) dengan 3 layer per arah, TF M1:**
```
PS31/M1/4530.00/260826.143022   (Sell posisi 1)
PS32/M1/4530.00/260826.143022   (Sell posisi 2)
PS33/M1/4530.00/260826.143022   (Sell posisi 3)
PB31/M1/4500.00/260826.143022   (Buy posisi 1 — dari PASANGAN yang sama, timestamp identik)
PB32/M1/4500.00/260826.143022   (Buy posisi 2)
PB33/M1/4500.00/260826.143022   (Buy posisi 3)
```

**PENTING — Independensi Sell vs Buy dalam 1 Timestamp:**
Meskipun `PS.../260826.143022` dan `PB.../260826.143022` berbagi Timestamp yang sama (karena berasal dari 1 pasangan Atap-Lantai), keduanya diperlakukan sebagai **2 GRUP TERPISAH SEPENUHNYA** untuk keperluan CLCC dan reentry. Identitas grup yang sebenarnya dipakai untuk logika cutloss/reentry adalah kombinasi **`[P/M][Arah]-Timestamp`**, bukan Timestamp saja. Event TP/CL di sisi Sell TIDAK mempengaruhi sisi Buy, dan sebaliknya — sepenuhnya independen.

**Keuntungan pendekatan Timestamp (dibanding KodeGrup angka urut):**
- **Tidak butuh penyimpanan counter eksternal sama sekali** (Global Variable, file, dsb) — konsisten penuh dengan prinsip arsitektur "tidak menyimpan state eksternal, semua direkonstruksi dari data live" yang dipakai di seluruh sistem (Panbes maupun PAC).
- **Restart VPS tidak masalah** — EA tidak perlu "mengingat" nomor terakhir, karena setiap grup baru otomatis mendapat identitas unik dari waktu pembuatannya.

**Cara membedakan comment PAC dari comment Panbes saat parsing:**
Cek 2 karakter pertama comment: jika karakter pertama adalah `P` atau `M`, DAN karakter kedua adalah `B` atau `S` (langsung menempel, tanpa pemisah) → kemungkinan besar format PAC, lanjutkan validasi struktur lebih lanjut (separator `/`, panjang segmen, dst). Format Panbes selalu PERSIS 3 karakter (1 huruf + 2 digit) sebelum `/` pertama, sehingga tidak akan cocok dengan pola ini.

---

## 6. REFERENSI KODE PANBES YANG SUDAH ADA

EA Panbes (terpisah, sudah live dipakai) sudah mengimplementasikan banyak mekanisme yang relevan dan SEHARUSNYA DIPAKAI ULANG polanya di EA PAC ini, khususnya:
- Struktur `PacGroup`, `LiveItem`, `Snapshot`, `TpBatch` untuk tracking grup, order, dan reentry batching
- `OnTradeTransaction()` untuk deteksi deal close beserta `DEAL_REASON` (TP/SL/CLIENT/MOBILE/EXPERT)
- Mekanisme CLCC berbasis deteksi pergantian candle (`lastCheckedBarTime` per grup) dan `IsClBreak()`
- Visual: HLine CL (`UpsertClLine`) dan countdown label (`UpsertCountdown`), dengan cleanup otomatis (`DeleteGroupVisuals`, `CleanupOrphanVisuals`)
- `NormalizePrice()`, `NormalizeLot()` untuk validasi harga/lot sebelum kirim order
- Mode Test (`InpTestMode` dkk) untuk simulasi Strategy Tester

**PENTING — Magic Number:** Panbes saat ini menggunakan `InpMagic = 0` (disamakan dengan order manual, sengaja disembunyikan/const). Karena EA PAC akan mengirim order-nya SENDIRI (bukan hasil input manual trader), EA PAC **WAJIB** menggunakan Magic Number yang **berbeda dan bukan 0**.

```
const long InpMagic = 999;  // Magic Number EA PAC
```

---

## 7. REENTRY & CLCC

Menggunakan mekanisme **PERSIS SAMA** seperti EA Panbes:
- CLCC berbasis deteksi pergantian candle (bukan estimasi sebelum close), per grup dengan TF masing-masing (`InpDetectionTF` yang aktif saat grup dibuat).
- Reentry dihitung sebagai **event harga TP** (bukan per order individual), dengan window batching singkat untuk mengelompokkan closing bersamaan.
- Lot & harga reentry mengikuti data **TERAKHIR** order yang closed (bukan data awal).
- Reentry berhenti PER SLOT (bukan per grup) jika order individual di-close manual (`DEAL_REASON_CLIENT`/`DEAL_REASON_MOBILE`) atau kena SL asli (`DEAL_REASON_SL`) — slot lain di grup yang sama tetap jalan normal.
- Reaktivasi otomatis: jika trader/EA memasang ulang order dengan comment persis sama, slot itu aktif kembali tanpa "blacklist" permanen.
- CL grup (CLCC break) menghapus SEMUA order dalam grup (identitas grup = `[P/M]-[Arah]-[KodeGrup]`, lihat section 5) dan menghentikan reentry grup itu total.

**Catatan:** Karena grup di EA PAC dibuat OTOMATIS oleh EA (bukan manual trader seperti Panbes), tidak ada perbedaan mekanisme reentry/CLCC yang diperlukan — logika Panbes yang sudah ada bisa diadaptasi langsung, hanya sumber pembuatan order pertamanya yang berbeda (EA vs trader manual).

---

## 9. VERIFIKASI: PARSING PANBES VS PAC TIDAK SALING KETUKER

Sudah diverifikasi terhadap kode Panbes aktual (`ParsePacComment` di Panbes.mq5):

**Panbes tidak akan salah membaca comment EA PAC:**
Panbes mensyaratkan `parts[0]` (bagian sebelum `/` pertama) harus **PERSIS 3 karakter** (`StringLen(parts[0]) != 3 → return false`, lihat baris ~1753). Comment EA PAC bagian pertamanya (misal `"PS31"`, 4 karakter) tidak akan cocok dengan syarat panjang 3 karakter ini, sehingga otomatis ditolak oleh parser Panbes.

**EA PAC harus divalidasi ketat agar tidak salah membaca comment Panbes:**
Comment Panbes (misal `"A31"`) berupa 1 huruf + 2 digit, tidak akan cocok dengan pola "P/M diikuti B/S" yang menjadi ciri comment PAC (lihat section 5). Parser EA PAC **WAJIB** memvalidasi pola ini serta struktur separator (`/`) secara ketat SEBELUM parsing lebih lanjut — jangan mencoba "menebak" atau parsing longgar.

**Kesimpulan:** Aman, dengan syarat implementasi parsing EA PAC menggunakan validasi struktur ketat (bukan pencarian pola longgar).

---

## 10. RINGKASAN STATUS

Seluruh poin yang sebelumnya ditandai PENDING sudah terjawab:
- ✅ Detail Kasus 2 (single-side) — lengkap di section 3.4, identik dengan Kasus 1 kecuali cara TP dihitung.
- ✅ Batas panjang comment MT5 Mobile — dikonfirmasi 30 karakter melalui uji langsung, format comment sudah disesuaikan agar selalu di bawah batas ini.

Dokumen ini sudah siap dijadikan acuan untuk tahap implementasi (coding) di Cursor.
