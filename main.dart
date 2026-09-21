import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

// ============================================================
//  GANTI URL DI BAWAH INI dengan URL Apps Script kamu
// ============================================================
const String SCRIPT_URL =
    'https://script.google.com/macros/s/AKfycbxelmoFg9Y4PiwFGa1e8tQYy7yAPmKetUUKzpBiy80VHOhzOXEP5vRPo7VxExDLyxIQ/exec';

void main() {
  runApp(const KasirApp());
}

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
      home: const KasirPage(),
    );
  }
}

class Transaksi {
  final int id;
  final String tanggal;
  final String jam;
  int nominal;
  bool synced;
  Transaksi({
    required this.id,
    required this.tanggal,
    required this.jam,
    required this.nominal,
    this.synced = false,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'tanggal': tanggal,
        'jam': jam,
        'nominal': nominal,
        'synced': synced,
      };
  factory Transaksi.fromJson(Map<String, dynamic> m) => Transaksi(
        id: m['id'],
        tanggal: m['tanggal'],
        jam: m['jam'],
        nominal: m['nominal'],
        synced: m['synced'] ?? false,
      );
}

class KasirPage extends StatefulWidget {
  const KasirPage({super.key});
  @override
  State<KasirPage> createState() => _KasirPageState();
}

class _KasirPageState extends State<KasirPage> {
  List<Transaksi> transaksi = [];
  int nextId = 1;
  bool sedangSync = false;
  final nominals = [5000, 10000, 15000, 20000, 25000, 30000, 35000, 40000, 45000, 50000];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('transaksi');
    if (data != null) {
      final list = jsonDecode(data) as List;
      transaksi = list.map((e) => Transaksi.fromJson(e)).toList();
      for (var t in transaksi) {
        if (t.id >= nextId) nextId = t.id + 1;
      }
    }
    setState(() {});
    // Coba sync otomatis saat app dibuka
    _syncSemua(silent: true);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('transaksi',
        jsonEncode(transaksi.map((t) => t.toJson()).toList()));
  }

  String _tglStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _jamStr(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _rp(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  // ============================================================
  //   GOOGLE SHEETS SYNC
  // ============================================================
  Future<bool> _kirimKeSheets(Transaksi t) async {
    try {
      final res = await http
          .post(
            Uri.parse(SCRIPT_URL),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'tanggal': t.tanggal,
              'jam': t.jam,
              'nominal': t.nominal,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['status'] == 'ok';
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _cobaSync(Transaksi t) async {
    final ok = await _kirimKeSheets(t);
    if (ok) {
      if (mounted) {
        setState(() => t.synced = true);
      }
      await _saveData();
    }
  }

  Future<void> _syncSemua({bool silent = false}) async {
    if (sedangSync) return;
    final pending = transaksi.where((t) => !t.synced).toList();
    if (pending.isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Semua data sudah tersinkron')));
      }
      return;
    }

    setState(() => sedangSync = true);
    int sukses = 0;
    for (final t in pending) {
      final ok = await _kirimKeSheets(t);
      if (ok) {
        t.synced = true;
        sukses++;
      }
    }
    await _saveData();
    if (mounted) {
      setState(() => sedangSync = false);
      if (!silent || sukses > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Sync selesai: $sukses dari ${pending.length} data')));
      }
    }
  }

  int get _jumlahBelumSync => transaksi.where((t) => !t.synced).length;

  // ============================================================
  //   CRUD TRANSAKSI
  // ============================================================
  Future<void> _konfirmasiNominal(int nominal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: Text('Simpan transaksi ini?\n\nNominal: Rp ${_rp(nominal)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('BATAL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA6E3A1)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SIMPAN', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (ok == true) {
      final now = DateTime.now();
      final baru = Transaksi(
          id: nextId++,
          tanggal: _tglStr(now),
          jam: _jamStr(now),
          nominal: nominal);
      setState(() => transaksi.add(baru));
      await _saveData();
      // Sync otomatis di background (tidak block UI)
      _cobaSync(baru);
    }
  }

  List<Transaksi> _riwayatHariIni() {
    final today = _tglStr(DateTime.now());
    return transaksi.where((t) => t.tanggal == today).toList().reversed.toList();
  }

  Future<void> _editTransaksi(Transaksi t) async {
    final controller = TextEditingController(text: t.nominal.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Nominal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Nominal baru (Rp)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('BATAL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA6E3A1)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SIMPAN', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (ok == true) {
      final baru = int.tryParse(controller.text);
      if (baru != null && baru > 0) {
        setState(() {
          t.nominal = baru;
          t.synced = false; // perlu sync ulang
        });
        await _saveData();
      }
    }
  }

  Future<void> _hapusTransaksi(Transaksi t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: Text('Hapus transaksi ${t.jam} - Rp ${_rp(t.nominal)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('BATAL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF38BA8)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('HAPUS', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => transaksi.removeWhere((x) => x.id == t.id));
      await _saveData();
    }
  }

  // ============================================================
  //   EXPORT CSV
  // ============================================================
  Future<void> _exportCsv() async {
    if (transaksi.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada transaksi')));
      return;
    }

    final pilihan = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export CSV'),
        content: const Text('Pilih periode yang mau di-export:'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('BATAL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF89B4FA)),
            onPressed: () => Navigator.pop(ctx, 'hari-ini'),
            child: const Text('HARI INI',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA6E3A1)),
            onPressed: () => Navigator.pop(ctx, 'rentang'),
            child: const Text('PILIH TANGGAL',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (pilihan == null || pilihan == 'cancel') return;

    String tgl1, tgl2;

    if (pilihan == 'hari-ini') {
      tgl1 = _tglStr(DateTime.now());
      tgl2 = tgl1;
    } else {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 7)),
          end: DateTime.now(),
        ),
        helpText: 'PILIH RENTANG TANGGAL',
        saveText: 'PILIH',
        cancelText: 'BATAL',
        builder: (context, child) {
          return Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF89B4FA),
                onPrimary: Colors.black,
                surface: Color(0xFF1E1E2E),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked == null) return;
      tgl1 = _tglStr(picked.start);
      tgl2 = _tglStr(picked.end);
    }

    final filtered = transaksi
        .where((t) => t.tanggal.compareTo(tgl1) >= 0 && t.tanggal.compareTo(tgl2) <= 0)
        .toList();

    if (filtered.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tidak ada transaksi dari $tgl1 sampai $tgl2')));
      }
      return;
    }

    final buffer = StringBuffer('No,Tanggal,Jam,Nominal\n');
    for (int i = 0; i < filtered.length; i++) {
      final t = filtered[i];
      buffer.writeln('${i + 1},${t.tanggal},${t.jam},${t.nominal}');
    }
    final total = filtered.fold<int>(0, (sum, t) => sum + t.nominal);
    buffer.writeln('');
    buffer.writeln('Total,,,$total');

    final namaFile = (tgl1 == tgl2)
        ? 'laporan_$tgl1.csv'
        : 'laporan_${tgl1}_sd_$tgl2.csv';

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$namaFile');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path)],
        text: 'Laporan Kasir ($tgl1${tgl1 == tgl2 ? '' : ' s/d $tgl2'})');
  }

