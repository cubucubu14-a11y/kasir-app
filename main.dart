import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

const String SCRIPT_URL =
    'https://script.google.com/macros/s/AKfycbwFep4Th6FMZ-uob8fiSjUKsBTU2boX-iK1i2gDlgKJT0E2dX4wxD0m5teRx-9dfS6g/exec';

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
  String tanggal;
  String jam;
  int nominal;
  String metode;
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
        id: m['id'],
        tanggal: m['tanggal'],
        jam: m['jam'],
        nominal: m['nominal'],
        metode: m['metode'] ?? 'Tunai',
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
  List<int> deletedIds = [];
  int nextId = 1;
  bool sedangSync = false;
  String progressSync = '';
  bool showOmset = false;
  final nominals = [
    5000,
    10000,
    15000,
    20000,
    25000,
    30000,
    35000,
    40000,
    45000,
    50000
  ];

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
    final delData = prefs.getString('deletedIds');
    if (delData != null) {
      final list = jsonDecode(delData) as List;
      deletedIds = list.map((e) => e as int).toList();
    }
    setState(() {});
    _syncSemua(silent: true);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'transaksi', jsonEncode(transaksi.map((t) => t.toJson()).toList()));
    await prefs.setString('deletedIds', jsonEncode(deletedIds));
  }

  String _tglStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _jamStr(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _rp(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  Future<http.Response> _getWithTimeout(Uri url) async {
    return await http.get(url).timeout(const Duration(seconds: 10));
  }

  Future<Map<String, dynamic>> _kirimUpsert(Transaksi t) async {
    try {
      final url = Uri.parse(SCRIPT_URL).replace(queryParameters: {
        'action': 'upsert',
        'id': t.id.toString(),
        'tanggal': t.tanggal,
        'jam': t.jam,
        'nominal': t.nominal.toString(),
        'metode': t.metode,
      });
      final res = await _getWithTimeout(url);
      if (res.statusCode == 200) {
        try {
          final body = jsonDecode(res.body);
          if (body['status'] == 'ok') return {'ok': true};
          return {'ok': false, 'err': 'server: ${body['message'] ?? '?'}'};
        } catch (_) {
          return {'ok': false, 'err': 'parse'};
        }
      }
      return {'ok': false, 'err': 'http-${res.statusCode}'};
    } catch (e) {
      return {'ok': false, 'err': '$e'};
    }
  }

  Future<Map<String, dynamic>> _kirimDelete(int id) async {
    try {
      final url = Uri.parse(SCRIPT_URL).replace(queryParameters: {
        'action': 'delete',
        'id': id.toString(),
      });
      final res = await _getWithTimeout(url);
      if (res.statusCode == 200) {
        try {
          final body = jsonDecode(res.body);
          if (body['status'] == 'ok') return {'ok': true};
          final msg = body['message'] ?? '?';
          if (msg.toString().contains('tidak ditemukan')) {
            return {'ok': true, 'notFound': true};
          }
          return {'ok': false, 'err': 'server: $msg'};
        } catch (_) {
          return {'ok': false, 'err': 'parse'};
        }
      }
      return {'ok': false, 'err': 'http-${res.statusCode}'};
    } catch (e) {
      return {'ok': false, 'err': '$e'};
    }
  }

  Future<Map<String, dynamic>> _kirimCleanup() async {
    try {
      final url = Uri.parse(SCRIPT_URL).replace(queryParameters: {
        'action': 'cleanup',
      });
      final res = await _getWithTimeout(url);
      if (res.statusCode == 200) {
        try {
          final body = jsonDecode(res.body);
          if (body['status'] == 'ok') return {'ok': true};
          return {'ok': false, 'err': 'server: ${body['message'] ?? '?'}'};
        } catch (_) {
          return {'ok': false, 'err': 'parse'};
        }
      }
      return {'ok': false, 'err': 'http-${res.statusCode}'};
    } catch (e) {
      return {'ok': false, 'err': '$e'};
    }
  }

  Future<void> _cobaSync(Transaksi t) async {
    final result = await _kirimUpsert(t);
    if (result['ok'] == true) {
      if (mounted) setState(() => t.synced = true);
      await _saveData();
    }
  }

  Future<void> _syncSemua({bool silent = false}) async {
    if (sedangSync) return;
    final pendingTrans = transaksi.where((t) => !t.synced).toList();
    final pendingDeletes = List<int>.from(deletedIds);

    if (pendingTrans.isEmpty && pendingDeletes.isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Semua data sudah tersinkron')));
      }
      return;
    }

    setState(() {
      sedangSync = true;
      progressSync = 'Memulai...';
    });

    int sukses = 0;
    int gagal = 0;
    final totalTugas = pendingTrans.length + pendingDeletes.length;
    int ke = 0;
    String errMsg = '';

    final sisaDeletes = <int>[];
    for (final id in pendingDeletes) {
      ke++;
      if (mounted) setState(() => progressSync = 'Hapus $ke/$totalTugas');
      final r = await _kirimDelete(id);
      if (r['ok'] == true) {
        sukses++;
      } else {
        sisaDeletes.add(id);
        gagal++;
        if (errMsg.isEmpty) errMsg = r['err'] ?? 'unknown';
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    for (final t in pendingTrans) {
      ke++;
      if (mounted) setState(() => progressSync = 'Kirim $ke/$totalTugas');
      final r = await _kirimUpsert(t);
      if (r['ok'] == true) {
        t.synced = true;
        sukses++;
      } else {
        gagal++;
        if (errMsg.isEmpty) errMsg = r['err'] ?? 'unknown';
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    deletedIds = sisaDeletes;
    await _saveData();

    if (mounted) {
      setState(() {
        sedangSync = false;
        progressSync = '';
      });
      String pesan;
      if (gagal == 0) {
        pesan = 'Sync berhasil: $sukses/$totalTugas data';
      } else if (sukses == 0) {
        pesan = 'Gagal semua: $errMsg';
      } else {
        pesan = 'Sebagian berhasil: $sukses/$totalTugas (gagal $gagal)';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pesan),
        duration: const Duration(seconds: 8),
      ));
    }
  }

  Future<void> _bersihkanSheetsDanSyncUlang() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bersihkan & Sync Ulang'),
        content: const Text(
            'INI AKAN MENGHAPUS SEMUA DATA DI SHEETS,\n'
            'lalu mengirim ulang semua data dari HP ini.\n\n'
            'Gunakan ini kalau ada selisih antara HP dan Sheets.\n\n'
            'Data di HP tetap aman.\n\n'
            'Lanjutkan?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('BATAL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF38BA8)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('BERSIHKAN',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (konfirmasi != true) return;

    setState(() {
      sedangSync = true;
      progressSync = 'Bersihkan Sheets...';
    });

    final hasil = await _kirimCleanup();

    if (hasil['ok'] != true) {
      if (mounted) {
        setState(() {
          sedangSync = false;
          progressSync = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal bersihkan Sheets: ${hasil['err']}'),
          duration: const Duration(seconds: 8),
        ));
      }
      return;
    }

    setState(() {
      for (final t in transaksi) {
        t.synced = false;
      }
      deletedIds = [];
      sedangSync = false;
      progressSync = '';
    });
    await _saveData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sheets dibersihkan. Mulai sync ulang...'),
        duration: Duration(seconds: 3),
      ));
    }

    _syncSemua();
  }

  int get _jumlahBelumSync =>
      transaksi.where((t) => !t.synced).length + deletedIds.length;

  List<Transaksi> _riwayatHariIni() {
    final today = _tglStr(DateTime.now());
    return transaksi.where((t) => t.tanggal == today).toList().reversed.toList();
  }

  int get _totalHariIni =>
      _riwayatHariIni().fold<int>(0, (sum, t) => sum + t.nominal);

  int get _totalTunaiHariIni => _riwayatHariIni()
      .where((t) => t.metode == 'Tunai')
      .fold<int>(0, (sum, t) => sum + t.nominal);

  int get _totalQrisHariIni => _riwayatHariIni()
      .where((t) => t.metode == 'QRIS')
      .fold<int>(0, (sum, t) => sum + t.nominal);

  Future<void> _konfirmasiNominal(int nominal) async {
    final hasil = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: Text('Simpan transaksi ini?\n\nNominal: Rp ${_rp(nominal)}'),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA6E3A1)),
            onPressed: () => Navigator.pop(ctx, 'Tunai'),
            child: const Text('TUNAI',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF89B4FA)),
            onPressed: () => Navigator.pop(ctx, 'QRIS'),
            child: const Text('QRIS',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('BATAL'),
          ),
        ],
      ),
    );

    if (hasil == 'Tunai' || hasil == 'QRIS') {
      final now = DateTime.now();
      final baru = Transaksi(
        id: nextId++,
        tanggal: _tglStr(now),
        jam: _jamStr(now),
        nominal: nominal,
        metode: hasil!,
      );
      setState(() => transaksi.add(baru));
      await _saveData();
      _cobaSync(baru);
    }
  }

  Future<void> _editTransaksi(Transaksi t) async {
    final controller = TextEditingController(text: t.nominal.toString());
    String metodeEdit = t.metode;

    final hasil = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Edit Transaksi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Nominal baru (Rp)'),
                ),
                const SizedBox(height: 16),
                const Text('Metode:',
                    style: TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setLocalState(() => metodeEdit = 'Tunai'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: metodeEdit == 'Tunai'
                                ? const Color(0xFFA6E3A1)
                                : const Color(0xFF45475A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.payments,
                                  size: 18,
                                  color: metodeEdit == 'Tunai'
                                      ? Colors.black
                                      : Colors.white),
                              const SizedBox(width: 6),
                              Text('Tunai',
                                  style: TextStyle(
                                      color: metodeEdit == 'Tunai'
                                          ? Colors.black
                                          : Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setLocalState(() => metodeEdit = 'QRIS'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: metodeEdit == 'QRIS'
                                ? const Color(0xFF89B4FA)
                                : const Color(0xFF45475A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.qr_code,
                                  size: 18,
                                  color: metodeEdit == 'QRIS'
                                      ? Colors.black
                                      : Colors.white),
                              const SizedBox(width: 6),
                              Text('QRIS',
                                  style: TextStyle(
                                      color: metodeEdit == 'QRIS'
                                          ? Colors.black
                                          : Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('BATAL')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA6E3A1)),
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('SIMPAN', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );

    if (hasil == true) {
      final baru = int.tryParse(controller.text);
      if (baru != null && baru > 0) {
        setState(() {
          t.nominal = baru;
          t.metode = metodeEdit;
          t.synced = false;
        });
        await _saveData();
        _cobaSync(t);
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
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF38BA8)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('HAPUS', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        transaksi.removeWhere((x) => x.id == t.id);
        if (t.synced) {
          deletedIds.add(t.id);
        }
      });
      await _saveData();
      _syncSemua(silent: true);
    }
  }

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
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF89B4FA)),
            onPressed: () => Navigator.pop(ctx, 'hari-ini'),
            child: const Text('HARI INI',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA6E3A1)),
            onPressed: () => Navigator.pop(ctx, 'rentang'),
            child: const Text('PILIH TANGGAL',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
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
        .where((t) =>
            t.tanggal.compareTo(tgl1) >= 0 && t.tanggal.compareTo(tgl2) <= 0)
        .toList();

    if (filtered.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Tidak ada transaksi dari $tgl1 sampai $tgl2')));
      }
      return;
    }

    final buffer = StringBuffer('No,Tanggal,Jam,Nominal,Metode\n');
    for (int i = 0; i < filtered.length; i++) {
      final t = filtered[i];
      buffer
          .writeln('${i + 1},${t.tanggal},${t.jam},${t.nominal},${t.metode}');
    }
    final total = filtered.fold<int>(0, (sum, t) => sum + t.nominal);
    final totalTunai = filtered
        .where((t) => t.metode == 'Tunai')
        .fold<int>(0, (sum, t) => sum + t.nominal);
    final totalQris = filtered
        .where((t) => t.metode == 'QRIS')
        .fold<int>(0, (sum, t) => sum + t.nominal);
    buffer.writeln('');
    buffer.writeln('Total,,,$total,');
    buffer.writeln('Tunai,,,$totalTunai,');
    buffer.writeln('QRIS,,,$totalQris,');

    final namaFile = (tgl1 == tgl2)
        ? 'laporan_$tgl1.csv'
        : 'laporan_${tgl1}_sd_$tgl2.csv';

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$namaFile');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path)],
        text: 'Laporan Kasir ($tgl1${tgl1 == tgl2 ? '' : ' s/d $tgl2'})');
  }

  Future<void> _bukaLaporan() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LaporanPage(transaksi: transaksi),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final riwayat = _riwayatHariIni();
    final total = _totalHariIni;
    final totalTunai = _totalTunaiHariIni;
    final totalQris = _totalQrisHariIni;
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
              GestureDetector(
                onLongPressStart: (_) => setState(() => showOmset = true),
                onLongPressEnd: (_) => setState(() => showOmset = false),
                onLongPressCancel: () => setState(() => showOmset = false),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF313244),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: showOmset
                      ? Column(
                          children: [
                            Text(
                              'Total hari ini: Rp ${_rp(total)}',
                              style: const TextStyle(
                                  fontSize: 20, color: Color(0xFFA6E3A1)),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.payments,
                                    size: 16, color: Color(0xFFA6E3A1)),
                                const SizedBox(width: 4),
                                Text('Rp ${_rp(totalTunai)}',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFFA6E3A1))),
                                const SizedBox(width: 20),
                                const Icon(Icons.qr_code,
                                    size: 16, color: Color(0xFF89B4FA)),
                                const SizedBox(width: 4),
                                Text('Rp ${_rp(totalQris)}',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF89B4FA))),
                              ],
                            ),
                          ],
                        )
                      : const Text(
                          'Total hari ini: ●●●●●●●',
                          style: TextStyle(
                              fontSize: 20, color: Color(0xFFA6E3A1)),
                        ),
                ),
              ),
              const SizedBox(height: 2),
              const Text('(tahan untuk lihat omset)',
                  style: TextStyle(fontSize: 10, color: Colors.white38)),
              const SizedBox(height: 6),
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
                        sedangSync
                            ? 'SYNC $progressSync'
                            : 'SYNC SEKARANG ($belumSync)',
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: const Color(0xFF313244),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          Icon(
                            e.value.synced
                                ? Icons.cloud_done
                                : Icons.cloud_off,
                            color: e.value.synced
                                ? const Color(0xFFA6E3A1)
                                : const Color(0xFFF9E2AF),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            e.value.metode == 'QRIS'
                                ? Icons.qr_code
                                : Icons.payments,
                            size: 18,
                            color: e.value.metode == 'QRIS'
                                ? const Color(0xFF89B4FA)
                                : const Color(0xFFA6E3A1),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(
                                  '${e.key + 1}. ${e.value.jam}  —  Rp ${_rp(e.value.nominal)}',
                                  style: const TextStyle(
                                      color: Colors.white))),
                          IconButton(
                              icon: const Icon(Icons.edit,
                                  color: Color(0xFF89B4FA)),
                              onPressed: () => _editTransaksi(e.value)),
                          IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Color(0xFFF38BA8)),
                              onPressed: () => _hapusTransaksi(e.value)),
                        ],
                      ),
                    )),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF89B4FA),
                      padding: const EdgeInsets.all(14)),
                  onPressed: _bukaLaporan,
                  icon: const Icon(Icons.bar_chart, color: Colors.black),
                  label: const Text('LAPORAN PENJUALAN',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF38BA8),
                      padding: const EdgeInsets.all(14)),
                  onPressed:
                      sedangSync ? null : _bersihkanSheetsDanSyncUlang,
                  icon: const Icon(Icons.cleaning_services,
                      color: Colors.black),
                  label: const Text('BERSIHKAN SHEETS & SYNC ULANG',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 13,
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

// ============================================================
//   HALAMAN LAPORAN - PILIH RENTANG TANGGAL
// ============================================================
class LaporanPage extends StatefulWidget {
  final List<Transaksi> transaksi;
  const LaporanPage({super.key, required this.transaksi});

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  DateTime? tglAwal;
  DateTime? tglAkhir;

  static const bulanNama = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];

  String _fmtTgl(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _rp(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  List<Transaksi> get _filtered {
    if (tglAwal == null || tglAkhir == null) return [];
    final d1 = _fmtTgl(tglAwal!);
    final d2 = _fmtTgl(tglAkhir!);
    return widget.transaksi
        .where((t) =>
            t.tanggal.compareTo(d1) >= 0 && t.tanggal.compareTo(d2) <= 0)
        .toList();
  }

  int get _total => _filtered.fold<int>(0, (sum, t) => sum + t.nominal);

  int get _totalTunai => _filtered
      .where((t) => t.metode == 'Tunai')
      .fold<int>(0, (sum, t) => sum + t.nominal);

  int get _totalQris => _filtered
      .where((t) => t.metode == 'QRIS')
      .fold<int>(0, (sum, t) => sum + t.nominal);

  Map<String, int> get _perHari {
    final map = <String, int>{};
    for (final t in _filtered) {
      map[t.tanggal] = (map[t.tanggal] ?? 0) + t.nominal;
    }
    return map;
  }

  Map<String, int> get _perHariCount {
    final map = <String, int>{};
    for (final t in _filtered) {
      map[t.tanggal] = (map[t.tanggal] ?? 0) + 1;
    }
    return map;
  }

  Future<void> _pilihRentang() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: (tglAwal != null && tglAkhir != null)
          ? DateTimeRange(start: tglAwal!, end: tglAkhir!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
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
    setState(() {
      tglAwal = picked.start;
      tglAkhir = picked.end;
    });
  }

  void _pilihCepat(int hari) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      tglAwal = today.subtract(Duration(days: hari - 1));
      tglAkhir = today;
    });
  }

  void _pilihBulanIni() {
    final now = DateTime.now();
    setState(() {
      tglAwal = DateTime(now.year, now.month, 1);
      tglAkhir = DateTime(now.year, now.month, now.day);
    });
  }

  String _tglTampil(DateTime d) =>
      '${d.day} ${bulanNama[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final perHari = _perHari;
    final perHariCount = _perHariCount;
    final keysSorted = perHari.keys.toList()..sort((a, b) => b.compareTo(a));
    final adaRentang = tglAwal != null && tglAkhir != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Penjualan'),
        backgroundColor: const Color(0xFF1E1E2E),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF89B4FA),
                      padding: const EdgeInsets.all(14)),
                  onPressed: _pilihRentang,
                  icon: const Icon(Icons.date_range, color: Colors.black),
                  label: const Text('PILIH RENTANG TANGGAL',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              const Text('ATAU PILIH CEPAT:',
                  style:
                      TextStyle(fontSize: 12, color: Color(0xFF89B4FA))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip('Hari Ini', () => _pilihCepat(1)),
                  _chip('7 Hari', () => _pilihCepat(7)),
                  _chip('30 Hari', () => _pilihCepat(30)),
                  _chip('Bulan Ini', _pilihBulanIni),
                ],
              ),
              const SizedBox(height: 16),
              if (adaRentang)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF313244),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                          'Periode: ${_tglTampil(tglAwal!)}  s/d  ${_tglTampil(tglAkhir!)}',
                          style: const TextStyle(
                              color: Color(0xFF89B4FA), fontSize: 13),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      const Text('TOTAL OMZET',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('Rp ${_rp(_total)}',
                          style: const TextStyle(
                              color: Color(0xFFA6E3A1),
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                      const Divider(color: Colors.white24, height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.payments,
                                        size: 16,
                                        color: Color(0xFFA6E3A1)),
                                    SizedBox(width: 4),
                                    Text('Tunai',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('Rp ${_rp(_totalTunai)}',
                                    style: const TextStyle(
                                        color: Color(0xFFA6E3A1),
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Container(
                              width: 1, height: 40, color: Colors.white24),
                          Expanded(
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.qr_code,
                                        size: 16,
                                        color: Color(0xFF89B4FA)),
                                    SizedBox(width: 4),
                                    Text('QRIS',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('Rp ${_rp(_totalQris)}',
                                    style: const TextStyle(
                                        color: Color(0xFF89B4FA),
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                          '${_filtered.length} transaksi  •  ${perHari.length} hari ada transaksi',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF313244),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Pilih rentang tanggal dulu untuk melihat laporan',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 16),
              if (adaRentang && keysSorted.isNotEmpty) ...[
                const Text('RINCIAN PER HARI',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFF89B4FA))),
                const SizedBox(height: 8),
                ...keysSorted.map((tgl) {
                  final bagian = tgl.split('-');
                  final tglTxt =
                      '${bagian[2]} ${bulanNama[int.parse(bagian[1]) - 1]} ${bagian[0]}';
                  final subtotal = perHari[tgl]!;
                  final jumlah = perHariCount[tgl]!;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF313244),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tglTxt,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            Text('$jumlah transaksi',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                        Text('Rp ${_rp(subtotal)}',
                            style: const TextStyle(
                                color: Color(0xFFA6E3A1),
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: const Color(0xFF45475A),
      labelStyle: const TextStyle(color: Colors.white),
      onPressed: onTap,
    );
  }
}
