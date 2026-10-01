import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/debt.dart';
import 'debt_supplier_provider.dart';

class CartItem {
  final Product product;
  String name;
  double costPrice;
  double sellPrice;
  int quantity;

  // Renamed from `discount` -> `lineDiscountTotal`.
  // This is the TOTAL discount for the whole line (sellPrice * quantity),
  // NOT a per-unit amount. `SaleItem.discountPerUnit` (see sale.dart) is
  // the per-unit equivalent used once the sale is recorded. The two used
  // to share the name `discount` while meaning different things, which
  // was a data-integrity landmine - see `discountPerUnit` getter below
  // for the conversion between the two.
  double lineDiscountTotal;

  CartItem({
    required this.product,
    required this.name,
    required this.costPrice,
    required this.sellPrice,
    required this.quantity,
    this.lineDiscountTotal = 0.0,
  });

  double get totalWithDiscount => (sellPrice * quantity) - lineDiscountTotal;
  double get discountPerUnit => quantity > 0 ? (lineDiscountTotal / quantity) : 0.0;
}

// NEW: a single POS "تبويبة" (tab) / session - its own fully independent
// cart. This is what makes "نقطة بيع معلقة" (a suspended/held sale)
// possible: the cashier can start ringing up a second customer on a new
// tab while a first customer's sale sits untouched, cart and all, on
// another tab - switching back to it later picks up exactly where it was
// left, with nothing merged or lost.
class PosSession {
  String label;
  List<CartItem> cart = [];

  PosSession({required this.label});
}

class PosProvider extends ChangeNotifier {
  // CHANGED: the provider now holds a list of independent POS sessions
  // (tabs) instead of one single cart. Every session owns its own cart,
  // so opening, switching between, or closing tabs never discards or
  // mixes items, quantities or discounts between them. The first session
  // is created eagerly, so a cashier who never opens a second tab sees
  // exactly the same behavior as before this feature existed.
  List<PosSession> sessions = [PosSession(label: 'فاتورة 1')];
  int currentSessionIndex = 0;

  // Monotonically increasing and never reused - even after a tab is
  // closed - so two tabs open at the same time can never end up with a
  // duplicate label.
  int _nextSessionNumber = 2;

  PosSession get _activeSession => sessions[currentSessionIndex];

  // BACKWARD-COMPATIBLE API: `cart`, `totalAmount` and every cart-mutating
  // method below now transparently resolve to the ACTIVE session. Nothing
  // elsewhere in the app (pos_screen.dart) needs to change how it calls
  // this provider - `posProvider.cart` simply now means "the cart of
  // whichever tab is currently selected".
  List<CartItem> get cart => _activeSession.cart;

  double get totalAmount =>
      cart.fold(0.0, (sum, item) => sum + item.totalWithDiscount);

  // --- إدارة التبويبات (الجلسات المعلقة) -----------------------------

  int get sessionCount => sessions.length;

  String get currentSessionLabel => _activeSession.label;

  String labelFor(int index) => sessions[index].label;

  int cartCountFor(int index) => sessions[index].cart.length;

  double totalAmountFor(int index) =>
      sessions[index].cart.fold(0.0, (sum, item) => sum + item.totalWithDiscount);

  /// فتح نافذة/تبويبة نقطة بيع جديدة بسلة مستقلة تماماً، والتحويل إليها
  /// فوراً. أي سلة معلقة في تبويبات أخرى مفتوحة حالياً تبقى كما هي دون أي
  /// تأثير - هذا ما يسمح بتعليق بيعة حالية والبدء ببيعة جديدة متزامنة.
  void addNewSession() {
    sessions.add(PosSession(label: 'فاتورة $_nextSessionNumber'));
    _nextSessionNumber++;
    currentSessionIndex = sessions.length - 1;
    notifyListeners();
  }

  /// التبديل إلى تبويبة أخرى مفتوحة مسبقاً لعرض/استكمال سلتها الخاصة.
  void switchToSession(int index) {
    if (index < 0 || index >= sessions.length) return;
    currentSessionIndex = index;
    notifyListeners();
  }

