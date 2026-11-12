import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:permission_handler/permission_handler.dart';

// ================== KONFIGURASI ==================
const String APP_HEADER = 'CIRENG WOII';

void main() => runApp(const KasirApp());

class KasirApp extends StatelessWidget {
  const KasirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kasir',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E2E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF89B4FA),
        ),
      ),
      home: const SplashPage(),
    );
  }
}

// ================== HELPERS ==================
String tglStr(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String jamStr(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String rp(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

String fmtTglPendek(String tgl) {
  if (tgl.length < 10) return tgl;
  final p = tgl.split('-');
  final bln = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  return '${p[2]} ${bln[int.parse(p[1]) - 1]} ${p[0]}';
}

Future<Map<String, dynamic>> apiGet(Map<String, String> params) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final scriptUrl = prefs.getString('scriptUrl') ?? '';
    if (scriptUrl.isEmpty) {
      return {'status': 'error', 'message': 'URL Script belum diatur di pengaturan'};
    }
    final uri = Uri.parse(scriptUrl).replace(queryParameters: params);
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      return {'status': 'error', 'message': 'Format response salah'};
    }
    return {'status': 'error', 'message': 'HTTP ${res.statusCode}'};
  } catch (e) {
    return {'status': 'error', 'message': e.toString()};
  }
}

// ================== MODEL ==================
class Transaksi {
  final int id;
  String tanggal, jam, metode;
  int nominal;
  bool synced;

  Transaksi({
    required this.id,
    required this.tanggal,
    required this.jam,
    required this.nominal,
    required this.metode,
    this.synced = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'tanggal': tanggal,
        'jam': jam,
        'nominal': nominal,
        'metode': metode,
        'synced': synced,
      };

  factory Transaksi.fromJson(Map<String, dynamic> m) => Transaksi(
        id: (m['id'] as num).toInt(),
        tanggal: m['tanggal'].toString(),
        jam: m['jam'].toString(),
        nominal: (m['nominal'] as num).toInt(),
        metode: (m['metode'] ?? 'Tunai').toString(),
        synced: m['synced'] ?? false,
      );
}

class MenuItem {
  String nama;
  int harga;
  MenuItem({required this.nama, required this.harga});

  Map<String, dynamic> toJson() => {'nama': nama, 'harga': harga};

  factory MenuItem.fromJson(Map<String, dynamic> m) => MenuItem(
        nama: (m['nama'] ?? '').toString(),
        harga: (m['harga'] as num?)?.toInt() ?? 0,
      );
}

// ================== SPLASH ==================
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _cek();
  }

  Future<void> _cek() async {
    final p = await SharedPreferences.getInstance();
    final nama = p.getString('namaKasir');
    if (!mounted) return;

    if (nama == null || nama.isEmpty) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const SetupKasirPage()));
    } else {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const KasirPage()));
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}

// ================== SETUP KASIR ==================
class SetupKasirPage extends StatefulWidget {
  const SetupKasirPage({super.key});
  @override
  State<SetupKasirPage> createState() => _SetupKasirPageState();
}

class _SetupKasirPageState extends State<SetupKasirPage> {
  final namaC = TextEditingController();
  final urlC = TextEditingController();
  String? errNama;
  String? errUrl;

  @override
  void initState() {
    super.initState();
    _loadExistingUrl();
  }

  Future<void> _loadExistingUrl() async {
    final p = await SharedPreferences.getInstance();
    urlC.text = p.getString('scriptUrl') ?? '';
  }

