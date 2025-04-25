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
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _timeCheckTimer;
  int _counter = 0;
  bool _flag = false;
  bool _isTrackingAllowed = false;
  final List<Timer> _locationTimers = [];

  final List<List<double>> polygon = [
    [12.99025580072816, 80.23199075195609],
    [12.99028258978537, 80.23245209192237],
    [12.989928451283715, 80.23203702006317],
    [12.989946746273082, 80.23248696063702],
  ];

  @override
  void initState() {
    super.initState();
    _checkTrackingTime(); // Check initially
    // Set up a timer to check every minute
    _timeCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkTrackingTime());
    _requestPermissionAndStartTracking();
    _fetchCounter();
    _subscribeToCounter();
  }

  bool _isWithinTrackingHours() {
    final now = DateTime.now();
    // Convert to IST (UTC+5:30)
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    
    // Check if it's Sunday (where Sunday is 7 in DateTime.weekday)
    if (ist.weekday == DateTime.sunday) {
      return false;
    }

    // Create DateTime objects for 8:00 AM and 9:45 PM
    final startTime = DateTime(ist.year, ist.month, ist.day, 8, 0);
    final endTime = DateTime(ist.year, ist.month, ist.day, 21, 45);

    return ist.isAfter(startTime) && ist.isBefore(endTime);
  }

  void _checkTrackingTime() {
    bool shouldTrack = _isWithinTrackingHours();
    
    if (shouldTrack != _isTrackingAllowed) {
      _isTrackingAllowed = shouldTrack;
      if (_isTrackingAllowed) {
        _startTracking();
        _startForegroundTask();
      } else {
        _stopTracking();
      }
    }
  }

  void _stopTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    // Cancel all active location timers
    for (var timer in _locationTimers) {
      timer.cancel();
    }
    _locationTimers.clear();
    FlutterForegroundTask.stopService();
    setState(() {
      _currentPosition = null;
    });
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
      _checkTrackingTime(); // This will start tracking only if within allowed hours
    } else {
      print("Permissions not granted");
    }
  }

  void _startTracking() {
    if (!_isWithinTrackingHours()) {
      return;
    }

    _positionStreamSubscription?.cancel(); // Cancel any existing subscription
    
    // Create a timer that gets location every 5 minutes
    final locationTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_isWithinTrackingHours()) {
        Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).then((Position position) {
          print("📍 Got position: ${position.latitude}, ${position.longitude}");
          setState(() {
            _currentPosition = position;
          });
          _checkIfInsidePolygon(position);
        });
      } else {
        _stopTracking();
      }
    });

    // Store the timer for cleanup
    _locationTimers.add(locationTimer);

    // Get initial position immediately
    Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).then((Position position) {
      print("📍 Initial position: ${position.latitude}, ${position.longitude}");
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
    _timeCheckTimer?.cancel();
    // Cancel all active location timers
    for (var timer in _locationTimers) {
      timer.cancel();
    }
    _locationTimers.clear();
    _stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gym Occupancy Tracker")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("People in Gym: $_counter", 
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            if (!_isTrackingAllowed)
              const Text("Tracking is only available from 8:00 AM to 9:45 PM IST\nExcept Sundays",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
            _currentPosition != null
                ? Text("Lat: ${_currentPosition!.latitude}, Lng: ${_currentPosition!.longitude}")
                : const Text("Tracking location..."),
          ],
        ),
      ),
    );
  }
}
