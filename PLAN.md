# Dynamic Island untuk MacBook — Rencana Implementasi

Target: aplikasi macOS native yang mengubah area notch MacBook menjadi "Dynamic Island" interaktif seperti iPhone 15 — bisa mengecil, membesar, menampilkan aktivitas live, dan bereaksi terhadap hover/klik dengan animasi spring yang halus.

Environment saat ini: macOS 26.6, Xcode 26.6, Swift 6.3.

---

## 1. Konsep & Perilaku (meniru iPhone)

Dynamic Island iPhone punya 4 bentuk presentasi. Kita tiru satu-satu:

| State | iPhone | Versi Mac |
|---|---|---|
| **Idle** | Pill hitam kecil | Persis sebesar notch fisik → tidak terlihat (menyatu dengan notch) |
| **Compact** | Leading + trailing di kiri/kanan kamera | Notch "melebar" ke kiri & kanan; ikon di kiri notch, info di kanan (mis. artwork lagu ⟷ waveform) |
| **Minimal** | Dua aktivitas: satu menempel, satu bulatan terpisah | Aktivitas kedua tampil sebagai bulatan kecil terpisah di sebelah kanan notch |
| **Expanded** | Long-press → kartu besar | Hover/klik → notch membesar ke bawah jadi panel (kontrol musik, timer, kalender, dsb.) |
| **Transient (HUD)** | Silent mode, Face ID, charging | Volume, brightness, charging, AirPods tersambung — muncul 1.5–2 detik lalu kembali |

Prinsip perilaku:
- Animasi selalu **spring** (morph bentuk, bukan fade). Konten masuk dengan blur + scale.
- Satu aktivitas prioritas tertinggi → compact. Dua aktivitas → compact + minimal. Lebih dari dua → sisanya antre.
- Hover sebentar (≈150 ms) → sedikit membesar ("peek"). Klik / hover lama → expanded. Mouse keluar → kembali.
- Saat idle, window **click-through** agar tidak mengganggu menu bar.

---

## 2. Tech Stack

- **Bahasa:** Swift 6 (strict concurrency).
- **UI:** SwiftUI untuk semua konten island; AppKit (`NSPanel`) untuk window hosting.
- **Target OS:** macOS 14+ (notch tersedia sejak MacBook Pro 2021; 14+ memberi `@Observable` dan API SwiftUI animasi terbaru).
- **Distribusi:** di luar Mac App Store (Developer ID + notarization). Alasan: beberapa fitur butuh API privat / Accessibility / non-sandbox.
- **Update:** Sparkle 2.
- **Launch at login:** `SMAppService.mainApp`.
- **Dependency opsional:** `mediaremote-adapter` (Now Playing di macOS 15.4+), `KeyboardShortcuts` (sindresorhus), `Defaults` (settings).

---

## 3. Arsitektur

```
DynamicIsland/
├── App/
│   ├── DynamicIslandApp.swift        // @main, LSUIElement (tanpa Dock icon)
│   ├── AppDelegate.swift             // setup window, lifecycle, sleep/wake
│   └── Permissions.swift             // Accessibility, Calendar, Bluetooth
├── Window/
│   ├── IslandPanel.swift             // NSPanel borderless non-activating
│   ├── IslandWindowController.swift  // posisi, multi-display, click-through
│   └── ScreenGeometry.swift          // deteksi notch & ukuran
├── Core/
│   ├── IslandState.swift             // enum state + ukuran target
│   ├── IslandViewModel.swift         // @Observable, sumber kebenaran UI
│   ├── ActivityManager.swift         // antrean + prioritas aktivitas
│   ├── LiveActivity.swift            // protocol modul
│   └── HoverController.swift         // tracking mouse, delay, gesture
├── UI/
│   ├── IslandShape.swift             // Shape notch dengan sudut melengkung
│   ├── IslandRootView.swift          // switch per state + matchedGeometry
│   ├── CompactView.swift
│   ├── MinimalView.swift
│   ├── ExpandedView.swift
│   └── Components/                   // Waveform, ProgressRing, Marquee, dll
├── Modules/
│   ├── NowPlaying/
│   ├── HUD/ (Volume, Brightness, Keyboard backlight)
│   ├── Battery/
│   ├── Timer/
│   ├── Calendar/
│   ├── Bluetooth/
│   ├── PrivacyIndicator/ (mic & kamera)
│   ├── FileShelf/ (drag & drop + AirDrop)
│   └── Downloads/
├── Settings/
│   ├── SettingsView.swift
│   └── Preferences.swift
└── Resources/
```

### 3.1 Protocol modul (inti ekstensibilitas)

