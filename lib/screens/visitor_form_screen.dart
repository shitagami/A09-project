import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/auth_service.dart';

class VisitorFormScreen extends StatefulWidget {
  const VisitorFormScreen({super.key});

  @override
  State<VisitorFormScreen> createState() => _VisitorFormScreenState();
}

class _VisitorFormScreenState extends State<VisitorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _ageController = TextEditingController();
  
  final FirebaseService _firebaseService = FirebaseService();
  final AuthService _authService = AuthService();
  
  bool _isLoading = false;
  
  // フォームの選択肢
  String _selectedGender = '男性';
  String _selectedEventSource = 'Web';
  String _selectedJob = '会社員';
  List<String> _selectedInterests = [];

  final List<String> _genderOptions = ['男性', '女性', 'その他'];
  final List<String> _eventSourceOptions = [
    'Web',
    'SNS',
    '友人・知人',
    '新聞・雑誌',
    'テレビ・ラジオ',
    '企業からの案内',
    'その他'
  ];
  final List<String> _jobOptions = [
    '会社員',
    '公務員',
    '自営業',
    '学生',
    '主婦・主夫',
    'フリーランス',
    '医師・看護師',
    'エンジニア',
    '教師・講師',
    'その他'
  ];
  final List<String> _interestOptions = [
    'テクノロジー',
    'ビジネス',
    '教育',
    '健康・医療',
    'エンターテイメント',
    'スポーツ',
    '料理・食品',
    '旅行',
    'アート・デザイン',
    '環境・サステナビリティ'
  ];

  @override
  void dispose() {
    _emailController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedInterests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('興味のある分野を少なくとも1つ選択してください'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 現在のユーザーIDを取得
      final userId = _authService.currentUserId;
      if (userId == null) {
        throw Exception('ユーザーIDが取得できませんでした');
      }
      
      // Firestoreに来場者情報を保存
      await _firebaseService.saveVisitorData(userId, {
        'email': _emailController.text.trim(),
        'age': int.parse(_ageController.text),
        'gender': _selectedGender,
        'eventSource': _selectedEventSource,
        'job': _selectedJob,
        'interests': _selectedInterests,
        'createdAt': DateTime.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登録が完了しました！'),
            backgroundColor: Colors.green,
          ),
        );

        // フォーム送信成功後、混雑状況画面に遷移
        Navigator.of(context).pushReplacementNamed('/crowd_heatmap');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _skipForm() {
    Navigator.of(context).pushReplacementNamed('/crowd_heatmap');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('来場者情報入力'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _skipForm,
            child: const Text(
              'スキップ',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ウェルカムメッセージ
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person_add, color: Colors.green.shade700, size: 28),
                          const SizedBox(width: 12),
                          const Text(
                            'ようこそ！',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'より良いサービス提供のため、簡単な情報をご記入ください。\n（任意項目ですが、ご協力いただけると幸いです）',
                        style: TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),

              // メールアドレス
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'メールアドレス',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                  hintText: 'example@email.com',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'メールアドレスを入力してください';
                  }
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                    return '正しいメールアドレスを入力してください';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),

              // 年齢
              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '年齢',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cake),
                  suffix: Text('歳'),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '年齢を入力してください';
                  }
                  final age = int.tryParse(value);
                  if (age == null || age < 0 || age > 150) {
                    return '正しい年齢を入力してください';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),

              // 性別
              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: const InputDecoration(
                  labelText: '性別',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                items: _genderOptions.map((gender) => DropdownMenuItem(
                  value: gender,
                  child: Text(gender),
                )).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedGender = value!;
                  });
                },
              ),
              
              const SizedBox(height: 16),

              // 職業
              DropdownButtonFormField<String>(
                value: _selectedJob,
                decoration: const InputDecoration(
                  labelText: '職業',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work),
                ),
                items: _jobOptions.map((job) => DropdownMenuItem(
                  value: job,
                  child: Text(job),
                )).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedJob = value!;
                  });
                },
              ),
              
              const SizedBox(height: 16),

              // イベント情報源
              DropdownButtonFormField<String>(
                value: _selectedEventSource,
                decoration: const InputDecoration(
                  labelText: 'このイベントをどこで知りましたか？',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.info),
                ),
                items: _eventSourceOptions.map((source) => DropdownMenuItem(
                  value: source,
                  child: Text(source),
                )).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedEventSource = value!;
                  });
                },
              ),
              
              const SizedBox(height: 24),

              // 興味のある分野
              const Text(
                '興味のある分野（複数選択可）',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: _interestOptions.map((interest) => FilterChip(
                      label: Text(interest),
                      selected: _selectedInterests.contains(interest),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedInterests.add(interest);
                          } else {
                            _selectedInterests.remove(interest);
                          }
                        });
                      },
                      selectedColor: Colors.green.shade100,
                      checkmarkColor: Colors.green.shade700,
                    )).toList(),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),

              // 送信ボタン
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '登録してアプリを開始',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              
              const SizedBox(height: 16),

              // スキップボタン
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _skipForm,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.grey),
                  ),
                  child: const Text(
                    '後で入力する',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
} 