  /// إغلاق تبويبة معينة. يُستدعى هذا من الواجهة بعد تأكيد المستخدم في حال
  /// كانت التبويبة تحتوي على أصناف لم تُباع بعد (لتجنّب فقدان بيانات غير
  /// مقصود). يتم الاحتفاظ بتبويبة واحدة مفتوحة دائماً على الأقل - لا يمكن
  /// إغلاق آخر تبويبة متبقية.
  void closeSession(int index) {
    if (sessions.length <= 1) return;
    if (index < 0 || index >= sessions.length) return;

    sessions.removeAt(index);

    if (currentSessionIndex >= sessions.length) {
      // كانت التبويبة النشطة هي الأخيرة وتم حذفها - التحويل لما قبلها.
      currentSessionIndex = sessions.length - 1;
    } else if (index < currentSessionIndex) {
      // تبويبة قبل النشطة أُغلقت - تعديل الفهرس ليبقى مشيراً لنفس التبويبة.
      currentSessionIndex -= 1;
    }
    // إن كانت `index > currentSessionIndex`: لا تغيير مطلوب، التبويبة
    // النشطة لم تتأثر. وإن كانت `index == currentSessionIndex` ولم تكن
    // الأخيرة: التبويبة التي تنزلق لهذا الموضع تصبح هي النشطة تلقائياً.

    notifyListeners();
  }

  // ---------------------------------------------------------------------

  String? addToCart(Product product) {
    int index = cart.indexWhere((item) => item.product.key == product.key);
    if (index != -1) {
      if (cart[index].quantity + 1 > product.stockQuantity) {
        return 'الكمية المطلوبة تتجاوز المخزون المتاح!';
      }
      cart[index].quantity += 1;
    } else {
      if (product.stockQuantity < 1) {
        return 'المنتج غير متوفر في المخزون!';
      }
      cart.add(CartItem(
        product: product,
        name: product.name,
        costPrice: product.costPrice,
        sellPrice: product.sellPrice,
        quantity: 1,
      ));
    }
    notifyListeners();
    return null;
  }

  void updateQuantity(int index, int newQty) {
    if (newQty > 0 && newQty <= cart[index].product.stockQuantity) {
      cart[index].quantity = newQty;
      notifyListeners();
    }
  }

  void updateDiscount(int index, double newDiscount) {
    cart[index].lineDiscountTotal = newDiscount;
    notifyListeners();
  }

  void removeItem(int index) {
    cart.removeAt(index);
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    notifyListeners();
  }

  /// Returns the first cart item (if any) in [cartList] whose requested
  /// quantity now exceeds its product's current stock, so callers can
  /// abort cleanly instead of committing a partial/negative-stock
  /// transaction.
  CartItem? _firstItemExceedingStockIn(List<CartItem> cartList) {
    for (final item in cartList) {
      if (item.quantity > item.product.stockQuantity) {
        return item;
      }
    }
    return null;
  }

