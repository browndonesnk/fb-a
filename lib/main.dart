import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const apiBase = 'https://graph.facebook.com/v21.0';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FB Auto',
        theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final pageId = TextEditingController();
  final token = TextEditingController();
  final message = TextEditingController();
  final imageUrl = TextEditingController();
  DateTime? when;
  List<dynamic> scheduled = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    pageId.text = p.getString('pageId') ?? '';
    token.text = p.getString('token') ?? '';
    if (pageId.text.isNotEmpty && token.text.isNotEmpty) _refresh();
  }

  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('pageId', pageId.text.trim());
    await p.setString('token', token.text.trim());
    _snack('Réglages enregistrés');
    _refresh();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        initialDate: now.add(const Duration(days: 1)),
        firstDate: now,
        lastDate: now.add(const Duration(days: 29)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (t == null) return;
    setState(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _schedule() async {
    if (message.text.trim().isEmpty || when == null) {
      _snack('Écris un message et choisis une date');
      return;
    }
    final ts = when!.millisecondsSinceEpoch ~/ 1000;
    final minTs = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600;
    if (ts < minTs) {
      _snack('Choisis une heure au moins 10 minutes dans le futur');
      return;
    }
    setState(() => busy = true);
    try {
      final hasImage = imageUrl.text.trim().isNotEmpty;
      final url = Uri.parse(
          '$apiBase/${pageId.text.trim()}/${hasImage ? 'photos' : 'feed'}');
      final body = {
        'access_token': token.text.trim(),
        'published': 'false',
        'scheduled_publish_time': ts.toString(),
        if (hasImage) 'url': imageUrl.text.trim(),
        hasImage ? 'caption' : 'message': message.text.trim(),
      };
      final r = await http.post(url, body: body);
      final j = jsonDecode(r.body);
      if (r.statusCode == 200) {
        _snack('Publication programmée ✔');
        message.clear();
        imageUrl.clear();
        setState(() => when = null);
        _refresh();
      } else {
        _snack('Erreur : ${j['error']?['message'] ?? r.body}');
      }
    } catch (e) {
      _snack('Erreur réseau : $e');
    }
    setState(() => busy = false);
  }

  Future<void> _refresh() async {
    try {
      final url = Uri.parse(
          '$apiBase/${pageId.text.trim()}/scheduled_posts?fields=message,scheduled_publish_time&access_token=${token.text.trim()}');
      final r = await http.get(url);
      final j = jsonDecode(r.body);
      if (r.statusCode == 200) setState(() => scheduled = j['data'] ?? []);
    } catch (_) {}
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('FB Auto'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Programmer'),
            Tab(text: 'À venir'),
            Tab(text: 'Réglages'),
          ]),
        ),
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
                controller: message,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Message', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: imageUrl,
                decoration: const InputDecoration(
                    labelText: 'Lien d\'une image (optionnel)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.schedule),
                label: Text(when == null ? 'Choisir date et heure' : _fmt(when!))),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: busy ? null : _schedule,
                child: Text(busy ? 'Envoi…' : 'Programmer')),
          ]),
          RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(children: [
              if (scheduled.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Aucune publication programmée.')),
              for (final p in scheduled)
                ListTile(
                  title: Text(p['message'] ?? '(photo)',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(p['scheduled_publish_time'] == null
                      ? ''
                      : _fmt(DateTime.fromMillisecondsSinceEpoch(
                          (p['scheduled_publish_time'] as int) * 1000))),
                ),
            ]),
          ),
          ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
                controller: pageId,
                decoration: const InputDecoration(
                    labelText: 'ID de la page', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: token,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Jeton d\'accès de la page',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _saveSettings, child: const Text('Enregistrer')),
          ]),
        ]),
      ),
    );
  }
}