```swift
@MainActor
protocol LiveActivity: AnyObject, Identifiable {
    var id: String { get }
    var priority: ActivityPriority { get }      // .critical, .high, .normal, .low
    var isActive: Bool { get }                  // modul memutuskan kapan tampil
    var expiresAfter: Duration? { get }         // untuk HUD transient

    @ViewBuilder func compactLeading() -> AnyView
    @ViewBuilder func compactTrailing() -> AnyView
    @ViewBuilder func minimal() -> AnyView
    @ViewBuilder func expanded() -> AnyView
}
```

`ActivityManager` mengamati semua modul, mengurutkan berdasarkan prioritas + waktu mulai, lalu menentukan:
- `primary` → ditampilkan compact
- `secondary` → ditampilkan minimal
- `transient` → menimpa sementara (HUD), lalu kembali ke state sebelumnya

### 3.2 Alur data

```
Sistem (CoreAudio, IOKit, MediaRemote, EventKit, ...)
        │  (async stream / notification)
        ▼
   Module Provider  ──►  ActivityManager  ──►  IslandViewModel (@Observable)
                                                   │
                         HoverController ─────────►│
                                                   ▼
                                     IslandRootView (SwiftUI, spring)
                                                   │
                                                   ▼
                              IslandPanel (resize hit-area / click-through)
```

---

## 4. Window & Notch — bagian paling krusial

### 4.1 Panel
```swift
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 3                 // di atas menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { true }  // perlu untuk tombol/slider di expanded
    override var canBecomeMain: Bool { false }
}
```

- Window dibuat **sebesar ukuran expanded maksimum** dan ditempel di tepi atas layar, tengah horizontal. SwiftUI yang menggambar bentuk sebenarnya. Ini menghindari resize window per-frame (yang patah-patah).
- Hit-testing: area transparan harus tembus klik. Pilihan: toggle `ignoresMouseEvents` berdasarkan posisi mouse vs. frame bentuk aktual (dihitung di `HoverController`).

### 4.2 Deteksi notch
```swift
extension NSScreen {
    var hasNotch: Bool { safeAreaInsets.top > 0 }
    var notchSize: CGSize {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea
        else { return CGSize(width: 200, height: 32) }      // fallback
        return CGSize(width: frame.width - left.width - right.width,
                      height: safeAreaInsets.top)
    }
}
```
- Layar **tanpa notch** (monitor eksternal / MacBook lama): tampilkan pill mengambang di bawah menu bar (opsi di Settings: "tampilkan di semua layar / hanya layar dengan notch / layar utama").
- Dengarkan `NSApplication.didChangeScreenParametersNotification` untuk reposisi saat monitor dicolok/dicabut atau resolusi berubah.

### 4.3 Bentuk (IslandShape)
- Bukan `RoundedRectangle` biasa. Notch Mac punya **sudut atas cekung keluar** (menyatu dengan bezel) dan **sudut bawah membulat**.
- Buat `Shape` custom dengan `animatableData` (lebar, tinggi, radius atas, radius bawah) supaya morph mulus.
- Warna isi: hitam pekat `#000` agar menyatu dengan notch fisik.

### 4.4 Fullscreen & edge case
- Saat app fullscreen dan menu bar tersembunyi: island ikut sembunyi (kecuali HUD transient). Deteksi via `NSWorkspace.activeSpaceDidChangeNotification` + cek `CGWindowList` untuk window fullscreen.
- Sleep/wake (`NSWorkspace.didWakeNotification`): rebuild posisi & observer.
- Screen recording/screenshot: opsi `sharingType = .none` agar island tidak ikut terekam.

---

## 5. Animasi & Interaksi

- **Spring standar:** `.spring(response: 0.42, dampingFraction: 0.78)` untuk expand; `.spring(response: 0.35, dampingFraction: 0.85)` untuk collapse (lebih cepat, sedikit bounce).
- **Morph konten:** `matchedGeometryEffect` untuk artwork album (compact → expanded) dan ikon.
- **Transisi konten:** `.blurReplace` / kombinasi `.opacity + .scale(0.8) + .blur`.
- **Haptic:** `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, ...)` saat expand (terasa di trackpad Force Touch).
- **Gesture:**
  - Hover → peek (scale 1.05) setelah 150 ms.
  - Klik / hover > 400 ms → expanded.
  - Swipe ke atas di trackpad / mouse keluar → collapse.
  - Klik kanan → menu konteks (Settings, Quit).
- **Hover detection:** `NSTrackingArea` di content view + `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` sebagai cadangan saat window ignore mouse events.

---

## 6. Modul (Live Activities)

Diurutkan dari paling penting/mudah ke paling sulit.