  // إتمام البيع كاش
  //
  // IMPORTANT: captures `_activeSession` into a local `session` variable
  // up front and operates on `session.cart` throughout, rather than the
  // ambient `cart` getter. This matters now that multiple tabs exist: the
  // `await`s below (writing the sale, then saving each product's stock)
  // yield control back to the UI, during which the cashier could tap a
  // different tab and change `currentSessionIndex`. Using the captured
  // `session` reference guarantees this method always finishes acting on
  // the exact tab that was active when the button was pressed - including
  // clearing the correct cart at the end - never whichever tab happens to
  // be active by the time the awaits resolve.
  Future<bool> completeSale() async {
    final session = _activeSession;
    final targetCart = session.cart;

    if (targetCart.isEmpty) return false;

    if (_firstItemExceedingStockIn(targetCart) != null) {
      // Stock changed under us (e.g. another sale) since items were added
      // to the cart. Abort rather than oversell or partially commit.
      return false;
    }

    final List<SaleItem> saleItems = targetCart
        .map((e) => SaleItem(
              name: e.name,
              costPrice: e.costPrice,
              sellPrice: e.sellPrice,
              quantity: e.quantity,
              discountPerUnit: e.discountPerUnit,
            ))
        .toList();

    double totalProfit = targetCart.fold(
        0.0, (sum, e) => sum + (e.totalWithDiscount - (e.costPrice * e.quantity)));
    double totalAmountValue =
        targetCart.fold(0.0, (sum, e) => sum + e.totalWithDiscount);

    final salesBox = Hive.box<Sale>('sales');
    final sale = Sale(
      items: saleItems,
      totalAmount: totalAmountValue,
      totalProfit: totalProfit,
      createdAt: DateTime.now(),
      source: SaleSource.pos,
    );

    // ATOMICITY FIX: persist the Sale record FIRST. It is the durable
    // source of truth that "this transaction happened". If the app
    // crashes after this line but before stock is decremented below,
    // the sale is still on disk and stock can be reconciled against it.
    // The previous order (decrement stock, then write the sale) meant a
    // crash mid-operation permanently lost stock with no record of why.
    await salesBox.add(sale);

    try {
      for (var item in targetCart) {
        item.product.stockQuantity -= item.quantity;
        await item.product.save();
      }
    } catch (e, stack) {
      debugPrint('[PosProvider] Stock decrement failed after sale was recorded: $e');
      debugPrint('$stack');
      // The sale is already durable and will not be lost; stock may be
      // temporarily inconsistent until reconciled. Rethrow so the calling
      // UI can inform the user, rather than silently reporting success.
      rethrow;
    }

    session.cart.clear();
    notifyListeners();
    return true;
  }

  // إتمام البيع بالدين مع تمرير تفاصيل الأصناف والأرباح لكائن الدين الجديد
  //
  // Same reasoning as completeSale() above: captures the target session
  // explicitly so a tab switch mid-await can never cause the wrong tab's
  // cart to be read or cleared.
  Future<bool> completeSaleAsDebt(String customerName, DebtSupplierProvider debtProvider) async {
    final session = _activeSession;
    final targetCart = session.cart;

    if (targetCart.isEmpty || customerName.trim().isEmpty) return false;

    if (_firstItemExceedingStockIn(targetCart) != null) {
      return false;
    }

    List<String> itemsTakenList = targetCart
        .map((item) => '${item.name} (${item.quantity} قطعة)')
        .toList();

    final List<SaleItem> saleItems = targetCart
        .map((e) => SaleItem(
              name: e.name,
              costPrice: e.costPrice,
              sellPrice: e.sellPrice,
              quantity: e.quantity,
              discountPerUnit: e.discountPerUnit,
            ))
        .toList();

    double totalProfit = targetCart.fold(
        0.0, (sum, e) => sum + (e.totalWithDiscount - (e.costPrice * e.quantity)));
    double totalAmountValue =
        targetCart.fold(0.0, (sum, e) => sum + e.totalWithDiscount);

    // Capital / رأس المال - the cost basis of everything going out on this
    // debt. Passed explicitly (rather than left to Debt's default of
    // `totalAmount - totalProfit`) so it's unambiguous and easy to audit:
    // this is exactly what the merchant paid for the goods, and it's what
    // DebtSupplierProvider.payCustomerDebt uses to decide how much of each
    // repayment is capital recovery vs realized profit.
    double totalCost = targetCart.fold(0.0, (sum, e) => sum + (e.costPrice * e.quantity));

    final newDebt = Debt(
      customerName: customerName.trim(),
      totalAmount: totalAmountValue,
      paidAmount: 0.0,
      remainingAmount: totalAmountValue,
      itemsTaken: itemsTakenList,
      createdAt: DateTime.now(),
      saleItems: saleItems,
      totalProfit: totalProfit,
      totalCost: totalCost,
    );

    // ATOMICITY FIX: persist the Debt record FIRST, same reasoning as
    // completeSale() above - it's the durable source of truth for this
    // transaction before stock is touched.
    await debtProvider.addDebt(newDebt);

    try {
      for (var item in targetCart) {
        item.product.stockQuantity -= item.quantity;
        await item.product.save();
      }
    } catch (e, stack) {
      debugPrint('[PosProvider] Stock decrement failed after debt was recorded: $e');
      debugPrint('$stack');
      rethrow;
    }

    session.cart.clear();
    notifyListeners();
    return true;
  }
}