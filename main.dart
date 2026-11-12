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
        colorScheme: const ColorScheme.dark(primary: const Color(0xFF89B4FA)),
      ),
      home: const SplashPage(),
    );
  }
}

// ================== HELPERS ==================
String tglStr(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String jamStr(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String rp(int n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

String fmtTglPendek(String tgl) {
  if (tgl.length < 10) return tgl;
  final p = tgl.split('-');
  final bln = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  return '${p[2]} ${bln[int.parse(p[1]) - 1]} ${p[0]}';
}

Future<Map<String, dynamic>> apiGet(Map<String, String> params) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final scriptUrl = prefs.getString('scriptUrl') ?? '';
    if (scriptUrl.isEmpty) return {'status': 'error', 'message': 'URL Script belum diatur'};
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
class RincianItem {
  String nama;
  int harga;
  int qty;
  RincianItem({required this.nama, required this.harga, required this.qty});
  Map<String, dynamic> toJson() => {'nama': nama, 'harga': harga, 'qty': qty};
  factory RincianItem.fromJson(Map<String, dynamic> m) => RincianItem(
        nama: m['nama'].toString(),
        harga: (m['harga'] as num).toInt(),
        qty: (m['qty'] as num).toInt(),
      );
}

class Transaksi {
  final int id;
  String tanggal, jam, metode;
  int nominal;
  bool synced;
  List<RincianItem> rincian;

  Transaksi({
    required this.id,
    required this.tanggal,
    required this.jam,
    required this.nominal,
    required this.metode,
    this.synced = false,
    this.rincian = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'tanggal': tanggal, 'jam': jam, 'nominal': nominal,
        'metode': metode, 'synced': synced,
        'rincian': rincian.map((e) => e.toJson()).toList(),
      };

  factory Transaksi.fromJson(Map<String, dynamic> m) => Transaksi(
        id: (m['id'] as num).toInt(),
        tanggal: m['tanggal'].toString(),
        jam: m['jam'].toString(),
        nominal: (m['nominal'] as num).toInt(),
        metode: (m['metode'] ?? 'Tunai').toString(),
        synced: m['synced'] ?? false,
        rincian: m['rincian'] != null 
            ? (m['rincian'] as List).map((e) => RincianItem.fromJson(e as Map<String, dynamic>)).toList()
            : [],
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

// ================== SPLASH & SETUP ==================
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
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SetupKasirPage()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const KasirPage()));
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class SetupKasirPage extends StatefulWidget {
  const SetupKasirPage({super.key});
  @override
  State<SetupKasirPage> createState() => _SetupKasirPageState();
}

class _SetupKasirPageState extends State<SetupKasirPage> {
  final namaC = TextEditingController();
  final urlC = TextEditingController();
  String? errNama, errUrl;

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
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const KasirPage()));
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
                const Text('PENGATURAN AWAL', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextField(controller: namaC, decoration: InputDecoration(labelText: 'Nama Tab (Kasir)', errorText: errNama, border: const OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(controller: urlC, decoration: InputDecoration(labelText: 'URL Apps Script', errorText: errUrl, border: const OutlineInputBorder())),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA6E3A1), padding: const EdgeInsets.all(14)),
                    onPressed: _simpan,
                    child: const Text('SIMPAN & MULAI', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
  bool syncing = false, _syncLock = false;
  String progress = '', tabKasir = '', namaKasir = '', namaCabang = '';
  bool _adaHantu = false, _sedangCek = false, _offline = false, _showKeranjang = false;
  List<MenuItem> menus = [], keranjang = [];
  String filterRiwayat = 'hari';
  int _riwayatTab = 0; // 0=Transaksi, 1=Produk
  DateTime? _customT1, _customT2;
  int _currentIndex = 0;

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
      data = (jsonDecode(d) as List).map((e) => Transaksi.fromJson(e as Map<String, dynamic>)).toList();
    }
    final dd = p.getString('kasirDel');
    if (dd != null) delIds = (jsonDecode(dd) as List).map((e) => e as int).toList();
    await _loadMenus();
    setState(() {});
    _sync(silent: true, retry: false);
    _cekHantu();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('transaksi', jsonEncode(data.map((t) => t.toJson()).toList()));
    await p.setString('kasirDel', jsonEncode(delIds));
  }

  Future<void> _loadMenus() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('menus');
    if (s != null) {
      try {
        menus = (jsonDecode(s) as List).map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) { menus = _defaultMenus(); }
    } else { menus = _defaultMenus(); }
    if (menus.isEmpty) menus.add(MenuItem(nama: '', harga: 0));
  }

  Future<void> _saveMenus() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('menus', jsonEncode(menus.map((m) => m.toJson()).toList()));
  }

  List<MenuItem> _defaultMenus() => [
    MenuItem(nama: 'Cireng', harga: 5000), MenuItem(nama: 'Cireng', harga: 10000),
    MenuItem(nama: 'Kentang', harga: 5000), MenuItem(nama: 'Kentang', harga: 10000),
    MenuItem(nama: 'Tahu', harga: 5000), MenuItem(nama: 'Bakso', harga: 10000),
  ];

  Future<void> _openMenuSettings() async {
    final result = await Navigator.push<List<MenuItem>>(context, MaterialPageRoute(builder: (_) => MenuSettingsPage(initial: menus)));
    if (result != null) { setState(() => menus = result); await _saveMenus(); }
  }

  Future<void> _openUrlSettings() async {
    final p = await SharedPreferences.getInstance();
    final urlC = TextEditingController(text: p.getString('scriptUrl') ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Atur URL Apps Script'),
        content: TextField(controller: urlC, decoration: const InputDecoration(labelText: 'URL')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('BATAL')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('SIMPAN')),
        ],
      ),
    );
    if (ok == true) {
      await p.setString('scriptUrl', urlC.text.trim());
      _snack('✓ URL diperbarui', ok: true);
      _cekHantu();
    }
  }

  Future<void> _cekHantu() async {
    if (_sedangCek || syncing) return;
    setState(() { _sedangCek = true; _offline = false; });
    final r = await apiGet({'action': 'cek-hantu', 'tab': tabKasir, 'mode': 'kasir', 'hari': '7'});
    if (!mounted) return;
    if (r['status'] == 'ok') {
      final idsSheets = (r['ids'] as List).map((e) => (e['id'] as num).toInt()).toSet();
      final idsHp = data.map((t) => t.id).toSet();
      setState(() { _adaHantu = idsSheets.any((id) => !idsHp.contains(id)); _sedangCek = false; });
    } else { setState(() { _sedangCek = false; _offline = true; }); }
  }

  int get belumSync => data.where((t) => !t.synced).length + delIds.length;

  List<Transaksi> _riwayat() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String t1, t2;
    switch (filterRiwayat) {
      case 'minggu':
        t1 = tglStr(today.subtract(Duration(days: today.weekday - 1)));
        t2 = tglStr(today);
        break;
      case 'bulan':
        t1 = tglStr(DateTime(now.year, now.month, 1));
        t2 = tglStr(today);
        break;
      case 'custom':
        if (_customT1 == null || _customT2 == null) return [];
        t1 = tglStr(_customT1!); t2 = tglStr(_customT2!);
        break;
      default:
        t1 = tglStr(today); t2 = t1;
    }
    return data.where((x) => x.tanggal.compareTo(t1) >= 0 && x.tanggal.compareTo(t2) <= 0).toList().reversed.toList();
  }

  String get _labelFilterAktif {
    switch (filterRiwayat) {
      case 'minggu': return 'Minggu Ini';
      case 'bulan': return 'Bulan Ini';
      case 'custom': return (_customT1 != null && _customT2 != null) ? '${fmtTglPendek(tglStr(_customT1!))} - ${fmtTglPendek(tglStr(_customT2!))}' : 'Rentang';
      default: return 'Hari Ini';
    }
  }

  int get _totalPeriode => _riwayat().fold(0, (s, t) => s + t.nominal);

  Future<Map<String, dynamic>> _upsert(Transaksi t) async => apiGet({
    'action': 'upsert', 'tab': tabKasir, 'id': t.id.toString(),
    'tanggal': t.tanggal, 'jam': t.jam, 'nominal': t.nominal.toString(), 'metode': t.metode,
  });

  Future<Map<String, dynamic>> _delete(int id) async => apiGet({'action': 'delete', 'tab': tabKasir, 'id': id.toString()});

  Future<void> _sync({bool silent = false, bool retry = true}) async {
    if (_syncLock) return; _syncLock = true;
    try {
      int attempt = 0;
      while (true) {
        attempt++;
        final pt = data.where((t) => !t.synced).toList();
        final pd = List<int>.from(delIds);
        if (pt.isEmpty && pd.isEmpty) {
          if (mounted && !silent && attempt == 1) _snack('Semua data tersinkron');
          return;
        }
        setState(() { syncing = true; progress = 'Memulai...'; });
        int ke = 0; final total = pt.length + pd.length; int gagal = 0; String err = ''; final sisa = <int>[];

        for (final id in pd) {
          ke++; if (mounted) setState(() => progress = 'Hapus $ke/$total');
          final r = await _delete(id);
          if (r['status'] != 'ok') { sisa.add(id); gagal++; if (err.isEmpty) err = r['message'] ?? '?'; }
          await Future.delayed(const Duration(milliseconds: 80));
        }
        for (final t in pt) {
          ke++; if (mounted) setState(() => progress = 'Kirim $ke/$total');
          final r = await _upsert(t);
          if (r['status'] == 'ok') { t.synced = true; } else { gagal++; if (err.isEmpty) err = r['message'] ?? '?'; }
          await Future.delayed(const Duration(milliseconds: 80));
        }
        delIds = sisa; await _save();
        if (gagal == 0) {
          if (mounted) setState(() { syncing = false; progress = ''; });
          if (!silent) _snack('✓ Sync berhasil', ok: true);
          _cekHantu(); return;
        }
        if (!retry || attempt >= 5) {
          if (mounted) setState(() { syncing = false; progress = ''; });
          _snack('Gagal setelah $attempt percobaan: $err', err: true); return;
        }
        if (mounted) setState(() => progress = 'Retry 3 dtk...');
        await Future.delayed(const Duration(seconds: 3));
      }
    } finally {
      _syncLock = false;
      if (mounted && syncing) setState(() { syncing = false; progress = ''; });
    }
  }

  void _snack(String m, {bool ok = false, bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), backgroundColor: ok ? const Color(0xFF2D4F2D) : err ? const Color(0xFF7F3F3F) : null,
    ));
  }

  Future<void> _tarikDanGabung() async {
    if (_syncLock) return;
    setState(() { syncing = true; progress = 'Ambil dari Sheets...'; });
    final r = await apiGet({'action': 'get-data-kasir', 'tab': tabKasir});
    if (r['status'] != 'ok') {
      if (mounted) setState(() { syncing = false; progress = ''; });
      _snack('Gagal: ${r['message']}', err: true); return;
    }
    final listSheets = (r['data'] as List).cast<Map<String, dynamic>>();
    final idsHp = data.map((t) => t.id).toSet();
    int ditambah = 0, dilewati = 0;
    for (var item in listSheets) {
      final id = (item['id'] as num).toInt();
      if (idsHp.contains(id)) { dilewati++; continue; }
      data.add(Transaksi(
        id: id, tanggal: (item['tanggal'] ?? '').toString(), jam: (item['jam'] ?? '').toString(),
        nominal: (item['nominal'] as num).toInt(), metode: (item['metode'] ?? 'Tunai').toString(), synced: true,
      ));
      ditambah++;
    }
    await _save();
    if (mounted) setState(() { syncing = false; progress = ''; });
    await _cekHantu();
    if (!mounted) return;
    await showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('✓ Tarik Selesai'),
      content: Text('Ditambahkan: $ditambah\nDilewati: $dilewati'),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ));
  }

  // --- PEMBAYARAN & KEMBALIAN ---
  Future<void> _prosesPembayaran() async {
  final total = keranjang.fold(0, (s, t) => s + t.harga);
  final cUang = TextEditingController();
  String metodePilihan = 'Tunai'; // Default
  
  final bayar = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (ctx, setL) {
        final uang = int.tryParse(cUang.text) ?? 0;
        final kembali = uang - total;
        
        // Jika QRIS, uang diterima dianggap Pas
        final isLunas = metodePilihan == 'QRIS' || uang >= total;

        return AlertDialog(
          title: const Text('Pembayaran'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total: Rp ${rp(total)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFA6E3A1))),
              const SizedBox(height: 12),
              
              // Pilihan Metode Pembayaran
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setL(() => metodePilihan = 'Tunai'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: metodePilihan == 'Tunai' ? const Color(0xFFA6E3A1) : const Color(0xFF45475A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.payments, size: 16, color: metodePilihan == 'Tunai' ? Colors.black : Colors.white),
                            const SizedBox(width: 4),
                            Text('Tunai', style: TextStyle(color: metodePilihan == 'Tunai' ? Colors.black : Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setL(() => metodePilihan = 'QRIS'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: metodePilihan == 'QRIS' ? const Color(0xFF89B4FA) : const Color(0xFF45475A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code, size: 16, color: metodePilihan == 'QRIS' ? Colors.black : Colors.white),
                            const SizedBox(width: 4),
                            Text('QRIS', style: TextStyle(color: metodePilihan == 'QRIS' ? Colors.black : Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Input Uang (Hanya muncul kalau pilih Tunai)
              if (metodePilihan == 'Tunai') ...[
                TextField(
                  controller: cUang,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setL(() {}),
                  decoration: const InputDecoration(labelText: 'Uang Diterima', prefixText: 'Rp '),
                ),
                const SizedBox(height: 8),
                Text('Kembalian: Rp ${rp(kembali > 0 ? kembali : 0)}', 
                  style: TextStyle(color: kembali >= 0 && uang > 0 ? Colors.green : Colors.red)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton(onPressed: () { cUang.text = total.toString(); setL(() {}); }, child: const Text('UANG PAS')),
                    ElevatedButton(
                      onPressed: isLunas ? () => Navigator.pop(c, true) : null,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF89B4FA)),
                      child: const Text('PROSES', style: TextStyle(color: Colors.black)),
                    ),
                  ],
                )
              ] else ...[
                // Jika QRIS, langsung tombol proses
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(c, true),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF89B4FA)),
                    child: const Text('PROSES QRIS', style: TextStyle(color: Colors.black)),
                  ),
                )
              ]
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('BATAL'))
          ],
        );
      }
    ),
  );

  if (bayar != true) return;
  
  final now = DateTime.now();
  final b = Transaksi(
    id: now.microsecondsSinceEpoch, 
    tanggal: tglStr(now), 
    jam: jamStr(now),
    nominal: total, 
    metode: metodePilihan, // <-- Ini yang menyimpan metode Tunai/QRIS
    rincian: _groupKeranjang(),
  );
  
  setState(() { 
    data.add(b); 
    keranjang.clear(); 
    _showKeranjang = false; 
  });
  
  await _save();
  _sync(silent: true, retry: true);
  _tanyaCetak(b);
}
  void _tanyaCetak(Transaksi t) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('Cetak Struk?'),
      content: Text('Transaksi Rp ${rp(t.nominal)} berhasil disimpan.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('TIDAK')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA6E3A1)),
          onPressed: () { Navigator.pop(c); _showPrintPreview(t); },
          child: const Text('CETAK', style: TextStyle(color: Colors.black)),
        ),
      ],
    ));
  }

  void _showPrintPreview(Transaksi t) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        content: SizedBox(
          width: 250,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(APP_HEADER, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Kasir: $namaKasir', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: 12)),
              const Divider(color: Colors.black),
              Text('Tgl: ${t.tanggal} ${t.jam}', style: const TextStyle(color: Colors.black, fontSize: 10)),
              const Divider(color: Colors.black),
              ...t.rincian.map((r) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${r.qty}x ${r.nama}', style: const TextStyle(color: Colors.black, fontSize: 11)),
                  Text('Rp ${rp(r.harga * r.qty)}', style: const TextStyle(color: Colors.black, fontSize: 11)),
                ],
              )),
              const Divider(color: Colors.black),
              Text('TOTAL: Rp ${rp(t.nominal)}', textAlign: TextAlign.right, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Text('Terima Kasih', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: 10)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('TUTUP', style: TextStyle(color: Colors.black54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF89B4FA)),
            onPressed: () async {
              Navigator.pop(c);
              if (!await _mintaIzinPrinter()) return;
              final perangkat = await Navigator.push<BluetoothInfo>(context, MaterialPageRoute(builder: (_) => const PrinterScanPage()));
              if (perangkat == null) return;
              try {
                bool konek = await PrintBluetoothThermal.connect(macPrinterAddress: perangkat.macAdress);
                if (!konek) { _snack('Gagal terhubung', err: true); return; }
                await PrintBluetoothThermal.writeBytes(_formatStruk(t, tabKasir));
                _snack('✓ Berhasil dicetak', ok: true);
                Future.microtask(() => PrintBluetoothThermal.disconnect);
              } catch (e) { _snack('Error: $e', err: true); }
            },
            child: const Text('CETAK', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  List<int> _formatStruk(Transaksi t, String kasir) {
    List<int> b = [];
    b += [0x1B, 0x40, 0x1B, 0x61, 0x01];
    b += latin1.encode("$APP_HEADER\nKasir: $kasir\n--------------------------------\n");
    b += [0x1B, 0x61, 0x00];
    b += latin1.encode("Tgl: ${t.tanggal} ${t.jam}\n--------------------------------\n");
    for (var r in t.rincian) {
      b += latin1.encode("${r.qty}x ${r.nama}\n");
      b += latin1.encode("    Rp ${rp(r.harga * r.qty)}\n");
    }
    b += latin1.encode("--------------------------------\n");
    b += [0x1B, 0x61, 0x02];
    b += latin1.encode("TOTAL: Rp ${rp(t.nominal)}\n\n\n");
    return b;
  }

  Future<void> _hapus(Transaksi t) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Hapus?'), content: Text('Hapus transaksi Rp ${rp(t.nominal)}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('BATAL')),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('HAPUS')),
      ],
    ));
    if (ok != true) return;
    setState(() { data.removeWhere((x) => x.id == t.id); if (t.synced) delIds.add(t.id); });
    await _save(); _sync(silent: true, retry: true);
  }

  Future<void> _pilihRentangRiwayat() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime(2100),
      initialDateRange: (_customT1 != null && _customT2 != null) ? DateTimeRange(start: _customT1!, end: _customT2!) : DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (r == null) return;
    setState(() { filterRiwayat = 'custom'; _customT1 = r.start; _customT2 = r.end; });
  }

  Future<void> _bukaLihatSubmenuFilter() async {
    final pilih = await showDialog<String>(context: context, builder: (c) => SimpleDialog(
      title: const Text('Filter Riwayat'),
      children: [
        _optFilter(c, 'hari', 'Hari Ini'), _optFilter(c, 'minggu', 'Minggu Ini'),
        _optFilter(c, 'bulan', 'Bulan Ini'), _optFilter(c, 'rentang', 'Rentang...'),
      ],
    ));
    if (pilih == null) return;
    if (pilih == 'rentang') { _pilihRentangRiwayat(); } else { setState(() => filterRiwayat = pilih); }
  }

  Widget _optFilter(BuildContext c, String val, String label) {
    final aktif = filterRiwayat == val || (val == 'rentang' && filterRiwayat == 'custom');
    return SimpleDialogOption(onPressed: () => Navigator.pop(c, val), child: Row(children: [
      Icon(aktif ? Icons.radio_button_checked : Icons.radio_button_off, color: aktif ? const Color(0xFFA6E3A1) : Colors.white54, size: 20),
      const SizedBox(width: 10), Text(label, style: TextStyle(color: aktif ? const Color(0xFFA6E3A1) : Colors.white)),
    ]));
  }

  Future<void> _bukaLihatSheet() async {
    if (tabKasir.isEmpty) { _snack('Tab kasir kosong', err: true); return; }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LihatSheetPage(mode: 'kasir', tabKasir: tabKasir)));
    _cekHantu();
  }

  // ================== UI ==================
  Widget _buildHalamanKasir() {
    final menuAktif = menus.where((m) => m.nama.isNotEmpty && m.harga > 0).toList();
    return Stack(children: [
      Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          width: double.infinity,
          color: const Color(0xFF313244),
          child: Text(APP_HEADER, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.5, crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemCount: menuAktif.length,
          itemBuilder: (context, i) {
            final m = menuAktif[i];
            final qty = keranjang.where((k) => k.nama == m.nama && k.harga == m.harga).length;
            return ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF89B4FA), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => setState(() => keranjang.add(m)),
              child: Stack(children: [
                Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(m.nama, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  Text('Rp ${rp(m.harga)}', style: const TextStyle(color: Colors.black, fontSize: 12)),
                ])),
                if (qty > 0) Positioned(top: 4, right: 4, child: CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Text('$qty', style: const TextStyle(fontSize: 10, color: Colors.white)))),
              ]),
            );
          },
        )),
      ]),
      Positioned(left: 12, right: 12, bottom: 12, child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA6E3A1), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        onPressed: () => setState(() => _showKeranjang = true),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Padding(padding: const EdgeInsets.only(left: 8), child: Text('${keranjang.length} Item', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
          Text('Bayar • Rp ${rp(keranjang.fold(0, (s, t) => s + t.harga))}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ]),
      )),
      if (_showKeranjang) Positioned.fill(child: GestureDetector(
        onTap: () => setState(() => _showKeranjang = false),
        child: Container(color: Colors.black54, child: Align(alignment: Alignment.bottomCenter, child: GestureDetector(
          onTap: () {}, child: Container(
            height: MediaQuery.of(context).size.height * 0.6,
            decoration: const BoxDecoration(color: Color(0xFF1E1E2E), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            child: Column(children: [
              Container(margin: const EdgeInsets.symmetric(vertical: 8), width: 40, height: 4, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2))),
              const Text('KERANJANG', style: TextStyle(fontWeight: FontWeight.bold)),
              const Divider(),
              Expanded(child: keranjang.isEmpty ? const Center(child: Text('Kosong')) : ListView.builder(
                itemCount: _groupKeranjang().length,
                itemBuilder: (c, i) {
                  final r = _groupKeranjang()[i];
                  return ListTile(
                    dense: true,
                    title: Text(r.nama, style: const TextStyle(fontSize: 13)),
                    subtitle: Text('Rp ${rp(r.harga)}', style: const TextStyle(fontSize: 11)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle, size: 20, color: Colors.orange),
                        onPressed: () {
                          setState(() {
                            final idx = keranjang.lastIndexWhere((k) => k.nama == r.nama && k.harga == r.harga);
                            if (idx >= 0) keranjang.removeAt(idx);
                            if (keranjang.isEmpty) _showKeranjang = false;
                          });
                        },
                      ),
                      Text('${r.qty}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle, size: 20, color: Colors.green),
                        onPressed: () {
                          setState(() {
                            final m = menus.firstWhere((k) => k.nama == r.nama && k.harga == r.harga);
                            keranjang.add(m);
                          });
                        },
                      ),
                    ]),
                  );
                },
              )),
              Container(
                padding: const EdgeInsets.all(12),
                color: const Color(0xFF313244),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Total:'),
                    Text('Rp ${rp(keranjang.fold(0, (s, t) => s + t.harga))}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFA6E3A1))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => setState(() => _showKeranjang = false),
                      child: const Text('BATAL', style: TextStyle(color: Colors.white)),
                    )),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF89B4FA)),
                      onPressed: keranjang.isEmpty ? null : _prosesPembayaran,
                      child: const Text('BAYAR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    )),
                  ])
                ]),
              )
            ]),
          ),
        ))),
      )),
    ]);
  }

  Widget _buildHalamanRiwayat() {
    final r = _riwayat();
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF313244),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total Omset:', style: TextStyle(fontSize: 12, color: Colors.white70)),
            Text('Rp ${rp(_totalPeriode)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFA6E3A1))),
          ]),
          TextButton.icon(onPressed: _bukaLihatSubmenuFilter, icon: const Icon(Icons.filter_list), label: Text(_labelFilterAktif)),
        ]),
      ),
      Row(children: [
        Expanded(child: TextButton(
          style: TextButton.styleFrom(backgroundColor: _riwayatTab == 0 ? const Color(0xFF45475A) : Colors.transparent),
          onPressed: () => setState(() => _riwayatTab = 0),
          child: Text('Transaksi', style: TextStyle(color: _riwayatTab == 0 ? Colors.white : Colors.white54)),
        )),
        Expanded(child: TextButton(
          style: TextButton.styleFrom(backgroundColor: _riwayatTab == 1 ? const Color(0xFF45475A) : Colors.transparent),
          onPressed: () => setState(() => _riwayatTab = 1),
          child: Text('Rekap Produk', style: TextStyle(color: _riwayatTab == 1 ? Colors.white : Colors.white54)),
        )),
      ]),
      Expanded(child: _riwayatTab == 0 ? _listTransaksi(r) : _listProduk(r)),
    ]);
  }

  Widget _listTransaksi(List<Transaksi> r) {
    if (r.isEmpty) return const Center(child: Text('Tidak ada data'));
    return ListView.builder(
      itemCount: r.length,
      itemBuilder: (c, i) => Card(
        color: const Color(0xFF313244),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ListTile(
          leading: Icon(r[i].metode == 'QRIS' ? Icons.qr_code : Icons.payments),
          title: Text('Rp ${rp(r[i].nominal)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${r[i].tanggal} ${r[i].jam}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.print, color: Color(0xFFA6E3A1)), onPressed: () => _showPrintPreview(r[i])),
            IconButton(icon: const Icon(Icons.delete, color: Color(0xFFF38BA8)), onPressed: () => _hapus(r[i])),
          ]),
        ),
      ),
    );
  }

  Widget _listProduk(List<Transaksi> r) {
    final map = <String, Map<String, dynamic>>{};
    for (var t in r) {
      for (var item in t.rincian) {
        final key = item.nama;
        if (map.containsKey(key)) {
          map[key]!['qty'] += item.qty;
          map[key]!['total'] += (item.qty * item.harga);
        } else {
          map[key] = {'qty': item.qty, 'total': (item.qty * item.harga)};
        }
      }
    }
    if (map.isEmpty) return const Center(child: Text('Tidak ada rincian produk'));
    final list = map.entries.toList()..sort((a, b) => b.value['total'].compareTo(a.value['total']));
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (c, i) => Card(
        color: const Color(0xFF313244),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ListTile(
          title: Text(list[i].key, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${list[i].value['qty']} Pcs terjual'),
          trailing: Text('Rp ${rp(list[i].value['total'])}', style: const TextStyle(color: Color(0xFFA6E3A1), fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildHalamanPengaturan() {
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('PENGATURAN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Card(color: const Color(0xFF313244), child: Column(children: [
        ListTile(leading: const Icon(Icons.cloud_upload, color: Color(0xFFF9E2AF)), title: Text('Kirim ke Sheets ($belumSync)'), onTap: () => _sync(retry: true)),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.cloud_download, color: Color(0xFFCBA6F7)), title: const Text('Tarik Data dari Sheets'), onTap: _tarikDanGabung),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.table_chart, color: Color(0xFFA6E3A1)), title: const Text('Lihat Data Sheet'), onTap: _bukaLihatSheet),
      ])),
      const SizedBox(height: 12),
      Card(color: const Color(0xFF313244), child: Column(children: [
        ListTile(leading: const Icon(Icons.tune, color: Color(0xFF89B4FA)), title: const Text('Atur Menu'), onTap: _openMenuSettings),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.link, color: Color(0xFF89B4FA)), title: const Text('Atur URL Script'), onTap: _openUrlSettings),
      ])),
      const SizedBox(height: 12),
      Card(color: const Color(0xFF313244), child: Column(children: [
        ListTile(leading: const Icon(Icons.person), title: const Text('Kasir'), subtitle: Text(namaKasir)),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.store), title: const Text('Cabang'), subtitle: Text(namaCabang.isEmpty ? '-' : namaCabang),
          trailing: const Icon(Icons.edit, size: 16),
          onTap: () async {
            final c = TextEditingController(text: namaCabang);
            final res = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Nama Cabang'), content: TextField(controller: c),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('BATAL')), ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('SIMPAN'))],
            ));
            if (res != null) {
              final p = await SharedPreferences.getInstance();
              await p.setString('namaCabang', res);
              setState(() => namaCabang = res);
            }
          },
        ),
      ])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _currentIndex, children: [
        _buildHalamanKasir(), _buildHalamanRiwayat(), _buildHalamanPengaturan(),
      ])),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: const Color(0xFF1E1E2E), selectedItemColor: const Color(0xFF89B4FA), unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.storefront), label: 'Kasir'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Riwayat'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Pengaturan'),
        ],
      ),
    );
  }
}

