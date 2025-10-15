import 'package:cloud_firestore/cloud_firestore.dart';

/// Firebaseにテスト用のユーザーデータを追加するスクリプト
/// このスクリプトは開発時のみ使用してください
class SetupTestUsers {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// テスト用のユーザーデータをFirebaseに追加
  static Future<void> setupTestUsers() async {
    try {
      // 出展者データ
      await _firestore.collection('exhibitors').doc('exhibitor001').set({
        'id': 'exhibitor001',
        'name': 'テスト出展者1',
        'password': 'password123',
        'company': 'テスト株式会社',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('exhibitors').doc('exhibitor002').set({
        'id': 'exhibitor002',
        'name': 'テスト出展者2',
        'password': 'password123',
        'company': 'サンプル企業',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 主催者データ
      await _firestore.collection('organizers').doc('organizer001').set({
        'id': 'organizer001',
        'name': 'テスト主催者1',
        'password': 'password123',
        'role': 'admin',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('organizers').doc('organizer002').set({
        'id': 'organizer002',
        'name': 'テスト主催者2',
        'password': 'password123',
        'role': 'manager',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // スタッフデータ
      await _firestore.collection('staff').doc('staff001').set({
        'id': 'staff001',
        'name': 'テストスタッフ1',
        'password': 'password123',
        'department': '運営部',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('staff').doc('staff002').set({
        'id': 'staff002',
        'name': 'テストスタッフ2',
        'password': 'password123',
        'department': '技術部',
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('テストユーザーデータの追加が完了しました');
    } catch (e) {
      print('テストユーザーデータの追加中にエラーが発生しました: $e');
    }
  }

  /// テスト用のユーザーデータを削除
  static Future<void> cleanupTestUsers() async {
    try {
      // 出展者データを削除
      await _firestore.collection('exhibitors').doc('exhibitor001').delete();
      await _firestore.collection('exhibitors').doc('exhibitor002').delete();

      // 主催者データを削除
      await _firestore.collection('organizers').doc('organizer001').delete();
      await _firestore.collection('organizers').doc('organizer002').delete();

      // スタッフデータを削除
      await _firestore.collection('staff').doc('staff001').delete();
      await _firestore.collection('staff').doc('staff002').delete();

      print('テストユーザーデータの削除が完了しました');
    } catch (e) {
      print('テストユーザーデータの削除中にエラーが発生しました: $e');
    }
  }
} 