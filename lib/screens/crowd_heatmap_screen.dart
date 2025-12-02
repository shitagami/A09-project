import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';
import '../services/auth_service.dart';
import 'dart:async';

/// ビーコン検出情報を保存するクラス
class BeaconDetectionInfo {
  final DateTime detectionTime;
  final int rssi;
  
  BeaconDetectionInfo({
    required this.detectionTime,
    required this.rssi,
  });
}

class CrowdHeatmapScreen extends StatefulWidget {
  const CrowdHeatmapScreen({super.key});

  @override
  State<CrowdHeatmapScreen> createState() => _CrowdHeatmapScreenState();
}

class _CrowdHeatmapScreenState extends State<CrowdHeatmapScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final AuthService _authService = AuthService();
  
  // RSSI閾値: この値以下の信号は検出しない（ブースから遠すぎる）
  // ブース設定: 3m×3m、ビーコンは中心配置
  // 実測値: 0.5m=-70dBm, 1.0m=-78dBm, 1.5m=-86dBm, 2.0m=-92dBm
  // ブースの角（2.12m）をカバーするには-92 dBm必要
  // 注意: -92 dBmより弱い信号は除外される
  static const int kRssiThreshold = -92;
  
  Map<String, dynamic> _todayStats = {};
  bool _isLoading = true;
  String _userName = '';
  Map<String, BeaconDetectionInfo> _detectedBeacons = {};  // RSSI値も保存
  Set<String> _countedToday = {};
  
  // ルート表示用の状態変数
  bool _showingRoute = false;
  List<BeaconLocation> _currentRoute = [];
  List<Offset> _currentPath = []; // 通路に沿った実際の経路
  
  // 近接ブース表示用の状態変数
  BeaconLocation? _nearbyBooth;        // 近くのブース
  bool _showBoothOverlay = false;      // オーバーレイ表示フラグ
  
  // 通路のネットワーク（パスファインディング用）
  final List<PathNode> _pathNodes = [
    // 横通路のノード
    PathNode(50, 95, 'horizontal_1_left'),     // 横通路1 左端
    PathNode(155, 95, 'horizontal_1_center1'), // 横通路1 中央1（縦通路1との交差点）
    PathNode(255, 95, 'horizontal_1_center2'), // 横通路1 中央2（縦通路2との交差点）
    PathNode(555, 95, 'horizontal_1_center3'), // 横通路1 中央3（縦通路3との交差点）
    PathNode(650, 95, 'horizontal_1_right'),   // 横通路1 右端
    
    PathNode(50, 215, 'horizontal_2_left'),     // 横通路2 左端
    PathNode(155, 215, 'horizontal_2_center1'), // 横通路2 中央1
    PathNode(255, 215, 'horizontal_2_center2'), // 横通路2 中央2
    PathNode(555, 215, 'horizontal_2_center3'), // 横通路2 中央3
    PathNode(650, 215, 'horizontal_2_right'),   // 横通路2 右端
    
    PathNode(50, 335, 'horizontal_3_left'),     // 横通路3 左端
    PathNode(155, 335, 'horizontal_3_center1'), // 横通路3 中央1
    PathNode(255, 335, 'horizontal_3_center2'), // 横通路3 中央2
    PathNode(555, 335, 'horizontal_3_center3'), // 横通路3 中央3
    PathNode(650, 335, 'horizontal_3_right'),   // 横通路3 右端
    
    // 縦通路のノード
    PathNode(155, 40, 'vertical_1_top'),      // 縦通路1 上端
    PathNode(155, 95, 'vertical_1_cross1'),   // 縦通路1 横通路1との交差点
    PathNode(155, 215, 'vertical_1_cross2'),  // 縦通路1 横通路2との交差点
    PathNode(155, 335, 'vertical_1_cross3'),  // 縦通路1 横通路3との交差点
    PathNode(155, 450, 'vertical_1_bottom'),  // 縦通路1 下端
    
    PathNode(255, 40, 'vertical_2_top'),      // 縦通路2 上端
    PathNode(255, 95, 'vertical_2_cross1'),   // 縦通路2 横通路1との交差点
    PathNode(255, 215, 'vertical_2_cross2'),  // 縦通路2 横通路2との交差点
    PathNode(255, 335, 'vertical_2_cross3'),  // 縦通路2 横通路3との交差点
    PathNode(255, 450, 'vertical_2_bottom'),  // 縦通路2 下端
    
    PathNode(555, 40, 'vertical_3_top'),      // 縦通路3 上端
    PathNode(555, 95, 'vertical_3_cross1'),   // 縦通路3 横通路1との交差点
    PathNode(555, 215, 'vertical_3_cross2'),  // 縦通路3 横通路2との交差点
    PathNode(555, 335, 'vertical_3_cross3'),  // 縦通路3 横通路3との交差点
    PathNode(555, 450, 'vertical_3_bottom'),  // 縦通路3 下端
  ];
  
  // 通路のつながり（隣接リスト）
  final Map<String, List<String>> _pathConnections = {
    // 横通路1
    'horizontal_1_left': ['horizontal_1_center1'],
    'horizontal_1_center1': ['horizontal_1_left', 'horizontal_1_center2', 'vertical_1_cross1'],
    'horizontal_1_center2': ['horizontal_1_center1', 'horizontal_1_center3', 'vertical_2_cross1'],
    'horizontal_1_center3': ['horizontal_1_center2', 'horizontal_1_right', 'vertical_3_cross1'],
    'horizontal_1_right': ['horizontal_1_center3'],
    
    // 横通路2
    'horizontal_2_left': ['horizontal_2_center1'],
    'horizontal_2_center1': ['horizontal_2_left', 'horizontal_2_center2', 'vertical_1_cross2'],
    'horizontal_2_center2': ['horizontal_2_center1', 'horizontal_2_center3', 'vertical_2_cross2'],
    'horizontal_2_center3': ['horizontal_2_center2', 'horizontal_2_right', 'vertical_3_cross2'],
    'horizontal_2_right': ['horizontal_2_center3'],
    
    // 横通路3
    'horizontal_3_left': ['horizontal_3_center1'],
    'horizontal_3_center1': ['horizontal_3_left', 'horizontal_3_center2', 'vertical_1_cross3'],
    'horizontal_3_center2': ['horizontal_3_center1', 'horizontal_3_center3', 'vertical_2_cross3'],
    'horizontal_3_center3': ['horizontal_3_center2', 'horizontal_3_right', 'vertical_3_cross3'],
    'horizontal_3_right': ['horizontal_3_center3'],
    
    // 縦通路1
    'vertical_1_top': ['vertical_1_cross1'],
    'vertical_1_cross1': ['vertical_1_top', 'vertical_1_cross2', 'horizontal_1_center1'],
    'vertical_1_cross2': ['vertical_1_cross1', 'vertical_1_cross3', 'horizontal_2_center1'],
    'vertical_1_cross3': ['vertical_1_cross2', 'vertical_1_bottom', 'horizontal_3_center1'],
    'vertical_1_bottom': ['vertical_1_cross3'],
    
    // 縦通路2
    'vertical_2_top': ['vertical_2_cross1'],
    'vertical_2_cross1': ['vertical_2_top', 'vertical_2_cross2', 'horizontal_1_center2'],
    'vertical_2_cross2': ['vertical_2_cross1', 'vertical_2_cross3', 'horizontal_2_center2'],
    'vertical_2_cross3': ['vertical_2_cross2', 'vertical_2_bottom', 'horizontal_3_center2'],
    'vertical_2_bottom': ['vertical_2_cross3'],
    
    // 縦通路3
    'vertical_3_top': ['vertical_3_cross1'],
    'vertical_3_cross1': ['vertical_3_top', 'vertical_3_cross2', 'horizontal_1_center3'],
    'vertical_3_cross2': ['vertical_3_cross1', 'vertical_3_cross3', 'horizontal_2_center3'],
    'vertical_3_cross3': ['vertical_3_cross2', 'vertical_3_bottom', 'horizontal_3_center3'],
    'vertical_3_bottom': ['vertical_3_cross3'],
  };

  // ブースの位置情報（Firebaseから動的に取得）
  List<BeaconLocation> _beaconLocations = [];
  
  // マップレイアウト情報（Firebaseから動的に取得）
  Map<String, dynamic>? _eventLayout;
  List<Map<String, dynamic>> _mapElements = [];

  // ビーコン検出の制御用
  Map<String, DateTime> _lastRecordedTime = {};
  Map<String, Set<String>> _activeUsers = {}; // 各ビーコンで現在アクティブなユーザーを追跡
  Map<String, Map<String, DateTime>> _userLastRecordedTime = {}; // 各ユーザーの最後の記録時刻を追跡
  Set<String> _processingBeacons = {}; // 処理中のビーコンを追跡（重複処理を防ぐ）
  Map<String, DateTime> _lastProcessedTime = {}; // 各ビーコンの最後の処理時刻を追跡
  Set<String> _recentlyProcessedUserBeacon = {}; // 最近処理されたユーザー・ビーコンの組み合わせを追跡
  static const Duration _recordingInterval = Duration(minutes: 5); // 5分間隔で記録（長時間滞在の判定用）
  static const Duration _minProcessingInterval = Duration(seconds: 2); // 最小処理間隔（2秒）

  // スキャン状態の管理
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription; // スキャン結果のリスナー
  
  // 混雑監視用の状態変数
  Timer? _monitoringTimer;
  Map<String, bool> _crowdingAlerts = {};
  int _crowdingThreshold = 25;
  
  // タイムスタンプ更新用のタイマー
  Timer? _timestampUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadMapLayout(); // Firebaseからマップレイアウトを読み込み
    _loadBoothData(); // Firebaseからブース情報を読み込み
    _loadCrowdData();
    // 30秒ごとにデータを更新
    _startPeriodicUpdate();
    // 混雑監視を開始
    _startCrowdingMonitoring();
    // BLEスキャンを開始（非同期処理として実行）
    _startBleScan();
    // タイムスタンプ更新を開始（10秒ごと）
    _startTimestampUpdate();
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel(); // スキャン結果リスナーをクリア
    _monitoringTimer?.cancel();
    _timestampUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final userName = await _authService.getUserName();
      setState(() {
        _userName = userName;
      });
    } catch (e) {
      print('ユーザー名の読み込みエラー: $e');
    }
  }

  /// Firebaseからマップレイアウト情報を読み込む
  Future<void> _loadMapLayout() async {
    try {
      print('=== マップレイアウトの読み込み開始 ===');
      
      // アクティブな展示会レイアウトを取得
      final eventLayout = await _firebaseService.getActiveEventLayout();
      
      if (eventLayout == null) {
        print('アクティブな展示会レイアウトがありません（デフォルトレイアウトを使用）');
        setState(() {
          _eventLayout = null;
          _mapElements = [];
        });
        return;
      }
      
      print('展示会レイアウトを取得: ${eventLayout['eventName']}');
      
      // マップ要素を取得
      final mapElements = await _firebaseService.getMapElements(eventLayout['id']);
      print('マップ要素を取得: ${mapElements.length}件');
      
      setState(() {
        _eventLayout = eventLayout;
        _mapElements = mapElements;
      });
      
      print('=== マップレイアウトの読み込み完了 ===');
    } catch (e) {
      print('マップレイアウトの読み込み中にエラーが発生しました: $e');
      // エラーの場合はデフォルトのレイアウトを使用
      setState(() {
        _eventLayout = null;
        _mapElements = [];
      });
    }
  }

  Future<void> _loadCrowdData() async {
    try {
      print('=== 混雑データの読み込み開始 ===');
      final stats = await _firebaseService.getTodayStats();
      print('取得した統計データ: $stats');
      print('統計データの数: ${stats.length}');
      
      // 各ビーコンのデータをログ出力
      stats.forEach((key, value) {
        print('ビーコン: $key, データ: $value');
        if (value is Map<String, dynamic>) {
          print('  - count: ${value['count']}');
          print('  - deviceName: ${value['deviceName']}');
        }
      });
      
      setState(() {
        _todayStats = stats;
        _isLoading = false;
      });
      print('=== 混雑データの読み込み完了 ===');
    } catch (e) {
      print('混雑データの読み込み中にエラーが発生しました: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Firebaseからブース情報を読み込む
  Future<void> _loadBoothData() async {
    try {
      print('=== ブース情報の読み込み開始 ===');
      final booths = await _firebaseService.getAllBooths();
      print('取得したブース情報: ${booths.length}件');
      
      final List<BeaconLocation> beaconLocations = [];
      
      for (final booth in booths) {
        print('ブース情報を処理中: ${booth['id']}');
        print('  - displayName: ${booth['displayName']}');
        print('  - company: ${booth['company']}');
        print('  - description: ${booth['description']}');
        
        final boothType = _getBoothTypeFromString(booth['type'] ?? 'booth');
        
        // Firebaseのデータ構造に合わせてBoothDetailsを作成
        BoothDetails? boothDetails;
        if (booth['displayName'] != null || booth['company'] != null) {
          boothDetails = BoothDetails(
            displayName: booth['displayName'] ?? booth['name'] ?? '',
            company: booth['company'] ?? '出展企業',
            description: booth['description'] ?? '詳細情報は準備中です。',
            products: booth['products'] != null 
                ? List<String>.from(booth['products'])
                : ['準備中'],
            contactEmail: booth['contactEmail'] ?? 'info@example.com',
            website: booth['website'] ?? 'https://example.com',
            features: booth['features'] != null 
                ? List<String>.from(booth['features'])
                : ['準備中'],
          );
          print('  - BoothDetails作成完了: ${boothDetails.displayName}');
        } else {
          print('  - BoothDetailsなし');
        }
        
        final beaconLocation = BeaconLocation(
          booth['id'] ?? '',
          booth['x']?.toDouble() ?? 0.0,
          booth['y']?.toDouble() ?? 0.0,
          booth['name'] ?? '',
          boothType,
          boothDetails: boothDetails,
          width: booth['width']?.toDouble() ?? 30.0,
          height: booth['height']?.toDouble() ?? 30.0,
          shape: booth['shape'] ?? 'circle',
        );
        
        beaconLocations.add(beaconLocation);
        print('  - BeaconLocation追加完了: ${beaconLocation.id} (size: ${beaconLocation.width}x${beaconLocation.height}, shape: ${beaconLocation.shape})');
      }
      
      // 基本エリア（エントランス、休憩エリアなど）は教室レイアウトでは不要のためコメントアウト
      // beaconLocations.addAll([
      //   BeaconLocation('Entrance-Main', 100, 50, '正面エントランス', BeaconType.entrance),
      //   BeaconLocation('Entrance-Side', 600, 50, 'サイドエントランス', BeaconType.entrance),
      //   BeaconLocation('Rest-Area1', 150, 100, '休憩エリア1', BeaconType.restArea),
      //   BeaconLocation('Rest-Area2', 550, 300, '休憩エリア2', BeaconType.restArea),
      //   BeaconLocation('Food-Court', 50, 400, 'フードコート', BeaconType.foodCourt),
      //   BeaconLocation('Info-Desk', 350, 80, '総合案内', BeaconType.infoDesk),
      // ]);
      
      setState(() {
        _beaconLocations = beaconLocations;
      });
      
      print('=== ブース情報の読み込み完了 ===');
    } catch (e) {
      print('ブース情報の読み込み中にエラーが発生しました: $e');
      // エラーの場合はデフォルトのブース情報を使用
      _loadDefaultBoothData();
    }
  }

  /// デフォルトのブース情報を読み込む（フォールバック用）
  void _loadDefaultBoothData() {
    _beaconLocations = [
      BeaconLocation('FSC-BP104D', 80, 150, 'ブースA1 (FSC-BP104D)', BeaconType.booth),
      BeaconLocation('Booth-A2', 200, 150, 'ブースA2', BeaconType.booth),
      BeaconLocation('Booth-A3', 320, 150, 'ブースA3', BeaconType.booth),
      BeaconLocation('Booth-B1', 80, 250, 'ブースB1', BeaconType.booth),
      BeaconLocation('Booth-B2', 200, 250, 'ブースB2', BeaconType.booth),
      BeaconLocation('Booth-B3', 320, 250, 'ブースB3', BeaconType.booth),
      BeaconLocation('Booth-C1', 80, 350, 'ブースC1', BeaconType.booth),
      BeaconLocation('Booth-C2', 200, 350, 'ブースC2', BeaconType.booth),
      BeaconLocation('Booth-C3', 320, 350, 'ブースC3', BeaconType.booth),
      BeaconLocation('Entrance-Main', 100, 50, '正面エントランス', BeaconType.entrance),
      BeaconLocation('Entrance-Side', 600, 50, 'サイドエントランス', BeaconType.entrance),
      BeaconLocation('Rest-Area1', 150, 100, '休憩エリア1', BeaconType.restArea),
      BeaconLocation('Rest-Area2', 550, 300, '休憩エリア2', BeaconType.restArea),
      BeaconLocation('Food-Court', 50, 400, 'フードコート', BeaconType.foodCourt),
      BeaconLocation('Info-Desk', 350, 80, '総合案内', BeaconType.infoDesk),
    ];
  }

  /// 文字列からBeaconTypeを取得
  BeaconType _getBoothTypeFromString(String type) {
    switch (type) {
      case 'entrance':
        return BeaconType.entrance;
      case 'booth':
        return BeaconType.booth;
      case 'restArea':
        return BeaconType.restArea;
      case 'foodCourt':
        return BeaconType.foodCourt;
      case 'infoDesk':
        return BeaconType.infoDesk;
      default:
        return BeaconType.booth;
    }
  }

  void _startPeriodicUpdate() {
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        _loadCrowdData();
        _startPeriodicUpdate();
      }
    });
  }

  // 検出中のビーコンのタイムスタンプを定期的に更新（10秒ごと）
  void _startTimestampUpdate() {
    _timestampUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final now = DateTime.now();
      final userId = _authService.currentUserId;
      
      if (userId == null) {
        return;
      }
      
      // 現在検出中のビーコン（15秒以内に検出されたもの）のタイムスタンプを更新
      for (final entry in _detectedBeacons.entries) {
        final beaconName = entry.key;
        final detectionInfo = entry.value;
        
        // 15秒以内に検出されたビーコンのみタイムスタンプを更新
        if (now.difference(detectionInfo.detectionTime) <= const Duration(seconds: 15) && _isRelevantBeacon(beaconName)) {
          print('タイムスタンプ更新: $beaconName (ユーザー: $userId)');
          // 専用メソッドでタイムスタンプのみを更新（カウントは増やさない）
          await _firebaseService.updateVisitorTimestamp(beaconName, userId, eventType: 'visit');
        }
      }
    });
  }

  Future<void> _startBleScan() async {
    print('=== BLEスキャンを開始 ===');
    
    // 既存のリスナーをクリア
    _scanSubscription?.cancel();
    _scanSubscription = null;
    
    // スキャンを開始
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    print('スキャン開始: 5秒間');

    // スキャン結果をリスン（単一のリスナーで継続）
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      print('スキャン結果を受信: ${results.length}件');
      
      final now = DateTime.now();
      bool dataUpdated = false;
      
      // 現在のスキャンで検出されたビーコンを記録
      final Set<String> currentlyDetectedBeacons = {};

      for (ScanResult r in results) {
        final beaconName = r.advertisementData.advName;
        final rssi = r.rssi;
        
        if (beaconName != null && beaconName.isNotEmpty) {
          // ビーコンの物理名をブースIDに変換
          final boothId = _firebaseService.getBoothIdFromBeaconName(beaconName);
          
          print('ビーコン検出: $beaconName (RSSI: $rssi dBm) → $boothId');
          
          // RSSI閾値チェック: 閾値以下は除外（ブースから遠すぎる）
          if (rssi < kRssiThreshold) {
            print('  ⚠️ RSSI値が閾値以下のため無視: $rssi < $kRssiThreshold dBm');
            
            // 既に検出済みのビーコンが閾値以下になった場合、即座に削除
            if (_detectedBeacons.containsKey(boothId)) {
              _detectedBeacons.remove(boothId);
              print('  🗑️ ビーコン $boothId を即座に削除（RSSI閾値以下）');
              dataUpdated = true;
            }
            
            continue;
          }
          
          print('  ✅ RSSI OK → ブースID: $boothId');
          
          // 現在のスキャンで検出されたビーコンとして記録
          currentlyDetectedBeacons.add(boothId);
          
          // 検出時刻とRSSI値を更新（ブースIDで記録）
          final wasExisting = _detectedBeacons.containsKey(boothId);
          _detectedBeacons[boothId] = BeaconDetectionInfo(
            detectionTime: now,
            rssi: rssi,
          );
          
          if (wasExisting) {
            print('既存のビーコン $boothId を再検出しました（RSSI: $rssi dBm）');
          } else {
            print('新しいビーコン $boothId を検出しました（RSSI: $rssi dBm）');
          }

          // FSC-BP104Dや他の実際のビーコンを検出した場合のみカウント
          final name = boothId;  // 以降の処理でnameとして使用
          if (_isRelevantBeacon(name)) {
            print('関連ビーコンを検出: $name');
            
            if (_processingBeacons.contains(name)) {
              print('ビーコン $name は既に処理中です。スキップします。');
              continue;
            }
            
            final userId = _authService.currentUserId;
            if (userId == null) {
              print('ユーザーIDが取得できませんでした');
              continue;
            }
            
            // 最近処理されたビーコンの場合はスキップ（2秒以内）
            final lastProcessed = _lastProcessedTime[name];
            if (lastProcessed != null && now.difference(lastProcessed) < const Duration(seconds: 2)) {
              final remainingSeconds = 2 - now.difference(lastProcessed).inSeconds;
              print('ビーコン $name は最近処理されました。次回処理まで: ${remainingSeconds}秒');
              continue;
            }
            
            // ユーザー・ビーコンの組み合わせでの重複チェック（5秒以内）
            final userBeaconKey = '${userId}_$name';
            if (_recentlyProcessedUserBeacon.contains(userBeaconKey)) {
              final remainingSeconds = 5 - now.difference(lastProcessed ?? now).inSeconds;
              print('ユーザー $userId のビーコン $name は最近処理されました。次回処理まで: ${remainingSeconds}秒');
              continue;
            }
            
            _processingBeacons.add(name);
            print('ビーコン $name の処理を開始します');
            
            try {
              // 🚀 新規追加: 同じユーザーが別のビーコンにいた場合、そこから削除
              for (final otherBeacon in _activeUsers.keys.toList()) {
                if (otherBeacon != name && _activeUsers[otherBeacon]!.contains(userId)) {
                  _activeUsers[otherBeacon]!.remove(userId);
                  print('🔄 ユーザー $userId を $otherBeacon から削除（$name に移動）');
                  dataUpdated = true;
                  
                  // 空になったらビーコンごと削除
                  if (_activeUsers[otherBeacon]!.isEmpty) {
                    _activeUsers.remove(otherBeacon);
                    _userLastRecordedTime.remove(otherBeacon);
                  }
                }
              }
              
              _activeUsers.putIfAbsent(name, () => <String>{});
              final isNewUser = !_activeUsers[name]!.contains(userId);
              
              if (isNewUser) {
                print('=== 新しいユーザーがビーコンを検出: $name (ユーザー: $userId) ===');
                print('Firebaseにカウントと来場者属性を保存中...');
                
                // Firebaseにカウントと来場者属性を保存
                _firebaseService.incrementBeaconCount(name, userId: userId, eventType: 'visit');
                
                _activeUsers[name]!.add(userId);
                _lastRecordedTime[name] = now;
                // 初回検出時に長時間滞在の基準時刻を保存
                _userLastRecordedTime.putIfAbsent(name, () => <String, DateTime>{});
                _userLastRecordedTime[name]![userId] = now;
                dataUpdated = true;
                print('ビーコン $name に新しいユーザー $userId を追加しました');
              } else {
                // 既存ユーザーの場合、再訪問として記録しない（重複記録を防ぐ）
                print('ビーコン $name でユーザー $userId は既にアクティブです（重複記録をスキップ）');
                
                // ただし、長時間滞在の場合は記録（5分間隔）
                _userLastRecordedTime.putIfAbsent(name, () => <String, DateTime>{});
                final userLastRecorded = _userLastRecordedTime[name]![userId];
                
                if (userLastRecorded != null && now.difference(userLastRecorded) >= _recordingInterval) {
                  print('=== 長時間滞在の記録: $name (ユーザー: $userId) ===');
                  print('前回記録時刻: $userLastRecorded, 経過時間: ${now.difference(userLastRecorded).inSeconds}秒');
                  print('Firebaseに長時間滞在データを保存中...');
                  
                  // Firebaseに長時間滞在データを保存
                  _firebaseService.incrementBeaconCount(name, userId: userId, eventType: 'long_stay');
                  
                  _userLastRecordedTime[name]![userId] = now;
                  dataUpdated = true;
                  print('ビーコン $name でユーザー $userId の長時間滞在を記録しました');
                } else if (userLastRecorded != null) {
                  final remainingTime = _recordingInterval - now.difference(userLastRecorded);
                  print('ビーコン $name でユーザー $userId は既にアクティブです（次回長時間滞在記録まで: ${remainingTime.inMinutes}分${remainingTime.inSeconds % 60}秒）');
                }
              }
            } finally {
              _processingBeacons.remove(name);
              _lastProcessedTime[name] = now;
              
              final userBeaconKey = '${userId}_$name';
              _recentlyProcessedUserBeacon.add(userBeaconKey);
              Future.delayed(const Duration(seconds: 5), () {
                _recentlyProcessedUserBeacon.remove(userBeaconKey);
              });
              print('ビーコン $name の処理が完了しました');
            }
          } else {
            print('ビーコン $name は関連ビーコンではありません（スキップ）');
          }
        }
      }
      
      // 🚀 新規追加: 現在のスキャンに含まれていないビーコンを削除
      // スキャン間隔（5秒）+ 余裕（1秒）= 6秒以内に検出されていないビーコンを削除
      final beaconsToRemove = <String>[];
      for (final entry in _detectedBeacons.entries) {
        final boothId = entry.key;
        final detectionInfo = entry.value;
        
        // 現在のスキャンに含まれていない && 6秒以上検出されていない
        if (!currentlyDetectedBeacons.contains(boothId) && 
            now.difference(detectionInfo.detectionTime).inSeconds > 6) {
          // 関連ビーコンの場合は、アクティブユーザーがいる場合は保持
          if (_isRelevantBeacon(boothId) && _activeUsers.containsKey(boothId) && _activeUsers[boothId]!.isNotEmpty) {
            print('📍 ビーコン $boothId は検出されていませんが、アクティブユーザーがいるため保持');
            continue;
          }
          
          beaconsToRemove.add(boothId);
          print('🚀 ビーコン $boothId を即座に削除（スキャンに含まれず、${now.difference(detectionInfo.detectionTime).inSeconds}秒間未検出）');
        }
      }
      
      // 削除実行（アクティブユーザーもクリア）
      for (final boothId in beaconsToRemove) {
        _detectedBeacons.remove(boothId);
        
        // このビーコンのアクティブユーザーもクリア
        if (_activeUsers.containsKey(boothId)) {
          final userCount = _activeUsers[boothId]!.length;
          _activeUsers.remove(boothId);
          _userLastRecordedTime.remove(boothId);
          print('  → アクティブユーザーをクリア（${userCount}人）');
        }
        
        dataUpdated = true;
      }
      
      // 8秒以上前に検出されたビーコンを削除（ただし関連ビーコンの場合は保持）
      // タイムラグ短縮: 20秒→8秒（スキャン間隔5秒 + バッファ3秒）
      _detectedBeacons.removeWhere((key, detectionInfo) {
        if (now.difference(detectionInfo.detectionTime).inSeconds > 8) {
          // 関連ビーコンの場合は、アクティブユーザーがいる場合は保持
          if (_isRelevantBeacon(key) && _activeUsers.containsKey(key) && _activeUsers[key]!.isNotEmpty) {
            print('関連ビーコン $key はアクティブユーザーがいるため保持します');
            return false;
          }
          print('🗑️ ビーコン $key を削除（検出から${now.difference(detectionInfo.detectionTime).inSeconds}秒経過）');
          return true;
        }
        return false;
      });
      
      // デバッグ用：現在の検出状態をログ出力
      if (_detectedBeacons.isNotEmpty) {
        print('=== 現在検出中のビーコン ===');
        for (final entry in _detectedBeacons.entries) {
          final beaconName = entry.key;
          final detectionInfo = entry.value;
          final isRelevant = _isRelevantBeacon(beaconName);
          final activeUsers = _activeUsers[beaconName]?.length ?? 0;
          print('  $beaconName: 最後の検出=${detectionInfo.detectionTime.toString()}, RSSI=${detectionInfo.rssi} dBm, 関連ビーコン=$isRelevant, アクティブユーザー=$activeUsers人');
        }
      } else {
        print('=== 現在検出中のビーコンはありません ===');
      }
      
      // 長時間検出されていないビーコンのアクティブユーザーをクリア
      // タイムラグ短縮: 25秒→10秒
      _activeUsers.removeWhere((beaconName, users) {
        final detectionInfo = _detectedBeacons[beaconName];
        if (detectionInfo == null || now.difference(detectionInfo.detectionTime).inSeconds > 10) {
          print('ビーコン $beaconName からアクティブユーザーをクリアしました（${users.length}人）');
          
          // このビーコンのユーザー別記録時刻もクリア
          _userLastRecordedTime.remove(beaconName);
          
          return true; // このビーコンのアクティブユーザーを削除
        }
        return false;
      });
      
      // 現在検出中のビーコンに基づいてブース情報を更新
      _updateNearbyBoothFromBLE();
      
      if (dataUpdated) {
        // 新しいデータが追加された場合、統計を更新
        _loadCrowdData();
      }

      setState(() {});
    });

    // ビーコンの離脱状態を定期的にチェック
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final now = DateTime.now();
      final disconnectedBeacons = <String>[];
      
      // 30秒以上検出されていないビーコンを離脱として判定
      for (final beaconName in _detectedBeacons.keys) {
        final detectionInfo = _detectedBeacons[beaconName];
        if (detectionInfo != null && now.difference(detectionInfo.detectionTime).inSeconds > 30) {
          disconnectedBeacons.add(beaconName);
          print('ビーコン $beaconName が離脱しました（最後の検出: ${detectionInfo.detectionTime.toString()}, RSSI: ${detectionInfo.rssi} dBm）');
        }
      }
      
      // 離脱したビーコンの状態をクリア（再検出を可能にする）
      for (final beaconName in disconnectedBeacons) {
        _detectedBeacons.remove(beaconName);
        
        // このビーコンのアクティブユーザーもクリア
        if (_activeUsers.containsKey(beaconName)) {
          final userCount = _activeUsers[beaconName]!.length;
          print('離脱したビーコン $beaconName のアクティブユーザー ${userCount}人 をクリアしました');
          _activeUsers.remove(beaconName);
          _userLastRecordedTime.remove(beaconName);
        }
        
        // 処理中のフラグはクリア（再検出を可能にする）
        _processingBeacons.remove(beaconName);
        _lastProcessedTime.remove(beaconName);
        
        // 最近処理されたユーザー・ビーコンの組み合わせもクリア（再検出を確実にする）
        _recentlyProcessedUserBeacon.removeWhere((key) => key.endsWith('_$beaconName'));
        
        print('ビーコン $beaconName の状態を完全にクリアしました（再検出準備完了）');
      }
      
      if (disconnectedBeacons.isNotEmpty) {
        setState(() {});
      }
      
      // デバッグ用：現在の検出状態をログ出力
      if (_detectedBeacons.isNotEmpty) {
        print('=== 現在検出中のビーコン ===');
        for (final entry in _detectedBeacons.entries) {
          final beaconName = entry.key;
          final detectionInfo = entry.value;
          final isRelevant = _isRelevantBeacon(beaconName);
          final activeUsers = _activeUsers[beaconName]?.length ?? 0;
          print('  $beaconName: 最後の検出=${detectionInfo.detectionTime.toString()}, RSSI=${detectionInfo.rssi} dBm, 関連ビーコン=$isRelevant, アクティブユーザー=$activeUsers人');
        }
      }
    });

    // スキャンを継続的に実行（リスナーは維持）
    Timer.periodic(const Duration(seconds: 7), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      print('スキャンを継続実行中...');
      
      // スキャンが停止している場合は再開
      if (!_isScanning) {
        print('スキャンが停止しているため再開します');
        FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      }
    });
  }

  bool _isRelevantBeacon(String beaconName) {
    // 実際のビーコンまたは設定されたビーコンIDかチェック
    final relevantBeacons = _beaconLocations.map((b) => b.id).toSet();
    return relevantBeacons.contains(beaconName);
  }

  // 混雑度に基づく色を取得
  Color _getCrowdColor(int count) {
    if (count == 0) return Colors.blue.shade100; // 空いている
    if (count <= 5) return Colors.green.shade300; // やや空いている
    if (count <= 15) return Colors.yellow.shade400; // 普通
    if (count <= 30) return Colors.orange.shade500; // やや混雑
    return Colors.red.shade600; // 混雑
  }

  // 混雑度のテキストを取得
  String _getCrowdText(int count) {
    if (count == 0) return '空いています';
    if (count <= 5) return 'やや空いています';
    if (count <= 15) return '適度な混雑';
    if (count <= 30) return 'やや混雑';
    return '混雑中';
  }

  /// 検出中のBLEビーコンに基づいてブース情報を更新
  /// RSSI値が最も強い（最も近い）ビーコンを優先表示
  void _updateNearbyBoothFromBLE() {
    BeaconLocation? nearestBooth;
    int? strongestRssi;
    
    // 現在検出中のビーコンの中で、RSSI値が最も強いブースを探す
    for (final entry in _detectedBeacons.entries) {
      final beaconName = entry.key;
      final detectionInfo = entry.value;
      final rssi = detectionInfo.rssi;
      
      // このビーコンに対応するブースを探す
      for (final beacon in _beaconLocations) {
        if (beacon.id == beaconName && 
            beacon.type == BeaconType.booth && 
            beacon.boothDetails != null) {
          // RSSI値が最も強い（値が大きい = より近い）ブースを選択
          if (strongestRssi == null || rssi > strongestRssi) {
            nearestBooth = beacon;
            strongestRssi = rssi;
            print('📶 最も強いビーコン更新: $beaconName (RSSI: $rssi dBm)');
          }
          break;
        }
      }
    }
    
    // 状態を更新
    setState(() {
      _nearbyBooth = nearestBooth;
      _showBoothOverlay = nearestBooth != null;
    });
  }

  /// ブース詳細情報ダイアログを表示
  Future<void> _showBoothDetailsDialog(BeaconLocation booth) async {
    final today = DateTime.now();
    final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    
    try {
      final visitorDetails = await _firebaseService.getBeaconVisitorDetails(booth.id, dateString);
      
      // 現在のユーザーIDを取得
      final userId = _authService.currentUserId;
      
      // 予約状態をチェック（FSC-BP104Dの場合のみ）
      bool isReserved = false;
      if (booth.id == 'FSC-BP104D' && userId != null) {
        isReserved = await _firebaseService.checkReservation(userId, booth.id);
      }
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.store, color: Colors.blue.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        booth.boothDetails?.displayName ?? booth.name,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ブース基本情報
                        if (booth.boothDetails != null) ...[
                          _buildInfoSection(
                            '出展企業',
                            booth.boothDetails!.company,
                            Icons.business,
                            Colors.blue.shade600,
                          ),
                          const Divider(height: 24),
                          
                          _buildInfoSection(
                            '説明',
                            booth.boothDetails!.description,
                            Icons.description,
                            Colors.green.shade600,
                          ),
                          const Divider(height: 24),
                          
                          // 特徴・アピールポイント
                          if (booth.boothDetails!.features.isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(Icons.star, color: Colors.orange.shade600, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  '特徴・アピールポイント',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...booth.boothDetails!.features.asMap().entries.map((entry) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${entry.key + 1}. ', 
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        entry.value,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const Divider(height: 24),
                          ],
                          
                          // 製品・サービス
                          if (booth.boothDetails!.products.isNotEmpty && 
                              booth.boothDetails!.products.first != '準備中') ...[
                            Row(
                              children: [
                                Icon(Icons.inventory_2, color: Colors.purple.shade600, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  '製品・サービス',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...booth.boothDetails!.products.map((product) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.chevron_right, 
                                      color: Colors.purple.shade600, 
                                      size: 16,
                                    ),
                                    Expanded(
                                      child: Text(
                                        product,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const Divider(height: 24),
                          ],
                          
                          // 連絡先情報
                          if (booth.boothDetails!.contactEmail != 'info@example.com') ...[
                            Row(
                              children: [
                                Icon(Icons.email, color: Colors.teal.shade600, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'お問い合わせ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const SizedBox(width: 28),
                                Expanded(
                                  child: Text(
                                    booth.boothDetails!.contactEmail,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.blue.shade700,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                          ],
                        ],
                        
                        // ブース予約ボタン（FSC-BP104Dのみ）
                        if (booth.id == 'FSC-BP104D' && userId != null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: isReserved ? null : () async {
                                // 予約処理
                                final success = await _firebaseService.saveBoothReservation(userId, booth.id);
                                if (success) {
                                  setState(() {
                                    isReserved = true;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text('ブースの予約が完了しました！'),
                                        backgroundColor: Colors.green,
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                } else {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('予約に失敗しました'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: Icon(isReserved ? Icons.check_circle : Icons.event_available),
                              label: Text(isReserved ? '予約済み' : 'ブース予約'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isReserved ? Colors.grey : Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const Divider(height: 24),
                        ],
                        
                        // 来場者統計
                        Row(
                          children: [
                            Icon(Icons.people, color: Colors.indigo.shade600, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '総来場者数: ${_todayStats[booth.id]?['count'] ?? 0}人',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // 来場者属性
                        if (visitorDetails.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(left: 28),
                            child: Text(
                              '来場者の詳細データはありません',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          )
                        else ...[
                          const Padding(
                            padding: EdgeInsets.only(left: 28),
                            child: Text(
                              '来場者属性:',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 200,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: visitorDetails.length,
                              itemBuilder: (context, index) {
                                final visitor = visitorDetails[index];
                                final timestamp = visitor['timestamp'];
                                final timeStr = timestamp != null 
                                    ? (timestamp is Timestamp 
                                        ? timestamp.toDate().toString().substring(11, 16)
                                        : timestamp.toString())
                                    : '不明';
                                
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 1,
                                  child: Padding(
                                    padding: const EdgeInsets.all(10.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                                            const SizedBox(width: 4),
                                            Text(
                                              '来場時刻: $timeStr',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text('年齢: ${visitor['age'] ?? '不明'}歳、性別: ${visitor['gender'] ?? '不明'}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text('職業: ${visitor['job'] ?? '不明'}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text('情報源: ${visitor['eventSource'] ?? '不明'}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        if (visitor['interests'] != null)
                                          Text('興味分野: ${visitor['interests'].join(', ')}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('閉じる'),
                  ),
                ],
              );
            }
          );
        },
      );
    } catch (e) {
      print('ブース詳細の取得中にエラーが発生しました: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ブース詳細の取得に失敗しました: $e')),
      );
    }
  }
  
  /// 情報セクションを構築するヘルパーメソッド
  Widget _buildInfoSection(String title, String content, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            content,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  /// ルート提案ダイアログを表示
  Future<void> _showRouteSuggestionDialog() async {
    // 空いているブースをリストアップ（混雑度が低い順）
    final availableBooths = _beaconLocations
        .where((b) => b.type == BeaconType.booth)
        .toList()
        ..sort((a, b) {
          final countA = _todayStats[a.id]?['count'] ?? 0;
          final countB = _todayStats[b.id]?['count'] ?? 0;
          return countA.compareTo(countB);
        });
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.route, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              const Text('推奨ルート', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '混雑状況から空いているブースへのルートを提案します',
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                const Text(
                  '訪問したいブースを選択してください:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 300,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableBooths.length,
                    itemBuilder: (context, index) {
                      final booth = availableBooths[index];
                      final count = _todayStats[booth.id]?['count'] ?? 0;
                      final crowdColor = _getCrowdColor(count);
                      final crowdText = _getCrowdText(count);
                      final hasDetails = booth.boothDetails != null;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: crowdColor,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            hasDetails 
                                ? booth.boothDetails!.displayName 
                                : booth.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (hasDetails)
                                Text(
                                  booth.boothDetails!.company,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              Text(
                                '$crowdText ($count人)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: crowdColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showRouteToBooths([booth]);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // 上位3つの空いているブースへの周遊ルートを提案
                if (availableBooths.length >= 3) {
                  _showRouteToBooths(availableBooths.take(3).toList());
                }
              },
              child: const Text('空いている3ブースを周遊'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }
  
  /// 指定されたブースへのルートを表示
  void _showRouteToBooths(List<BeaconLocation> targetBooths) {
    if (targetBooths.isEmpty) return;
    
    // 現在地を決定：検出中のビーコンがあればそれを使用、なければエントランス
    BeaconLocation? startBooth;
    
    // 検出中のビーコンの中からブースまたはエリアを探す
    if (_detectedBeacons.isNotEmpty) {
      for (final beaconName in _detectedBeacons.keys) {
        final detectedBooth = _beaconLocations.firstWhere(
          (b) => b.id == beaconName,
          orElse: () => _beaconLocations.first,
        );
        if (detectedBooth.id == beaconName) {
          startBooth = detectedBooth;
          print('現在地として検出中のビーコンを使用: ${startBooth.name}');
          break;
        }
      }
    }
    
    // 検出中のビーコンがない場合はエントランスを使用
    if (startBooth == null) {
      startBooth = _beaconLocations.firstWhere(
        (b) => b.type == BeaconType.entrance,
        orElse: () => _beaconLocations.first,
      );
      print('現在地としてエントランスを使用: ${startBooth.name}');
    }
    
    // ルートを計算（通路のパスファインディングを使用）
    final routeBeacons = [startBooth, ...targetBooths];
    final routePath = _calculateRoutePath(routeBeacons);
    
    setState(() {
      _showingRoute = true;
      _currentRoute = routeBeacons;
      _currentPath = routePath;
    });
    
    // スナックバーで通知
    final startLocationName = startBooth.boothDetails?.displayName ?? startBooth.name;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$startLocationNameから${targetBooths.length}箇所へのルートを表示しました'),
        action: SnackBarAction(
          label: 'クリア',
          onPressed: () {
            setState(() {
              _showingRoute = false;
              _currentRoute = [];
              _currentPath = [];
            });
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }
  
  /// 通路に沿ったルートパスを計算
  List<Offset> _calculateRoutePath(List<BeaconLocation> beacons) {
    if (beacons.length < 2) return [];
    
    final path = <Offset>[];
    
    for (int i = 0; i < beacons.length - 1; i++) {
      final start = beacons[i];
      final end = beacons[i + 1];
      
      // 各ビーコン間のパスを計算
      final segmentPath = _findPathBetweenBeacons(start, end);
      
      // 最初のセグメント以外は、最初の点を除外（重複を避けるため）
      if (i > 0 && segmentPath.isNotEmpty) {
        path.addAll(segmentPath.skip(1));
      } else {
        path.addAll(segmentPath);
      }
    }
    
    return path;
  }
  
  /// 2つのビーコン間のパスを探索（A*アルゴリズム）
  List<Offset> _findPathBetweenBeacons(BeaconLocation start, BeaconLocation end) {
    final startPos = Offset(start.x, start.y);
    final endPos = Offset(end.x, end.y);
    
    // 開始位置と終了位置に最も近い通路ノードを見つける
    PathNode? startNode;
    PathNode? endNode;
    double minStartDist = double.infinity;
    double minEndDist = double.infinity;
    
    for (final node in _pathNodes) {
      final startDist = (node.position - startPos).distance;
      if (startDist < minStartDist) {
        minStartDist = startDist;
        startNode = node;
      }
      
      final endDist = (node.position - endPos).distance;
      if (endDist < minEndDist) {
        minEndDist = endDist;
        endNode = node;
      }
    }
    
    if (startNode == null || endNode == null) {
      // フォールバック: 直線パス
      return [startPos, endPos];
    }
    
    // A*アルゴリズムでパスを探索
    final openSet = <PathNode>[startNode];
    final cameFrom = <String, PathNode>{};
    final gScore = <String, double>{startNode.id: 0};
    final fScore = <String, double>{
      startNode.id: startNode.distanceTo(endNode),
    };
    
    while (openSet.isNotEmpty) {
      // fScoreが最小のノードを選択
      openSet.sort((a, b) {
        final aScore = fScore[a.id] ?? double.infinity;
        final bScore = fScore[b.id] ?? double.infinity;
        return aScore.compareTo(bScore);
      });
      
      final current = openSet.removeAt(0);
      
      // ゴールに到達
      if (current.id == endNode.id) {
        return _reconstructPath(cameFrom, current, startPos, endPos);
      }
      
      // 隣接ノードを探索
      final neighbors = _pathConnections[current.id] ?? [];
      for (final neighborId in neighbors) {
        final neighbor = _pathNodes.firstWhere((n) => n.id == neighborId);
        final tentativeGScore = (gScore[current.id] ?? double.infinity) + 
                                current.distanceTo(neighbor);
        
        if (tentativeGScore < (gScore[neighbor.id] ?? double.infinity)) {
          cameFrom[neighbor.id] = current;
          gScore[neighbor.id] = tentativeGScore;
          fScore[neighbor.id] = tentativeGScore + neighbor.distanceTo(endNode);
          
          if (!openSet.contains(neighbor)) {
            openSet.add(neighbor);
          }
        }
      }
    }
    
    // パスが見つからない場合は直線パス
    return [startPos, endPos];
  }
  
  /// パスを再構築
  List<Offset> _reconstructPath(
    Map<String, PathNode> cameFrom,
    PathNode current,
    Offset startPos,
    Offset endPos,
  ) {
    final path = <Offset>[current.position];
    var currentNode = current;
    
    while (cameFrom.containsKey(currentNode.id)) {
      currentNode = cameFrom[currentNode.id]!;
      path.insert(0, currentNode.position);
    }
    
    // 開始位置と終了位置を追加
    path.insert(0, startPos);
    path.add(endPos);
    
    return path;
  }

  /// 混雑監視を開始
  void _startCrowdingMonitoring() {
    // 30秒ごとに混雑度をチェック
    _monitoringTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _checkCrowdingLevels();
      }
    });
  }

  /// 混雑度をチェック
  void _checkCrowdingLevels() {
    final newAlerts = <String, bool>{};
    
    for (final beacon in _beaconLocations) {
      if (beacon.type == BeaconType.booth) {
        final count = _todayStats[beacon.id]?['count'] ?? 0;
        final isCrowded = count >= _crowdingThreshold;
        
        newAlerts[beacon.id] = isCrowded;
        
        // 新しく混雑になった場合、ログを出力
        if (isCrowded && !(_crowdingAlerts[beacon.id] ?? false)) {
          print('ブース ${beacon.name} が混雑しています（${count}人）');
        }
      }
    }
    
    setState(() {
      _crowdingAlerts = newAlerts;
    });
  }

  /// ブースの来場者属性詳細を表示
  Future<void> _showBeaconDetails(BeaconLocation beacon) async {
    final today = DateTime.now();
    final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    
    try {
      final visitorDetails = await _firebaseService.getBeaconVisitorDetails(beacon.id, dateString);
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(beacon.name),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('総来場者数: ${_todayStats[beacon.id]?['count'] ?? 0}人'),
                  const SizedBox(height: 16),
                  if (visitorDetails.isEmpty)
                    const Text('来場者の詳細データはありません')
                  else ...[
                    const Text('来場者属性:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: visitorDetails.length,
                        itemBuilder: (context, index) {
                          final visitor = visitorDetails[index];
                          final timestamp = visitor['timestamp'];
                          final timeStr = timestamp != null 
                              ? (timestamp is Timestamp 
                                  ? timestamp.toDate().toString().substring(11, 16)
                                  : timestamp.toString())
                              : '不明';
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('来場時刻: $timeStr', style: const TextStyle(fontSize: 12)),
                                  Text('年齢: ${visitor['age'] ?? '不明'}歳、性別: ${visitor['gender'] ?? '不明'}'),
                                  Text('職業: ${visitor['job'] ?? '不明'}'),
                                  Text('情報源: ${visitor['eventSource'] ?? '不明'}'),
                                  if (visitor['interests'] != null)
                                    Text('興味分野: ${visitor['interests'].join(', ')}'),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildVisitorAnalysis(visitorDetails),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('詳細データの取得に失敗しました: $e')),
      );
    }
  }

  /// 来場者分析サマリーを作成
  Widget _buildVisitorAnalysis(List<Map<String, dynamic>> visitors) {
    if (visitors.isEmpty) return const SizedBox();

    // 年代分析
    final ageGroups = <String, int>{};
    final genderCount = <String, int>{};
    final jobCount = <String, int>{};
    final sourceCount = <String, int>{};

    for (final visitor in visitors) {
      // 年代グループ化
      final age = visitor['age'] ?? 0;
      final ageGroup = age < 20 ? '10代' : age < 30 ? '20代' : age < 40 ? '30代' : age < 50 ? '40代' : age < 60 ? '50代' : '60代以上';
      ageGroups[ageGroup] = (ageGroups[ageGroup] ?? 0) + 1;
      
      // 性別集計
      final gender = visitor['gender'] ?? '不明';
      genderCount[gender] = (genderCount[gender] ?? 0) + 1;
      
      // 職業集計
      final job = visitor['job'] ?? '不明';
      jobCount[job] = (jobCount[job] ?? 0) + 1;
      
      // 情報源集計
      final source = visitor['eventSource'] ?? '不明';
      sourceCount[source] = (sourceCount[source] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('属性分析', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildAnalysisSection('年代別', ageGroups),
        _buildAnalysisSection('性別', genderCount),
        _buildAnalysisSection('職業別', jobCount),
        _buildAnalysisSection('情報源別', sourceCount),
      ],
    );
  }

  Widget _buildAnalysisSection(String title, Map<String, int> data) {
    if (data.isEmpty) return const SizedBox();
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title:', style: const TextStyle(fontWeight: FontWeight.w500)),
          ...data.entries.map((entry) => 
            Text('  ${entry.key}: ${entry.value}人', style: const TextStyle(fontSize: 12))
          ),
        ],
      ),
    );
  }

  Future<void> _generateTestData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      await _firebaseService.generateTestCrowdData();
      await _loadCrowdData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('テストデータを生成しました！'),
            backgroundColor: Colors.green,
          ),
        );
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
    }
  }

  Future<void> _clearTestData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      await _firebaseService.clearTestData();
      await _loadCrowdData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('テストデータをクリアしました！'),
            backgroundColor: Colors.orange,
          ),
        );
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
    }
  }

  Future<void> _debugFirebaseData() async {
    try {
      await _firebaseService.debugAllDates();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firebaseデバッグ情報をコンソールに出力しました'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('デバッグ実行中にエラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadSpecificDate() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 2025-08-05のデータを直接取得
      final specificData = await _firebaseService.getStatsForDate('2025-08-05');
      
      setState(() {
        _todayStats = specificData;
        _isLoading = false;
      });

      // 強制的にヒートマップを再描画
      print('=== setState完了、ヒートマップ再描画 ===');
      print('設定された_todayStats: $_todayStats');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('2025-08-05のデータを取得しました: ${specificData.length}件'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('特定日付データ取得中にエラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ブース情報をFirebaseに初期化
  Future<void> _initializeBoothData() async {
    try {
      print('=== ブース情報の初期化開始 ===');
      await _firebaseService.initializeBoothData();
      print('=== ブース情報の初期化完了 ===');
      
      // 初期化後、ブース情報を再読み込み
      await _loadBoothData();
      
      // 成功メッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ブース情報の初期化が完了しました！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('ブース情報の初期化中にエラーが発生しました: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ブース情報の初期化に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// マップレイアウトをFirebaseに初期化
  Future<void> _initializeMapLayout() async {
    try {
      print('=== マップレイアウトの初期化開始 ===');
      await _firebaseService.initializeMapLayout();
      print('=== マップレイアウトの初期化完了 ===');
      
      // 初期化後、マップレイアウトを再読み込み
      await _loadMapLayout();
      
      // 成功メッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('マップレイアウトの初期化が完了しました！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('マップレイアウトの初期化中にエラーが発生しました: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('マップレイアウトの初期化に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ブースサイズを初期化
  Future<void> _initializeBoothSizes() async {
    try {
      print('=== ブースサイズの初期化開始 ===');
      await _firebaseService.initializeBoothSizes();
      print('=== ブースサイズの初期化完了 ===');
      
      // 初期化後、ブースデータを再読み込み
      await _loadBoothData();
      
      // 成功メッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ブースサイズの初期化が完了しました！すべてのブースにデフォルトサイズが設定されました。'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('ブースサイズの初期化中にエラーが発生しました: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ブースサイズの初期化に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// カスタムブースサイズを設定
  Future<void> _setCustomBoothSizes() async {
    try {
      print('=== カスタムブースサイズの設定開始 ===');
      await _firebaseService.setCustomBoothSizes();
      print('=== カスタムブースサイズの設定完了 ===');
      
      // 設定後、ブースデータを再読み込み
      await _loadBoothData();
      
      // 成功メッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('カスタムブースサイズの設定が完了しました！ブースごとに異なるサイズが設定されました。'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('カスタムブースサイズの設定中にエラーが発生しました: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('カスタムブースサイズの設定に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 教室レイアウトに変更
  Future<void> _initializeClassroom() async {
    try {
      print('=== 教室レイアウトへの変更開始 ===');
      await _firebaseService.initializeClassroomLayout();
      print('=== 教室レイアウトへの変更完了 ===');
      
      // 変更後、マップレイアウトとブースデータを再読み込み
      await _loadMapLayout();
      await _loadBoothData();
      
      // 成功メッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('教室レイアウトへの変更が完了しました！マップサイズ: 950x850、FSC-BP104DをブースA09に配置しました。'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('教室レイアウトへの変更中にエラーが発生しました: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('教室レイアウトへの変更に失敗しました: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 教室ブース座標を設定
  Future<void> _setupClassroomBooths() async {
    try {
      print('=== 教室ブース座標の設定開始 ===');
      await _firebaseService.setupClassroomBooths();
      print('=== 教室ブース座標の設定完了 ===');
      
      // 設定後、ブースデータを再読み込み
      await _loadBoothData();
      
      // 成功メッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('教室ブース座標の設定が完了しました！15個のブースを教室レイアウトに配置しました。'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('教室ブース座標の設定中にエラーが発生しました: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('教室ブース座標の設定に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        title: const Text('会場混雑状況'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.route, color: Colors.white),
            onPressed: _showRouteSuggestionDialog,
            tooltip: 'ルート提案',
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'generate') {
                await _generateTestData();
              } else if (value == 'clear') {
                await _clearTestData();
              } else if (value == 'refresh') {
                await _loadCrowdData();
              } else if (value == 'debug') {
                await _debugFirebaseData();
              } else if (value == 'load_specific') {
                await _loadSpecificDate();
              } else if (value == 'init_booths') {
                await _initializeBoothData();
              } else if (value == 'init_map_layout') {
                await _initializeMapLayout();
              } else if (value == 'init_booth_sizes') {
                await _initializeBoothSizes();
              } else if (value == 'set_custom_booth_sizes') {
                await _setCustomBoothSizes();
              } else if (value == 'init_classroom') {
                await _initializeClassroom();
              } else if (value == 'setup_classroom_booths') {
                await _setupClassroomBooths();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'generate',
                child: Row(
                  children: [
                    Icon(Icons.data_usage),
                    SizedBox(width: 8),
                    Text('テストデータ生成'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all),
                    SizedBox(width: 8),
                    Text('テストデータクリア'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('データ更新'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'debug',
                child: Row(
                  children: [
                    Icon(Icons.bug_report),
                    SizedBox(width: 8),
                    Text('Firebaseデバッグ'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'load_specific',
                child: Row(
                  children: [
                    Icon(Icons.calendar_today),
                    SizedBox(width: 8),
                    Text('2025-08-05データ取得'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'init_booths',
                child: Row(
                  children: [
                    Icon(Icons.store),
                    SizedBox(width: 8),
                    Text('ブース情報初期化'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'init_map_layout',
                child: Row(
                  children: [
                    Icon(Icons.map),
                    SizedBox(width: 8),
                    Text('マップレイアウト初期化'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'init_booth_sizes',
                child: Row(
                  children: [
                    Icon(Icons.aspect_ratio),
                    SizedBox(width: 8),
                    Text('ブースサイズ初期化'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'set_custom_booth_sizes',
                child: Row(
                  children: [
                    Icon(Icons.auto_fix_high),
                    SizedBox(width: 8),
                    Text('カスタムブースサイズ設定'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'init_classroom',
                child: Row(
                  children: [
                    Icon(Icons.school),
                    SizedBox(width: 8),
                    Text('教室レイアウトに変更'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'setup_classroom_booths',
                child: Row(
                  children: [
                    Icon(Icons.table_chart),
                    SizedBox(width: 8),
                    Text('教室ブース座標設定'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ユーザー情報
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.person, color: Colors.green.shade700, size: 32),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ようこそ、$_userName さん',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                '会場の混雑状況をリアルタイムで確認できます',
                                style: TextStyle(fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // 凡例
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '混雑度の見方',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildLegendItem(Colors.blue.shade100, '空いている'),
                              _buildLegendItem(Colors.green.shade300, 'やや空き'),
                              _buildLegendItem(Colors.yellow.shade400, '適度'),
                              _buildLegendItem(Colors.orange.shade500, 'やや混雑'),
                              _buildLegendItem(Colors.red.shade600, '混雑'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // 会場マップ
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                '会場マップ - リアルタイム混雑状況',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              if (_detectedBeacons.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.bluetooth, 
                                           color: Colors.green.shade700, 
                                           size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        'ビーコン検出中',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.bluetooth_searching, 
                                           color: Colors.grey.shade600, 
                                           size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        'ビーコン検索中',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 680,  // 固定の高さを設定
                            width: double.infinity,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: InteractiveViewer(
                                boundaryMargin: const EdgeInsets.all(20),  // スクロール可能に
                                minScale: 0.8,
                                maxScale: 3.0,
                                constrained: false,  // スクロール可能に変更
                                child: SizedBox(
                                  width: _eventLayout?['mapWidth']?.toDouble() ?? 380, // 動的に幅を設定
                                  height: _eventLayout?['mapHeight']?.toDouble() ?? 650, // 動的に高さを設定
                                  child: Stack(
                                    children: [
                                      GestureDetector(
                                        onTapDown: (TapDownDetails details) {
                                          final RenderBox renderBox = context.findRenderObject() as RenderBox;
                                          final localPosition = renderBox.globalToLocal(details.globalPosition);
                                          
                                          // タップされた位置に近いビーコンを探す（従来の機能）
                                          for (final beacon in _beaconLocations) {
                                            final distance = (localPosition - Offset(beacon.x, beacon.y)).distance;
                                            if (distance < 30) { // 30px以内
                                              _showBeaconDetails(beacon);
                                              break;
                                            }
                                          }
                                        },
                                        child: CustomPaint(
                                          key: ValueKey('${_todayStats.hashCode}_${_activeUsers.hashCode}'), // 強制再描画用のKey（activeUsersの変更も反映）
                                          painter: VenuePainter(
                                            _beaconLocations, 
                                            _todayStats, 
                                            showRoute: _showingRoute,
                                            routeBeacons: _currentRoute,
                                            routePath: _currentPath,
                                            mapElements: _mapElements,
                                            activeUsers: _activeUsers, // リアルタイムのアクティブユーザー数を渡す
                                          ),
                                          size: Size(
                                            _eventLayout?['mapWidth']?.toDouble() ?? 380, // 動的に幅を設定
                                            _eventLayout?['mapHeight']?.toDouble() ?? 650, // 動的に高さを設定
                                          ),
                                        ),
                                      ),
                                
                                // ブース名オーバーレイ
                                if (_showBoothOverlay && _nearbyBooth != null)
                                  Positioned(
                                    left: _nearbyBooth!.x - 100,
                                    top: _nearbyBooth!.y - 80,
                                    child: GestureDetector(
                                      onTap: () => _showBoothDetailsDialog(_nearbyBooth!),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.blue.shade600,
                                              Colors.blue.shade800,
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _nearbyBooth!.boothDetails?.displayName ?? _nearbyBooth!.name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.touch_app,
                                                  color: Colors.white70,
                                                  size: 12,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'タップして詳細を見る',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // 詳細統計
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'エリア別詳細情報',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          ..._beaconLocations.map((beacon) {
                            final count = _todayStats[beacon.id]?['count'] ?? 0;
                            final hasDetails = beacon.boothDetails != null;
                            final displayName = hasDetails 
                                ? beacon.boothDetails!.displayName 
                                : beacon.name;
                            final companyName = hasDetails 
                                ? beacon.boothDetails!.company 
                                : _getCrowdText(count);
                            
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getCrowdColor(count),
                                child: Icon(
                                  hasDetails ? Icons.business : _getBeaconIcon(beacon.type),
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: TextStyle(
                                        fontWeight: hasDetails ? FontWeight.bold : FontWeight.normal,
                                        color: hasDetails ? Colors.blue.shade800 : Colors.black,
                                      ),
                                    ),
                                  ),
                                  if (hasDetails)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade600,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        '詳細あり',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(companyName),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getCrowdColor(count),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$count人',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    hasDetails ? Icons.info : Icons.chevron_right,
                                    color: hasDetails ? Colors.blue.shade600 : Colors.grey,
                                  ),
                                ],
                              ),
                              onTap: () {
                                print('ブースタップ: ${beacon.id}');
                                print('  - hasDetails: $hasDetails');
                                print('  - boothDetails: ${beacon.boothDetails}');
                                if (hasDetails) {
                                  _showBoothDetailsDialog(beacon);
                                } else {
                                  _showBeaconDetails(beacon);
                                }
                              },
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // リアルタイム検出状況
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.bluetooth_searching, color: Colors.blue.shade600),
                              const SizedBox(width: 8),
                              const Text(
                                'リアルタイム検出中のビーコン',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_detectedBeacons.isEmpty)
                            const Text(
                              '現在検出中のビーコンはありません',
                              style: TextStyle(color: Colors.grey),
                            )
                          else
                            ..._detectedBeacons.entries.map((entry) {
                              final beaconName = entry.key;
                              final isRelevant = _isRelevantBeacon(beaconName);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.bluetooth,
                                      color: isRelevant ? Colors.green : Colors.grey,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        beaconName,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isRelevant ? Colors.black : Colors.grey,
                                          fontWeight: isRelevant ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (isRelevant)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          '記録中',
                                          style: TextStyle(color: Colors.white, fontSize: 10),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Column(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  IconData _getBeaconIcon(BeaconType type) {
    switch (type) {
      case BeaconType.entrance:
        return Icons.door_front_door;
      case BeaconType.booth:
        return Icons.store;
      case BeaconType.restArea:
        return Icons.chair;
      case BeaconType.foodCourt:
        return Icons.restaurant;
      case BeaconType.infoDesk:
        return Icons.info;
    }
  }

  /// 現在のユーザーの訪問者データを取得
  Future<Map<String, dynamic>?> _getCurrentVisitorData(String userId) async {
    try {
      // テストユーザーデータから該当するユーザーを検索
      final testUsersData = await _loadTestUsers();
      for (final user in testUsersData) {
        if (user['userId'] == userId) {
          return {
            'age': user['age'],
            'gender': user['gender'],
            'job': user['job'],
            'eventSource': user['eventSource'] ?? 'BLE_Detection',
            'interests': user['interests'] ?? ['一般'],
          };
        }
      }
      
      // テストユーザーに該当しない場合は基本的なデータを返す
      print('テストユーザーに該当しないユーザー: $userId');
      return {
        'age': 25,
        'gender': '未設定',
        'job': '一般',
        'eventSource': 'BLE_Detection',
        'interests': ['一般'],
      };
    } catch (e) {
      print('訪問者データの取得中にエラーが発生しました: $e');
      // エラーの場合は基本的なデータを返す
      return {
        'age': 25,
        'gender': '未設定',
        'job': '一般',
        'eventSource': 'BLE_Detection',
        'interests': ['一般'],
      };
    }
  }

  /// テストユーザーデータを読み込む
  Future<List<Map<String, dynamic>>> _loadTestUsers() async {
    try {
      // テストユーザーデータを読み込む
      final testUsersData = await _firebaseService.getTestUsers();
      print('テストユーザーデータを読み込みました: ${testUsersData.length}件');
      return testUsersData;
    } catch (e) {
      print('テストユーザーデータの読み込み中にエラーが発生しました: $e');
      // エラーの場合は空のリストを返す
      return [];
    }
  }

}

// パスファインディング用のノードクラス
class PathNode {
  final double x;
  final double y;
  final String id;

  PathNode(this.x, this.y, this.id);
  
  Offset get position => Offset(x, y);
  
  double distanceTo(PathNode other) {
    return (position - other.position).distance;
  }
}

// ビーコンの位置情報を管理するクラス
class BeaconLocation {
  final String id;
  final double x;
  final double y;
  final String name;
  final BeaconType type;
  final BoothDetails? boothDetails; // ブース詳細情報
  final double width;  // ブースの幅（デフォルト: 30）
  final double height; // ブースの高さ（デフォルト: 30）
  final String shape;  // ブースの形状（"circle", "rect", "square"）

  BeaconLocation(
    this.id, 
    this.x, 
    this.y, 
    this.name, 
    this.type, {
    this.boothDetails,
    this.width = 30.0,
    this.height = 30.0,
    this.shape = 'circle',
  });
}

// ブースの詳細情報クラス
class BoothDetails {
  final String displayName;        // 表示用ブース名
  final String company;           // 会社名
  final String description;       // 説明
  final List<String> products;    // 製品・サービス一覧
  final String contactEmail;     // 連絡先メール
  final String website;          // ウェブサイト
  final List<String> features;   // 特徴・アピールポイント

  BoothDetails({
    required this.displayName,
    required this.company,
    required this.description,
    required this.products,
    required this.contactEmail,
    required this.website,
    required this.features,
  });
}

enum BeaconType {
  entrance,
  booth,
  restArea,
  foodCourt,
  infoDesk,
}

// 会場レイアウトとヒートマップを描画するカスタムペインター
class VenuePainter extends CustomPainter {
  final List<BeaconLocation> beacons;
  final Map<String, dynamic> crowdData;
  final bool showRoute;
  final List<BeaconLocation> routeBeacons;
  final List<Offset> routePath; // 通路に沿った実際の経路
  final List<Map<String, dynamic>> mapElements; // マップ要素（Firebaseから取得）
  final Map<String, Set<String>> activeUsers; // リアルタイムのアクティブユーザー

  VenuePainter(
    this.beacons, 
    this.crowdData, {
    this.showRoute = false,
    this.routeBeacons = const [],
    this.routePath = const [],
    this.mapElements = const [],
    this.activeUsers = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    
    // マップ要素がある場合は動的に描画、ない場合はデフォルトのハードコードされたレイアウトを使用
    if (mapElements.isNotEmpty) {
      // Firebaseから取得したマップ要素を描画
      _drawMapElementsFromFirebase(canvas, size, paint);
    } else {
      // デフォルトのハードコードされたレイアウトを描画
      _drawDefaultLayout(canvas, size, paint);
    }
    
    // ビーコンと混雑状況を描画
    for (final beacon in beacons) {
      final beaconData = crowdData[beacon.id];
      
      // 🚀 リアルタイムのアクティブユーザー数を使用
      // Firebaseの累積カウントではなく、現在検出中のユーザー数を表示
      int count = activeUsers[beacon.id]?.length ?? 0;

      final crowdColor = _getCrowdColor(count);
      
      // 混雑度に応じたヒートマップ効果を描画
      _drawCrowdHeatmap(canvas, beacon, count, crowdColor, paint);
      
      // ビーコンアイコンを形状とサイズに応じて描画
      _drawBeaconIcon(canvas, beacon, crowdColor, paint);
      
      // ビーコン名を描画
      final textPainter = TextPainter(
        text: TextSpan(
          text: beacon.name,
          style: TextStyle(
            color: Colors.black87,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      
      // テキストの位置を形状に応じて調整
      final textYOffset = beacon.shape == 'rect' 
          ? beacon.height / 2 + 5
          : beacon.shape == 'square'
              ? beacon.width / 2 + 5
              : 20.0;
      
      textPainter.paint(
        canvas,
        Offset(beacon.x - textPainter.width / 2, beacon.y + textYOffset),
      );
      
      // 人数を描画
      final countPainter = TextPainter(
        text: TextSpan(
          text: '$count',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      countPainter.layout();
      
      final textOffset = Offset(beacon.x - countPainter.width / 2, beacon.y - 6);
      countPainter.paint(canvas, textOffset);
    }
    
    // ルート表示
    if (showRoute && routeBeacons.isNotEmpty) {
      _drawRoute(canvas, size);
    }
  }



  /// 推奨ルートを描画（通路に沿った経路）
  void _drawRoute(Canvas canvas, Size size) {
    if (routePath.length < 2 || routeBeacons.isEmpty) return;
    
    // まず通路のハイライトを描画（背景）
    _drawPathHighlight(canvas);
    
    // メインルート線を描画（前景）
    _drawMainRouteLine(canvas);
    
    // 矢印を描画（通路の途中のポイントに）
    _drawRouteArrows(canvas);
    
    // ルート番号を描画（ビーコンの位置に）
    for (int i = 0; i < routeBeacons.length; i++) {
      final beacon = routeBeacons[i];
      _drawRouteNumber(canvas, beacon, i + 1);
    }
  }

  /// メインルート線を描画（より目立つスタイル）
  void _drawMainRouteLine(Canvas canvas) {
    if (routePath.length < 2) return;
    
    // 外側の白いアウトライン
    final outlinePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    
    // 内側のメインルート線
    final mainPaint = Paint()
      ..color = Colors.red.shade600  // より目立つ赤色に変更
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    
    final path = Path();
    path.moveTo(routePath.first.dx, routePath.first.dy);
    
    for (int i = 1; i < routePath.length; i++) {
      path.lineTo(routePath[i].dx, routePath[i].dy);
    }
    
    // 先にアウトラインを描画
    canvas.drawPath(path, outlinePaint);
    // その後メインライン描画
    canvas.drawPath(path, mainPaint);
  }

  /// 通路経路のハイライトを描画（より薄く）
  void _drawPathHighlight(Canvas canvas) {
    if (routePath.length < 2) return;
    
    final paint = Paint()
      ..color = Colors.blue.shade200.withOpacity(0.3)  // より薄いハイライト
      ..strokeWidth = 12  // 幅は少し広げて背景感を出す
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    // 通路のハイライトを描画
    for (int i = 0; i < routePath.length - 1; i++) {
      canvas.drawLine(routePath[i], routePath[i + 1], paint);
    }
  }

  /// 通路経路に矢印を描画（より目立つ）
  void _drawRouteArrows(Canvas canvas) {
    if (routePath.length < 2) return;
    
    // 経路の一定間隔で矢印を描画
    const arrowInterval = 80.0; // 間隔を少し広げる
    
    for (int i = 0; i < routePath.length - 1; i++) {
      final start = routePath[i];
      final end = routePath[i + 1];
      final segmentDistance = (end - start).distance;
      
      // セグメント内で矢印を配置
      int arrowCount = math.max(1, (segmentDistance / arrowInterval).floor());
      for (int j = 1; j <= arrowCount; j++) {
        final t = j / (arrowCount + 1);
        final arrowPos = start + (end - start) * t;
        final direction = end - start;
        
        if (direction.distance > 30) { // より長いセグメントのみに描画
          _drawPathArrow(canvas, arrowPos, direction);
        }
      }
    }
  }

  /// 通路上の矢印を描画（より大きく、目立つ）
  void _drawPathArrow(Canvas canvas, Offset position, Offset direction) {
    final angle = math.atan2(direction.dy, direction.dx);
    const arrowSize = 12.0; // サイズを大きく
    
    // 矢印の影（アウトライン）
    final shadowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    // メインの矢印
    final mainPaint = Paint()
      ..color = Colors.red.shade700  // メインルートと同じ色系統
      ..style = PaintingStyle.fill;
    
    // 矢印の頂点を計算
    final arrowPoint1 = Offset(
      position.dx - arrowSize * math.cos(angle - math.pi / 6),
      position.dy - arrowSize * math.sin(angle - math.pi / 6),
    );
    
    final arrowPoint2 = Offset(
      position.dx - arrowSize * math.cos(angle + math.pi / 6),
      position.dy - arrowSize * math.sin(angle + math.pi / 6),
    );
    
    // 矢印のパスを作成
    final arrowPath = Path();
    arrowPath.moveTo(position.dx, position.dy);
    arrowPath.lineTo(arrowPoint1.dx, arrowPoint1.dy);
    arrowPath.lineTo(arrowPoint2.dx, arrowPoint2.dy);
    arrowPath.close();
    
    // 影を少し大きめに描画（アウトライン効果）
    final shadowPath = Path();
    const shadowOffset = 1.5;
    shadowPath.moveTo(position.dx, position.dy);
    shadowPath.lineTo(
      arrowPoint1.dx - shadowOffset, 
      arrowPoint1.dy - shadowOffset,
    );
    shadowPath.lineTo(
      arrowPoint2.dx - shadowOffset, 
      arrowPoint2.dy + shadowOffset,
    );
    shadowPath.close();
    
    // 先に影を描画
    canvas.drawPath(shadowPath, shadowPaint);
    // その後メイン矢印を描画
    canvas.drawPath(arrowPath, mainPaint);
  }



  /// ルート番号を描画（より目立つ）
  void _drawRouteNumber(Canvas canvas, BeaconLocation beacon, int number) {
    final position = Offset(beacon.x - 30, beacon.y - 30);
    const radius = 16.0; // サイズを大きく
    
    // 外側の白い縁（アウトライン）
    final outlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    // 内側のメイン色
    final mainPaint = Paint()
      ..color = Colors.red.shade600  // ルートと同じ色系統
      ..style = PaintingStyle.fill;
    
    // 影効果用
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    // 影を描画（少し下にずらして）
    canvas.drawCircle(Offset(position.dx + 2, position.dy + 2), radius, shadowPaint);
    
    // 外側の白い円を描画
    canvas.drawCircle(position, radius, outlinePaint);
    
    // 内側のメインカラー円を描画
    canvas.drawCircle(position, radius - 2, mainPaint);
    
    // 番号のテキストを描画
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,  // フォントサイズを大きく
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              offset: Offset(1, 1),
              blurRadius: 2,
              color: Colors.black26,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(position.dx - textPainter.width / 2, position.dy - textPainter.height / 2),
    );
  }

  /// Firebaseから取得したマップ要素を描画
  void _drawMapElementsFromFirebase(Canvas canvas, Size size, Paint paint) {
    for (final element in mapElements) {
      final type = element['type'] as String?;
      final shape = element['shape'] as String? ?? 'rect';
      final x = (element['x'] as num?)?.toDouble() ?? 0.0;
      final y = (element['y'] as num?)?.toDouble() ?? 0.0;
      final width = (element['width'] as num?)?.toDouble() ?? 0.0;
      final height = (element['height'] as num?)?.toDouble() ?? 0.0;
      final colorHex = element['color'] as String? ?? '#EEEEEE';
      final filled = element['filled'] as bool? ?? true;
      final strokeWidth = (element['strokeWidth'] as num?)?.toDouble() ?? 1.0;
      
      // 16進数カラーをColorオブジェクトに変換
      final color = _parseColor(colorHex);
      
      paint.color = color;
      paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
      paint.strokeWidth = strokeWidth;
      
      // 図形の種類に応じて描画
      if (shape == 'rect') {
        canvas.drawRect(Rect.fromLTWH(x, y, width, height), paint);
      } else if (shape == 'circle') {
        final radius = width / 2;
        canvas.drawCircle(Offset(x + radius, y + radius), radius, paint);
      }
    }
  }

  /// デフォルトのハードコードされたレイアウトを描画
  void _drawDefaultLayout(Canvas canvas, Size size, Paint paint) {
    // 背景を描画
    paint.color = Colors.grey.shade50;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    
    // 会場の外枠を描画
    paint.color = Colors.grey.shade400;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(20, 20, size.width - 40, size.height - 40), paint);
    
    // エントランスを描画
    paint.color = Colors.brown.shade300;
    paint.style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(80, 20, 40, 20), paint); // 正面エントランス
    canvas.drawRect(Rect.fromLTWH(580, 20, 40, 20), paint); // サイドエントランス
    
    // 通路を描画
    paint.color = Colors.grey.shade200;
    // 横通路
    canvas.drawRect(Rect.fromLTWH(20, 80, 660, 30), paint);
    canvas.drawRect(Rect.fromLTWH(20, 200, 660, 30), paint);
    canvas.drawRect(Rect.fromLTWH(20, 320, 660, 30), paint);
    // 縦通路
    canvas.drawRect(Rect.fromLTWH(140, 20, 30, size.height - 40), paint);
    canvas.drawRect(Rect.fromLTWH(240, 20, 30, size.height - 40), paint);
    canvas.drawRect(Rect.fromLTWH(540, 20, 30, size.height - 40), paint);
  }

  /// 16進数カラー文字列をColorオブジェクトに変換
  Color _parseColor(String colorHex) {
    try {
      // "#RRGGBB" 形式を "0xFFRRGGBB" 形式に変換
      String hexColor = colorHex.replaceAll('#', '');
      if (hexColor.length == 6) {
        hexColor = 'FF$hexColor';
      }
      return Color(int.parse(hexColor, radix: 16));
    } catch (e) {
      // パースエラーの場合はグレーを返す
      return Colors.grey.shade200;
    }
  }

  Color _getCrowdColor(int count) {
    if (count == 0) return Colors.blue.shade100;
    if (count <= 5) return Colors.green.shade300;
    if (count <= 15) return Colors.yellow.shade400;
    if (count <= 30) return Colors.orange.shade500;
    return Colors.red.shade600;
  }

  /// 混雑度に応じたヒートマップ効果を描画
  void _drawCrowdHeatmap(Canvas canvas, BeaconLocation beacon, int count, Color crowdColor, Paint paint) {
    // 混雑度に応じた半径を計算
    final baseRadius = beacon.shape == 'circle' 
        ? beacon.width / 2
        : math.max(beacon.width, beacon.height) / 2;
    
    final radius = math.max(baseRadius + 5, math.min(50.0, count.toDouble() * 2 + baseRadius));
    
    // グラデーション効果のために複数の円を描画
    for (int i = 3; i >= 1; i--) {
      paint.color = crowdColor.withOpacity(0.1 * i);
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(beacon.x, beacon.y),
        radius * i / 3,
        paint,
      );
    }
  }

  /// ビーコンアイコンを形状とサイズに応じて描画
  void _drawBeaconIcon(Canvas canvas, BeaconLocation beacon, Color crowdColor, Paint paint) {
    final centerX = beacon.x;
    final centerY = beacon.y;
    
    if (beacon.shape == 'circle') {
      // 円形のブース
      final radius = beacon.width / 2;
      
      // 塗りつぶし
      paint.color = Colors.white;
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, centerY), radius, paint);
      
      // 枠線
      paint.color = crowdColor;
      paint.strokeWidth = 2;
      paint.style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(centerX, centerY), radius, paint);
      
    } else if (beacon.shape == 'rect') {
      // 長方形のブース
      final rect = Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: beacon.width,
        height: beacon.height,
      );
      
      // 塗りつぶし
      paint.color = Colors.white;
      paint.style = PaintingStyle.fill;
      canvas.drawRect(rect, paint);
      
      // 枠線
      paint.color = crowdColor;
      paint.strokeWidth = 2;
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(rect, paint);
      
    } else if (beacon.shape == 'square') {
      // 正方形のブース
      final size = beacon.width;
      final rect = Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: size,
        height: size,
      );
      
      // 塗りつぶし
      paint.color = Colors.white;
      paint.style = PaintingStyle.fill;
      canvas.drawRect(rect, paint);
      
      // 枠線
      paint.color = crowdColor;
      paint.strokeWidth = 2;
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
} 