// ================== LAIN-LAIN (Printer & Lihat Sheet) ==================
class PrinterScanPage extends StatefulWidget {
  const PrinterScanPage({super.key});
  @override
  State<PrinterScanPage> createState() => _PrinterScanPageState();
}

class _PrinterScanPageState extends State<PrinterScanPage> {
  List<BluetoothInfo> perangkatList = [];
  bool scanning = true;
  @override
  void initState() { super.initState(); _scanPrinter(); }
  Future<void> _scanPrinter() async {
    setState(() => scanning = true);
   try {
  final list = await PrintBluetoothThermal.pairedBluetooths;
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
      appBar: AppBar(title: const Text('Pilih Printer'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: scanning ? null : _scanPrinter)]),
      body: scanning ? const Center(child: CircularProgressIndicator()) : perangkatList.isEmpty ? const Center(child: Text('Tidak ada printer ter-pairing')) : ListView.builder(
        itemCount: perangkatList.length,
        itemBuilder: (c, i) => ListTile(
          leading: const Icon(Icons.print), title: Text(perangkatList[i].name), subtitle: Text(perangkatList[i].macAdress),
          onTap: () => Navigator.pop(context, perangkatList[i]),
        ),
      ),
    );
  }
}

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
    menus = widget.initial.map((m) => MenuItem(nama: m.nama, harga: m.harga)).toList();
    if (menus.isEmpty) menus.add(MenuItem(nama: '', harga: 0));
  }
  Future<void> _edit(int index) async {
    final m = menus[index];
    final namaC = TextEditingController(text: m.nama);
    final hargaC = TextEditingController(text: m.harga > 0 ? m.harga.toString() : '');
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Menu ${index + 1}'), content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: namaC, decoration: const InputDecoration(labelText: 'Nama')),
        TextField(controller: hargaC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('BATAL')), ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('SIMPAN'))],
    ));
    if (ok == true) setState(() => menus[index] = MenuItem(nama: namaC.text.trim(), harga: int.tryParse(hargaC.text) ?? 0));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Atur Menu')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        ...menus.asMap().entries.map((e) => Card(
          color: const Color(0xFF313244),
          child: ListTile(
            title: Text(e.value.nama.isEmpty ? '(Kosong)' : e.value.nama), subtitle: Text('Rp ${rp(e.value.harga)}'),
            onTap: () => _edit(e.key),
            trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => menus.removeAt(e.key))),
          ),
        )),
        ElevatedButton.icon(onPressed: () => setState(() => menus.add(MenuItem(nama: '', harga: 0))), icon: const Icon(Icons.add), label: const Text('TAMBAH')),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: () => Navigator.pop(context, menus), child: const Text('SIMPAN SEMUA')),
      ]),
    );
  }
}

class LihatSheetPage extends StatefulWidget {
  final String mode; final String? tabKasir;
  const LihatSheetPage({super.key, required this.mode, required this.tabKasir});
  @override
  State<LihatSheetPage> createState() => _LihatSheetPageState();
}

class _LihatSheetPageState extends State<LihatSheetPage> {
  bool loading = true; String? error; List<Map<String, dynamic>> listData = [];
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    final r = await apiGet({'action': 'get-data-tab', 'tab': widget.tabKasir ?? ''});
    if (!mounted) return;
    if (r['status'] != 'ok') setState(() { loading = false; error = r['message']; });
    else setState(() { loading = false; listData = (r['data'] as List).cast<Map<String, dynamic>>(); });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sheet ${widget.tabKasir}')),
      body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Text(error!)) : ListView.builder(
        itemCount: listData.length,
        itemBuilder: (c, i) => ListTile(title: Text('Rp ${rp((listData[i]['nominal'] as num).toInt())}'), subtitle: Text(listData[i]['tanggal'].toString())),
      ),
    );
  }
}
