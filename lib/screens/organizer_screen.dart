import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import 'package:fl_chart/fl_chart.dart';

class OrganizerScreen extends StatefulWidget {
  const OrganizerScreen({super.key});

  @override
  State<OrganizerScreen> createState() => _OrganizerScreenState();
}

class _OrganizerScreenState extends State<OrganizerScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final FirebaseService _firebaseService = FirebaseService();
  Map<String, dynamic> _todayStats = {};
  List<Map<String, dynamic>> _visitorData = [];
  Map<String, dynamic> _companyAttributeStats = {};
  bool _isLoading = false;
  String _userName = '';
  int _selectedTabIndex = 0;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTabIndex = _tabController.index;
      });
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userName = await _authService.getUserName();
      final stats = await _firebaseService.getTodayStats();
      final visitors = await _firebaseService.getAllVisitors();
      final companyStats = await _firebaseService.getCompanyAttributeStats();
      
      print('=== データ読み込み結果 ===');
      print('ユーザー名: $userName');
      print('統計データ: $stats');
      print('来場者データ: ${visitors.length}件');
      print('来場者データ詳細: $visitors');
      print('企業属性統計: $companyStats');
      
      setState(() {
        _userName = userName;
        _todayStats = stats;
        _visitorData = visitors;
        _companyAttributeStats = companyStats;
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

  int _getTotalCount() {
    int total = 0;
    for (final data in _todayStats.values) {
      total += (data['count'] as int? ?? 0);
    }
    return total;
  }

  int _getTotalVisitors() {
    return _visitorData.length;
  }

  Map<String, int> _getGenderDistribution() {
    final genderCount = <String, int>{};
    for (final visitor in _visitorData) {
      final gender = visitor['gender']?.toString() ?? '不明';
      genderCount[gender] = (genderCount[gender] ?? 0) + 1;
    }
    return genderCount;
  }

  Map<String, int> _getAgeDistribution() {
    final ageCount = <String, int>{};
    for (final visitor in _visitorData) {
      final age = visitor['age'] as int? ?? 0;
      String ageGroup;
      if (age < 20) {
        ageGroup = '10代';
      } else if (age < 30) {
        ageGroup = '20代';
      } else if (age < 40) {
        ageGroup = '30代';
      } else if (age < 50) {
        ageGroup = '40代';
      } else if (age < 60) {
        ageGroup = '50代';
      } else if (age < 70) {
        ageGroup = '60代';
      } else {
        ageGroup = '70歳以上';
      }
      ageCount[ageGroup] = (ageCount[ageGroup] ?? 0) + 1;
    }
    return ageCount;
  }

  // デバッグ用メソッド
  Future<void> _debugData() async {
    print('=== デバッグ情報 ===');
    print('今日の統計: $_todayStats');
    print('来場者データ: $_visitorData');
    print('総来場者数: ${_getTotalVisitors()}');
    print('性別分布: ${_getGenderDistribution()}');
    print('年齢分布: ${_getAgeDistribution()}');
    
    // Firebaseのデータを直接確認
    await _firebaseService.debugAllDates();
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = _getTotalCount();
    final totalVisitors = _getTotalVisitors();
    final genderData = _getGenderDistribution();
    final ageData = _getAgeDistribution();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('主催者管理画面'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _debugData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: const [
            Tab(text: 'heatmap'),
            Tab(text: 'attribute'),
            Tab(text: '企業属性'),
            Tab(text: '興味分野'),
            Tab(text: 'performance'),
            Tab(text: 'popularity'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildHeatmapTab(),
                _buildAttributeTab(totalVisitors, genderData, ageData),
                _buildCompanyAttributeTab(),
                _buildInterestTab(),
                _buildPerformanceTab(),
                _buildPopularityTab(),
              ],
            ),
    );
  }

  Widget _buildHeatmapTab() {
    final totalCount = _getTotalCount();
    
    return Padding(
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
                  const Icon(Icons.admin_panel_settings, size: 40, color: Colors.purple),
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
                        '主催者',
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
          
          // 総合統計
          Card(
            color: Colors.purple.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.analytics, size: 40, color: Colors.purple),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '今日の総受信数',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        '$totalCount回',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 詳細統計
          const Text(
            'ビーコン別受信統計',
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
                      leading: const Icon(Icons.bluetooth, color: Colors.purple),
                      title: Text(deviceName),
                      subtitle: Text('受信回数: $count回'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${((count / totalCount) * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple,
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
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttributeTab(int totalVisitors, Map<String, int> genderData, Map<String, int> ageData) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // デバッグ情報表示
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'デバッグ情報',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('総来場者数: $totalVisitors'),
                  Text('性別データ: $genderData'),
                  Text('年齢データ: $ageData'),
                  Text('来場者データ件数: ${_visitorData.length}'),
                  if (_visitorData.isNotEmpty)
                    Text('最初の来場者: ${_visitorData.first}'),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 総来場者数
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.people,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        totalVisitors.toString(),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const Text(
                        '総来場者数',
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
          
          // 性別分布
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '性別分布',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (genderData.isEmpty)
                    const Text(
                      '性別データがありません',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    SizedBox(
                      height: 200,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: CustomPaint(
                              painter: GenderPieChartPainter(genderData, totalVisitors),
                              size: const Size(200, 200),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: genderData.entries.map((entry) {
                                final color = _getGenderColor(entry.key);
                                final percentage = totalVisitors > 0 
                                    ? ((entry.value / totalVisitors) * 100).toStringAsFixed(0)
                                    : '0';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${entry.key} ${percentage}%'),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 年齢分布
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '年齢分布',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (ageData.isEmpty)
                    const Text(
                      '年齢データがありません',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    SizedBox(
                      height: 200,
                      child: CustomPaint(
                        painter: AgeBarChartPainter(ageData),
                        size: const Size(double.infinity, 200),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 追加の統計情報
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '詳細統計',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (totalVisitors > 0) ...[
                    _buildStatRow('平均年齢', '${_getAverageAge().toStringAsFixed(1)}歳'),
                    _buildStatRow('最多年齢層', _getMostCommonAgeGroup()),
                    _buildStatRow('男性比率', '${_getGenderPercentage('男性')}%'),
                    _buildStatRow('女性比率', '${_getGenderPercentage('女性')}%'),
                  ] else
                    const Text(
                      '来場者データがありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 100), // 下部の余白
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.purple,
            ),
          ),
        ],
      ),
    );
  }

  double _getAverageAge() {
    if (_visitorData.isEmpty) return 0;
    final totalAge = _visitorData.fold<int>(0, (sum, visitor) => sum + (visitor['age'] as int? ?? 0));
    return totalAge / _visitorData.length;
  }

  String _getMostCommonAgeGroup() {
    final ageData = _getAgeDistribution();
    if (ageData.isEmpty) return 'データなし';
    return ageData.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  double _getGenderPercentage(String gender) {
    if (_visitorData.isEmpty) return 0;
    final count = _visitorData.where((v) => v['gender'] == gender).length;
    return ((count / _visitorData.length) * 100);
  }

  Widget _buildCompanyAttributeTab() {
    final industryData = _companyAttributeStats['industry'] as Map<String, int>? ?? {};
    final positionData = _companyAttributeStats['position'] as Map<String, int>? ?? {};
    final jobData = _companyAttributeStats['job'] as Map<String, int>? ?? {};
    final interestData = _companyAttributeStats['interests'] as Map<String, int>? ?? {};
    final totalVisitors = _companyAttributeStats['totalVisitors'] as int? ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          Card(
            color: Colors.purple.shade50,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.purple,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.business_center,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        totalVisitors.toString(),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                      const Text(
                        '来場者の企業属性分析',
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
          
          // 業種別分布（円グラフ）
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '業種別分布',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (industryData.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          '業種データがありません',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        SizedBox(
                          height: 250,
                          child: PieChart(
                            PieChartData(
                              sections: _createIndustryPieChartSections(industryData, totalVisitors),
                              sectionsSpace: 2,
                              centerSpaceRadius: 50,
                              borderData: FlBorderData(show: false),
                              pieTouchData: PieTouchData(
                                touchCallback: (FlTouchEvent event, pieTouchResponse) {},
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildLegend(industryData, totalVisitors, _getIndustryColor),
                      ],
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 役職別分布（棒グラフ）
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '役職別分布',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (positionData.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          '役職データがありません',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 300,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: positionData.values.reduce(math.max).toDouble() * 1.2,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                final position = positionData.keys.elementAt(groupIndex);
                                return BarTooltipItem(
                                  '$position\n${rod.toY.toInt()}人',
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                );
                              },
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index >= 0 && index < positionData.length) {
                                    final position = positionData.keys.elementAt(index);
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        position,
                                        style: const TextStyle(fontSize: 10),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                                reservedSize: 30,
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    value.toInt().toString(),
                                    style: const TextStyle(fontSize: 10),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: _createPositionBarGroups(positionData),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: 5,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: Colors.grey.shade300,
                                strokeWidth: 1,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 職業別分布（横棒グラフ）
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '職業別分布',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (jobData.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          '職業データがありません',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: math.max(300, jobData.length * 40.0),
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: jobData.values.reduce(math.max).toDouble() * 1.2,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                final job = jobData.keys.elementAt(groupIndex);
                                return BarTooltipItem(
                                  '$job\n${rod.toY.toInt()}人',
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                );
                              },
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index >= 0 && index < jobData.length) {
                                    final job = jobData.keys.elementAt(index);
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        job,
                                        style: const TextStyle(fontSize: 10),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                                reservedSize: 30,
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    value.toInt().toString(),
                                    style: const TextStyle(fontSize: 10),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: _createJobBarGroups(jobData),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: 5,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: Colors.grey.shade300,
                                strokeWidth: 1,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // サマリー統計
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'サマリー統計',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (totalVisitors > 0) ...[
                    _buildStatRow('最多業種', _getMostCommon(industryData)),
                    _buildStatRow('最多役職', _getMostCommon(positionData)),
                    _buildStatRow('最多職業', _getMostCommon(jobData)),
                    _buildStatRow('業種種類数', '${industryData.length}種類'),
                    _buildStatRow('役職種類数', '${positionData.length}種類'),
                  ] else
                    const Text(
                      '来場者データがありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 100), // 下部の余白
        ],
      ),
    );
  }

  // 円グラフのセクションを作成
  List<PieChartSectionData> _createIndustryPieChartSections(Map<String, int> data, int total) {
    final sections = <PieChartSectionData>[];
    int index = 0;
    
    for (final entry in data.entries) {
      final percentage = total > 0 ? (entry.value / total * 100) : 0.0;
      // 8%以上の場合のみパーセンテージを表示（重なりを防ぐため）
      final showTitle = percentage >= 8.0;
      
      sections.add(
        PieChartSectionData(
          color: _getIndustryColor(entry.key, index),
          value: entry.value.toDouble(),
          title: showTitle ? '${percentage.toStringAsFixed(1)}%' : '',
          radius: 90,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          titlePositionPercentageOffset: 0.55,
        ),
      );
      index++;
    }
    
    return sections;
  }

  // 役職別の棒グラフグループを作成
  List<BarChartGroupData> _createPositionBarGroups(Map<String, int> data) {
    final groups = <BarChartGroupData>[];
    int index = 0;
    
    for (final entry in data.entries) {
      groups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: entry.value.toDouble(),
              color: Colors.purple,
              width: 20,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
      index++;
    }
    
    return groups;
  }

  // 職業別の棒グラフグループを作成
  List<BarChartGroupData> _createJobBarGroups(Map<String, int> data) {
    final groups = <BarChartGroupData>[];
    int index = 0;
    
    for (final entry in data.entries) {
      groups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: entry.value.toDouble(),
              color: Colors.teal,
              width: 20,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
      index++;
    }
    
    return groups;
  }

  // 興味分野別の棒グラフグループを作成
  List<BarChartGroupData> _createInterestBarGroups(Map<String, int> data) {
    final groups = <BarChartGroupData>[];
    int index = 0;
    
    for (final entry in data.entries) {
      groups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: entry.value.toDouble(),
              color: Colors.orange,
              width: 20,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
      index++;
    }
    
    return groups;
  }

  // 凡例を作成
  Widget _buildLegend(Map<String, int> data, int total, Color Function(String, int) getColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12) / 2; // 2列表示
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: data.entries.map((entry) {
            final index = data.keys.toList().indexOf(entry.key);
            final color = getColor(entry.key, index);
            final percentage = total > 0 
                ? ((entry.value / total) * 100).toStringAsFixed(1)
                : '0.0';
            return SizedBox(
              width: itemWidth,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${entry.key} $percentage% (${entry.value}人)',
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // 業種別の色を取得
  Color _getIndustryColor(String industry, int index) {
    final colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.lime,
      Colors.deepOrange,
      Colors.lightBlue,
      Colors.brown,
    ];
    return colors[index % colors.length];
  }

  // 最頻出項目を取得
  String _getMostCommon(Map<String, int> data) {
    if (data.isEmpty) return 'データなし';
    return data.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  Widget _buildInterestTab() {
    final interestData = _companyAttributeStats['interests'] as Map<String, int>? ?? {};
    final totalVisitors = _companyAttributeStats['totalVisitors'] as int? ?? 0;
    
    // 興味分野の合計選択数を計算
    final totalSelections = interestData.values.fold<int>(0, (sum, count) => sum + count);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.interests,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          totalVisitors.toString(),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const Text(
                          '来場者の興味分野分析',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 注意書き
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '複数選択可能なため、合計が総来場者数を超える場合があります',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 興味のある分野別分布（棒グラフ）
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '興味のある分野別分布',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (interestData.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          '興味分野データがありません',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: math.max(300, interestData.length * 40.0),
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: interestData.values.reduce(math.max).toDouble() * 1.2,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                final interest = interestData.keys.elementAt(groupIndex);
                                final percentage = totalSelections > 0 
                                    ? ((rod.toY / totalSelections) * 100).toStringAsFixed(1)
                                    : '0.0';
                                return BarTooltipItem(
                                  '$interest\n${rod.toY.toInt()}人 ($percentage%)',
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                );
                              },
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index >= 0 && index < interestData.length) {
                                    final interest = interestData.keys.elementAt(index);
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        interest,
                                        style: const TextStyle(fontSize: 10),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                                reservedSize: 40,
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    value.toInt().toString(),
                                    style: const TextStyle(fontSize: 10),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: _createInterestBarGroups(interestData),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: 10,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: Colors.grey.shade300,
                                strokeWidth: 1,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // サマリー統計
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'サマリー統計',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (totalVisitors > 0 && interestData.isNotEmpty) ...[
                    _buildStatRow('最多興味分野', _getMostCommon(interestData)),
                    _buildStatRow('総来場者数', '$totalVisitors人'),
                    _buildStatRow('総選択数', '$totalSelections回'),
                    _buildStatRow('1人あたり平均', '${(totalSelections / totalVisitors).toStringAsFixed(1)}個'),
                    _buildStatRow('分野数', '${interestData.length}種類'),
                  ] else
                    const Text(
                      '興味分野データがありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 100), // 下部の余白
        ],
      ),
    );
  }

  Widget _buildPerformanceTab() {
    return const Center(
      child: Text(
        'Performance Tab\n(準備中)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, color: Colors.grey),
      ),
    );
  }

  Widget _buildPopularityTab() {
    return const Center(
      child: Text(
        'Popularity Tab\n(準備中)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, color: Colors.grey),
      ),
    );
  }

  Color _getGenderColor(String gender) {
    switch (gender) {
      case '男性':
        return Colors.blue;
      case '女性':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class GenderPieChartPainter extends CustomPainter {
  final Map<String, int> genderData;
  final int totalVisitors;

  GenderPieChartPainter(this.genderData, this.totalVisitors);

  @override
  void paint(Canvas canvas, Size size) {
    if (totalVisitors == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 20;
    
    double startAngle = -math.pi / 2; // Start from top
    
    final colors = [Colors.blue, Colors.red, Colors.grey];
    int colorIndex = 0;
    
    for (final entry in genderData.entries) {
      final sweepAngle = (entry.value / totalVisitors) * 2 * math.pi;
      
      final paint = Paint()
        ..color = colors[colorIndex % colors.length]
        ..style = PaintingStyle.fill;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
      
      startAngle += sweepAngle;
      colorIndex++;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class AgeBarChartPainter extends CustomPainter {
  final Map<String, int> ageData;

  AgeBarChartPainter(this.ageData);

  @override
  void paint(Canvas canvas, Size size) {
    if (ageData.isEmpty) return;

    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final maxValue = ageData.values.isNotEmpty ? ageData.values.reduce(math.max) : 1;
    final barWidth = size.width / (ageData.length + 1);
    final maxHeight = size.height - 40;

    final ageGroups = ['10代', '20代', '30代', '40代', '50代', '60代', '70歳以上'];
    
    for (int i = 0; i < ageGroups.length; i++) {
      final ageGroup = ageGroups[i];
      final value = ageData[ageGroup] ?? 0;
      final barHeight = (value / maxValue) * maxHeight;
      
      final x = (i + 0.5) * barWidth;
      final y = size.height - barHeight - 20;
      
      canvas.drawRect(
        Rect.fromLTWH(x - barWidth * 0.3, y, barWidth * 0.6, barHeight),
        paint,
      );
      
      // Draw labels
      final textPainter = TextPainter(
        text: TextSpan(
          text: ageGroup,
          style: const TextStyle(fontSize: 10, color: Colors.black),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, size.height - 15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
