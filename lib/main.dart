import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
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
  bool _flag = false; // Ensures counter updates only once per entry/exit

  // Define the quadrilateral coordinates
  final List<List<double>> polygon = [
    [12.99124192963391, 80.23533800799297], // Point 1 (Latitude, Longitude)
    [12.991155682260397, 80.23519786257853], // Point 2    
    [12.991333404088223, 80.2350610699252], // Point 3
    [12.99142814545182, 80.23518713374297], // Point 4
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissionAndStartTracking();
  }

  // ✅ Step 1: Request location permission
  Future<void> _requestPermissionAndStartTracking() async {
    var status = await Permission.location.request();
    if (status.isGranted) {
      _startTracking();
    } else {
      print("Location permission denied.");
    }
  }

  // ✅ Step 2: Track live location
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

  // ✅ Step 3: Check if inside the quadrilateral (using Ray-Casting Algorithm)
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

  // ✅ Step 4: Update counter based on location
  void _checkIfInsidePolygon(Position position) {
    bool isInside = _isPointInsidePolygon(position.latitude, position.longitude, polygon);

    if (isInside && !_flag) {
      _counter++; // Increase counter if entering the zone
      _flag = true; // Set flag to prevent continuous increment
    } else if (!isInside && _flag) {
      _counter--; // Decrease counter if exiting the zone
      _flag = false; // Reset flag
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Location Counter")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Counter: $_counter", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
