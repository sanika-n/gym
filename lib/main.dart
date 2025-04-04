import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://rhavhpvmgeirzkpfaigw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoYXZocHZtZ2VpcnprcGZhaWd3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzcyNTkxMDQsImV4cCI6MjA1MjgzNTEwNH0.75WgRMov_Xu_E5uL3Q0yhFxlIIsscTyD7JJ6q2q54Yg',
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
  Stream<Position>? _positionStream;
  int _counter = 0;
  bool _flag = false; // Prevents continuous increment/decrement

  // Define the quadrilateral coordinates
  final List<List<double>> polygon = [
    //rjn
    [12.99025580072816, 80.23199075195609],
    [12.99028258978537, 80.23245209192237],
    [12.989928451283715, 80.23203702006317],
    [12.989946746273082, 80.23248696063702],
    

    //rmn
    // [12.989102897973158, 80.23152454068848],
    // [12.98917607816954, 80.23311240835073],
    // [12.988337118196176, 80.23363812129298],
    // [12.988407685032058, 80.23123486212849],
    //swarna
    // [12.99124192963391, 80.23533800799297],
    // [12.991155682260397, 80.23519786257853],
    // [12.991333404088223, 80.2350610699252],
    // [12.99142814545182, 80.23518713374297],
  ];

  @override
  void initState() {
    super.initState();
    _fetchCounter(); // Fetch initial counter value
    _subscribeToCounter(); // Listen for real-time changes
    _requestPermissionAndStartTracking(); // Start location tracking
  }

  // ✅ Fetch counter from Supabase
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

  // ✅ Update counter in Supabase
  Future<void> _updateCounterInSupabase(int newCounter) async {
    await Supabase.instance.client
        .from('gym')
        .update({'counter': newCounter})
        .eq('id', 1);
  }

  // ✅ Listen for real-time updates from Supabase
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

  // ✅ Request location permission
  Future<void> _requestPermissionAndStartTracking() async {
    var status = await Permission.location.request();
    if (status.isGranted) {
      _startTracking();
    } else {
      print("Location permission denied.");
    }
  }

  // ✅ Start tracking location
  void _startTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    );

    _positionStream!.listen((Position position) {
      setState(() {
        _currentPosition = position;
      });
      _checkIfInsidePolygon(position);
    });
  }

  // ✅ Check if point is inside the quadrilateral using Ray-Casting Algorithm
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
    return (intersections % 2) == 1; // Odd intersections mean inside
  }

  // ✅ Update counter based on entry/exit
  void _checkIfInsidePolygon(Position position) async {
    bool isInside = _isPointInsidePolygon(position.latitude, position.longitude, polygon);

    if (isInside && !_flag) {
      _counter++;
      _flag = true;
    } else if (!isInside && _flag) {
      _counter--;
      _flag = false;
    }

    setState(() {});
    await _updateCounterInSupabase(_counter); // ✅ Update Supabase
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Gym Occupancy Tracker")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "People in Gym: $_counter",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
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
