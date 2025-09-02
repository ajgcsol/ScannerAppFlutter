
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/event.dart';
import 'package:flutter_app/models/scan.dart';
import 'package:flutter_app/models/student.dart';

class ScannerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Event>> getEvents() async {
    final snapshot = await _firestore.collection('events').get();
    return snapshot.docs.map((doc) => Event.fromFirestore(doc)).toList();
  }

  Future<List<Student>> getStudents() async {
    final snapshot = await _firestore.collection('students').get();
    return snapshot.docs.map((doc) => Student.fromFirestore(doc)).toList();
  }

  Stream<List<Scan>> getScansStream(String eventId) {
    return _firestore
        .collection('events')
        .doc(eventId)
        .collection('scans')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Scan.fromFirestore(doc)).toList());
  }

  Future<void> addScan(String eventId, String studentId) async {
    await _firestore
        .collection('events')
        .doc(eventId)
        .collection('scans')
        .add({
      'studentId': studentId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> addErrorReport(String scannedId, String email) async {
    await _firestore.collection('error_reports').add({
      'scannedId': scannedId,
      'email': email,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
