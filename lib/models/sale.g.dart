// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sale.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SaleItemAdapter extends TypeAdapter<SaleItem> {
  @override
  final int typeId = 1;

  @override
  SaleItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SaleItem(
      name: fields[0] as String,
      costPrice: fields[1] as double,
      sellPrice: fields[2] as double,
      quantity: fields[3] as int,
      discountPerUnit: fields[4] as double,
    );
  }

  @override
  void write(BinaryWriter writer, SaleItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.costPrice)
      ..writeByte(2)
      ..write(obj.sellPrice)
      ..writeByte(3)
      ..write(obj.quantity)
      ..writeByte(4)
      ..write(obj.discountPerUnit);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SaleAdapter extends TypeAdapter<Sale> {
  @override
  final int typeId = 2;

  @override
  Sale read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Sale(
      items: (fields[0] as List).cast<SaleItem>(),
      totalAmount: fields[1] as double,
      totalProfit: fields[2] as double,
      createdAt: fields[3] as DateTime,
      source: fields[4] as SaleSource,
    );
  }

  @override
  void write(BinaryWriter writer, Sale obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.items)
      ..writeByte(1)
      ..write(obj.totalAmount)
      ..writeByte(2)
      ..write(obj.totalProfit)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.source);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SaleSourceAdapter extends TypeAdapter<SaleSource> {
  @override
  final int typeId = 7;

  @override
  SaleSource read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SaleSource.pos;
      case 1:
        return SaleSource.debtPayment;
      default:
        return SaleSource.pos;
    }
  }

  @override
  void write(BinaryWriter writer, SaleSource obj) {
    switch (obj) {
      case SaleSource.pos:
        writer.writeByte(0);
        break;
      case SaleSource.debtPayment:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleSourceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
