import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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
  Transaksi({required this.id, required this.tanggal, required this.jam, required this.nominal});
  Map<String, dynamic> toJson() => {'id': id, 'tanggal': tanggal, 'jam': jam, 'nominal': nominal};
  factory Transaksi.fromJson(Map<String, dynamic> m) => Transaksi(
    id: m['id'], tanggal: m['tanggal'], jam: m['jam'], nominal: m['nominal']);
}

class KasirPage extends StatefulWidget {
  const KasirPage({super.key});
  @override
  State<KasirPage> createState() => _KasirPageState();
}

class _KasirPageState extends State<KasirPage> {
  List<Transaksi> transaksi = [];
  int nextId = 1;
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
      setState(() {
        transaksi.add(Transaksi(
            id: nextId++, tanggal: _tglStr(now), jam: _jamStr(now), nominal: nominal));
      });
      await _saveData();
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
        setState(() => t.nominal = baru);
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

  Future<void> _exportCsv() async {
    if (transaksi.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada transaksi')));
      return;
    }
    final buffer = StringBuffer('No,Tanggal,Jam,Nominal\n');
    for (int i = 0; i < transaksi.length; i++) {
      final t = transaksi[i];
      buffer.writeln('${i + 1},${t.tanggal},${t.jam},${t.nominal}');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/laporan_kasir_${_tglStr(DateTime.now())}.csv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'Laporan Kasir');
  }

  @override
  Widget build(BuildContext context) {
    final riwayat = _riwayatHariIni();
    final total = riwayat.fold<int>(0, (sum, t) => sum + t.nominal);

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
