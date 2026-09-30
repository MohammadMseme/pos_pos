import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/debt.dart';

class InventoryProvider extends ChangeNotifier {
  Box<Sale> get _salesBox => Hive.box<Sale>('sales');
  Box<Product> get _productsBox => Hive.box<Product>('products');

  List<Sale> get allSales => _salesBox.values.toList();

  // المنتجات التي قارب مخزونها على النفاذ (أقل من 5 قطع)
  List<Product> get lowStockProducts {
    return _productsBox.values.where((p) => p.stockQuantity <= 5).toList();
  }

  double get totalRevenue {
    return _salesBox.values.fold(0.0, (sum, sale) => sum + sale.totalAmount);
  }

  double get totalProfit {
    return _salesBox.values.fold(0.0, (sum, sale) => sum + sale.totalProfit);
  }

  // إجمالي الديون الحالية للزبائن (تستثني الديون المسددة بالكامل والمؤرشفة)
  double get totalCustomerDebts {
    final debtBox = Hive.box<Debt>('debts');
    return debtBox.values
        .where((d) => !d.isPaid)
        .fold(0.0, (sum, debt) => sum + debt.remainingAmount);
  }

  // صفوف الأصناف المعلقة في الديون الحالية (مع حساب السعر الفعلي بعد الخصم)
  List<Map<String, dynamic>> get pendingDebtInventoryRows {
    final debtBox = Hive.box<Debt>('debts');
    List<Map<String, dynamic>> rows = [];
    for (var debt in debtBox.values) {
      if (debt.isPaid) continue;

      double ratio = debt.totalAmount > 0 ? (debt.remainingAmount / debt.totalAmount) : 0.0;
      for (var item in debt.saleItems) {
        int remainingQty = (item.quantity * ratio).round();
        if (remainingQty > 0 || debt.saleItems.length == 1) {
          int finalQty = remainingQty > 0 ? remainingQty : item.quantity;
          
          double actualUnitPrice = item.sellPrice - item.discountPerUnit;
          double totalActualPrice = actualUnitPrice * finalQty;

          rows.add({
            'customerName': debt.customerName,
            'name': item.name,
            'quantity': finalQty,
            'actualPrice': totalActualPrice,
          });
        }
      }
    }
    return rows;
  }

  // إجمالي الأرباح المتوقعة من الديون المعلقة (غير المسددة فقط)
  double get totalExpectedDebtProfit {
    final debtBox = Hive.box<Debt>('debts');
    return debtBox.values
        .where((d) => !d.isPaid)
        .fold(0.0, (sum, debt) => sum + debt.totalProfit);
  }
}