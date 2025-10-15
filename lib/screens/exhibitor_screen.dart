import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';

class ExhibitorScreen extends StatefulWidget {
  const ExhibitorScreen({super.key});

  @override
  State<ExhibitorScreen> createState() => _ExhibitorScreenState();
}

class _ExhibitorScreenState extends State<ExhibitorScreen> {
  final AuthService _authService = AuthService();
  final FirebaseService _firebaseService = FirebaseService();
  Map<String, dynamic> _todayStats = {};
  bool _isLoading = false;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userName = await _authService.getUserName();
      final stats = await _firebaseService.getTodayStats();
      
      setState(() {
        _userName = userName;
        _todayStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      print('データ読み込みエラー: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _logout() {
    _authService.logout();
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('出展者管理画面'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ユーザー情報
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 40, color: Colors.blue),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _userName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                '出展者',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 管理機能
                  const Text(
                    '管理機能',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).pushNamed('/visitor_management');
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  const Icon(Icons.people, size: 40, color: Colors.blue),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '来場者管理',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    '見込み客リスト',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          child: InkWell(
                            onTap: () {
                              // ブース詳細
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('ブース詳細機能は準備中です'),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  const Icon(Icons.store, size: 40, color: Colors.orange),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'ブース詳細',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 今日の統計
                  const Text(
                    '今日のビーコン受信統計',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (_todayStats.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          '今日の統計データはありません',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _todayStats.length,
                        itemBuilder: (context, index) {
                          final deviceName = _todayStats.keys.elementAt(index);
                          final data = _todayStats[deviceName] as Map<String, dynamic>;
                          final count = data['count'] ?? 0;
                          
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.bluetooth, color: Colors.blue),
                              title: Text(deviceName),
                              subtitle: Text('受信回数: $count回'),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  count.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