### 6.1 Now Playing (prioritas utama — fitur "wajib")
- **Compact:** artwork kiri, waveform animasi kanan (warna dari dominant color artwork).
- **Expanded:** artwork besar, judul/artis (marquee), progress bar yang bisa di-scrub, tombol prev/play/next, output device (AirPlay).
- **Sumber data:**
  - `MediaRemote.framework` (privat) — sejak macOS 15.4 dibatasi untuk proses ber-entitlement Apple. Solusi: **`mediaremote-adapter`** (menjalankan helper via `/usr/bin/perl` yang punya entitlement).
  - Fallback: AppleScript / `ScriptingBridge` untuk Music.app & Spotify.
- **Risiko:** API privat bisa rusak saat update macOS. Bungkus di balik protocol `NowPlayingProvider` agar mudah diganti.

### 6.2 HUD Volume / Brightness / Keyboard backlight
- Ganti HUD bawaan macOS dengan progress bar di island.
- **Tangkap tombol media:** `CGEventTap` untuk `NX_SYSDEFINED` (butuh izin **Accessibility**). Konsumsi event agar HUD sistem tidak muncul, lalu set nilai sendiri.
- **Volume:** CoreAudio (`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`).
- **Brightness:** `DisplayServices` (privat) `DisplayServicesGetBrightness/SetBrightness`.
- **Keyboard backlight:** `CoreBrightness` `KeyboardBrightnessClient` (privat).
- Mode opsional: "hanya tampilkan, jangan ganti HUD sistem" (pakai observer CoreAudio tanpa event tap) — lebih aman.

### 6.3 Battery & Charging
- `IOPSNotificationCreateRunLoopSource` + `IOPSCopyPowerSourcesInfo`.
- Transient saat colok charger: ikon petir + persen + animasi (seperti iPhone).
- Alert baterai rendah (20%, 10%).

### 6.4 Timer & Stopwatch
- Modul internal murni (paling mudah, bagus untuk menguji arsitektur pertama kali).
- Compact: ikon timer kiri, countdown kanan (`Text(timerInterval:)` agar tidak perlu timer per detik).
- Expanded: pause/resume/stop, preset.
- Selesai → transient + suara.

### 6.5 Kalender
- `EventKit` (izin Calendar). Tampilkan acara berikutnya < 15 menit sebagai compact; expanded berisi agenda hari ini + tombol "Join" untuk link Zoom/Meet/Teams.

### 6.6 Indikator Privasi (Mic & Kamera)
- Mic: CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere`.
- Kamera: CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere`.
- Tampilkan titik oranye/hijau di minimal view.

### 6.7 Bluetooth / AirPods
- `IOBluetooth` notification saat perangkat tersambung → transient dengan ikon perangkat + baterai (jika tersedia).

### 6.8 File Shelf & AirDrop
- Drag file ke notch → island membesar jadi "rak" sementara.
- Drop zone AirDrop: `NSSharingService(named: .sendViaAirDrop)`.
- File disimpan sebagai bookmark, bisa di-drag keluar lagi.

### 6.9 Download Progress
- Pantau `~/Downloads` via `FSEvents`/`DispatchSource` untuk `.crdownload`, `.download`, `.part`. Tampilkan progress ring di compact.

### 6.10 Di luar cakupan (sengaja tidak dibuat)
- Membaca notifikasi app lain — tidak ada API publik; butuh hack database notifikasi yang tidak stabil dan bermasalah privasi.
- Live Activities dari app pihak ketiga — macOS tidak menyediakan API untuk ini. (Bisa ditambah nanti lewat URL scheme / XPC agar app lain bisa push aktivitas.)

---

## 7. Settings

- Modul on/off + urutan prioritas.
- Perilaku hover (delay, buka saat hover vs. klik).
- Layar target (notch saja / semua / utama).
- Ganti HUD sistem: on/off.
- Tampilan: ukuran expanded, haptic, sembunyikan di fullscreen, sembunyikan dari screen recording.
- Launch at login.
- Shortcut global (mis. ⌥⌘I untuk buka/tutup island).

---

## 8. Izin (Permissions)

| Izin | Untuk | Kapan diminta |
|---|---|---|
| Accessibility | Event tap tombol media (ganti HUD) | Saat user mengaktifkan "Ganti HUD sistem" |
| Calendar | Modul Kalender | Saat modul diaktifkan |
| Bluetooth | AirPods/perangkat | Saat modul diaktifkan |
| Automation (Apple Events) | Fallback Music/Spotify | Saat pertama kontrol musik |

Onboarding singkat 3 langkah saat pertama dibuka. Jangan minta semua izin sekaligus.

---

## 9. Performa