  Future<void> _simpan() async {
    final nama = namaC.text.trim();
    final url = urlC.text.trim();
    setState(() {
      errNama = nama.isEmpty ? 'Wajib diisi' : null;
      errUrl = url.isEmpty ? 'Wajib diisi' : null;
    });

    if (nama.isEmpty || url.isEmpty) return;

    final p = await SharedPreferences.getInstance();
    await p.setString('namaKasir', nama);
    await p.setString('tabKasir', nama);
    await p.setString('scriptUrl', url);

    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const KasirPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                const Icon(Icons.store, size: 80, color: Color(0xFF89B4FA)),
                const SizedBox(height: 20),
                const Text('PENGATURAN AWAL',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Masukkan Nama Tab & URL Apps Script',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  controller: namaC,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Nama Tab (Kasir)',
                    hintText: 'Contoh: CIREng WOII',
                    errorText: errNama,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlC,
                  decoration: InputDecoration(
                    labelText: 'URL Apps Script',
                    hintText: 'https://script.google.com/...',
                    errorText: errUrl,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA6E3A1),
                        padding: const EdgeInsets.all(14)),
                    onPressed: _simpan,
                    child: const Text('SIMPAN & MULAI',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================== KASIR PAGE ==================
class KasirPage extends StatefulWidget {
  const KasirPage({super.key});
  @override
  State<KasirPage> createState() => _KasirPageState();
}

class _KasirPageState extends State<KasirPage> with WidgetsBindingObserver {
  List<Transaksi> data = [];
  List<int> delIds = [];
  bool syncing = false;
  String progress = '';
  bool showOmset = false;
  String tabKasir = '';
  String namaKasir = '';
  String namaCabang = '';
  bool _adaHantu = false;
  bool _sedangCek = false;
  bool _offline = false;
  List<MenuItem> menus = [];
  String filterRiwayat = 'hari';
  DateTime? _customT1, _customT2;
  bool _syncLock = false;

  // Variabel untuk Bottom Navigation & Keranjang
  int _currentIndex = 0;
  List<MenuItem> keranjang = [];
  bool _showKeranjang = false; // <--- TAMBAHKAN INI
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cekHantu();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    tabKasir = p.getString('tabKasir') ?? '';
    namaKasir = p.getString('namaKasir') ?? '';
    namaCabang = p.getString('namaCabang') ?? '';
    final d = p.getString('transaksi');
    if (d != null) {
      data = (jsonDecode(d) as List)
          .map((e) => Transaksi.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final dd = p.getString('kasirDel');
    if (dd != null) {
      delIds = (jsonDecode(dd) as List).map((e) => e as int).toList();
    }
    await _loadMenus();
    setState(() {});
    _sync(silent: true, retry: false);
    _cekHantu();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('transaksi',
        jsonEncode(data.map((t) => t.toJson()).toList()));
    await p.setString('kasirDel', jsonEncode(delIds));
  }

  Future<void> _loadMenus() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('menus');
    if (s != null) {
      try {
        menus = (jsonDecode(s) as List)
            .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        menus = _defaultMenus();
      }
    } else {
      menus = _defaultMenus();
    }
    if (menus.isEmpty) {
      menus.add(MenuItem(nama: '', harga: 0));
    }
  }

  Future<void> _saveMenus() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('menus',
        jsonEncode(menus.map((m) => m.toJson()).toList()));
  }

  List<MenuItem> _defaultMenus() => [
        MenuItem(nama: 'Cireng', harga: 5000),
        MenuItem(nama: 'Cireng', harga: 10000),
        MenuItem(nama: 'Kentang', harga: 5000),
        MenuItem(nama: 'Kentang', harga: 10000),
        MenuItem(nama: 'Tahu', harga: 5000),
        MenuItem(nama: 'Bakso', harga: 10000),
      ];

  Future<void> _openMenuSettings() async {
    final result = await Navigator.push<List<MenuItem>>(
      context,
      MaterialPageRoute(builder: (_) => MenuSettingsPage(initial: menus)),
    );
    if (result != null) {
      setState(() => menus = result);
      await _saveMenus();
    }
  }

  Future<void> _openUrlSettings() async {
    final p = await SharedPreferences.getInstance();
    final currentUrl = p.getString('scriptUrl') ?? '';
    final urlC = TextEditingController(text: currentUrl);

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Atur URL Apps Script'),
        content: TextField(
          controller: urlC,
          decoration: const InputDecoration(
            labelText: 'URL Apps Script',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('BATAL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA6E3A1)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('SIMPAN', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (ok == true) {
      final newUrl = urlC.text.trim();
      await p.setString('scriptUrl', newUrl);
      _snack('✓ URL Script berhasil diperbarui', ok: true);
      _cekHantu();
    }
  }

  Future<bool> _mintaIzinPrinter() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();

    final semuaDiizinkan = statuses.values.every(
      (s) => s.isGranted || s.isLimited || s.isRestricted,
    );

    if (!semuaDiizinkan) {
      final permanent = statuses.values.any((s) => s.isPermanentlyDenied);
      if (permanent) {
        _snack(
            'Izin Bluetooth ditolak permanen. Buka Pengaturan aplikasi.',
            err: true);
        await openAppSettings();
      } else {
        _snack('Izin Bluetooth diperlukan untuk mencetak', err: true);
      }
      return false;
    }
    return true;
  }

  Future<void> _cetakStruk(Transaksi t) async {
    final izin = await _mintaIzinPrinter();
    if (!izin) return;

    final perangkat = await Navigator.push<BluetoothInfo>(
      context,
      MaterialPageRoute(builder: (_) => const PrinterScanPage()),
    );

    if (perangkat == null) {
      _snack('Cetak dibatalkan');
      return;
    }

    try {
      bool konek = await PrintBluetoothThermal.connect(
          macPrinterAddress: perangkat.macAdress);
      if (!konek) {
        _snack('Gagal terhubung ke printer', err: true);
        return;
      }

      bool cetakData = await PrintBluetoothThermal.writeBytes(
          _formatStruk(t, tabKasir));
      if (cetakData) {
        _snack('✓ Struk berhasil dicetak', ok: true);
      } else {
        _snack('Gagal mencetak struk', err: true);
      }
      
      // PERBAIKAN DISCONNECT
      Future.microtask(() => PrintBluetoothThermal.disconnect);
      
    } catch (e) {
      _snack('Error printer: $e', err: true);
    }
  }

  List<int> _formatStruk(Transaksi t, String kasir) {
    List<int> bytes = [];
    bytes += [0x1B, 0x40];
    bytes += [0x1B, 0x61, 0x01];
    bytes += latin1.encode("$APP_HEADER\n");
    bytes += latin1.encode("Kasir: $kasir\n");
    if (namaCabang.isNotEmpty) {
      bytes += latin1.encode("Cabang: $namaCabang\n");
    }
    bytes += latin1.encode("--------------------------------\n");
    bytes += [0x1B, 0x61, 0x00];
    bytes += latin1.encode("Tanggal : ${t.tanggal} ${t.jam}\n");
    bytes += latin1.encode("No. Trx  : #${t.id}\n");
    bytes += latin1.encode("Metode   : ${t.metode}\n");
    bytes += latin1.encode("--------------------------------\n");
    bytes += [0x1B, 0x61, 0x02];
    bytes += latin1.encode("TOTAL: Rp ${rp(t.nominal)}\n");
    bytes += [0x1B, 0x61, 0x01];
    bytes += latin1.encode("--------------------------------\n");
    bytes += latin1.encode("Terima Kasih Atas Kunjungan Anda!\n\n\n");
    return bytes;
  }

  Future<void> _cekHantu() async {
    if (_sedangCek || syncing) return;
    setState(() {
      _sedangCek = true;
      _offline = false;
    });
    final r = await apiGet({
      'action': 'cek-hantu',
      'tab': tabKasir,
      'mode': 'kasir',
      'hari': '7'
    });
    if (!mounted) return;
    if (r['status'] == 'ok') {
      final idsSheets = (r['ids'] as List)
          .map((e) => (e['id'] as num).toInt())
          .toSet();
      final idsHp = data.map((t) => t.id).toSet();
      final hantu = idsSheets.where((id) => !idsHp.contains(id)).toList();
      setState(() {
        _adaHantu = hantu.isNotEmpty;
        _sedangCek = false;
      });
    } else {
      setState(() {
        _sedangCek = false;
        _offline = true;
      });
    }
  }

  int get belumSync => data.where((t) => !t.synced).length + delIds.length;

  List<Transaksi> _riwayat() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String t1, t2;
    switch (filterRiwayat) {
      case 'kemarin':
        final k = today.subtract(const Duration(days: 1));
        t1 = tglStr(k);
        t2 = t1;
        break;
      case 'kemarin2':
        final k = today.subtract(const Duration(days: 2));
        t1 = tglStr(k);
        t2 = t1;
        break;
      case 'custom':
        if (_customT1 == null || _customT2 == null) return [];
        t1 = tglStr(_customT1!);
        t2 = tglStr(_customT2!);
        break;
      default:
        t1 = tglStr(today);
        t2 = t1;
    }
    return data
        .where((x) =>
            x.tanggal.compareTo(t1) >= 0 && x.tanggal.compareTo(t2) <= 0)
        .toList()
        .reversed
        .toList();
  }

  String get _labelFilterAktif {
    switch (filterRiwayat) {
      case 'kemarin':
        return 'Kemarin';
      case 'kemarin2':
        return 'Kemarin Lagi';
      case 'custom':
        if (_customT1 != null && _customT2 != null) {
          return '${fmtTglPendek(tglStr(_customT1!))} - ${fmtTglPendek(tglStr(_customT2!))}';
        }
        return 'Rentang';
      default:
        return 'Hari Ini';
    }
  }

  int get _totalPeriode => _riwayat().fold(0, (s, t) => s + t.nominal);

  Future<Map<String, dynamic>> _upsert(Transaksi t) async => apiGet({
        'action': 'upsert',
        'tab': tabKasir,
        'id': t.id.toString(),
        'tanggal': t.tanggal,
        'jam': t.jam,
        'nominal': t.nominal.toString(),
        'metode': t.metode,
      });

  Future<Map<String, dynamic>> _delete(int id) async =>
      apiGet({'action': 'delete', 'tab': tabKasir, 'id': id.toString()});

  Future<void> _cobaSync(Transaksi t) async {
    await _sync(silent: true, retry: false);
  }

  Future<void> _sync({bool silent = false, bool retry = true}) async {
    if (_syncLock) return;
    _syncLock = true;
    try {
      int attempt = 0;
      while (true) {
        attempt++;
        final pt = data.where((t) => !t.synced).toList();
        final pd = List<int>.from(delIds);
        if (pt.isEmpty && pd.isEmpty) {
          if (mounted && !silent && attempt == 1) {
            _snack('Semua data sudah tersinkron');
          }
          return;
        }
        setState(() {
          syncing = true;
          progress = 'Memulai...';
        });
        int ke = 0;
        final total = pt.length + pd.length;
        int gagal = 0;
        String err = '';
        final sisa = <int>[];

        for (final id in pd) {
          ke++;
          if (mounted) setState(() => progress = 'Hapus $ke/$total');
          final r = await _delete(id);
          if (r['status'] != 'ok') {
            sisa.add(id);
            gagal++;
            if (err.isEmpty) err = r['message'] ?? '?';
          }
          await Future.delayed(const Duration(milliseconds: 80));
        }

        for (final t in pt) {
          ke++;
          if (mounted) setState(() => progress = 'Kirim $ke/$total');
          final r = await _upsert(t);
          if (r['status'] == 'ok') {
            t.synced = true;
          } else {
            gagal++;
            if (err.isEmpty) err = r['message'] ?? '?';
          }
          await Future.delayed(const Duration(milliseconds: 80));
        }

        delIds = sisa;
        await _save();

        if (gagal == 0) {
          if (mounted) {
            setState(() {
              syncing = false;
              progress = '';
            });
          }
          if (!silent) _snack('✓ Sync berhasil', ok: true);
          _cekHantu();
          return;
        }
        if (!retry || attempt >= 5) {
          if (mounted) {
            setState(() {
              syncing = false;
              progress = '';
            });
          }
          _snack('Gagal setelah $attempt percobaan: $err', err: true);
          return;
        }
        if (mounted) setState(() => progress = 'Retry 3 dtk...');
        await Future.delayed(const Duration(seconds: 3));
      }
    } finally {
      _syncLock = false;
      if (mounted && syncing) {
        setState(() {
          syncing = false;
          progress = '';
        });
      }
    }
  }

  void _snack(String m, {bool ok = false, bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      duration: const Duration(seconds: 4),
      backgroundColor: ok
          ? const Color(0xFF2D4F2D)
          : err
              ? const Color(0xFF7F3F3F)
              : null,
    ));
  }

  Future<void> _tarikDanGabung() async {
    if (_syncLock) return;
    setState(() {
      syncing = true;
      progress = 'Ambil dari Sheets...';
    });

    final r = await apiGet({
      'action': 'get-data-kasir',
      'tab': tabKasir,
    });

    if (r['status'] != 'ok') {
      if (mounted) {
        setState(() {
          syncing = false;
          progress = '';
        });
      }
      _snack('Gagal: ${r['message']}', err: true);
      return;
    }

    final listSheets = (r['data'] as List).cast<Map<String, dynamic>>();
    final idsHp = data.map((t) => t.id).toSet();
    int ditambah = 0;
    int dilewati = 0;

    for (var item in listSheets) {
      final id = (item['id'] as num).toInt();
      if (idsHp.contains(id)) {
        dilewati++;
        continue;
      }
      data.add(Transaksi(
        id: id,
        tanggal: (item['tanggal'] ?? '').toString(),
        jam: (item['jam'] ?? '').toString(),
        nominal: (item['nominal'] as num).toInt(),
        metode: (item['metode'] ?? 'Tunai').toString(),
        synced: true,
      ));
      ditambah++;
    }

    await _save();
    if (mounted) {
      setState(() {
        syncing = false;
        progress = '';
      });
    }
    await _cekHantu();

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('✓ Tarik & Gabung Selesai'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Data baru yang ditambahkan ke HP:'),
              const SizedBox(height: 8),
              Text('• Ditambahkan: $ditambah'),
              Text('• Dilewati (sudah ada): $dilewati'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _prosesPembayaran() async {
    final total = keranjang.fold(0, (s, t) => s + t.harga);
    
    final h = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pilih Pembayaran'),
        content: Text('Total Belanja: Rp ${rp(total)}'),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA6E3A1)),
            onPressed: () => Navigator.pop(c, 'Tunai'),
            child: const Text('TUNAI', style: TextStyle(color: Colors.black)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF89B4FA)),
            onPressed: () => Navigator.pop(c, 'QRIS'),
            child: const Text('QRIS', style: TextStyle(color: Colors.black)),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('BATAL')),
        ],
      ),
    );

    if (h == 'Tunai' || h == 'QRIS') {
      final now = DateTime.now();
      final b = Transaksi(
        id: now.microsecondsSinceEpoch,
        tanggal: tglStr(now),
        jam: jamStr(now),
        nominal: total,
        metode: h!,
      );
      
      setState(() {
        data.add(b);
        keranjang.clear();
      });
      
      await _save();
      _cobaSync(b);
      _tanyaCetak(b);
    }
  }

  void _tanyaCetak(Transaksi t) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cetak Struk?'),
        content: Text('Transaksi Rp ${rp(t.nominal)} berhasil disimpan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('TIDAK')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA6E3A1)),
            onPressed: () {
              Navigator.pop(c);
              _cetakStruk(t);
            },
            child: const Text('CETAK', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> _hapus(Transaksi t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus?'),
        content: Text('Hapus transaksi Rp ${rp(t.nominal)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('BATAL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF38BA8)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('HAPUS', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      data.removeWhere((x) => x.id == t.id);
      if (t.synced) delIds.add(t.id);
    });
    await _save();
    _sync(silent: true, retry: true);
  }

  Future<void> _pilihRentangRiwayat() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: (_customT1 != null && _customT2 != null)
          ? DateTimeRange(start: _customT1!, end: _customT2!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)), end: now),
      builder: (c, ch) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF89B4FA),
            onPrimary: Colors.black,
            surface: Color(0xFF1E1E2E),
            onSurface: Colors.white,
          ),
        ),
        child: ch!,
      ),
    );
    if (r == null) return;
    setState(() {
      filterRiwayat = 'custom';
      _customT1 = r.start;
      _customT2 = r.end;
    });
  }

  Future<void> _bukaLihatSubmenuFilter() async {
    final pilih = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Riwayat Penjualan'),
        children: [
          _optFilter(c, 'hari', 'Hari Ini'),
          _optFilter(c, 'kemarin', 'Kemarin'),
          _optFilter(c, 'kemarin2', 'Kemarin Lagi'),
          _optFilter(c, 'rentang', 'Rentang...'),
        ],
      ),
    );
    if (pilih == null) return;
    if (pilih == 'rentang') {
      _pilihRentangRiwayat();
    } else {
      setState(() => filterRiwayat = pilih);
    }
  }

  Widget _optFilter(BuildContext c, String val, String label) {
    final aktif = filterRiwayat == val ||
        (val == 'rentang' && filterRiwayat == 'custom');
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(c, val),
      child: Row(children: [
        Icon(
          aktif ? Icons.radio_button_checked : Icons.radio_button_off,
          color: aktif ? const Color(0xFFA6E3A1) : Colors.white54,
          size: 20,
        ),
        const SizedBox(width: 10),
        Text(
          val == 'rentang' &&
                  filterRiwayat == 'custom' &&
                  _customT1 != null &&
                  _customT2 != null
              ? '${fmtTglPendek(tglStr(_customT1!))} - ${fmtTglPendek(tglStr(_customT2!))}'
              : label,
          style: TextStyle(
            color: aktif ? const Color(0xFFA6E3A1) : Colors.white,
            fontWeight: aktif ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ]),
    );
  }

  Future<void> _bukaLihatSheet() async {
    if (tabKasir.isEmpty) {
      _snack('Tab kasir belum diset', err: true);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => LihatSheetPage(mode: 'kasir', tabKasir: tabKasir)),
    );
    _cekHantu();
  }

  // ================== HALAMAN KASIR (TAB 1) ==================
  Widget _buildHalamanKasir() {
  final menuAktif = menus.where((m) => m.nama.isNotEmpty && m.harga > 0).toList();

  return Stack(
    children: [
      Column(
        children: [
          // Header Omset
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            color: const Color(0xFF313244),
            child: Column(
              children: [
                Text(APP_HEADER, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                GestureDetector(
                  onLongPressStart: (_) => setState(() => showOmset = true),
                  onLongPressEnd: (_) => setState(() => showOmset = false),
                  child: Text(
                    showOmset ? 'Omset Hari Ini: Rp ${rp(_totalPeriode)}' : 'Omset: ••••••••',
                    style: const TextStyle(fontSize: 16, color: Color(0xFFA6E3A1)),
                  ),
                ),
              ],
            ),
          ),
          
          // Grid Menu Full Screen
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80), // Padding bawah untuk tombol keranjang
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: menuAktif.length,
              itemBuilder: (context, i) {
                final m = menuAktif[i];
                // Hitung berapa banyak menu ini ada di keranjang
                final qty = keranjang.where((k) => k.nama == m.nama && k.harga == m.harga).length;

                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF89B4FA),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    setState(() {
                      keranjang.add(m);
                    });
                  },
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(m.nama, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                            const SizedBox(height: 4),
                            Text('Rp ${rp(m.harga)}', style: const TextStyle(color: Colors.black, fontSize: 14)),
                          ],
                        ),
                      ),
                      // Badge jumlah jika ada di keranjang
                      if (qty > 0)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.red,
                            child: Text('$qty', style: const TextStyle(fontSize: 12, color: Colors.white)),
                          ),
                        )
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // Tombol Keranjang Melayang di Bawah
      Positioned(
        left: 16,
        right: 16,
        bottom: 16,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFA6E3A1),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            elevation: 8,
          ),
          onPressed: () {
            setState(() => _showKeranjang = true); // Buka Overlay Keranjang
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text('${keranjang.length} Item', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Text('Lihat Keranjang • Rp ${rp(keranjang.fold(0, (s, t) => s + t.harga))}', 
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      ),

      // OVERLAY KERANJANG (Muncul dari bawah)
      if (_showKeranjang)
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _showKeranjang = false), // Klik luar untuk tutup
            child: Container(
              color: Colors.black.withOpacity(0.6),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: () {}, // Cegah klik tembus ke background
                  child: Container(
                    height: MediaQuery.of(context).size.height * 0.6, // 60% tinggi layar
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Column(
                      children: [
                        // Handle bar
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
                        ),
                        const Text('KERANJANG BELANJA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const Divider(),
                        
                        // List Item Keranjang
                        Expanded(
                          child: keranjang.isEmpty
                            ? const Center(child: Text('Keranjang masih kosong'))
                            : ListView.builder(
                                itemCount: keranjang.length,
                                itemBuilder: (c, i) {
                                  final k = keranjang[i];
                                  return ListTile(
                                    title: Text(k.nama, style: const TextStyle(color: Colors.white)),
                                    subtitle: Text('Rp ${rp(k.harga)}', style: const TextStyle(color: Colors.white70)),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Color(0xFFF38BA8)),
                                      onPressed: () {
                                        setState(() {
                                          keranjang.removeAt(i);
                                          if (keranjang.isEmpty) _showKeranjang = false; // Tutup jika kosong
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                        ),
                        
                        // Area Total & Tombol Bayar
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Color(0xFF313244),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total Belanja:', style: TextStyle(fontSize: 16)),
                                  Text('Rp ${rp(keranjang.fold(0, (s, t) => s + t.harga))}', 
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFA6E3A1))),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF89B4FA),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  onPressed: keranjang.isEmpty ? null : () {
                                    setState(() => _showKeranjang = false);
                                    _prosesPembayaran();
                                  },
                                  child: const Text('BAYAR SEKARANG', 
                                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
  // ================== HALAMAN RIWAYAT (TAB 2) ==================
  Widget _buildHalamanRiwayat() {
    final r = _riwayat();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Riwayat Penjualan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _bukaLihatSubmenuFilter,
                icon: const Icon(Icons.filter_list),
                label: Text(_labelFilterAktif),
              )
            ],
          ),
        ),
        Expanded(
          child: r.isEmpty
              ? const Center(child: Text('Belum ada transaksi'))
              : ListView.builder(
                  itemCount: r.length,
                  itemBuilder: (c, i) {
                    final t = r[i];
                    return Card(
                      color: const Color(0xFF313244),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: Icon(t.metode == 'QRIS' ? Icons.qr_code : Icons.payments),
                        title: Text('Rp ${rp(t.nominal)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text('${t.tanggal} ${t.jam} - ${t.metode}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.print, color: Color(0xFFA6E3A1)), onPressed: () => _cetakStruk(t)),
                            IconButton(icon: const Icon(Icons.delete, color: Color(0xFFF38BA8)), onPressed: () => _hapus(t)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ================== HALAMAN PENGATURAN (TAB 3) ==================
  Widget _buildHalamanPengaturan() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('PENGATURAN APLIKASI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        
        // Sinkronisasi & Tarik Data
        Card(
          color: const Color(0xFF313244),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_upload, color: Color(0xFFF9E2AF)),
                title: Text('Kirim ke Sheets ($belumSync data)'),
                onTap: () => _sync(retry: true),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cloud_download, color: Color(0xFFCBA6F7)),
                title: const Text('Tarik Data dari Sheets'),
                onTap: _tarikDanGabung,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.table_chart, color: Color(0xFFA6E3A1)),
                title: const Text('Lihat Data di Sheet'),
                onTap: _bukaLihatSheet,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Pengaturan Menu & Script
        Card(
          color: const Color(0xFF313244),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.tune, color: Color(0xFF89B4FA)),
                title: const Text('Atur Menu & Harga'),
                onTap: _openMenuSettings,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.link, color: Color(0xFF89B4FA)),
                title: const Text('Atur URL Apps Script'),
                onTap: _openUrlSettings,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Profil Kasir & Cabang
        Card(
          color: const Color(0xFF313244),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person, color: Colors.white70),
                title: const Text('Nama Kasir'),
                subtitle: Text(namaKasir),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.store, color: Colors.white70),
                title: const Text('Cabang'),
                subtitle: Text(namaCabang.isEmpty ? '-' : namaCabang),
                trailing: const Icon(Icons.edit, size: 16),
                onTap: () async {
                  final c = TextEditingController(text: namaCabang);
                  final res = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Nama Cabang'),
                      content: TextField(controller: c),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('BATAL')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, c.text),
                          child: const Text('SIMPAN'),
                        ),
                      ],
                    ),
                  );
                  if (res != null) {
                    final p = await SharedPreferences.getInstance();
                    await p.setString('namaCabang', res);
                    setState(() => namaCabang = res);
                  }
                },
              ),
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _pages = [
      _buildHalamanKasir(),
      _buildHalamanRiwayat(),
      _buildHalamanPengaturan(),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
        },
        backgroundColor: const Color(0xFF1E1E2E),
        selectedItemColor: const Color(0xFF89B4FA),
        unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront),
            label: 'Kasir',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Riwayat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}

