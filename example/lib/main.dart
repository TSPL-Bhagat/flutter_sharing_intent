import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription _intentDataStreamSubscription;
  List<SharedFile>? list;

  @override
  void initState() {
    initSharingListener();

    super.initState();
  }

  void initSharingListener() {
    // For sharing coming from outside the app while the app is in memory
    _intentDataStreamSubscription = FlutterSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedFile> value) {
      setState(() {
        list = value;
      });
      _handleSharedFiles(value);
    }, onError: (err) {
      if (kDebugMode) {
        print("Shared: getIntentDataStream error: $err");
      }
    });

    // For sharing coming from outside the app while the app is closed
    FlutterSharingIntent.instance
        .getInitialSharing()
        .then((List<SharedFile> value) {
      setState(() {
        list = value;
      });
      _handleSharedFiles(value);
    });
  }

  void _handleSharedFiles(List<SharedFile> sharedFiles) {
    for (final file in sharedFiles) {
      switch (file.type) {
        case SharedMediaType.URL:
          if (kDebugMode) {
            print("Shared URL: ${file.value}");
          }
        case SharedMediaType.TEXT:
          if (kDebugMode) {
            print("Shared text: ${file.value}");
          }
        case SharedMediaType.IMAGE:
          if (kDebugMode) {
            print("Shared image path: ${file.value}");
          }
        case SharedMediaType.VIDEO:
          if (kDebugMode) {
            print(
                "Shared video path: ${file.value}, thumbnail: ${file.thumbnail}");
          }
        case SharedMediaType.FILE:
          if (kDebugMode) {
            print(
                "Shared file path: ${file.value}, mimeType: ${file.mimeType}");
          }
        default:
          if (kDebugMode) {
            print("Shared other: ${file.value}");
          }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              child: SingleChildScrollView(
                  child: Text('Sharing data: \n${list?.join("\n\n")}\n'))),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            FlutterSharingIntent.instance.shareDebugLogs();
          },
          icon: const Icon(Icons.bug_report),
          label: const Text('Share Logs'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }
}
