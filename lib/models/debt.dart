import 'package:hive/hive.dart';
import 'sale.dart';

part 'debt.g.dart';

@HiveType(typeId: 5)
class Debt extends HiveObject {
  @HiveField(0)
  String customerName;

  @HiveField(1)
  double totalAmount;

  @HiveField(2)
  double paidAmount;

  @HiveField(3)
  double remainingAmount;

  @HiveField(4)
  List<String> itemsTaken;

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6)
  List<SaleItem> saleItems; 

  @HiveField(7)
  double totalProfit; 

  @HiveField(8)
  bool isPaid;

  Debt({
    required this.customerName,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.itemsTaken,
    required this.createdAt,
    this.saleItems = const [], 
    this.totalProfit = 0.0,    
    this.isPaid = false,
  });
}