  // ============================================================
  //   UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final riwayat = _riwayatHariIni();
    final total = riwayat.fold<int>(0, (sum, t) => sum + t.nominal);
    final belumSync = _jumlahBelumSync;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Text('KASIR',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Total hari ini: Rp ${_rp(total)}',
                  style: const TextStyle(fontSize: 22, color: Color(0xFFA6E3A1))),

              // Status sync
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    belumSync == 0 ? Icons.cloud_done : Icons.cloud_off,
                    color: belumSync == 0
                        ? const Color(0xFFA6E3A1)
                        : const Color(0xFFF9E2AF),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    belumSync == 0
                        ? 'Semua tersinkron ke Sheets'
                        : '$belumSync data belum tersinkron',
                    style: TextStyle(
                      fontSize: 12,
                      color: belumSync == 0
                          ? const Color(0xFFA6E3A1)
                          : const Color(0xFFF9E2AF),
                    ),
                  ),
                ],
              ),

              // Tombol SYNC manual
              if (belumSync > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF9E2AF),
                        padding: const EdgeInsets.all(10),
                      ),
                      onPressed: sedangSync ? null : () => _syncSemua(),
                      icon: sedangSync
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.sync, color: Colors.black),
                      label: Text(
                        sedangSync ? 'SEDANG SYNC...' : 'SYNC SEKARANG',
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: nominals
                    .map((n) => ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF89B4FA)),
                          onPressed: () => _konfirmasiNominal(n),
                          child: Text(_rp(n),
                              style: const TextStyle(
                                  fontSize: 20,
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 20),
              const Text('RIWAYAT HARI INI',
                  style: TextStyle(fontSize: 14, color: Color(0xFF89B4FA))),
              const SizedBox(height: 8),
              if (riwayat.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Belum ada transaksi',
                        style: TextStyle(color: Colors.grey)))
              else
                ...riwayat.asMap().entries.map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: const Color(0xFF313244),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          Icon(
                            e.value.synced ? Icons.cloud_done : Icons.cloud_off,
                            color: e.value.synced
                                ? const Color(0xFFA6E3A1)
                                : const Color(0xFFF9E2AF),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  '${e.key + 1}. ${e.value.jam}  —  Rp ${_rp(e.value.nominal)}',
                                  style: const TextStyle(color: Colors.white))),
                          IconButton(
                              icon: const Icon(Icons.edit, color: Color(0xFF89B4FA)),
                              onPressed: () => _editTransaksi(e.value)),
                          IconButton(
                              icon: const Icon(Icons.delete, color: Color(0xFFF38BA8)),
                              onPressed: () => _hapusTransaksi(e.value)),
                        ],
                      ),
                    )),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA6E3A1),
                      padding: const EdgeInsets.all(16)),
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.download, color: Colors.black),
                  label: const Text('EXPORT KE CSV',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
