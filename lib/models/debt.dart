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

  // NEW: capital / رأس المال — the cost-basis (sum of costPrice * quantity)
  // of the items sold on this debt. This is what makes "capital-first"
  // repayment allocation possible: every payment is measured against this
  // fixed number to decide how much of it is capital recovery vs realized
  // profit (see DebtSupplierProvider.payCustomerDebt).
  //
  // Defaults to `totalAmount - totalProfit` when not explicitly supplied,
  // which is mathematically identical to summing costPrice*quantity over
  // the sale items (revenue - profit = cost). This also keeps old/callers
  // that don't pass it explicitly correct without extra bookkeeping.
  @HiveField(9)
  double totalCost;

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
    double? totalCost,
  }) : totalCost = totalCost ?? (totalAmount - totalProfit);

  /// Capital (cost) recovered so far from payments made to date. Clamped
  /// between 0 and [totalCost] - a payment can never "over-recover"
  /// capital; anything beyond [totalCost] is profit (see
  /// [profitRecovered]).
  double get capitalRecovered {
    if (paidAmount <= 0) return 0.0;
    return paidAmount >= totalCost ? totalCost : paidAmount;
  }

  /// Capital still outstanding - the part of the cost basis not yet
  /// recovered from the customer.
  double get remainingCapital {
    final double remaining = totalCost - capitalRecovered;
    return remaining > 0 ? remaining : 0.0;
  }

  /// Whether every ILS of capital (cost price) tied up in this debt's
  /// items has been recovered yet. This is debt-wide rather than per-item
  /// because payments are allocated capital-first across the whole debt,
  /// not per line item - drives the "تم استرداد رأس المال" label shown in
  /// the inventory/stock page.
  bool get isCapitalRecovered => paidAmount >= totalCost;

  /// Profit actually realized/collected so far - i.e. any payment amount
  /// beyond what was needed to fully recover capital.
  double get profitRecovered {
    final double excess = paidAmount - totalCost;
    return excess > 0 ? excess : 0.0;
  }

  /// Profit not yet collected from the customer. Until capital is fully
  /// recovered this equals the full [totalProfit] (nothing has been
  /// "promoted" from owed-balance to realized-profit yet); it only shrinks
  /// once payments start exceeding [totalCost]. This is what should keep
  /// counting toward "أرباح الديون" (expected/outstanding debt profit)
  /// until the debt is fully settled.
  double get remainingProfit {
    final double remaining = totalProfit - profitRecovered;
    return remaining > 0 ? remaining : 0.0;
  }
}