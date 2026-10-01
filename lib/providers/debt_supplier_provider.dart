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

  /// Unique customer names seen across all debts (paid and unpaid),
  /// most-recently-created first. Used to power the autocomplete
  /// customer picker on the POS debt-sale dialog.
  List<String> get knownCustomerNames {
    final sortedByDate = [...debts]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final seen = <String>{};
    final names = <String>[];
    for (final d in sortedByDate) {
      final name = d.customerName.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (seen.add(key)) {
        names.add(name);
      }
    }
    return names;
  }

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
        // NEW: keep the capital (cost) basis merged in step with amount
        // and profit - otherwise a top-up purchase would silently shrink
        // the proportion of this debt considered "capital", skewing the
        // capital-first payment allocation below.
        existingDebt.totalCost += newDebt.totalCost;
        await existingDebt.save();
      } else {
        await _debtBox!.add(newDebt);
      }
      
      loadDebts();
    }
  }

  // عند سداد الدين (جزئياً أو كلياً):
  //
  // المبدأ المحاسبي المطلوب - "رأس المال أولاً، ثم الربح":
  //   1) كل دفعة (جزئية أو كلية) تُضاف فوراً بالكامل إلى إجمالي المبيعات
  //      (إجمالي المبيعات)، بمجرد سدادها - وليس فقط عند سداد الدين بالكامل.
  //   2) طالما لم يُسترد كامل رأس مال الأصناف المباعة على هذا الدين بعد،
  //      فإن الدفعة (أو الجزء المستحق منها) تُحتسب كاسترداد رأس مال فقط،
  //      ولا تُضاف إلى الأرباح.
  //   3) بعد اكتمال استرداد رأس المال بالكامل، أي دفعة لاحقة (أو الجزء
  //      المتبقي من الدفعة الحالية بعد تغطية آخر ما تبقى من رأس المال)
  //      يُحتسب ربحاً محققاً فعلياً، ويُضاف إلى الأرباح بالتوازي مع إضافته
  //      إلى إجمالي المبيعات.
  //
  // مثال: دين بقيمة 100 شيكل (رأس المال = 50، الربح المتوقع = 50):
  //   - دفعة أولى 30 شيكل: إجمالي المبيعات += 30، الأرباح += 0 (كلها رأس
  //     مال، ولا يزال متبقياً 20 من رأس المال).
  //   - دفعة ثانية 40 شيكل: أول 20 منها تُكمل رأس المال (الأرباح += 0)،
  //     والـ 20 المتبقية تتجاوز رأس المال فتُحتسب ربحاً (الأرباح += 20).
  //     إجمالي المبيعات += 40 بالكامل كالعادة.
  //   - دفعة ثالثة 30 شيكل (تُغلق الدين): كل رأس المال مسترد مسبقاً، فكل
  //     الـ 30 شيكل تُحتسب ربحاً (الأرباح += 30)، وإجمالي المبيعات += 30.
  //   - الإجمالي النهائي: إجمالي المبيعات = 100، الأرباح = 50. ✓
  //
  // نستخدم getters الدين (`remainingCapital`) المحسوبة من `paidAmount` مقابل
  // `totalCost` الثابت لمعرفة سقف رأس المال المتبقي قبل كل دفعة - هذا يمنع
  // أي تكرار أو ازدواجية عبر الدفعات المتعددة لأن `paidAmount` تراكمي دائماً.
  //
  // ملاحظة: هذا لا يغيّر شيئاً في المخزون الفعلي (الكمية) - فالصنف يكون قد
  // خرج من المخزون فعلياً لحظة إتمام البيع بالدين (انظر
  // PosProvider.completeSaleAsDebt)؛ هذا المنطق يخص فقط توقيت وتوزيع ظهور
  // المبلغ المسدَّد بين "مبيعات" و"أرباح" في التقارير المالية.
  Future<void> payCustomerDebt(Debt debt, double amount) async {
    if (amount <= 0 || debt.remainingAmount <= 0) return;

    // لا يمكن دفع أكثر من المبلغ المتبقي فعلياً
    if (amount > debt.remainingAmount) {
      amount = debt.remainingAmount;
    }

    // ما تبقى من رأس المال غير المسترد قبل هذه الدفعة تحديداً (مشتق من
    // paidAmount الحالي، قبل إضافة هذه الدفعة إليه).
    final double remainingCapitalBeforePayment = debt.remainingCapital;

    // توزيع هذه الدفعة: الجزء الأول (حتى سقف رأس المال المتبقي) يُعتبر
    // استرداد رأس مال فقط، وأي فائض بعد ذلك يُعتبر ربحاً محققاً الآن.
    final double capitalPortion = amount <= remainingCapitalBeforePayment
        ? amount
        : remainingCapitalBeforePayment;
    final double profitPortion = amount - capitalPortion;

    // نسجل دفعة بيع تمثل هذه العملية بالكامل - `totalAmount` هو المبلغ
    // الكامل المدفوع (يدخل بالكامل ضمن إجمالي المبيعات كما هو مطلوب)،
    // بينما `totalProfit` هو فقط الجزء الذي تجاوز رأس المال المتبقي (الجزء
    // الذي يُحتسب ربحاً فعلياً الآن). نستخدم صنفاً تلخيصياً واحداً (وليس
    // تقسيم الأصناف الأصلية تناسبياً) لأن التوزيع هنا على مستوى الدين ككل.
    final salesBox = Hive.box<Sale>('sales');
    try {
      await salesBox.add(Sale(
        items: [
          SaleItem(
            name: 'دفعة دين - ${debt.customerName}',
            costPrice: capitalPortion,
            sellPrice: amount,
            quantity: 1,
            discountPerUnit: 0.0,
          ),
        ],
        totalAmount: amount,
        totalProfit: profitPortion,
        createdAt: DateTime.now(),
        // مصدر مميز لدفعات الديون حتى تُستبعد من "الأكثر مبيعاً" (التي
        // يجب أن تعكس أصنافاً حقيقية فقط)، بينما تبقى محسوبة ضمن إجمالي
        // المبيعات/الأرباح لأن تلك الحسابات تجمع كل الفواتير بغض النظر
        // عن المصدر.
        source: SaleSource.debtPayment,
      ));
    } catch (e, stack) {
      debugPrint('[DebtSupplierProvider] Failed to record debt-payment sale: $e');
      debugPrint('$stack');
      rethrow;
    }

    // `debt.saleItems`/`debt.totalCost`/`debt.totalProfit` تبقى كما هي
    // (القيم الأصلية الكاملة وقت البيع) - فقط `paidAmount`/`remainingAmount`
    // يتغيران. كل ما يخص "كم تم استرداده من رأس المال/ربح حتى الآن" يُشتق
    // ديناميكياً من `paidAmount` عبر getters على Debt، بدلاً من تعديل هذه
    // الحقول مباشرة في كل دفعة - هذا يمنع أي تراكم لأخطاء التقريب أو
    // الازدواجية عبر الدفعات المتعددة.
    debt.paidAmount += amount;
    debt.remainingAmount -= amount;

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