# Khanza Brook REST API (High-Performance Backend)

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Pascal](https://img.shields.io/badge/Language-Pascal%20%28FPC%2FLazarus%29-orange.svg)]()

Repositori ini berisi REST API berkinerja tinggi murni berbasis kode (*Console Application*) yang dirancang khusus untuk menjembatani atau mengekstensi kebutuhan integrasi **SIMRS Khanza**. Dibangun menggunakan **Brook Framework (Tardigrade - Class Based Routing)** dan **Zeos 8.0** dengan dialek `{$MODE DELPHI}`.

Proyek ini fokus pada kecepatan eksekusi, penggunaan memori yang minimal, serta struktur kode yang aman dari *memory leak*.

---

## 📌 Fitur Utama
* **Pure Code / Non-GUI:** Berjalan sebagai aplikasi konsol yang sangat ringan dan siap di-deploy ke server Linux berbasis CLI.
* **Tardigrade Routing:** Manajemen endpoint yang rapi menggunakan *Class-Based Routing* dari Brook Framework.
* **Direct Database Connectivity:** Menggunakan Zeos 8.0 murni via kode untuk koneksi super cepat ke MySQL/MariaDB.
* **Strict Memory Control:** Implementasi blok `try-finally` yang presisi untuk memastikan stabilitas server jangka panjang tanpa kebocoran memori.

---

## ⚠️ Disclaimer & Kepatuhan Lisensi

1. **Hubungan dengan SIMRS Khanza:** Proyek ini merupakan perangkat lunak independen/ekstensi pihak ketiga dan **bukan** merupakan bagian resmi dari rilis inti Yaski (Yayasan SIMRS Khanza Indonesia).
2. **Lisensi:** Proyek ini tunduk pada lisensi **GNU GPL v3**, sejalan dengan semangat open-source SIMRS Khanza. Anda bebas mendistribusikan dan memodifikasi kode ini dengan tetap mempertahankan lisensi yang sama.
3. **Keamanan Data (PENTING):** * **TIDAK ADA** data pasien riil, rekam medis, atau informasi klinis yang disertakan dalam repositori ini. Semua contoh skema atau respons JSON menggunakan data fiktif untuk keperluan pengembangan/testing.
   * Kredensial database pada kode contoh telah dianonimkan. Pastikan Anda menggunakan *Environment Variables* atau konfigurasi eksternal yang aman saat production.

---

## 🛠️ Prasyarat & Tools Pengembangan

* **Compiler:** Free Pascal Compiler (FPC) versi terbaru.
* **IDE / Editor:** Lazarus IDE (untuk manajemen proyek & kompilasi) + Notepad++ (sebagai kode editor utama).
* **Libraries:**
  * Brook Framework (Tardigrade branch)
  * ZeosLib 8.0-stable
* **Database:** MySQL / MariaDB (Skema standar SIMRS Khanza / `sik`).

---

## 🚀 Cara Menjalankan (Development)

1. Clone repositori ini:
   ```bash
   git clone [[https://github.com/username](https://github.com/username](https://github.com/mailhasan/Rest-Api-SimrsERM)) Anda/nama-repo.git

📝 Dokumentasi API (OpenAPI Specification)

Dokumentasi API proyek ini ditulis menggunakan standar OpenAPI 3.0 (Swagger/YAML). Anda dapat mengimpor file dokumentasi yang tersedia di folder docs/ ke dalam Postman atau Swagger Editor untuk melihat daftar endpoint, parameter, dan contoh respon JSON secara interaktif.
🤝 Kontribusi & Rekomendasi

Proyek ini terbuka untuk seluruh komunitas pengembang SIMRS Khanza. Jika Anda menemukan bug, memiliki ide optimasi query, atau ingin menambahkan endpoint baru sesuai modul Khanza lainnya, silakan kirimkan Pull Request atau buka Issue.

Besar harapan kami proyek ini dapat menjadi salah satu rekomendasi solusi bagi YASKI dan rekan-rekan sejawat dalam mempercepat migrasi atau interkoneksi SIMRS Khanza ke platform modern.

## 👨‍💻 Pengembang & Kontak

Proyek ini diinisiasi dan dikembangkan secara aktif oleh:

* **Nama:** Ismail Hasan
* **Email:** [mail.hasan06@gmail.com](mailto:mail.hasan06@gmail.com)
* **Telegram:** [@Mailhasan1](https://t.me/Mailhasan1)

Jika Anda memiliki pertanyaan seputar integrasi, kebutuhan bridging kustom untuk SIMRS Khanza, atau ingin berdiskusi mengenai arsitektur sistem ini, silakan hubungi melalui jalur komunikasi di atas.