// ================== HALAMAN SCAN PRINTER BLUETOOTH ==================
class PrinterScanPage extends StatefulWidget {
  const PrinterScanPage({super.key});

  @override
  State<PrinterScanPage> createState() => _PrinterScanPageState();
}

class _PrinterScanPageState extends State<PrinterScanPage> {
  List<BluetoothInfo> perangkatList = [];
  bool scanning = true;

  @override
  void initState() {
    super.initState();
    _scanPrinter();
  }

  Future<void> _scanPrinter() async {
    setState(() => scanning = true);
    try {
      List<BluetoothInfo> list =
          await PrintBluetoothThermal.pairedBluetooths;
      setState(() {
        perangkatList = list;
        scanning = false;
      });
    } catch (e) {
      setState(() => scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Printer Bluetooth'),
        backgroundColor: const Color(0xFF1E1E2E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: scanning ? null : _scanPrinter,
          )
        ],
      ),
      body: scanning
          ? const Center(child: CircularProgressIndicator())
          : perangkatList.isEmpty
              ? const Center(
                  child: Text(
                      'Tidak ada printer bluetooth ter-pairing.\nSilakan sambungkan lewat pengaturan Bluetooth HP.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  itemCount: perangkatList.length,
                  itemBuilder: (context, index) {
                    final p = perangkatList[index];
                    return ListTile(
                      leading:
                          const Icon(Icons.print, color: Color(0xFF89B4FA)),
                      title: Text(p.name,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(p.macAdress,
                          style: const TextStyle(color: Colors.white54)),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
    );
  }
}

// ================== MENU SETTINGS PAGE (BISA SCROLL & TAMBAH) ==================
class MenuSettingsPage extends StatefulWidget {
  final List<MenuItem> initial;
  const MenuSettingsPage({super.key, required this.initial});
  @override
  State<MenuSettingsPage> createState() => _MenuSettingsPageState();
}

class _MenuSettingsPageState extends State<MenuSettingsPage> {
  late List<MenuItem> menus;

  @override
  void initState() {
    super.initState();
    menus = widget.initial
        .map((m) => MenuItem(nama: m.nama, harga: m.harga))
        .toList();
    if (menus.isEmpty) {
      menus.add(MenuItem(nama: '', harga: 0));
    }
  }

  Future<void> _edit(int index) async {
    final m = menus[index];
    final namaC = TextEditingController(text: m.nama);
    final hargaC = TextEditingController(
        text: m.harga > 0 ? m.harga.toString() : '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Menu ${index + 1}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: namaC,
                decoration: const InputDecoration(
                    labelText: 'Nama produk', hintText: 'Contoh: Cireng'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: hargaC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Harga (Rp)', hintText: 'Contoh: 5000'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('BATAL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA6E3A1)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('SIMPAN', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (ok == true) {
      final harga = int.tryParse(hargaC.text) ?? 0;
      setState(() {
        menus[index] = MenuItem(nama: namaC.text.trim(), harga: harga);
      });
    }
  }

  void _tambahMenu() {
    setState(() {
      menus.add(MenuItem(nama: '', harga: 0));
    });
  }

  void _hapusMenu(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Menu?'),
        content: const Text('Yakin ingin menghapus menu ini dari daftar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('BATAL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF38BA8)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('HAPUS', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        menus.removeAt(index);
      });
    }
  }

  void _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset Menu?'),
        content: const Text(
            'Kembalikan ke menu default?\n\n'
            'Cireng 5.000, Cireng 10.000\n'
            'Kentang 5.000, Kentang 10.000\n'
            'Tahu 5.000, Bakso 10.000'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('BATAL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF38BA8)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('RESET', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        menus = [
          MenuItem(nama: 'Cireng', harga: 5000),
          MenuItem(nama: 'Cireng', harga: 10000),
          MenuItem(nama: 'Kentang', harga: 5000),
          MenuItem(nama: 'Kentang', harga: 10000),
          MenuItem(nama: 'Tahu', harga: 5000),
          MenuItem(nama: 'Bakso', harga: 10000),
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atur Menu'),
        backgroundColor: const Color(0xFF1E1E2E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reset,
            tooltip: 'Reset ke default',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF313244),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Tap tombol untuk ubah nama & harga.\n'
                'Tekan ikon tong sampah untuk menghapus.\n'
                'Kosongkan nama & harga = tombol disembunyikan di kasir.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
            const SizedBox(height: 16),
            ...menus.asMap().entries.map((entry) {
              final i = entry.key;
              final m = entry.value;
              final kosong = m.nama.isEmpty || m.harga == 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: kosong ? const Color(0xFF45475A) : const Color(0xFF89B4FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFCBA6F7),
                    width: 1,
                  ),
                ),
                child: ListTile(
                  onTap: () => _edit(i),
                  title: Text(
                    m.nama.isEmpty ? '(kosong - tap untuk isi)' : m.nama,
                    style: TextStyle(
                      color: kosong ? Colors.white54 : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    m.harga == 0 ? '—' : 'Rp ${rp(m.harga)}',
                    style: TextStyle(
                      color: kosong ? Colors.white38 : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Color(0xFFF38BA8)),
                    onPressed: () => _hapusMenu(i),
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCBA6F7),
                padding: const EdgeInsets.all(14),
              ),
              onPressed: _tambahMenu,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('TAMBAH MENU BARU',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA6E3A1),
                padding: const EdgeInsets.all(16),
              ),
              onPressed: () => Navigator.pop(context, menus),
              icon: const Icon(Icons.save, color: Colors.black),
              label: const Text('SIMPAN MENU',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ================== HALAMAN LIHAT SHEET ==================
class LihatSheetPage extends StatefulWidget {
  final String mode;
  final String? tabKasir;
  const LihatSheetPage(
      {super.key, required this.mode, required this.tabKasir});

  @override
  State<LihatSheetPage> createState() => _LihatSheetPageState();
}

class _LihatSheetPageState extends State<LihatSheetPage> {
  bool loading = true;
  String? error;
  Map<String, List<Map<String, dynamic>>> dataPerTab = {};
  List<String> urutanTab = [];
  Set<String> expandedTabs = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    final tab = widget.tabKasir ?? '';
    if (tab.isEmpty) {
      setState(() {
        loading = false;
        error = 'Tab kasir belum diset';
      });
      return;
    }
    final r = await apiGet({'action': 'get-data-tab', 'tab': tab});
    if (!mounted) return;
    if (r['status'] != 'ok') {
      setState(() {
        loading = false;
        error = r['message'] ?? 'Gagal';
      });
      return;
    }
    final list = (r['data'] as List).cast<Map<String, dynamic>>();
    setState(() {
      loading = false;
      urutanTab = [tab];
      dataPerTab = {tab: list};
    });
  }

  void _showProgress(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Text(msg),
        ]),
      ),
    );
  }

  void _snack(String m, {bool ok = false, bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      duration: const Duration(seconds: 4),
      backgroundColor: ok
          ? const Color(0xFF2D4F2D)
          : err
              ? const Color(0xFF7F3F3F)
              : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sheet - ${widget.tabKasir}'),
        backgroundColor: const Color(0xFF1E1E2E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error,
                              color: Color(0xFFF38BA8), size: 64),
                          const SizedBox(height: 16),
                          Text(error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(
                              onPressed: _load,
                              child: const Text('COBA LAGI')),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (urutanTab.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Tidak ada tab yang ditemukan',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey)),
                          )
                        else
                          ...urutanTab.map((tab) =>
                              _buildTabCard(tab, dataPerTab[tab] ?? [])),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildTabCard(String tab, List<Map<String, dynamic>> dataTab) {
    final total =
        dataTab.fold<int>(0, (s, t) => s + ((t['nominal'] ?? 0) as int));
    final isKosong = dataTab.isEmpty;
    final isExpanded = expandedTabs.contains(tab);
    final showData = isExpanded ? dataTab : dataTab.take(10).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF313244),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF45475A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF45475A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              const Icon(Icons.store, color: Color(0xFF89B4FA), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tab,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
              Text(
                isKosong ? 'Kosong' : '${dataTab.length} data',
                style: TextStyle(
                    fontSize: 12,
                    color: isKosong ? Colors.white38 : Colors.white70),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total nominal:',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
                Text('Rp ${rp(total)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isKosong
                          ? Colors.white38
                          : const Color(0xFFA6E3A1),
                      fontWeight: FontWeight.bold,
                    )),
              ],
            ),
          ),
          if (isKosong)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Tab kosong',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  ...showData.map((t) {
                    final id = t['id'];
                    final tgl = (t['tanggal'] ?? '').toString();
                    final jam = (t['jam'] ?? '').toString();
                    final nom = (t['nominal'] ?? 0) as int;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Text('#$id',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white38)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('$tgl $jam',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white70)),
                        ),
                        Text('Rp ${rp(nom)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white)),
                      ]),
                    );
                  }),
                  if (dataTab.length > 10)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (isExpanded) {
                            expandedTabs.remove(tab);
                          } else {
                            expandedTabs.add(tab);
                          }
                        });
                      },
                      child: Text(
                        isExpanded
                            ? '▲ Sembunyikan'
                            : '▼ Lihat semua (${dataTab.length})',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF89B4FA)),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isKosong
                    ? const Color(0xFF45475A)
                    : const Color(0xFFF38BA8),
                padding: const EdgeInsets.symmetric(vertical: 12),
                disabledBackgroundColor: const Color(0xFF45475A),
              ),
              onPressed: isKosong ? null : () => _hapusRentang(tab, dataTab),
              icon: Icon(Icons.delete_sweep,
                  color: isKosong ? Colors.white38 : Colors.black),
              label: Text('HAPUS RENTANG TAB INI',
                  style: TextStyle(
                      color: isKosong ? Colors.white38 : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _hapusRentang(
      String tab, List<Map<String, dynamic>> dataTab) async {
    if (dataTab.isEmpty) {
      _snack('Tidak ada data di tab ini');
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
      builder: (c, ch) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFF38BA8),
            onPrimary: Colors.black,
            surface: Color(0xFF1E1E2E),
            onSurface: Colors.white,
          ),
        ),
        child: ch!,
      ),
    );
    if (range == null) return;

    final tgl1 = tglStr(range.start);
    final tgl2 = tglStr(range.end);
    final akanHapus = dataTab.where((t) {
      final tgl = (t['tanggal'] ?? '').toString();
      return tgl.compareTo(tgl1) >= 0 && tgl.compareTo(tgl2) <= 0;
    }).toList();
    final totalNominal =
        akanHapus.fold<int>(0, (s, t) => s + ((t['nominal'] ?? 0) as int));

    if (akanHapus.isEmpty) {
      _snack('Tidak ada data di rentang ini');
      return;
    }
    if (!mounted) return;

    final konf = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('⚠ Konfirmasi Hapus'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tab: $tab',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF89B4FA))),
              const SizedBox(height: 8),
              Text(
                  'Periode: ${fmtTglPendek(tgl1)} s/d ${fmtTglPendek(tgl2)}'),
              Text('Jumlah data: ${akanHapus.length}'),
              Text('Total: Rp ${rp(totalNominal)}',
                  style: const TextStyle(
                      color: Color(0xFFF38BA8),
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('BATAL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF38BA8)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('HAPUS',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (konf != true) return;

    _showProgress('Menghapus...');
    final r = await apiGet({
      'action': 'delete-range-tab',
      'tab': tab,
      'tgl1': tgl1,
      'tgl2': tgl2,
    });
    if (!mounted) return;
    Navigator.pop(context);

    if (r['status'] == 'ok') {
      final hapus = r['hapus'] ?? akanHapus.length;
      _snack('✓ $hapus data dihapus dari tab "$tab"', ok: true);
      _load();
    } else {
      _snack('Gagal: ${r['message']}', err: true);
    }
  }
}
