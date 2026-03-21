import 'package:pocketbase/pocketbase.dart';

class PublicSettings {
  const PublicSettings({
    required this.id,
    required this.favicon,
    required this.setupCompleted,
    required this.websiteTitle,
  });

  final String id;
  final String favicon;
  final bool setupCompleted;
  final String websiteTitle;

  factory PublicSettings.fromRecord(RecordModel record) {
    return PublicSettings(
      id: record.id,
      favicon: record.getStringValue('favicon'),
      setupCompleted: record.getBoolValue('setup_completed'),
      websiteTitle: record.getStringValue('website_title'),
    );
  }

  String get effectiveTitle =>
      websiteTitle.trim().isEmpty ? 'UpSnap' : websiteTitle.trim();

  Map<String, dynamic> toBody() {
    return {'website_title': websiteTitle.trim(), 'favicon': favicon};
  }

  PublicSettings copyWith({
    String? id,
    String? favicon,
    bool? setupCompleted,
    String? websiteTitle,
  }) {
    return PublicSettings(
      id: id ?? this.id,
      favicon: favicon ?? this.favicon,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      websiteTitle: websiteTitle ?? this.websiteTitle,
    );
  }
}

class PrivateSettings {
  const PrivateSettings({
    required this.id,
    required this.interval,
    required this.lazyPing,
    required this.scanRange,
  });

  final String id;
  final String interval;
  final bool lazyPing;
  final String scanRange;

  factory PrivateSettings.fromRecord(RecordModel record) {
    return PrivateSettings(
      id: record.id,
      interval: record.getStringValue('interval'),
      lazyPing: record.getBoolValue('lazy_ping'),
      scanRange: record.getStringValue('scan_range'),
    );
  }

  Map<String, dynamic> toBody() {
    return {
      'interval': interval.trim(),
      'lazy_ping': lazyPing,
      'scan_range': scanRange.trim(),
    };
  }

  PrivateSettings copyWith({
    String? id,
    String? interval,
    bool? lazyPing,
    String? scanRange,
  }) {
    return PrivateSettings(
      id: id ?? this.id,
      interval: interval ?? this.interval,
      lazyPing: lazyPing ?? this.lazyPing,
      scanRange: scanRange ?? this.scanRange,
    );
  }
}
