
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
  static const String _hfOrgPrefsKey = 'cactus_hf_org';
  final TextEditingController _hfOrgController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _hfOrgController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final hfOrg = prefs.getString(_hfOrgPrefsKey);
    if (hfOrg != null && hfOrg.isNotEmpty) {
      CactusConfig.setHuggingFaceOrg(hfOrg);
    }
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final hfOrg = _hfOrgController.text.trim();
    if (hfOrg.isNotEmpty) {
      await prefs.setString(_hfOrgPrefsKey, hfOrg);
      CactusConfig.setHuggingFaceOrg(hfOrg);
    } else {
      await prefs.remove(_hfOrgPrefsKey);
    }
  }

  Future<void> _resetConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hfOrgPrefsKey);
    _hfOrgController.clear();
  }

  void _showConfigDialog() async {
    final prefs = await SharedPreferences.getInstance();
    _hfOrgController.text = prefs.getString(_hfOrgPrefsKey) ?? '';
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
                controller: _hfOrgController,
                decoration: const InputDecoration(
                  labelText: 'HuggingFace Org',
                  hintText: 'Default: Cactus-Compute',
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
