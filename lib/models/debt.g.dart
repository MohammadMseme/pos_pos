// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'debt.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************
//
// NOTE: This file is normally produced by `build_runner`/`hive_generator`.
// It has been hand-updated here to add field 9 (`totalCost`) to the Debt
// model. If you regenerate this file later with `build_runner`, make sure
// the generated `read()` keeps the same null-safe fallback for field 9 so
// that debts saved by earlier app versions (without this field) still load
// correctly instead of crashing on a missing key.

class DebtAdapter extends TypeAdapter<Debt> {
  @override
  final int typeId = 5;

  @override
  Debt read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };

    final double totalAmount = fields[1] as double;
    final double totalProfit = fields[7] as double;

    return Debt(
      customerName: fields[0] as String,
      totalAmount: totalAmount,
      paidAmount: fields[2] as double,
      remainingAmount: fields[3] as double,
      itemsTaken: (fields[4] as List).cast<String>(),
      createdAt: fields[5] as DateTime,
      saleItems: (fields[6] as List).cast<SaleItem>(),
      totalProfit: totalProfit,
      isPaid: fields[8] as bool,
      // Field 9 (totalCost) will be absent on debts written before this
      // field existed. Falling back to `totalAmount - totalProfit`
      // reconstructs the same value the constructor's default would have
      // produced, so old debts behave exactly as if totalCost had always
      // been stored.
      totalCost: fields[9] == null
          ? (totalAmount - totalProfit)
          : fields[9] as double,
    );
  }

  @override
  void write(BinaryWriter writer, Debt obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.customerName)
      ..writeByte(1)
      ..write(obj.totalAmount)
      ..writeByte(2)
      ..write(obj.paidAmount)
      ..writeByte(3)
      ..write(obj.remainingAmount)
      ..writeByte(4)
      ..write(obj.itemsTaken)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.saleItems)
      ..writeByte(7)
      ..write(obj.totalProfit)
      ..writeByte(8)
      ..write(obj.isPaid)
      ..writeByte(9)
      ..write(obj.totalCost);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DebtAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}