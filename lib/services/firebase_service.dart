import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'package:intl/intl.dart'; // DateFormatを追加

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // ユーザーが同じビーコンに短時間でアクセスしたかどうかを記録するマップ
  final Map<String, DateTime> _lastProcessedUserBeacon = {};

  /// BLEビーコン受信時にカウントと来場者属性をFirebaseに保存
  Future<void> incrementBeaconCount(String deviceName, {String? userId, String eventType = 'visit'}) async {
    try {
      final now = DateTime.now();
      final dateString = DateFormat('yyyy-MM-dd').format(now);
      print('=== incrementBeaconCount開始: $deviceName (ユーザー: $userId) ===');
      print('日付: $dateString, 時刻: ${now.toString()}');
      
      // 重複チェック: 同じユーザーが同じビーコンに短時間でアクセスしていないかチェック
      if (userId != null) {
        final userBeaconKey = '${userId}_$deviceName';
        final lastProcessedTime = _lastProcessedUserBeacon[userBeaconKey];
        
        if (lastProcessedTime != null && now.difference(lastProcessedTime) < const Duration(seconds: 5)) {
          print('重複防止: ユーザー $userId のビーコン $deviceName は最近処理されました。スキップします。');
          print('前回処理時刻: $lastProcessedTime, 経過時間: ${now.difference(lastProcessedTime).inSeconds}秒');
          return;
        }
        
        // 処理時刻を記録
        _lastProcessedUserBeacon[userBeaconKey] = now;
        print('重複防止: ユーザー $userId のビーコン $deviceName の処理時刻を記録しました');
      }
      
      // 来場者の属性情報を取得
      Map<String, dynamic>? visitorData;
      if (userId != null) {
        visitorData = await getVisitorData(userId);
        print('来場者属性データ: $visitorData');
      }
      
      // デバイス名と日付でドキュメントを参照
      final docRef = _firestore
          .collection('beacon_counts')
          .doc(dateString)
          .collection('devices')
          .doc(deviceName);

      // トランザクションを使用してカウントを安全にインクリメント
      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        
        // 来場者の記録データを準備
        Map<String, dynamic>? visitorRecord;
        if (userId != null) {
          // visitorDataがnullでも、基本的な訪問者情報は記録する
          if (visitorData != null) {
            visitorRecord = {
              'userId': userId,
              'timestamp': Timestamp.now(),
              'microsecondsSinceEpoch': DateTime.now().microsecondsSinceEpoch, // 一意性を確保
              'eventType': eventType,
              'age': visitorData['age'],
              'gender': visitorData['gender'],
              'job': visitorData['job'],
              'eventSource': visitorData['eventSource'],
              'interests': visitorData['interests'],
            };
          } else {
            // visitorDataがnullの場合の基本的な記録
            visitorRecord = {
              'userId': userId,
              'timestamp': Timestamp.now(),
              'microsecondsSinceEpoch': DateTime.now().microsecondsSinceEpoch, // 一意性を確保
              'eventSource': 'BLE_Detection',
              'eventType': eventType,
              'detectedAt': now.toString(),
            };
            print('visitorDataがnullのため、基本的な訪問者情報を作成: $visitorRecord');
          }
        }
        
        if (doc.exists) {
          // 既存のドキュメントがある場合はカウントをインクリメント
          final currentCount = doc.data()?['count'] ?? 0;
          final existingFirstSeen = doc.data()?['firstSeen']; // 既存のfirstSeenを保持
          print('既存のドキュメントを更新: 現在のカウント = $currentCount, 既存のfirstSeen = $existingFirstSeen');
          
          // 既存のvisitors配列を取得
          final rawVisitors = doc.data()?['visitors'];
          print('生のvisitorsデータ: $rawVisitors (型: ${rawVisitors.runtimeType})');
          
          final existingVisitors = <Map<String, dynamic>>[];
          if (rawVisitors != null && rawVisitors is List) {
            for (final visitor in rawVisitors) {
              if (visitor is Map<String, dynamic>) {
                existingVisitors.add(visitor);
              }
            }
          }
          print('処理後の既存visitors: ${existingVisitors.length}件');
          
          // 新しい訪問者データを追加
          if (visitorRecord != null) {
            existingVisitors.add(visitorRecord);
            print('新しい訪問者を追加: ${visitorRecord['userId']}');
            print('更新後のvisitors総数: ${existingVisitors.length}件');
          }
          
          // long_stayの場合はcountをインクリメントしない
          final newCount = visitorRecord?['eventType'] == 'long_stay' ? currentCount : currentCount + 1;
          
          final updateData = {
            'count': newCount,
            'firstSeen': existingFirstSeen, // 既存のfirstSeenを保持
            'lastSeen': FieldValue.serverTimestamp(),
            'deviceName': deviceName,
            'visitors': existingVisitors, // 更新された配列を設定
          };
          
          transaction.update(docRef, updateData);
          print('新しいカウント: $newCount, 訪問者数: ${existingVisitors.length}, firstSeen保持: $existingFirstSeen');
        } else {
          // 新しいドキュメントを作成
          print('新しいドキュメントを作成');
          
          // long_stayの場合はcountを1にしない
          final initialCount = visitorRecord?['eventType'] == 'long_stay' ? 0 : 1;
          
          final newDocData = {
            'count': initialCount,
            'firstSeen': FieldValue.serverTimestamp(),
            'lastSeen': FieldValue.serverTimestamp(),
            'deviceName': deviceName,
            'visitors': visitorRecord != null ? [visitorRecord] : [],
          };
          
          transaction.set(docRef, newDocData);
          print('初期カウント: $initialCount');
        }
      });

      print('=== Firebase保存完了: $deviceName ===');
    } catch (e) {
      print('Firebaseへの保存中にエラーが発生しました: $e');
    }
  }

  /// テストユーザーデータを取得
  Future<List<Map<String, dynamic>>> getTestUsers() async {
    try {
      print('=== getTestUsers開始 ===');
      
      // テストユーザーコレクションからデータを取得
      final querySnapshot = await _firestore.collection('test_users').get();
      
      final testUsers = <Map<String, dynamic>>[];
      for (final doc in querySnapshot.docs) {
        final userData = doc.data();
        testUsers.add(userData);
        print('テストユーザー: ${userData['userId']} - ${userData['name']}');
      }
      
      print('=== getTestUsers完了: ${testUsers.length}件 ===');
      return testUsers;
    } catch (e) {
      print('テストユーザーデータの取得中にエラーが発生しました: $e');
      // エラーの場合はデフォルトのテストユーザーを返す
      return [
        {
          'userId': 'visitor_1755849847010',
          'name': 'テストユーザー1',
          'age': 25,
          'gender': '男性',
          'job': '会社員',
          'eventSource': 'Web',
          'interests': ['テクノロジー'],
        },
        {
          'userId': 'visitor_1755849847011',
          'name': 'テストユーザー2',
          'age': 30,
          'gender': '女性',
          'job': 'エンジニア',
          'eventSource': 'Web',
          'interests': ['ビジネス'],
        },
      ];
    }
  }

  /// 指定した日付のビーコン受信統計を取得
  Future<Map<String, dynamic>> getBeaconStats(String dateString) async {
    try {
      print('=== getBeaconStats開始: $dateString ===');
      final querySnapshot = await _firestore
          .collection('beacon_counts')
          .doc(dateString)
          .collection('devices')
          .get();

      print('取得されたドキュメント数: ${querySnapshot.docs.length}');
      
      final stats = <String, dynamic>{};
      for (final doc in querySnapshot.docs) {
        final rawData = doc.data();
        print('ドキュメントID: ${doc.id}, 生データ: $rawData');
        
        // Timestampやその他のFirebase特有の型を安全な形式に変換
        final cleanData = <String, dynamic>{
          'count': rawData['count'] ?? 0,
          'deviceName': rawData['deviceName'] ?? doc.id,
          'firstSeen': rawData['firstSeen']?.toString() ?? '',
          'lastSeen': rawData['lastSeen']?.toString() ?? '',
        };
        
        print('変換後データ: $cleanData');
        stats[doc.id] = cleanData;
      }
      
      print('=== getBeaconStats完了: stats = $stats ===');
      return stats;
    } catch (e) {
      print('統計データの取得中にエラーが発生しました: $e');
      return {};
    }
  }

  /// 最新のビーコン受信統計を取得（日付に関係なく最新データを取得）
  Future<Map<String, dynamic>> getTodayStats() async {
    try {
      print('=== 最新データの検索開始 ===');
      
      // まず今日の日付でチェック
      final today = DateTime.now();
      final todayString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      print('今日の日付でチェック: $todayString');
      
      Map<String, dynamic> result = await getBeaconStats(todayString);
      
      // 今日のデータがない場合、最新のデータを検索
      if (result.isEmpty) {
        print('今日のデータがないため、最新データを検索中...');
        result = await getLatestStats();
      }
      
      print('=== 最終取得結果: $result ===');
      return result;
    } catch (e) {
      print('最新データ取得中にエラー: $e');
      return {};
    }
  }

  /// 最新のビーコンデータを取得（過去7日間から検索）
  Future<Map<String, dynamic>> getLatestStats() async {
    try {
      print('=== 過去7日間の最新データを検索 ===');
      
      final today = DateTime.now();
      Map<String, dynamic> latestData = {};
      
      // 過去7日間を検索
      for (int i = 0; i < 7; i++) {
        final checkDate = today.subtract(Duration(days: i));
        final dateString = '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
        
        print('検索中の日付: $dateString');
        final dayData = await getBeaconStats(dateString);
        
        if (dayData.isNotEmpty) {
          print('データが見つかりました: $dateString (${dayData.length}件)');
          
          // 複数日のデータをマージ（最新の値を優先）
          dayData.forEach((key, value) {
            if (!latestData.containsKey(key) || 
                (value['lastSeen'] != null && latestData[key]['lastSeen'] != null &&
                 value['lastSeen'].compareTo(latestData[key]['lastSeen']) > 0)) {
              latestData[key] = value;
            }
          });
        }
      }
      
      print('=== 最新データの検索完了: ${latestData.length}件 ===');
      return latestData;
    } catch (e) {
      print('最新データ検索中にエラー: $e');
      return {};
    }
  }

  /// 来場者データをFirestoreに保存
  Future<void> saveVisitorData(String userId, Map<String, dynamic> visitorData) async {
    try {
      // ユーザーIDを使ってドキュメントIDを指定して保存
      await _firestore.collection('visitors').doc(userId).set(visitorData);
      print('来場者データを保存しました: $userId - ${visitorData['email']}');
    } catch (e) {
      print('来場者データの保存中にエラーが発生しました: $e');
      throw Exception('来場者データの保存に失敗しました: $e');
    }
  }

  /// 来場者の属性情報を取得
  Future<Map<String, dynamic>?> getVisitorData(String userId) async {
    try {
      final doc = await _firestore.collection('visitors').doc(userId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('来場者データの取得中にエラーが発生しました: $e');
      return null;
    }
  }

  /// 特定のビーコンの来場者属性情報を取得
  Future<List<Map<String, dynamic>>> getBeaconVisitorDetails(String deviceName, String dateString) async {
    try {
      final doc = await _firestore
          .collection('beacon_counts')
          .doc(dateString)
          .collection('devices')
          .doc(deviceName)
          .get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['visitors'] != null && data['visitors'] is List) {
          return List<Map<String, dynamic>>.from(data['visitors']);
        }
      }
      return [];
    } catch (e) {
      print('ビーコン来場者詳細の取得中にエラーが発生しました: $e');
      return [];
    }
  }

  /// テスト用の混雑データを生成
  Future<void> generateTestCrowdData() async {
    try {
      final today = DateTime.now();
      final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      // 実際の会場のビーコンID一覧
      final beaconIds = [
        'Entrance-Main',
        'Entrance-Side',
        'FSC-BP104D', // 実際のビーコン（ブースA1）
        'Booth-A2', 
        'Booth-A3',
        'Booth-B1',
        'Booth-B2',
        'Booth-B3',
        'Booth-C1',
        'Booth-C2',
        'Booth-C3',
        'Rest-Area1',
        'Rest-Area2',
        'Food-Court',
        'Info-Desk',
      ];

      final random = math.Random();
      final batch = _firestore.batch();

      for (final beaconId in beaconIds) {
        // ランダムな混雑度を生成（0-50人の範囲）
        final count = random.nextInt(51);
        
        final docRef = _firestore
            .collection('beacon_counts')
            .doc(dateString)
            .collection('devices')
            .doc(beaconId);

        // テスト用の来場者データを生成
        final visitors = <Map<String, dynamic>>[];
        final genders = ['男性', '女性'];
        final jobs = ['会社員', '学生', '自営業', '主婦'];
        final sources = ['SNS', 'ウェブサイト', '友人紹介', 'チラシ'];
        final interests = [['IT', 'ビジネス'], ['アート', 'デザイン'], ['教育', '学習'], ['健康', '美容']];
        
        for (int i = 0; i < count; i++) {
          final userId = 'test_visitor_${random.nextInt(100000)}';
          final age = 20 + random.nextInt(41); // 20-60歳
          final gender = genders[random.nextInt(genders.length)];
          final job = jobs[random.nextInt(jobs.length)];
          final source = sources[random.nextInt(sources.length)];
          final interest = interests[random.nextInt(interests.length)];
          
          // visitorsコレクションにも保存（見込み客リスト用）
          await _firestore.collection('visitors').doc(userId).set({
            'userId': userId,
            'displayName': 'テストユーザー${i + 1}',
            'email': 'test${i + 1}@example.com',
            'age': age,
            'gender': gender,
            'job': job,
            'eventSource': source,
            'interests': interest,
          });
          
          // 見込み客の条件を満たすデータを生成
          final visitTime = today.subtract(Duration(minutes: random.nextInt(480))); // 8時間前まで
          final eventType = random.nextDouble() < 0.1 ? 'long_stay' : 'visit'; // 10%の確率でlong_stay
          
          visitors.add({
            'userId': userId,
            'timestamp': Timestamp.fromDate(visitTime),
            'age': age,
            'gender': gender,
            'job': job,
            'eventSource': source,
            'interests': interest,
            'eventType': eventType,
          });
          
          // 再訪問のテストデータを追加（30%の確率）
          if (random.nextDouble() < 0.3) {
            final revisitTime = visitTime.add(Duration(minutes: random.nextInt(60) + 30)); // 30分後から90分後
            visitors.add({
              'userId': userId,
              'timestamp': Timestamp.fromDate(revisitTime),
              'age': age,
              'gender': gender,
              'job': job,
              'eventSource': source,
              'interests': interest,
              'eventType': 'visit',
            });
          }
        }

        batch.set(docRef, {
          'count': count,
          'deviceName': beaconId,
          'visitors': visitors, // 来場者データを追加
          'firstSeen': Timestamp.fromDate(
            today.subtract(Duration(hours: random.nextInt(8) + 1))
          ),
          'lastSeen': Timestamp.fromDate(
            today.subtract(Duration(minutes: random.nextInt(30)))
          ),
          'generatedAt': FieldValue.serverTimestamp(),
          'isTestData': true,
        });
      }

      await batch.commit();
      print('テスト用混雑データを生成しました');
    } catch (e) {
      print('テストデータ生成中にエラーが発生しました: $e');
      throw Exception('テストデータの生成に失敗しました: $e');
    }
  }

  /// テストデータをクリア
  Future<void> clearTestData() async {
    try {
      final today = DateTime.now();
      final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      final querySnapshot = await _firestore
          .collection('beacon_counts')
          .doc(dateString)
          .collection('devices')
          .where('isTestData', isEqualTo: true)
          .get();

      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('テストデータをクリアしました');
    } catch (e) {
      print('テストデータクリア中にエラーが発生しました: $e');
      throw Exception('テストデータのクリアに失敗しました: $e');
    }
  }

  /// 存在するすべての日付のビーコンデータを確認
  Future<void> debugAllDates() async {
    try {
      print('=== 全日付データの確認開始 ===');
      final collectionSnapshot = await _firestore.collection('beacon_counts').get();
      
      print('見つかった日付の数: ${collectionSnapshot.docs.length}');
      
      for (final dateDoc in collectionSnapshot.docs) {
        final dateString = dateDoc.id;
        print('--- 日付: $dateString ---');
        
        final devicesSnapshot = await dateDoc.reference.collection('devices').get();
        print('  この日付のデバイス数: ${devicesSnapshot.docs.length}');
        
        for (final deviceDoc in devicesSnapshot.docs) {
          final deviceData = deviceDoc.data();
          print('  デバイス: ${deviceDoc.id}, カウント: ${deviceData['count']}');
        }
      }
      print('=== 全日付データの確認完了 ===');
    } catch (e) {
      print('全日付データ確認中にエラー: $e');
    }
  }

  /// 特定の日付のデータを取得（デバッグ用）
  Future<Map<String, dynamic>> getStatsForDate(String dateString) async {
    try {
      print('=== 指定日付のデータ取得: $dateString ===');
      final result = await getBeaconStats(dateString);
      return result;
    } catch (e) {
      print('指定日付データ取得中にエラー: $e');
      return {};
    }
  }

  /// ブース情報をFirebaseに保存
  Future<void> saveBoothInfo(String boothId, Map<String, dynamic> boothData) async {
    try {
      await _firestore.collection('booths').doc(boothId).set(boothData);
      print('ブース情報を保存しました: $boothId');
    } catch (e) {
      print('ブース情報の保存中にエラーが発生しました: $e');
    }
  }

  /// 全ブース情報をFirebaseから取得
  Future<List<Map<String, dynamic>>> getAllBooths() async {
    try {
      final querySnapshot = await _firestore.collection('booths').get();
      final booths = <Map<String, dynamic>>[];
      
      for (final doc in querySnapshot.docs) {
        final boothData = doc.data();
        boothData['id'] = doc.id; // ドキュメントIDを追加
        booths.add(boothData);
      }
      
      print('ブース情報を取得しました: ${booths.length}件');
      return booths;
    } catch (e) {
      print('ブース情報の取得中にエラーが発生しました: $e');
      return [];
    }
  }

  /// 特定のブース情報を取得
  Future<Map<String, dynamic>?> getBoothInfo(String boothId) async {
    try {
      final doc = await _firestore.collection('booths').doc(boothId).get();
      if (doc.exists) {
        final boothData = doc.data()!;
        boothData['id'] = doc.id;
        return boothData;
      }
      return null;
    } catch (e) {
      print('ブース情報の取得中にエラーが発生しました: $e');
      return null;
    }
  }

  /// テスト用のブース情報をFirebaseに保存
  Future<void> initializeBoothData() async {
    try {
      print('=== ブース情報の初期化を開始 ===');
      
      // ブースA1 (FSC-BP104D)
      await saveBoothInfo('FSC-BP104D', {
        'displayName': 'TechInnovate 2024',
        'company': '株式会社テックイノベーション',
        'description': 'AI・IoT技術で未来を創造する最先端企業です。次世代スマートデバイスから産業用IoTソリューションまで、幅広い革新的な製品を展示しています。',
        'products': [
          'スマートビーコン FSC-BP104D',
          'AIコンパニオンロボット',
          '産業用IoTセンサー',
          'リアルタイム位置追跡システム',
          'スマートホーム統合プラットフォーム',
        ],
        'contactEmail': 'info@tech-innovate.jp',
        'website': 'https://tech-innovate.jp',
        'features': [
          '業界最高精度の位置検知技術',
          'AI搭載による自動最適化',
          '低消費電力設計',
          '24時間365日の技術サポート',
          '導入実績500社以上',
        ],
        'type': 'booth',
        'x': 80,
        'y': 150,
        'name': 'ブースA1 (FSC-BP104D)',
      });

      // ブースA2
      await saveBoothInfo('Booth-A2', {
        'displayName': 'デジタルライフ 2024',
        'company': '株式会社デジタルライフソリューションズ',
        'description': '日常生活をより便利で快適にするスマートホーム・デジタルソリューションの総合企業です。IoTデバイスから統合プラットフォームまで、家庭のデジタル化を包括的にサポートします。',
        'products': [
          'スマートホーム統合システム',
          '音声制御アシスタント',
          'IoTセンサーネットワーク',
          'スマート家電連携アプリ',
          'エネルギー管理ダッシュボード',
        ],
        'contactEmail': 'contact@digital-life.co.jp',
        'website': 'https://digital-life.co.jp',
        'features': [
          '直感的な音声・ジェスチャー操作',
          'Amazon Alexa・Google Assistant連携',
          '業界最高レベルのセキュリティ',
          '24時間365日サポート',
          '設置から運用まで一括サポート',
        ],
        'type': 'booth',
        'x': 200,
        'y': 150,
        'name': 'ブースA2',
      });

      // ブースA3
      await saveBoothInfo('Booth-A3', {
        'displayName': 'グリーンテック ソリューション',
        'company': '環境テクノロジー株式会社',
        'description': '持続可能な社会を実現する環境技術のパイオニア企業です。太陽光発電からスマートグリッド、環境データ分析まで、地球環境保護と経済効果を両立するソリューションを提供しています。',
        'products': [
          '次世代ソーラー発電システム',
          'スマートグリッド制御システム',
          'AI環境予測・分析プラットフォーム',
          'カーボンニュートラル支援ツール',
          '企業向け環境データダッシュボード',
        ],
        'contactEmail': 'info@green-tech.co.jp',
        'website': 'https://green-tech.co.jp',
        'features': [
          'CO2削減効果最大85%を実現',
          '発電効率従来比40%向上',
          '環境省・経産省認定技術',
          '導入企業1,500社突破',
          '投資回収期間平均3.2年',
        ],
        'type': 'booth',
        'x': 320,
        'y': 150,
        'name': 'ブースA3',
      });

      // ブースB1
      await saveBoothInfo('Booth-B1', {
        'displayName': 'HealthTech Innovation',
        'company': '株式会社ヘルステックイノベーション',
        'description': '医療・ヘルスケア分野におけるデジタル変革を推進する企業です。AI診断技術からウェアラブルデバイス、遠隔医療ソリューションまで、最先端の医療技術を展示しています。',
        'products': [
          'AI画像診断システム',
          'スマートウェアラブルデバイス',
          '遠隔診療プラットフォーム',
          '健康管理アプリケーション',
          '医療データ分析ツール',
        ],
        'contactEmail': 'info@healthtech-innovation.jp',
        'website': 'https://healthtech-innovation.jp',
        'features': [
          '医師監修の高精度AI診断',
          '24時間健康モニタリング',
          '厚生労働省認証取得',
          '全国200病院導入実績',
          'プライバシー完全保護',
        ],
        'type': 'booth',
        'x': 80,
        'y': 250,
        'name': 'ブースB1',
      });

      // ブースB2
      await saveBoothInfo('Booth-B2', {
        'displayName': 'SmartEducation 2024',
        'company': '株式会社エデュケーショナルAI',
        'description': '教育現場のデジタル化を支援する次世代教育プラットフォームを提供しています。AI個別指導システムから学習データ分析まで、一人ひとりに最適化された学習環境を実現します。',
        'products': [
          'AI個別指導システム',
          'オンライン授業プラットフォーム',
          '学習進捗分析ダッシュボード',
          'VR・AR教材コンテンツ',
          '多言語対応学習支援ツール',
        ],
        'contactEmail': 'contact@edu-ai.co.jp',
        'website': 'https://smarteducation-ai.co.jp',
        'features': [
          '一人ひとりに最適化された学習',
          '全国1,000校導入実績',
          '学習効果30%向上を実証',
          '文部科学省推奨システム',
          '多言語対応（10カ国語）',
        ],
        'type': 'booth',
        'x': 200,
        'y': 250,
        'name': 'ブースB2',
      });

      // その他のブース（基本情報のみ）
      final List<Map<String, dynamic>> basicBooths = [
        {'id': 'Booth-B3', 'x': 320, 'y': 250, 'name': 'ブースB3'},
        {'id': 'Booth-C1', 'x': 80, 'y': 350, 'name': 'ブースC1'},
        {'id': 'Booth-C2', 'x': 200, 'y': 350, 'name': 'ブースC2'},
        {'id': 'Booth-C3', 'x': 320, 'y': 350, 'name': 'ブースC3'},
      ];

      for (final booth in basicBooths) {
        await saveBoothInfo(booth['id'] as String, {
          'displayName': booth['name'] as String,
          'company': '出展企業',
          'description': '詳細情報は準備中です。',
          'products': ['準備中'],
          'contactEmail': 'info@example.com',
          'website': 'https://example.com',
          'features': ['準備中'],
          'type': 'booth',
          'x': booth['x'] as int,
          'y': booth['y'] as int,
          'name': booth['name'] as String,
        });
      }

      print('=== ブース情報の初期化が完了しました ===');
    } catch (e) {
      print('ブース情報の初期化中にエラーが発生しました: $e');
    }
  }

  /// 見込み客リストを取得
  Future<List<Map<String, dynamic>>> getProspectList() async {
    try {
      print('=== 見込み客リストの取得開始 ===');
      
      final today = DateTime.now();
      final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      // 今日の全ビーコンデータを取得
      final allDevices = await _firestore
          .collection('beacon_counts')
          .doc(dateString)
          .collection('devices')
          .get();
      
      print('取得したデバイス数: ${allDevices.docs.length}');
      
      // 見込み客の条件を満たすユーザーを抽出
      final prospects = <String, Map<String, dynamic>>{};
      
      for (final device in allDevices.docs) {
        final deviceData = device.data();
        final visitors = deviceData['visitors'] as List<dynamic>?;
        final boothId = device.id;
        final boothName = deviceData['deviceName'] ?? boothId;
        
        if (visitors == null || visitors.isEmpty) continue;
        
        print('デバイス $boothId の来場者数: ${visitors.length}');
        
        // ユーザーごとに時系列で処理
        final List<Map<String, dynamic>> normalized = visitors
            .whereType<Map<String, dynamic>>()
            .map((v) => {
                  ...v,
                  'timestamp': (v['timestamp'] is Timestamp)
                      ? (v['timestamp'] as Timestamp).toDate()
                      : DateTime.tryParse(v['timestamp']?.toString() ?? '') ?? DateTime.now(),
                  'eventType': (v['eventType'] ?? 'visit').toString(),
                })
            .toList()
          ..sort((a, b) => (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime));
        
        for (final v in normalized) {
          final userId = v['userId'] as String?;
          if (userId == null) continue;
          
          if (!prospects.containsKey(userId)) {
            prospects[userId] = {
              'userId': userId,
              'visits': <Map<String, dynamic>>[],
              'boothVisitEvents': <String, int>{}, // boothId -> visitイベント回数
              'boothLastTimestamp': <String, DateTime>{},
              'boothLastVisitTs': <String, DateTime>{},
              'totalTime': 0,
            };
          }
          final u = prospects[userId]!;
          (u['visits'] as List<Map<String, dynamic>>).add({
            'boothId': boothId,
            'timestamp': v['timestamp'],
            'boothName': boothName,
            'eventType': v['eventType'],
          });
          
          // 再訪問カウントは eventType == 'visit' のみ対象（同一ブースで30秒以上間隔が空いた場合のみカウント）
          if (v['eventType'] == 'visit') {
            final lastVisitMap = (u['boothLastVisitTs'] as Map<String, DateTime>);
            final prev = lastVisitMap[boothId];
            final current = v['timestamp'] as DateTime;
            if (prev == null || current.difference(prev) >= const Duration(seconds: 30)) {
              final map = (u['boothVisitEvents'] as Map<String, int>);
              map[boothId] = (map[boothId] ?? 0) + 1;
            } else {
              print('短時間の重複visitを無視: $boothId (${current.difference(prev).inSeconds}秒差)');
            }
            lastVisitMap[boothId] = current;
          }
          
          // 滞在時間の推定（連続visitやlong_stayの間隔を利用）
          final lastMap = (u['boothLastTimestamp'] as Map<String, DateTime>);
          final last = lastMap[boothId];
          final currentTs = v['timestamp'] as DateTime;
          if (last != null) {
            final diffMin = currentTs.difference(last).inMinutes;
            if (diffMin > 0) u['totalTime'] = (u['totalTime'] as int) + diffMin;
          }
          lastMap[boothId] = currentTs;
        }
      }
      
      // 見込み客の条件をチェック
      final qualifiedProspects = <Map<String, dynamic>>[];
      
      for (final u in prospects.values) {
        final visits = (u['visits'] as List<Map<String, dynamic>>);
        final byBoothCounts = (u['boothVisitEvents'] as Map<String, int>);
        final totalTime = (u['totalTime'] as int);
        
        final hasRevisit = byBoothCounts.values.any((c) => c >= 2) && totalTime >= 1; // visitイベントが2回以上かつ1分以上滞在
        final hasLongStay = totalTime >= 5;
        
        print('ユーザー ${u['userId']}: 再訪問=$hasRevisit, 長時間滞在=$hasLongStay, 総時間=${totalTime}分');
        
        if (hasRevisit || hasLongStay) {
          final visitorInfo = await _getVisitorInfo(u['userId']);
          if (visitorInfo != null) {
            final int visitEventCount = visits.where((e) => e['eventType'] == 'visit').length;
            qualifiedProspects.add({
              ...visitorInfo,
              'totalTime': totalTime,
              'visitCount': visitEventCount,
              'revisitCount': byBoothCounts.values.where((c) => c >= 2).length,
              'boothVisits': byBoothCounts.keys.toList(),
              'lastVisit': visits.isNotEmpty ? visits.last['timestamp'] : null,
              'hasLongStay': hasLongStay,
              'hasRevisit': hasRevisit,
            });
          }
        }
      }
      
      qualifiedProspects.sort((a, b) => (b['totalTime'] as int).compareTo(a['totalTime'] as int));
      print('=== 見込み客リストの取得完了: ${qualifiedProspects.length}件 ===');
      return qualifiedProspects;
      
    } catch (e) {
      print('見込み客リストの取得中にエラーが発生しました: $e');
      return [];
    }
  }
  
  /// 来場者情報を取得
  Future<Map<String, dynamic>?> _getVisitorInfo(String userId) async {
    try {
      final visitorDoc = await _firestore.collection('visitors').doc(userId).get();
      if (visitorDoc.exists) {
        return {
          'id': userId,
          ...visitorDoc.data()!,
        };
      }
      return null;
    } catch (e) {
      print('来場者情報の取得エラー: $e');
      return null;
    }
  }

  /// 全来場者リストを取得（見込み客条件に関係なく）
  Future<List<Map<String, dynamic>>> getAllVisitors() async {
    try {
      print('=== 全来場者リストの取得開始 ===');
      
      final today = DateTime.now();
      final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      // 今日の全ビーコンデータを取得
      final allDevices = await _firestore
          .collection('beacon_counts')
          .doc(dateString)
          .collection('devices')
          .get();
      
      print('取得したデバイス数: ${allDevices.docs.length}');
      
      // 全来場者を抽出
      final allVisitors = <String, Map<String, dynamic>>{};
      
      for (final device in allDevices.docs) {
        final deviceData = device.data();
        final visitors = deviceData['visitors'] as List<dynamic>?;
        final boothId = device.id;
        final boothName = deviceData['deviceName'] ?? boothId;
        
        if (visitors == null || visitors.isEmpty) continue;
        
        print('デバイス $boothId の来場者数: ${visitors.length}');
        
        // ユーザーごとに時系列で処理
        final List<Map<String, dynamic>> normalized = visitors
            .whereType<Map<String, dynamic>>()
            .map((v) => {
                  ...v,
                  'timestamp': (v['timestamp'] is Timestamp)
                      ? (v['timestamp'] as Timestamp).toDate()
                      : DateTime.tryParse(v['timestamp']?.toString() ?? '') ?? DateTime.now(),
                  'eventType': (v['eventType'] ?? 'visit').toString(),
                })
            .toList()
          ..sort((a, b) => (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime));
        
        for (final v in normalized) {
          final userId = v['userId'] as String?;
          if (userId == null) continue;
          
          if (!allVisitors.containsKey(userId)) {
            allVisitors[userId] = {
              'userId': userId,
              'visits': <Map<String, dynamic>>[],
              'boothVisitEvents': <String, int>{}, // boothId -> visitイベント回数
              'boothLastTimestamp': <String, DateTime>{},
              'boothLastVisitTs': <String, DateTime>{},
              'totalTime': 0,
            };
          }
          final u = allVisitors[userId]!;
          (u['visits'] as List<Map<String, dynamic>>).add({
            'boothId': boothId,
            'timestamp': v['timestamp'],
            'boothName': boothName,
            'eventType': v['eventType'],
          });
          
          // 再訪問カウントは eventType == 'visit' のみ対象（同一ブースで30秒以上間隔が空いた場合のみカウント）
          if (v['eventType'] == 'visit') {
            final lastVisitMap = (u['boothLastVisitTs'] as Map<String, DateTime>);
            final prev = lastVisitMap[boothId];
            final current = v['timestamp'] as DateTime;
            if (prev == null || current.difference(prev) >= const Duration(seconds: 30)) {
              final map = (u['boothVisitEvents'] as Map<String, int>);
              map[boothId] = (map[boothId] ?? 0) + 1;
            } else {
              print('短時間の重複visitを無視: $boothId (${current.difference(prev).inSeconds}秒差)');
            }
            lastVisitMap[boothId] = current;
          }
          
          // 滞在時間の推定（連続visitやlong_stayの間隔を利用）
          final lastMap = (u['boothLastTimestamp'] as Map<String, DateTime>);
          final last = lastMap[boothId];
          final currentTs = v['timestamp'] as DateTime;
          if (last != null) {
            final diffMin = currentTs.difference(last).inMinutes;
            if (diffMin > 0) u['totalTime'] = (u['totalTime'] as int) + diffMin;
          }
          lastMap[boothId] = currentTs;
        }
      }
      
      // 全来場者の情報を取得
      final visitorList = <Map<String, dynamic>>[];
      
      for (final u in allVisitors.values) {
        final visits = (u['visits'] as List<Map<String, dynamic>>);
        final byBoothCounts = (u['boothVisitEvents'] as Map<String, int>);
        final totalTime = (u['totalTime'] as int);
        
        final hasRevisit = byBoothCounts.values.any((c) => c >= 2) && totalTime >= 1; // visitイベントが2回以上かつ1分以上滞在
        final hasLongStay = totalTime >= 5;
        
        final visitorInfo = await _getVisitorInfo(u['userId']);
        if (visitorInfo != null) {
          final int visitEventCount = visits.where((e) => e['eventType'] == 'visit').length;
          visitorList.add({
            ...visitorInfo,
            'totalTime': totalTime,
            'visitCount': visitEventCount,
            'revisitCount': byBoothCounts.values.where((c) => c >= 2).length,
            'boothVisits': byBoothCounts.keys.toList(),
            'lastVisit': visits.isNotEmpty ? visits.last['timestamp'] : null,
            'hasLongStay': hasLongStay,
            'hasRevisit': hasRevisit,
            'isProspect': hasRevisit || (hasLongStay && visitEventCount >= 2), // 見込み客かどうかのフラグ
          });
        }
      }
      
      visitorList.sort((a, b) => (b['totalTime'] as int).compareTo(a['totalTime'] as int));
      print('=== 全来場者リストの取得完了: ${visitorList.length}件 ===');
      return visitorList;
      
    } catch (e) {
      print('全来場者リストの取得中にエラーが発生しました: $e');
      return [];
    }
  }

  /// ブース予約を保存
  Future<bool> saveBoothReservation(String userId, String boothId) async {
    try {
      print('=== ブース予約の保存開始: userId=$userId, boothId=$boothId ===');
      
      // 既に予約済みかチェック
      final isReserved = await checkReservation(userId, boothId);
      if (isReserved) {
        print('既に予約済みです');
        return false;
      }
      
      // 来場者の属性情報を取得
      final visitorData = await getVisitorData(userId);
      
      // 来場者データがない場合でも基本情報で予約を保存
      final reservationData = {
        'userId': userId,
        'boothId': boothId,
        'displayName': visitorData?['displayName'] ?? '来場者',
        'email': visitorData?['email'] ?? '未登録',
        'age': visitorData?['age'] ?? 0,
        'gender': visitorData?['gender'] ?? '未設定',
        'job': visitorData?['job'] ?? '未設定',
        'eventSource': visitorData?['eventSource'] ?? 'BLE検知',
        'interests': visitorData?['interests'] ?? [],
        'reservedAt': FieldValue.serverTimestamp(),
        'hasVisitorInfo': visitorData != null, // 来場者情報があるかのフラグ
      };
      
      // booth_reservationsコレクションに保存（ドキュメントIDは userId_boothId）
      final docId = '${userId}_$boothId';
      await _firestore.collection('booth_reservations').doc(docId).set(reservationData);
      
      print('=== ブース予約の保存完了 ===');
      print('来場者情報の有無: ${visitorData != null}');
      return true;
    } catch (e) {
      print('ブース予約の保存中にエラーが発生しました: $e');
      return false;
    }
  }

  /// 予約済みかチェック
  Future<bool> checkReservation(String userId, String boothId) async {
    try {
      final docId = '${userId}_$boothId';
      final doc = await _firestore.collection('booth_reservations').doc(docId).get();
      return doc.exists;
    } catch (e) {
      print('予約チェック中にエラーが発生しました: $e');
      return false;
    }
  }

  /// 特定ブースの予約情報を取得
  Future<List<Map<String, dynamic>>> getBoothReservations(String boothId) async {
    try {
      print('=== ブース予約情報の取得開始: boothId=$boothId ===');
      
      final querySnapshot = await _firestore
          .collection('booth_reservations')
          .where('boothId', isEqualTo: boothId)
          .get();
      
      final reservations = <Map<String, dynamic>>[];
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        reservations.add({
          ...data,
          'id': doc.id,
        });
      }
      
      print('=== ブース予約情報の取得完了: ${reservations.length}件 ===');
      return reservations;
    } catch (e) {
      print('ブース予約情報の取得中にエラーが発生しました: $e');
      return [];
    }
  }

  /// 全予約情報を取得
  Future<List<Map<String, dynamic>>> getAllReservations() async {
    try {
      print('=== 全予約情報の取得開始 ===');
      
      final querySnapshot = await _firestore.collection('booth_reservations').get();
      
      final reservations = <Map<String, dynamic>>[];
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        reservations.add({
          ...data,
          'id': doc.id,
        });
      }
      
      print('=== 全予約情報の取得完了: ${reservations.length}件 ===');
      return reservations;
    } catch (e) {
      print('全予約情報の取得中にエラーが発生しました: $e');
      return [];
    }
  }
}
