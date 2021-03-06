import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:g_taxi/global_variables.dart';
import 'package:g_taxi/helpers/map_kit_helper.dart';
import 'package:g_taxi/models/trip_details.dart';
import 'package:g_taxi/style/my_colors.dart';
import 'package:g_taxi/widgets/collect_payment.dart';
import 'package:g_taxi/widgets/sign_button.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:g_taxi/helpers/functions_helper.dart';

class NewTripScreen extends StatefulWidget {
  static const String routeName = 'new_trip_screen';
  @override
  _NewTripScreenState createState() => _NewTripScreenState();
}

class _NewTripScreenState extends State<NewTripScreen> {
  GoogleMapController mapController;
  Completer<GoogleMapController> _completer = Completer();

  Set<Marker> _markers = Set<Marker>();
  Set<Circle> _circles = Set<Circle>();
  Set<Polyline> _polylines = Set<Polyline>();

  List<LatLng> polylineCoordinates = [];
  PolylinePoints polylinePoints = PolylinePoints();
  TripDetails tripDetails;
  BitmapDescriptor riderIcon;
  BitmapDescriptor movingMarkerIcon;
  Position myPosition;
  String status = 'accepted';
  String durationString = '';
  bool isRequestingDirection = false;
  String buttonTitle = 'Arrived';
  Timer timer;
  int durationCounter = 0;

  Future<void> getDirection(LatLng pickupLatLng, LatLng destinationLatLng) async {
    var destinationDetails = await FunctionsHelper.getDirectionDetails(pickupLatLng, destinationLatLng);

    List<PointLatLng> results = polylinePoints.decodePolyline(destinationDetails.encodedPoints);
    polylineCoordinates.clear();
    if (results.isNotEmpty) {
      results.forEach((PointLatLng points) {
        polylineCoordinates.add(LatLng(points.latitude, points.longitude));
      });
    }

    _polylines.clear();
    setState(() {
      Polyline polyline = Polyline(
        polylineId: PolylineId('polyId'),
        // color: Color.fromARGB(255, 95, 109, 237),
        color: Colors.blue,
        points: polylineCoordinates,
        jointType: JointType.round,
        width: 4,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: true,
      );
      _polylines.add(polyline);
    });

    LatLngBounds bounds;
    if (pickupLatLng.latitude > destinationLatLng.latitude &&
        pickupLatLng.longitude > destinationLatLng.longitude) {
      bounds = LatLngBounds(southwest: destinationLatLng, northeast: pickupLatLng);
    } else if (pickupLatLng.longitude > destinationLatLng.longitude) {
      bounds = LatLngBounds(
          southwest: LatLng(pickupLatLng.latitude, destinationLatLng.longitude),
          northeast: LatLng(destinationLatLng.latitude, pickupLatLng.longitude));
    } else if (pickupLatLng.latitude > destinationLatLng.latitude) {
      bounds = LatLngBounds(
          southwest: LatLng(destinationLatLng.latitude, pickupLatLng.longitude),
          northeast: LatLng(pickupLatLng.latitude, destinationLatLng.longitude));
    } else {
      bounds = LatLngBounds(southwest: pickupLatLng, northeast: destinationLatLng);
    }
    mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
    // Marker pickupMarker = Marker(
    //   markerId: MarkerId('pickup'),
    //   position: pickupLatLng,
    //   icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    // );
    Marker destinationMarker = Marker(
      markerId: MarkerId('destination'),
      position: destinationLatLng,
      // icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      icon: riderIcon,
    );

    Circle pickupCircle = Circle(
        circleId: CircleId('pickup'),
        strokeColor: Colors.green,
        strokeWidth: 3,
        radius: 12,
        center: pickupLatLng,
        fillColor: Colors.greenAccent);

    Circle destinationCircle = Circle(
      circleId: CircleId('destination'),
      strokeColor: Colors.deepPurple,
      strokeWidth: 3,
      radius: 12,
      center: destinationLatLng,
      fillColor: Colors.purple,
    );
    setState(() {
      // _markers.add(pickupMarker);
      _markers.add(destinationMarker);
      _circles.add(pickupCircle);
      _circles.add(destinationCircle);
    });
  }

  void acceptTrip() {
    rideRef = FirebaseDatabase.instance.reference().child('RideRequests/${tripDetails.rideId}');
    rideRef.child('status').set('Accepted');
    rideRef.child('driver_id').set(currentDriverInfo.id);
    rideRef.child('driver_name').set(currentDriverInfo.name);
    rideRef.child('driver_phone').set(currentDriverInfo.phone);
    rideRef.child('car_details').set('${currentDriverInfo.carModel} - ${currentDriverInfo.carColor}');
    rideRef.child('driver_location').set({
      'latitude': currentPosition.latitude,
      'longitude': currentPosition.longitude,
    });
  }

  void createRiderMarker() async {
    if (riderIcon == null) {
      ImageConfiguration imageConfiguration = createLocalImageConfiguration(
        context,
        size: Size(2, 2),
      );
      riderIcon = await BitmapDescriptor.fromAssetImage(
        imageConfiguration,
        'assets/images/rider_marker.png',
      );
    }
  }

  void createmovingMarker() async {
    if (movingMarkerIcon == null) {
      ImageConfiguration imageConfiguration = createLocalImageConfiguration(
        context,
        size: Size(2, 2),
      );
      movingMarkerIcon = await BitmapDescriptor.fromAssetImage(
        imageConfiguration,
        'assets/images/car_android.png',
      );
    }
  }

