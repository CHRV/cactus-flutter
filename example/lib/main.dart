
import 'package:cactus/cactus.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/basic_completion.dart';
import 'pages/chat.dart';
import 'pages/embedding.dart';
import 'pages/fetch_models.dart';
import 'pages/function_calling.dart';
import 'pages/hybrid_completion.dart';
import 'pages/rag.dart';
import 'pages/streaming_completion.dart';
import 'pages/stt.dart';
import 'pages/vision.dart';
import 'pages/context_test.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cactus Examples',
      theme: ThemeData(
        primarySwatch: Colors.grey,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: Colors.black,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 1,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black),
          ),
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const String _proKeyPrefsKey = 'cactus_pro_key';
  static const String _hfOrgPrefsKey = 'cactus_hf_org';
  static const String _supabaseUrlPrefsKey = 'cactus_supabase_url';
  static const String _supabaseKeyPrefsKey = 'cactus_supabase_key';
  final TextEditingController _proKeyController = TextEditingController();
  final TextEditingController _hfOrgController = TextEditingController();
  final TextEditingController _supabaseUrlController = TextEditingController();
  final TextEditingController _supabaseKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    CactusConfig.setTelemetryToken('a83c7f7a-43ad-4823-b012-cbeb587ae788');
    _loadConfig();
  }

  @override
  void dispose() {
    _proKeyController.dispose();
    _hfOrgController.dispose();
    _supabaseUrlController.dispose();
    _supabaseKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final proKey = prefs.getString(_proKeyPrefsKey);
    if (proKey != null && proKey.isNotEmpty) {
      CactusConfig.setProKey(proKey);
    }
    final hfOrg = prefs.getString(_hfOrgPrefsKey);
    if (hfOrg != null && hfOrg.isNotEmpty) {
      CactusConfig.setHuggingFaceOrg(hfOrg);
    }
    final supabaseUrl = prefs.getString(_supabaseUrlPrefsKey);
    if (supabaseUrl != null && supabaseUrl.isNotEmpty) {
      CactusConfig.setSupabaseUrl(supabaseUrl);
    }
    final supabaseKey = prefs.getString(_supabaseKeyPrefsKey);
    if (supabaseKey != null && supabaseKey.isNotEmpty) {
      CactusConfig.setSupabaseKey(supabaseKey);
    }
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final proKey = _proKeyController.text.trim();
    if (proKey.isNotEmpty) {
      await prefs.setString(_proKeyPrefsKey, proKey);
      CactusConfig.setProKey(proKey);
    }
    final hfOrg = _hfOrgController.text.trim();
    if (hfOrg.isNotEmpty) {
      await prefs.setString(_hfOrgPrefsKey, hfOrg);
      CactusConfig.setHuggingFaceOrg(hfOrg);
    } else {
      await prefs.remove(_hfOrgPrefsKey);
    }
    final supabaseUrl = _supabaseUrlController.text.trim();
    if (supabaseUrl.isNotEmpty) {
      await prefs.setString(_supabaseUrlPrefsKey, supabaseUrl);
      CactusConfig.setSupabaseUrl(supabaseUrl);
    } else {
      await prefs.remove(_supabaseUrlPrefsKey);
    }
    final supabaseKey = _supabaseKeyController.text.trim();
    if (supabaseKey.isNotEmpty) {
      await prefs.setString(_supabaseKeyPrefsKey, supabaseKey);
      CactusConfig.setSupabaseKey(supabaseKey);
    } else {
      await prefs.remove(_supabaseKeyPrefsKey);
    }
  }

  Future<void> _resetConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hfOrgPrefsKey);
    await prefs.remove(_supabaseUrlPrefsKey);
    await prefs.remove(_supabaseKeyPrefsKey);
    CactusConfig.resetConfig();
    _hfOrgController.clear();
    _supabaseUrlController.clear();
    _supabaseKeyController.clear();
  }

  void _showConfigDialog() async {
    final prefs = await SharedPreferences.getInstance();
    _proKeyController.text = prefs.getString(_proKeyPrefsKey) ?? '';
    _hfOrgController.text = CactusConfig.huggingFaceOrg != 'Cactus-Compute' ? CactusConfig.huggingFaceOrg : '';
    _supabaseUrlController.text = CactusConfig.supabaseUrl != 'https://vlqqczxwyaodtcdmdmlw.supabase.co' ? CactusConfig.supabaseUrl : '';
    _supabaseKeyController.text = CactusConfig.supabaseKey != 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZscXFjenh3eWFvZHRjZG1kbWx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE1MTg2MzIsImV4cCI6MjA2NzA5NDYzMn0.nBzqGuK9j6RZ6mOPWU2boAC_5H9XDs-fPpo5P3WZYbI' ? CactusConfig.supabaseKey : '';
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuration'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _proKeyController,
                decoration: const InputDecoration(
                  labelText: 'Pro Key',
                  hintText: 'Enter your pro key',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hfOrgController,
                decoration: const InputDecoration(
                  labelText: 'HuggingFace Org',
                  hintText: 'Default: Cactus-Compute',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _supabaseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Supabase URL',
                  hintText: 'Custom Supabase URL',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _supabaseKeyController,
                decoration: const InputDecoration(
                  labelText: 'Supabase Key',
                  hintText: 'Custom Supabase anon key',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _resetConfig();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Configuration reset to defaults')),
                );
              }
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _saveConfig();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Configuration saved')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Cactus Examples'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: 'Set Pro Key',
            onPressed: _showConfigDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configuration',
            onPressed: _showConfigDialog,
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Basic Completion'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const BasicCompletionPage()),
              );
            },
          ),
          ListTile(
            title: const Text('Streaming Completion'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StreamingCompletionPage()),
              );
            },
          ),
          ListTile(
            title: const Text('Function Calling'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FunctionCallingPage()),
              );
            },
          ),
          ListTile(
            title: const Text('Hybrid Completion'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HybridCompletionPage()),
              );
            },
          ),
          ListTile(
            title: const Text('Fetch Models'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FetchModelsPage()),
              );
            },
          ),
          ListTile(
            title: const Text('Embedding'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EmbeddingPage()),
              );
            },
          ),
          ListTile(
            title: const Text('RAG'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RAGPage()),
              );
            },
          ),
          ListTile(
            title: const Text('Speech-to-Text'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const STTPage()),
              );
            },
          ),
          ListTile(
            title: const Text('Chat'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ChatPage()),
              );
            },
          ),
          ListTile(
            title: const Text('Vision'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const VisionPage()),
              );
            },
          ),
          ListTile(
            title: const Text('4K Context Test'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ContextTestPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
