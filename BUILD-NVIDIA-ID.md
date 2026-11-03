# Build ISO XeroLinux untuk RTX 5060

Workflow ini membangun profil `nVidia` dari source di repository ini, memakai
Arch Linux x86_64 dalam container di runner GitHub Actions. Profil menyertakan
`nvidia-open-dkms`, `linux-headers`, NVIDIA utilities, dan firmware NVIDIA.
Versi `archiso` dipatok ke **91-1**, sesuai `archiso.readme` upstream.
Download bootstrap Chaotic-AUR memakai CDN resmi dan mirror cadangan, dengan
verifikasi tanda tangan paket tetap aktif.

## Jalankan lewat GitHub Actions

1. Fork <https://github.com/xerolinux/XeroBuild> ke akun GitHub Anda.
2. Salin dua file berikut ke fork tersebut dengan path yang sama, lalu commit
   ke branch default:
   - `.github/workflows/build-nvidia-iso.yml`
   - `.github/scripts/build-nvidia-iso.sh`
3. Buka tab **Actions** di fork. Aktifkan Actions jika diminta oleh GitHub.
4. Pilih **Build XeroLinux NVIDIA ISO**, lalu **Run workflow**.
5. Setelah run sukses, buka run tersebut. Di bagian **Artifacts**, unduh
   `xerolinux-nvidia-rtx5060-<nomor-run>`, lalu ekstrak ZIP-nya.

File hasil meliputi `xerolinux-nvidia-<versi>-x86_64.iso`, `SHA256SUMS`, informasi
build, dan laporan pemeriksaan driver serta boot. Artefak disimpan **3 hari**.
Log build tetap diunggah jika build gagal. Tidak perlu membuat personal access
token atau menambahkan repository secret untuk menjalankan workflow ini.

Paket `.zip` source yang disertakan juga memuat seluruh source XeroBuild beserta
workflow. Folder `.github` tersembunyi di Finder; tekan **Command+Shift+.** untuk
menampilkannya. Jika menyalin dua file lewat situs GitHub, gunakan **Add file →
Create new file** dan masukkan path lengkap di atas.

## Verifikasi hasil di macOS

Jalankan Terminal di folder hasil ekstraksi:

```bash
shasum -a 256 -c SHA256SUMS
```

Hasil yang benar berakhir dengan `OK`. Checksum ini memeriksa integritas unduhan;
ini bukan tanda tangan rilis resmi XeroLinux.

## Flash atau burn

Gunakan **balenaEtcher** yang sudah terpasang di Mac ini: **Flash from file →
pilih file .iso → Select target → pilih USB → Flash**. Pilih media tujuan dengan
benar karena isinya akan dihapus. Gunakan USB yang lebih besar daripada file ISO;
USB 16 GB merupakan titik awal, lalu cek ukuran hasil build.

Untuk DVD/Blu-ray, gunakan opsi **Burn disc image** pada aplikasi burner dan
pastikan kapasitas disc cukup. Jangan menyalin file ISO sebagai file data biasa.
Ukuran final belum diketahui sebelum build; jangan mengasumsikan muat DVD 4,7 GB.

Boot komputer RTX 5060 dari media tersebut dalam mode UEFI, dengan Secure Boot
dinonaktifkan untuk image ini. Pilih entri NVIDIA bawaan. Setelah desktop hidup,
jalankan `nvidia-smi` untuk memastikan GPU dan driver terdeteksi.

## Apa yang diperiksa

- Resolusi paket dari repository Arch, XeroLinux, dan Chaotic-AUR.
- Modul NVIDIA open berhasil dibangun untuk kernel di ISO.
- Keempat modul NVIDIA ada dalam initramfs.
- Entri boot BIOS/UEFI dan metadata hybrid USB ada pada ISO.
- Checksum SHA-256 file ISO.

Pemeriksaan tersebut tidak menjalankan GPU RTX 5060 fisik. Paket menggunakan
repository rolling release, sehingga ketersediaan paket dan versi driver dapat
berubah. Build penuh belum dijalankan dari sesi macOS ini; workflow baru bisa
menghasilkan ISO setelah dijalankan di akun GitHub Anda.

## Referensi

- Source dan profil NVIDIA: <https://github.com/xerolinux/XeroBuild>
- GPU NVIDIA yang didukung: <https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus>
- Bootstrap keyring Chaotic-AUR: <https://aur.chaotic.cx/docs/>
- Unduh artefak Actions: <https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts>
