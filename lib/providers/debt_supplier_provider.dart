import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/debt.dart';
import '../models/supplier.dart';
import '../models/sale.dart';

class DebtSupplierProvider extends ChangeNotifier {
  Box<Debt>? _debtBox;
  Box<Supplier>? _supplierBox;

  List<Debt> debts = [];
  List<Supplier> suppliers = [];

  /// Debts that are still outstanding. Paid-off debts are no longer
  /// deleted (see payCustomerDebt below) - they are archived via
  /// `isPaid = true` so history is preserved - so screens that only care
  /// about debts a customer still owes should read this instead of the
  /// raw `debts` list.
  List<Debt> get activeDebts => debts.where((d) => !d.isPaid).toList();

  DebtSupplierProvider() {
    _init();
  }

  Future<void> _init() async {
    _debtBox = Hive.isBoxOpen('debts') 
        ? Hive.box<Debt>('debts') 
        : await Hive.openBox<Debt>('debts');
        
    _supplierBox = Hive.isBoxOpen('suppliers') 
        ? Hive.box<Supplier>('suppliers') 
        : await Hive.openBox<Supplier>('suppliers');

    loadDebts();
    loadSuppliers();
  }

  void loadDebts() {
    if (_debtBox != null && _debtBox!.isOpen) {
      debts = _debtBox!.values.toList();
      notifyListeners();
    }
  }

  void loadSuppliers() {
    if (_supplierBox != null && _supplierBox!.isOpen) {
      suppliers = _supplierBox!.values.toList();
      notifyListeners();
    }
  }

  // إضافة دين مع دمج الأصناف والأرباح في حال وجود نفس الزبون مسبقاً
  Future<void> addDebt(Debt newDebt) async {
    if (_debtBox != null && _debtBox!.isOpen) {
      Debt? existingDebt;
      try {
        // Only merge into an existing debt that is still outstanding.
        // A customer who fully paid off a previous debt (now archived
        // with isPaid = true) should get a fresh debt record, not have
        // their new purchase silently merged into old, closed history.
        existingDebt = _debtBox!.values.firstWhere(
          (d) =>
              !d.isPaid &&
              d.customerName.trim().toLowerCase() ==
                  newDebt.customerName.trim().toLowerCase(),
        );
      } catch (_) {
        existingDebt = null;
      }

      if (existingDebt != null) {
        existingDebt.totalAmount += newDebt.totalAmount;
        existingDebt.remainingAmount += newDebt.remainingAmount;
        existingDebt.itemsTaken.addAll(newDebt.itemsTaken);
        existingDebt.saleItems.addAll(newDebt.saleItems);
        existingDebt.totalProfit += newDebt.totalProfit;
        await existingDebt.save();
      } else {
        await _debtBox!.add(newDebt);
      }
      
      loadDebts();
    }
  }

  // عند سداد الدين: يتم تسجيل الجزء المسدد كعملية بيع حقيقية في الجرد والأرباح
  Future<void> payCustomerDebt(Debt debt, double amount) async {
    if (amount <= 0 || debt.totalAmount <= 0) return;

    // حساب نسبة المبلغ المسدد من إجمالي الدين
    double paymentRatio = amount / debt.totalAmount;
    if (paymentRatio > 1.0) paymentRatio = 1.0;

    // استخراج الأصناف والأرباح الخاصة بالدفعة المسددة
    List<SaleItem> paidSaleItems = debt.saleItems.map((item) {
      int proportionalQty = (item.quantity * paymentRatio).round();
      if (proportionalQty < 1 && item.quantity > 0 && paymentRatio > 0) {
        proportionalQty = 1;
      }
      if (proportionalQty > item.quantity) proportionalQty = item.quantity;

      return SaleItem(
        name: item.name,
        costPrice: item.costPrice,
        sellPrice: item.sellPrice,
        quantity: proportionalQty,
        discountPerUnit: item.discountPerUnit,
      );
    }).where((item) => item.quantity > 0).toList();

    double paidProfit = debt.totalProfit * paymentRatio;
    double paidTotalAmount = debt.totalAmount * paymentRatio;

    // إرسال هذه الدفعة لصندوق المبيعات لتظهر في الأرباح والجرد بشكل طبيعي
    if (paidSaleItems.isNotEmpty) {
      final salesBox = Hive.box<Sale>('sales');
      try {
        await salesBox.add(Sale(
          items: paidSaleItems,
          totalAmount: paidTotalAmount,
          totalProfit: paidProfit,
          createdAt: DateTime.now(),
          // Marked distinctly from a real POS sale so reports can tell
          // debt collections apart from register sales.
          source: SaleSource.debtPayment,
        ));
      } catch (e, stack) {
        debugPrint('[DebtSupplierProvider] Failed to record debt-payment sale: $e');
        debugPrint('$stack');
        rethrow;
      }
    }

    debt.paidAmount += amount;
    debt.remainingAmount = debt.totalAmount - debt.paidAmount;

    if (debt.remainingAmount <= 0) {
      // Archive instead of delete: preserve debt/customer history so it
      // remains queryable (e.g. "how much has this customer ever owed").
      debt.remainingAmount = 0;
      debt.isPaid = true;
    }
    await debt.save();

    loadDebts();
  }

  Future<void> addOrUpdateSupplierDebt(String supplierName, double amount, String note) async {
    if (_supplierBox != null && _supplierBox!.isOpen) {
      Supplier? existingSupplier;
      try {
        existingSupplier = _supplierBox!.values.firstWhere(
          (s) => s.name.trim().toLowerCase() == supplierName.trim().toLowerCase(),
        );
      } catch (_) {
        existingSupplier = null;
      }

      if (existingSupplier != null) {
        existingSupplier.remainingAmount += amount;
        if (note.trim().isNotEmpty) {
          existingSupplier.notes = existingSupplier.notes.isEmpty 
              ? note 
              : '${existingSupplier.notes} | $note';
        }
        await existingSupplier.save();
      } else {
        final newSupplier = Supplier(
          name: supplierName.trim(),
          remainingAmount: amount,
          notes: note.trim(),
        );
        await _supplierBox!.add(newSupplier);
      }
      loadSuppliers();
    }
  }

  Future<void> addSupplier(Supplier supplier) async {
    if (_supplierBox != null && _supplierBox!.isOpen) {
      _supplierBox!.add(supplier);
      loadSuppliers();
    }
  }

  // CHANGED: now takes the Supplier object directly instead of a raw list
  // index. Indexing into `suppliers` was fragile - if the cached list is
  // reloaded or reordered between when the UI captured the index and when
  // this method runs, the wrong supplier could be paid. HiveObjects carry
  // their own box reference, so operating on the object directly is both
  // simpler and safe regardless of list ordering.
  Future<void> addSupplierPayment(Supplier supplier, SupplierPayment payment) async {
    supplier.payments.add(payment);
    supplier.remainingAmount -= payment.amountPaid;

    if (supplier.remainingAmount <= 0) {
      supplier.remainingAmount = 0; // avoid a meaningless negative balance
      await supplier.delete();
    } else {
      await supplier.save();
    }
    loadSuppliers();
  }
}