- Target idle: **CPU ~0%**, RAM < 60 MB.
- Tidak ada `Timer` yang berjalan saat idle — semua berbasis notifikasi/async stream.
- Waveform & animasi hanya aktif saat terlihat.
- Gunakan `TimelineView`/`Text(timerInterval:)` daripada update state tiap detik.
- Profil dengan Instruments (Time Profiler, SwiftUI, Animation Hitches).

---

## 10. Roadmap / Fase

### Fase 0 — Fondasi (1–2 hari)
- Project Xcode, `LSUIElement`, struktur folder, `IslandPanel`, deteksi notch.
- **Selesai jika:** bentuk hitam muncul pas di atas notch di semua Space & di atas menu bar.

### Fase 1 — Shape & State Machine (2–3 hari)
- `IslandShape` animatable, `IslandState`, `IslandViewModel`, transisi idle ⟷ compact ⟷ expanded dengan data dummy.
- Hover/klik, click-through.
- **Selesai jika:** morph terasa seperti iPhone, tidak ada flicker, menu bar tetap bisa diklik saat idle.

### Fase 2 — ActivityManager + modul pertama (2 hari)
- Protocol `LiveActivity`, antrean prioritas, compact + minimal bersamaan.
- Modul **Timer** dan **Battery**.
- **Selesai jika:** timer + charging tampil bersamaan (compact + minimal) dan HUD charging menimpa lalu kembali.

### Fase 3 — Now Playing (3–4 hari)
- Integrasi `mediaremote-adapter`, fallback AppleScript, artwork + warna dominan, waveform, kontrol, scrubbing, `matchedGeometryEffect`.
- **Selesai jika:** Spotify, Music, dan YouTube di browser terdeteksi dan bisa dikontrol.

### Fase 4 — HUD sistem (2–3 hari)
- Volume, brightness, keyboard backlight; mode observer-only dan mode replace (event tap).

### Fase 5 — Modul tambahan (3–5 hari)
- Kalender, indikator privasi, Bluetooth, File Shelf/AirDrop, Downloads.

### Fase 6 — Polish & Settings (2–3 hari)
- Settings window, onboarding izin, shortcut, multi-display, fullscreen, sleep/wake, haptic.

### Fase 7 — Rilis (1–2 hari)
- Ikon app, signing Developer ID, notarization, DMG, Sparkle feed.

Total estimasi: **~3–4 minggu** kerja santai sendirian.

---

## 11. Testing

- **Unit test:** `ActivityManager` (urutan prioritas, expiry transient, antrean), kalkulasi geometri notch untuk berbagai ukuran layar (14" vs 16" vs non-notch).
- **Snapshot/preview:** SwiftUI Preview untuk setiap state × setiap modul dengan data mock.
- **Manual checklist:**
  - Monitor eksternal colok/cabut
  - Ganti resolusi ("More Space" / "Larger Text")
  - App fullscreen, Mission Control, Stage Manager
  - Sleep/wake, lock/unlock
  - Dark/light mode (island tetap hitam, tapi Settings ikut tema)
  - Menu bar auto-hide aktif

---

## 12. Risiko & Mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| MediaRemote dibatasi lebih jauh di update macOS | Now Playing mati | Abstraksi provider + fallback AppleScript |
| API privat (DisplayServices, CoreBrightness) berubah | HUD brightness rusak | Mode observer-only, deteksi `dlsym` gagal → nonaktifkan modul dengan anggun |
| Event tap mengganggu tombol media | Volume tidak bisa diubah | Selalu teruskan event jika handler gagal; tombol "disable" darurat |
| Window menutupi item menu bar | UX buruk | Click-through ketat; lebar compact dibatasi agar tidak menabrak menu app/status item |
| Tidak bisa masuk Mac App Store | Distribusi | Developer ID + notarization + Sparkle |

---

## 13. Referensi Open Source

Pelajari (jangan copy mentah; cek lisensi):
- **boring.notch** (TheBoredTeam) — app notch open source paling lengkap, SwiftUI.
- **DynamicNotchKit** — library SwiftUI untuk konten di notch.
- **mediaremote-adapter** (ungive) — akses Now Playing di macOS 15.4+.
- Komersial untuk inspirasi UX: NotchNook, Alcove.

---

## 14. Keputusan yang Perlu Dikonfirmasi

1. Target minimum macOS: 14 (disarankan) atau 15?
2. Ganti HUD sistem (butuh Accessibility + API privat) atau cukup observer-only di awal?
3. Dukungan layar tanpa notch di versi pertama, atau notch-only dulu?
4. Distribusi pribadi saja atau rilis publik (perlu akun Apple Developer berbayar untuk notarization)?
