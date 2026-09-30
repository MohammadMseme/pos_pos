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

class PosProvider extends ChangeNotifier {
  List<CartItem> cart = [];

  double get totalAmount =>
      cart.fold(0.0, (sum, item) => sum + item.totalWithDiscount);

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

  /// Returns the first cart item (if any) whose requested quantity now
  /// exceeds its product's current stock, so callers can abort cleanly
  /// instead of committing a partial/negative-stock transaction.
  CartItem? _firstItemExceedingStock() {
    for (final item in cart) {
      if (item.quantity > item.product.stockQuantity) {
        return item;
      }
    }
    return null;
  }

  // إتمام البيع كاش
  Future<bool> completeSale() async {
    if (cart.isEmpty) return false;

    if (_firstItemExceedingStock() != null) {
      // Stock changed under us (e.g. another sale) since items were added
      // to the cart. Abort rather than oversell or partially commit.
      return false;
    }

    final List<SaleItem> saleItems = cart
        .map((e) => SaleItem(
              name: e.name,
              costPrice: e.costPrice,
              sellPrice: e.sellPrice,
              quantity: e.quantity,
              discountPerUnit: e.discountPerUnit,
            ))
        .toList();

    double totalProfit = cart.fold(
        0.0, (sum, e) => sum + (e.totalWithDiscount - (e.costPrice * e.quantity)));

    final salesBox = Hive.box<Sale>('sales');
    final sale = Sale(
      items: saleItems,
      totalAmount: totalAmount,
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
      for (var item in cart) {
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

    clearCart();
    return true;
  }

  // إتمام البيع بالدين مع تمرير تفاصيل الأصناف والأرباح لكائن الدين الجديد
  Future<bool> completeSaleAsDebt(String customerName, DebtSupplierProvider debtProvider) async {
    if (cart.isEmpty || customerName.trim().isEmpty) return false;

    if (_firstItemExceedingStock() != null) {
      return false;
    }

    List<String> itemsTakenList = cart
        .map((item) => '${item.name} (${item.quantity} قطعة)')
        .toList();

    final List<SaleItem> saleItems = cart
        .map((e) => SaleItem(
              name: e.name,
              costPrice: e.costPrice,
              sellPrice: e.sellPrice,
              quantity: e.quantity,
              discountPerUnit: e.discountPerUnit,
            ))
        .toList();

    double totalProfit = cart.fold(
        0.0, (sum, e) => sum + (e.totalWithDiscount - (e.costPrice * e.quantity)));

    final newDebt = Debt(
      customerName: customerName.trim(),
      totalAmount: totalAmount,
      paidAmount: 0.0,
      remainingAmount: totalAmount,
      itemsTaken: itemsTakenList,
      createdAt: DateTime.now(),
      saleItems: saleItems,
      totalProfit: totalProfit,
    );

    // ATOMICITY FIX: persist the Debt record FIRST, same reasoning as
    // completeSale() above - it's the durable source of truth for this
    // transaction before stock is touched.
    await debtProvider.addDebt(newDebt);

    try {
      for (var item in cart) {
        item.product.stockQuantity -= item.quantity;
        await item.product.save();
      }
    } catch (e, stack) {
      debugPrint('[PosProvider] Stock decrement failed after debt was recorded: $e');
      debugPrint('$stack');
      rethrow;
    }

    clearCart();
    return true;
  }
}