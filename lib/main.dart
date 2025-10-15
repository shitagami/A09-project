import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/staff_screen.dart';
import 'screens/organizer_screen.dart';
import 'screens/exhibitor_screen.dart';
import 'screens/visitor_form_screen.dart';
import 'screens/crowd_heatmap_screen.dart';
import 'screens/visitor_management_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Firebaseの初期化
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase初期化成功');
  } catch (e) {
    print('Firebase初期化エラー: $e');
    // Firebase初期化に失敗してもアプリは起動する
  }
  
  try {
    // 通知サービスを初期化
    await NotificationService().initialize();
    print('通知サービス初期化成功');
  } catch (e) {
    print('通知サービス初期化エラー: $e');
    // 通知サービス初期化に失敗してもアプリは起動する
  }
  
  runApp(const MyApp());
}

void setup() async {
  // Bluetoothが有効でパーミッションが許可されるまで待機
  // await FlutterBluePlus.adapterState
  //     .where((val) => val == BluetoothAdapterState.on)
  //     .first;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Beacon App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginScreen(), // ログイン画面をメイン画面に戻す
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/setup': (context) => const SetupScreen(),
        '/staff': (context) => const StaffScreen(),
        '/organizer': (context) => const OrganizerScreen(),
        '/exhibitor': (context) => const ExhibitorScreen(),
        '/visitor_form': (context) => const VisitorFormScreen(),
        '/crowd_heatmap': (context) => const CrowdHeatmapScreen(),
        '/visitor_management': (context) => const VisitorManagementScreen(),
      },
    );
  }
}


