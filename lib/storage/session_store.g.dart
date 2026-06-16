// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_store.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SessionConfigAdapter extends TypeAdapter<SessionConfig> {
  @override
  final int typeId = 0;

  @override
  SessionConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SessionConfig(
      backgroundModel: fields[0] as String,
      faceMeshEnabled: fields[1] as bool,
      createdAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, SessionConfig obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.backgroundModel)
      ..writeByte(1)
      ..write(obj.faceMeshEnabled)
      ..writeByte(2)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
