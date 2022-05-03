// Copyright 2017, Paul DeMarco.
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter_blue_example/widgets.dart';

import 'package:convert/convert.dart';

void main() {
  runApp(FlutterBlueApp());
}

class FlutterBlueApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      color: Colors.lightBlue,
      home: StreamBuilder<BluetoothState>(
          stream: FlutterBlue.instance.state,
          initialData: BluetoothState.unknown,
          builder: (c, snapshot) {
            final state = snapshot.data;
            if (state == BluetoothState.on) {
              return FindDevicesScreen();
            }
            return BluetoothOffScreen(state: state);
          }),
    );
  }
}

class BluetoothOffScreen extends StatelessWidget {
  const BluetoothOffScreen({Key? key, this.state}) : super(key: key);

  final BluetoothState? state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.bluetooth_disabled,
              size: 200.0,
              color: Colors.white54,
            ),
            Text(
              'Bluetooth Adapter is ${state != null ? state.toString().substring(15) : 'not available'}.',
              style: Theme.of(context)
                  .primaryTextTheme
                  .headline1
                  ?.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class FindDevicesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Find Devices'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            FlutterBlue.instance.startScan(timeout: Duration(seconds: 4)),
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              StreamBuilder<List<BluetoothDevice>>(
                stream: Stream.periodic(Duration(seconds: 2))
                    .asyncMap((_) => FlutterBlue.instance.connectedDevices),
                initialData: [],
                builder: (c, snapshot) => Column(
                  children: snapshot.data!
                      .map((d) => ListTile(
                            title: Text(d.name),
                            subtitle: Text(d.id.toString()),
                            trailing: StreamBuilder<BluetoothDeviceState>(
                              stream: d.state,
                              initialData: BluetoothDeviceState.disconnected,
                              builder: (c, snapshot) {
                                if (snapshot.data ==
                                    BluetoothDeviceState.connected) {
                                  return RaisedButton(
                                    child: Text('OPEN'),
                                    onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                DeviceScreen(device: d))),
                                  );
                                }
                                return Text(snapshot.data.toString());
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
              StreamBuilder<List<ScanResult>>(
                stream: FlutterBlue.instance.scanResults,
                initialData: [],
                builder: (c, snapshot) => Column(
                  children: snapshot.data!
                      .map(
                        (r) => ScanResultTile(
                          result: r,
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (context) {
                            r.device.connect();
                            return DeviceScreen(device: r.device);
                          })),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: StreamBuilder<bool>(
        stream: FlutterBlue.instance.isScanning,
        initialData: false,
        builder: (c, snapshot) {
          if (snapshot.data!) {
            return FloatingActionButton(
              child: Icon(Icons.stop),
              onPressed: () => FlutterBlue.instance.stopScan(),
              backgroundColor: Colors.red,
            );
          } else {
            return FloatingActionButton(
                child: Icon(Icons.search),
                onPressed: () => FlutterBlue.instance
                    .startScan(timeout: Duration(seconds: 4)));
          }
        },
      ),
    );
  }
}

class DeviceScreen extends StatelessWidget {
  //const DeviceScreen({Key? key, required this.device}) : super(key: key);
  DeviceScreen({Key? key, required this.device}) : super(key: key);

  final BluetoothDevice device;

  //List<BluetoothService> myServices;
  //BluetoothService watchService;
  BluetoothCharacteristic? rxChar;
  BluetoothCharacteristic? txChar;

  String dataDeviceTime = 'Device Time';
  String dataRealtimeStep = 'Realtime Step';

  String dataBLE = '';

  List<int> _getDeviceTimeBytes() {
    return [65, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 65];
  }

  List<int> _startRealtimeStepBytes() {
    return [9, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11];
  }

  List<int> _stopRealtimeStepBytes() {
    return [9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9];
  }

  // byte ModeStart = 0;
  // byte ModeContinue = 2;
  // byte ModeDelete = (byte)0x99;

  // byte[0]: cmd
  // byte[1]: mode
  // byte[4]: year
  // byte[5]: month
  // byte[6]: day
  // byte[7]: hour
  // byte[8]: min
  // byte[9]: second
  List<int> _getStaticHRBytes() {
    return [85, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 85];
  }

  List<int> _getHistoryBloodPressureBytes() {
    return [103, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 103];
  }

  List<Widget> _buildServiceTiles(List<BluetoothService> services) {
    return services
        .map(
          (s) => ServiceTile(
            service: s,
            characteristicTiles: s.characteristics
                .map(
                  (c) => CharacteristicTile(
                    characteristic: c,
                    onReadPressed: () => c.read(),
                    onWritePressed: () async {
                      await c.write(_getDeviceTimeBytes(),
                          withoutResponse: true);
                      await c.read();
                    },
                    onNotificationPressed: () async {
                      await c.setNotifyValue(c.isNotifying);
                      await c.read();
                    },
                    descriptorTiles: c.descriptors
                        .map(
                          (d) => DescriptorTile(
                            descriptor: d,
                            onReadPressed: () => d.read(),
                            onWritePressed: () =>
                                d.write(_getDeviceTimeBytes()),
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(device.name),
        actions: <Widget>[
          StreamBuilder<BluetoothDeviceState>(
            stream: device.state,
            initialData: BluetoothDeviceState.connecting,
            builder: (c, snapshot) {
              VoidCallback? onPressed;
              String text;
              switch (snapshot.data) {
                case BluetoothDeviceState.connected:
                  onPressed = () => device.disconnect();
                  text = 'DISCONNECT';
                  break;
                case BluetoothDeviceState.disconnected:
                  onPressed = () => device.connect();
                  text = 'CONNECT';
                  break;
                default:
                  onPressed = null;
                  text = snapshot.data.toString().substring(21).toUpperCase();
                  break;
              }
              return FlatButton(
                  onPressed: onPressed,
                  child: Text(
                    text,
                    style: Theme.of(context)
                        .primaryTextTheme
                        .button
                        ?.copyWith(color: Colors.white),
                  ));
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            StreamBuilder<BluetoothDeviceState>(
              stream: device.state,
              initialData: BluetoothDeviceState.connecting,
              builder: (c, snapshot) => ListTile(
                leading: (snapshot.data == BluetoothDeviceState.connected)
                    ? Icon(Icons.bluetooth_connected)
                    : Icon(Icons.bluetooth_disabled),
                title: Text(
                    'Device is ${snapshot.data.toString().split('.')[1]}.'),
                subtitle: Text('${device.id}'),
                trailing: StreamBuilder<bool>(
                  stream: device.isDiscoveringServices,
                  initialData: false,
                  builder: (c, snapshot) => IndexedStack(
                    index: snapshot.data! ? 1 : 0,
                    children: <Widget>[
                      IconButton(
                        icon: Icon(Icons.refresh),
                        onPressed: () => device.discoverServices(),
                      ),
                      IconButton(
                        icon: SizedBox(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.grey),
                          ),
                          width: 18.0,
                          height: 18.0,
                        ),
                        onPressed: null,
                      )
                    ],
                  ),
                ),
              ),
            ),
            StreamBuilder<int>(
              stream: device.mtu,
              initialData: 0,
              builder: (c, snapshot) => ListTile(
                title: Text('MTU Size'),
                subtitle: Text('${snapshot.data} bytes'),
                trailing: IconButton(
                  icon: Icon(Icons.edit),
                  onPressed: () => device.requestMtu(223),
                ),
              ),
            ),
            StreamBuilder<List<BluetoothService>>(
              stream: device.services,
              initialData: [],
              builder: (c, snapshot) {
                return Column(
                  children: _buildServiceTiles(snapshot.data!),
                );
              },
            ),
            TextButton(
              child: Text('Start'),
              onPressed: () async {
                var myServices = await device.discoverServices();
                var watchService = myServices.firstWhere((element) =>
                    element.uuid.toString() ==
                    '0000fff0-0000-1000-8000-00805f9b34fb');
                rxChar = watchService.characteristics.firstWhere((element) =>
                    element.uuid.toString() ==
                    '0000fff7-0000-1000-8000-00805f9b34fb');
                txChar = watchService.characteristics.firstWhere((element) =>
                    element.uuid.toString() ==
                    '0000fff6-0000-1000-8000-00805f9b34fb');
                await rxChar?.setNotifyValue(true);
              },
            ),
            TextButton(
              child: Text('Clear'),
              onPressed: () async {
                dataBLE = '';
                //
                // This is the trick to update state for StatelessWidget
                //
                (context as Element).markNeedsBuild();
              },
            ),
            TextButton(
              child: Text('Get Device Time'),
              onPressed: () async {
                await txChar?.write(_getDeviceTimeBytes(),
                    withoutResponse: true);
                var rxCharResult = await rxChar?.read();
                dataDeviceTime = decodeDeviceTime(rxCharResult!);
                //
                // This is the trick to update state for StatelessWidget
                //
                (context as Element).markNeedsBuild();
              },
            ),
            Text(dataDeviceTime),
            TextButton(
              child: Text('Start Realtime Step'),
              onPressed: () async {
                await txChar?.write(_startRealtimeStepBytes(),
                    withoutResponse: true);
                //
                // This is the trick to update state for StatelessWidget
                //
                (context as Element).markNeedsBuild();
              },
            ),
            TextButton(
              child: Text('Stop Realtime Step'),
              onPressed: () async {
                await txChar?.write(_stopRealtimeStepBytes(),
                    withoutResponse: true);
              },
            ),
            TextButton(
              child: Text('Get Static HR'),
              onPressed: () async {
                await txChar?.write(_getStaticHRBytes(),
                    withoutResponse: true);
              },
            ),
            TextButton(
              child: Text('Get History Blood Pressure'),
              onPressed: () async {
                await txChar?.write(_getHistoryBloodPressureBytes(),
                    withoutResponse: true);
              },
            ),
            StreamBuilder<List<int>>(
              stream: rxChar?.value,
              initialData: [],
              builder: (c, snapshot) {
                dataBLE += decodeBLEData(snapshot.data!) + '\n';
                return Column(
                  children: [Text(dataBLE)],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String decodeDeviceTime(List<int> bytes) {
    var result = "Device Time: ";
    if (bytes[0].toString() != '65') {
      print("It's not Device Time. Data Code: " + bytes[0].toString());
      return result;
    }
    result += '20' +
        hex.encode([bytes[1]]) +
        '-' +
        hex.encode([bytes[2]]) +
        '-' +
        hex.encode([bytes[3]]);
    result += ' ' +
        hex.encode([bytes[4]]) +
        ':' +
        hex.encode([bytes[5]]) +
        ':' +
        hex.encode([bytes[6]]);
    return result;
  }

  String decodeRealtimeStep(List<int> bytes) {
    var result = "Realtime Step: ";
    if (bytes[0].toString() != '9') {
      print("It's not Realtime Step. Data Code: " + bytes[0].toString());
      return result;
    }

    Map<String, String> mapData = new Map<String, String>();
    List activityData = List.filled(6, 0);
    int step = 0;
    double cal = 0;
    double distance = 0;
    int time = 0;
    int exerciseTime = 0;
    int heart = 0;
    int temp = 0;
    for (int i = 1; i < 5; i++) {
      step += getValue(bytes[i], i - 1);
    }
    for (int i = 5; i < 9; i++) {
      cal += getValue(bytes[i], i - 5);
    }
    for (int i = 9; i < 13; i++) {
      distance += getValue(bytes[i], i - 9);
    }
    for (int i = 13; i < 17; i++) {
      time += getValue(bytes[i], i - 13);
    }
    for (int i = 17; i < 21; i++) {
      exerciseTime += getValue(bytes[i], i - 17);
    }
    heart = getValue(bytes[21], 0);
    temp = getValue(bytes[22], 0) + getValue(bytes[23], 1);

    activityData[0] = step;
    activityData[1] = cal / 100;
    activityData[2] = distance / 100;
    activityData[3] = time / 60;
    activityData[4] = heart;
    activityData[5] = exerciseTime;

    mapData["step"] = activityData[0].toString();
    mapData["calories"] = activityData[1].toString();
    mapData["distance"] = activityData[2].toString();
    mapData["exerciseMinutes"] = activityData[3].toString();
    mapData["heartRate"] = activityData[4].toString();
    mapData["activeMinutes"] = activityData[5].toString();
    mapData["tempData"] = (temp * 0.1).toString();

    result += mapData.toString();
    return result;
  }

  String decodeActivityExercise(List<int> bytes) {
    var result = "Activity Exercise: ";
    if (bytes[0].toString() != '24') {
      print("It's not Activity Exercise. Data Code: " + bytes[0].toString());
      return result;
    }
    result += bytes.toString();
    return result;
  }

  String decodeStaticHR(List<int> bytes) {
    var result = "Static HR: ";
    if (bytes[0].toString() != '85') {
      print("It's not Static HR. Data Code: " + bytes[0].toString());
      return result;
    }
    List listData = List.empty(growable: true);
    int count = 10;
    int length = bytes.length;
    int size = (length / count).toInt();
    if (size == 0) {
      return result + "Static HR End";
    }
    for (int i=0; i<size; i++) {
      // int flag = 1 + (i + 1) * count;

      // datetime
      Map<String, String> mapData = new Map<String, String>();
      var dateTime = "";
      var staticHR = "";
      dateTime += '20' +
          hex.encode([bytes[3 + i * 10]]) +
          '-' +
          hex.encode([bytes[4 + i * 10]]) +
          '-' +
          hex.encode([bytes[5 + i * 10]]);
      dateTime += ' ' +
          hex.encode([bytes[6 + i * 10]]) +
          ':' +
          hex.encode([bytes[7 + i * 10]]) +
          ':' +
          hex.encode([bytes[8 + i * 10]]);
      mapData["dateTime"] = dateTime;
      staticHR += getValue(bytes[9 + i * 10], 0).toString();
      mapData["staticHR"] = staticHR;
      listData.add(mapData);
    }
    result += listData.toString();
    if (bytes[length-1].toString() == '255') {
      result += "Static HR End";
    }
    return result;
  }

  String decodeHistoryBloodPressure(List<int> bytes) {
    var result = "History Blood Pressure: ";
    if (bytes[0].toString() != '103') {
      print("It's not History Blood Pressure. Data Code: " + bytes[0].toString());
      return result;
    }
    List listData = List.empty(growable: true);
    int count = 12;
    int length = bytes.length;
    int size = (length / count).toInt();
    if (size == 0) {
      return result + "History Blood Pressure End";
    }
    for (int i=0; i<size; i++) {
      // datetime
      Map<String, String> mapData = new Map<String, String>();
      var dateTime = "";
      var staticHR = "";
      dateTime += '20' +
          hex.encode([bytes[3 + i * count]]) +
          '-' +
          hex.encode([bytes[4 + i * count]]) +
          '-' +
          hex.encode([bytes[5 + i * count]]);
      dateTime += ' ' +
          hex.encode([bytes[6 + i * count]]) +
          ':' +
          hex.encode([bytes[7 + i * count]]) +
          ':' +
          hex.encode([bytes[8 + i * count]]);
      mapData["dateTime"] = dateTime;
      mapData["bloodPressureHigh"] = getValue(bytes[9 + i * count], 0).toString();
      mapData["bloodPressureLow"] = getValue(bytes[10 + i * count], 0).toString();
      listData.add(mapData);
    }
    result += listData.toString();
    if (bytes[length-1].toString() == '255') {
      result += "History Blood Pressure End";
    }
    return result;
  }

  int getValue(int b, int count) {
    return (b * pow(256, count).toInt());
  }

  String decodeBLEData(List<int> bytes) {
    if (bytes.isEmpty) {
      return "";
    }
    switch (bytes[0].toString()) {
      case '65': //0x41
        return decodeDeviceTime(bytes);
        break;
      case '9': //0x09
        return decodeRealtimeStep(bytes);
        break;
      case '24': //0x18
        return decodeActivityExercise(bytes);
        break;
      case '85': //0x55
        return decodeStaticHR(bytes);
        break;
      case '103': //0x67
        return decodeHistoryBloodPressure(bytes);
        break;
      default:
        return bytes.toString();
    }
  }
}