  void getLocationUpdate() {
    LatLng oldPosition = LatLng(0, 0);
    ridePositionStream = Geolocator.getPositionStream().listen((position) {
      myPosition = position;
      currentPosition = position;
      LatLng positionLatLng = LatLng(myPosition.latitude, myPosition.longitude);
      var rotation = MapKitHelper.getMarkerRotation(
        oldPosition.latitude,
        oldPosition.longitude,
        positionLatLng.latitude,
        positionLatLng.longitude,
      );

      Marker movingMarker = Marker(
        markerId: MarkerId('moving'),
        position: positionLatLng,
        icon: movingMarkerIcon,
        infoWindow: InfoWindow(title: 'Current Location'),
        rotation: rotation,
      );
      setState(() {
        CameraPosition cp = CameraPosition(target: positionLatLng, zoom: 17);
        mapController.animateCamera(CameraUpdate.newCameraPosition(cp));
        _markers.removeWhere((marker) => marker.markerId.value == 'moving');
        _markers.add(movingMarker);
      });
      oldPosition = positionLatLng;
      updateTripDetails();

      rideRef.child('driver_location').set({
        'latitude': myPosition.latitude,
        'longitude': myPosition.longitude,
      });
    });
  }

  void updateTripDetails() async {
    if (!isRequestingDirection) {
      isRequestingDirection = true;
      if (myPosition == null) {
        return;
      }
      LatLng positionLatLng = LatLng(myPosition.latitude, myPosition.longitude);
      LatLng destinationLatLng;
      if (status == 'accepted') {
        destinationLatLng = tripDetails.pickup;
      } else {
        destinationLatLng = tripDetails.destination;
      }
      var directionDetails = await FunctionsHelper.getDirectionDetails(positionLatLng, destinationLatLng);
      if (directionDetails != null) {
        setState(() {
          durationString = directionDetails.durationText;
        });
      }
      isRequestingDirection = false;
    }
  }

  void startTimer() {
    const interval = Duration(seconds: 1);
    timer = Timer.periodic(interval, (timer) {
      durationCounter++;
    });
  }

  void endTrip() async {
    timer.cancel();
    var currentLatlng = LatLng(myPosition.latitude, myPosition.longitude);
    var directionDetails = await FunctionsHelper.getDirectionDetails(tripDetails.pickup, currentLatlng);

    Navigator.of(context).pop();

    int cost = FunctionsHelper.calculateTripCost(directionDetails);

    rideRef.child('cost').set(cost);
    rideRef.child('status').set('ended');
    ridePositionStream.cancel();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => CollectPaymentDialog(
        tripDetails.paymentMethod,
        cost,
      ),
    );
    topUpEarnings(cost);
  }

  void topUpEarnings(int cost) {
    DatabaseReference earningsRef =
        FirebaseDatabase().reference().child('Drivers/${currentUser.uid}/earnings');
    earningsRef.once().then((DataSnapshot snapshot) {
      if (snapshot.value != null) {
        double oldEarnings = snapshot.value;
        double adjustCost = cost + oldEarnings;
        earningsRef.set(adjustCost);
      } else {
        double adjustedEarnings = cost * 0.85;
        earningsRef.set(adjustedEarnings);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    tripDetails = ModalRoute.of(context).settings.arguments;
    acceptTrip();
    createRiderMarker();
    createmovingMarker();
    return Scaffold(
      // appBar: AppBar(title: Text('New Trip')),
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              padding: const EdgeInsets.only(bottom: 280),
              initialCameraPosition: cameraPosition,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              compassEnabled: true,
              trafficEnabled: true,
              mapType: MapType.normal,
              markers: _markers,
              circles: _circles,
              polylines: _polylines,
              onMapCreated: (GoogleMapController controller) async {
                mapController = controller;
                _completer.complete(controller);
                LatLng currentLatLng = LatLng(currentPosition.latitude, currentPosition.longitude);
                LatLng pickupLatLng = tripDetails.pickup;
                await getDirection(currentLatLng, pickupLatLng);
                getLocationUpdate();
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 280,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(15),
                    topRight: Radius.circular(15),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 15,
                      spreadRadius: 0.5,
                      offset: Offset(0.7, 0.7),
                    )
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      durationString,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Brand-Bold',
                        color: MyColors.accentPurple,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${tripDetails.riderName}',
                          style: TextStyle(
                            fontSize: 20,
                            fontFamily: 'Brand-Bold',
                          ),
                        ),
                        Icon(Icons.call),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset('assets/images/pickicon.png', height: 20, width: 20),
                        SizedBox(width: 15),
                        Expanded(
                            child: Container(
                          child: Text(
                            '${tripDetails.pickupAddress}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16),
                          ),
                        )),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset('assets/images/desticon.png', height: 20, width: 20),
                        SizedBox(width: 15),
                        Expanded(
                            child: Container(
                          child: Text(
                            '${tripDetails.destinationName}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16),
                          ),
                        )),
                      ],
                    ),
                    SignButton(
                      title: buttonTitle,
                      function: () async {
                        if (status == 'accepted') {
                          status = 'arrived';
                          rideRef.child('status').set('arrived');
                          setState(() {
                            buttonTitle = 'Start Trip';
                          });
                          await getDirection(tripDetails.pickup, tripDetails.destination);
                        } else if (status == 'arrived') {
                          status = 'ontrip';
                          rideRef.child('status').set('ontrip');
                          setState(() {
                            buttonTitle = 'End Trip';
                          });
                          startTimer();
                        } else if (status == 'ontrip') {
                          endTrip();
                        }
                      },
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
