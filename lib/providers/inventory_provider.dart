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

  // CHANGED: كل ما يخص الديون أدناه أصبح يعمل على قائمة ديون مُمرَّرة من
  // الواجهة (`List<Debt>`) بدلاً من قراءة صندوق Hive مباشرة وبدون أي فلترة.
  // هذا يسمح لصفحة الجرد بتمرير الديون بعد تطبيق فلتر الفترة الزمنية
  // المختار حالياً فيها (يومي/أسبوعي/شهري/سنوي/الكل) - بالضبط كما تُفلتَر
  // المبيعات والمشتريات في نفس الصفحة - بينما تبقى صفحة "ديون التجار
  // والموردين" تعرض كل الديون دوماً دون أي قيد زمني (وهي التي تستدعي هذه
  // الدوال، إن استدعتها، بقائمة الديون الكاملة بدون فلترة).
  //
  // المتصل (inventory_screen.dart) مسؤول عن استبعاد الديون المسددة
  // (isPaid) قبل التمرير هنا (عبر DebtSupplierProvider.activeDebts)، لذا
  // هذه الدوال لا تُعيد فلترة ذلك بنفسها.

  // إجمالي الديون المستحقة ضمن القائمة المُمرَّرة (بعد فلترة الفترة الزمنية
  // في الواجهة، إن وُجدت).
  double totalCustomerDebtsFor(List<Debt> debts) {
    return debts.fold(0.0, (sum, debt) => sum + debt.remainingAmount);
  }

  // صفوف الأصناف المعلقة ضمن قائمة الديون المُمرَّرة (مع حساب السعر الفعلي
  // بعد الخصم).
  List<Map<String, dynamic>> pendingDebtInventoryRowsFor(List<Debt> debts) {
    List<Map<String, dynamic>> rows = [];
    for (var debt in debts) {
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
            // Capital-recovery status for the item's debt. Payments are
            // allocated capital-first at the debt level (see
            // DebtSupplierProvider.payCustomerDebt), so every item on the
            // same debt shares this status - there's no meaningful
            // per-item capital split since the merchant doesn't choose
            // which specific item's cost a given payment "covers" first.
            'capitalRecovered': debt.isCapitalRecovered,
            'remainingCapital': debt.remainingCapital,
            'remainingProfit': debt.remainingProfit,
          });
        }
      }
    }
    return rows;
  }

  // إجمالي الأرباح المتوقعة من الديون ضمن القائمة المُمرَّرة.
  // ملاحظة: نستخدم `remainingProfit` (الربح الذي لم يتحقق/يُحصَّل بعد)
  // وليس `totalProfit` (الربح الأصلي الكامل) - فبموجب منطق السداد على
  // أساس رأس المال أولاً، يبقى كامل الربح المتوقع "معلقاً" هنا حتى تتجاوز
  // مدفوعات الزبون قيمة رأس المال، ثم يتناقص تدريجياً بعد ذلك فقط.
  double totalExpectedDebtProfitFor(List<Debt> debts) {
    return debts.fold(0.0, (sum, debt) => sum + debt.remainingProfit);
  }

  /// أفضل الأصناف مبيعاً خلال فترة زمنية معينة (بالأيام)، مرتبة تنازلياً
  /// حسب الكمية المباعة.
  ///
  /// ملاحظة هامة: تشمل هذه الدالة فقط عمليات البيع الحقيقية لأصناف فعلية
  /// من نقطة البيع (`SaleSource.pos`). سجلات دفعات الديون
  /// (`SaleSource.debtPayment`) تُستبعد بالكامل، لأنها ليست بيع منتج على
  /// الإطلاق - هي مجرد قيد مالي لتحصيل نقدي يُمثَّل داخلياً بصنف وهمي
  /// باسم "دفعة دين - <اسم الزبون>" (انظر
  /// DebtSupplierProvider.payCustomerDebt) لغرض إظهاره في سجل الحركات
  /// المالية فقط. عدّه كصنف مباع حقيقي هو ما تسبب سابقاً بظهور دفعات
  /// الديون ضمن قائمة "الأكثر مبيعاً". أي مصدر بيع مستقبلي غير
  /// `SaleSource.pos` (سجلات إدارية، تسويات، إلخ) يُستبعد بنفس المنطق.
  ///
  /// [days] عدد الأيام المطلوب احتساب المبيعات خلالها (مثال: 1 = اليوم
  /// فقط، 2 = آخر يومين، 7 = آخر أسبوع).
  /// [topN] أقصى عدد من الأصناف المراد إرجاعها.
  List<MapEntry<String, int>> getBestSellingItems({
    required int days,
    int topN = 10,
  }) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final Map<String, int> soldQuantityByName = {};

    for (var sale in _salesBox.values) {
      // Only real point-of-sale product sales count as "best-selling
      // items". Debt-payment entries (and any other non-POS source added
      // later) are financial/administrative records, not product sales.
      if (sale.source != SaleSource.pos) continue;
      if (sale.createdAt.isBefore(cutoff)) continue;

      for (var item in sale.items) {
        soldQuantityByName[item.name] =
            (soldQuantityByName[item.name] ?? 0) + item.quantity;
      }
    }

    final sortedEntries = soldQuantityByName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedEntries.length > topN) {
      return sortedEntries.sublist(0, topN);
    }
    return sortedEntries;
  }
}