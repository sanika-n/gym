import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://rhavhpvmgeirzkpfaigw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoYXZocHZtZ2VpcnprcGZhaWd3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzcyNTkxMDQsImV4cCI6MjA1MjgzNTEwNH0.75WgRMov_Xu_E5uL3Q0yhFxlIIsscTyD7JJ6q2q54Yg',
  
  );

  // Initialize Foreground Task plugin
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'location_tracking_channel',
      channelName: 'Location Tracking',
      channelDescription: 'This notification appears when tracking is active.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      iconData: const NotificationIconData(
        resType: ResourceType.mipmap,
        resPrefix: ResourcePrefix.ic,
        name: 'launcher',
      ),
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: const ForegroundTaskOptions(
      interval: 5000,
      isOnceEvent: false,
      autoRunOnBoot: false,
    ),
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: LocationTracker(),
    );
  }
}

class LocationTracker extends StatefulWidget {
  @override
  _LocationTrackerState createState() => _LocationTrackerState();
}

class _LocationTrackerState extends State<LocationTracker> {
  Position? _currentPosition;
  //StreamSubscription<Position>? _positionStreamSubscription;
  int _counter = 0;
  bool _flag = false;

  final List<List<double>> polygon = [
   [12.98569353591303, 80.23595564260987],
   [12.985058905487486, 80.23596478987726],
   [12.985128429686197, 80.23684109809409],
   [12.985732754594002, 80.23687402825674],
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissionAndStartTracking();
    _fetchCounter();
    _subscribeToCounter();
  }

  Future<void> _fetchCounter() async {
    final response = await Supabase.instance.client
        .from('gym')
        .select('counter')
        .eq('id', 1)
        .single();
    if (response != null) {
      setState(() {
        _counter = response['counter'];
      });
    }
  }

  Future<void> _updateCounterInSupabase(int newCounter) async {
    await Supabase.instance.client
        .from('gym')
        .update({'counter': newCounter})
        .eq('id', 1);
  }

  void _subscribeToCounter() {
    Supabase.instance.client
        .from('gym')
        .stream(primaryKey: ['id'])
        .eq('id', 1)
        .listen((data) {
      if (data.isNotEmpty) {
        setState(() {
          _counter = data.first['counter'];
        });
      }
    });
  }

  Future<void> _requestPermissionAndStartTracking() async {
    var locationPermission = await Permission.location.request();
    var backgroundLocationPermission = await Permission.locationAlways.request();
    var batteryPermission = await Permission.ignoreBatteryOptimizations.request();

    if (locationPermission.isGranted && backgroundLocationPermission.isGranted) {
      _startForegroundTask();
      _startTracking();
    } else {
      print("Permissions not granted");
      // Optionally, show a dialog to the user about missing permissions
    }
  }

Timer? _locationTimer;

void _startTracking() {
  _locationTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    print("📍 Got position: ${position.latitude}, ${position.longitude}");

    setState(() {
      _currentPosition = position;
    });

    _checkIfInsidePolygon(position);
  });
}

  bool _isPointInsidePolygon(double lat, double lon, List<List<double>> polygon) {
    int intersections = 0;
    for (int i = 0; i < polygon.length; i++) {
      int j = (i + 1) % polygon.length;
      double lat1 = polygon[i][0], lon1 = polygon[i][1];
      double lat2 = polygon[j][0], lon2 = polygon[j][1];

      if ((lon1 > lon) != (lon2 > lon)) {
        double intersectLat = lat1 + (lat2 - lat1) * (lon - lon1) / (lon2 - lon1);
        if (intersectLat > lat) {
          intersections++;
        }
      }
    }
    return (intersections % 2) == 1;
  }

  void _checkIfInsidePolygon(Position position) async {
    bool isInside = _isPointInsidePolygon(position.latitude, position.longitude, polygon);

    if (isInside && !_flag) {
      _counter++;
      _flag = true;
      await _updateCounterInSupabase(_counter);
    } else if (!isInside && _flag) {
      _counter--;
      _flag = false;
      await _updateCounterInSupabase(_counter);
    }

    setState(() {});
  }

  void _startForegroundTask() {
    FlutterForegroundTask.startService(
      notificationTitle: 'Gym Tracker Running',
      notificationText: 'Tracking your location in background',
      
    );
  }

  @override
  void dispose() {
    FlutterForegroundTask.stopService();
    _locationTimer?.cancel();  // ✅ Changed from stream cancellation to timer cancellation
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Gym Occupancy Tracker")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("People in Gym: $_counter", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            _currentPosition != null
                ? Text("Lat: ${_currentPosition!.latitude}, Lng: ${_currentPosition!.longitude}")
                : Text("Tracking location..."),
          ],
        ),
      ),
    );
  }
}
