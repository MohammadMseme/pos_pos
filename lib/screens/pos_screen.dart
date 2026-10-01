import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import '../providers/product_provider.dart';
import '../providers/debt_supplier_provider.dart';

// NEW: dedicated widget for the customer-name autocomplete field used in
// the debt/deferred-invoice dialog.
//
// Why this is its own StatefulWidget rather than an inline Autocomplete:
// `Autocomplete<String>` (and the `RawAutocomplete` it wraps) asserts that
// `focusNode` and `textEditingController` are either BOTH supplied or BOTH
// left null - passing just a controller (as the previous version did)
// trips `(focusNode == null) == (textEditingController == null)` and
// throws during build. Flutter's fallback error rendering for a failed
// build has no real height constraint, which is what produced the
// "Bottom overflowed by 9957 pixels" error alongside the assertion - it
// was a symptom of the same root cause, not a second bug.
// Wrapping the paired FocusNode in a State object also means it gets
// created exactly once and properly disposed, instead of being a
// throwaway local variable inside a dialog builder.
class _DebtCustomerAutocomplete extends StatefulWidget {
  final TextEditingController nameController;
  final List<String> knownCustomerNames;

  const _DebtCustomerAutocomplete({
    required this.nameController,
    required this.knownCustomerNames,
  });

  @override
  State<_DebtCustomerAutocomplete> createState() => _DebtCustomerAutocompleteState();
}

class _DebtCustomerAutocompleteState extends State<_DebtCustomerAutocomplete> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      // Paired together - fixes the assertion error.
      textEditingController: widget.nameController,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) {
          // Show the full known-customer list when the field is focused
          // but empty, so cashiers can browse it too.
          return widget.knownCustomerNames;
        }
        return widget.knownCustomerNames.where(
          (name) => name.toLowerCase().contains(query),
        );
      },
      onSelected: (String selection) {
        widget.nameController.text = selection;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'اكتب اسم الزبون أو اختر من القائمة',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_search),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final optionsList = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              // Hard cap on the dropdown's height, regardless of how many
              // customers match - this is what actually prevents the
              // overflow, rather than a hand-computed `length * 48.0`
              // pixel height that grows without bound as the customer
              // list grows.
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 328),
              child: optionsList.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'لا يوجد زبون مطابق',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      // shrinkWrap + the ConstrainedBox above together
                      // guarantee this list always sizes itself within a
                      // bounded box, however many options there are.
                      shrinkWrap: true,
                      itemCount: optionsList.length,
                      itemBuilder: (context, index) {
                        final option = optionsList[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.person, size: 18, color: Colors.orange),
                          title: Text(option),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _processSearchOrBarcode(String value, ProductProvider productProvider, PosProvider posProvider) {
    final query = value.trim();
    if (query.isEmpty) return;

    try {
      final exactBarcodeMatch = productProvider.products.firstWhere(
        (p) => p.barcode.toLowerCase() == query.toLowerCase(),
      );
      _addToCartAndReset(exactBarcodeMatch, posProvider);
      return;
    } catch (_) {}

    final matchingProducts = productProvider.products.where((p) =>
        p.name.toLowerCase().contains(query.toLowerCase()) ||
        p.barcode.toLowerCase().contains(query.toLowerCase())).toList();

    if (matchingProducts.length == 1) {
      _addToCartAndReset(matchingProducts.first, posProvider);
    } else if (matchingProducts.length > 1) {
      _showProductOptionsDialog(context, matchingProducts, posProvider);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم يتم العثور على أي منتج بهذا الاسم أو الرمز'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _addToCartAndReset(product, PosProvider posProvider) {
    String? warning = posProvider.addToCart(product);
    if (warning != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(warning),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
    _searchController.clear();
    _searchFocusNode.requestFocus();
  }

  void _showProductOptionsDialog(BuildContext context, List products, PosProvider posProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر المنتج المطابق'),
        content: SizedBox(
          width: 300,
          height: 250,
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              final p = products[index];
              return ListTile(
                title: Text(p.name),
                subtitle: Text('الباركود: ${p.barcode} | السعر: ${p.sellPrice} شيكل'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addToCartAndReset(p, posProvider);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  // NEW: شريط التبويبات (الفواتير المعلقة) - يسمح بفتح أكثر من نافذة بيع
  // متزامنة، كل منها بسلة مستقلة تماماً، والتبديل بينها دون فقدان أي
  // بيانات في أي منها (انظر PosSession/PosProvider في pos_provider.dart).
  Widget _buildSessionTabsBar(BuildContext context, PosProvider posProvider) {
    return Container(
      height: 52,
      color: Colors.grey.shade200,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: posProvider.sessionCount,
              itemBuilder: (context, index) {
                final bool isActive = index == posProvider.currentSessionIndex;
                final int itemCount = posProvider.cartCountFor(index);
                final bool canClose = posProvider.sessionCount > 1;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => posProvider.switchToSession(index),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.blue : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive ? Colors.blue.shade700 : Colors.grey.shade400,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 16,
                            color: isActive ? Colors.white : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            posProvider.labelFor(index),
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (itemCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.white : Colors.blue,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$itemCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isActive ? Colors.blue.shade700 : Colors.white,
                                ),
                              ),
                            ),
                          ],
                          if (canClose) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => _handleCloseSession(context, posProvider, index),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: isActive ? Colors.white : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: IconButton(
              icon: const Icon(Icons.add_box, color: Colors.blue),
              tooltip: 'فتح نقطة بيع جديدة (معلقة)',
              onPressed: () => posProvider.addNewSession(),
            ),
          ),
        ],
      ),
    );
  }

  // تأكيد إغلاق تبويبة تحتوي على أصناف لم تُباع بعد، لتجنب فقدان بيانات
  // السلة بشكل غير مقصود بضغطة واحدة. تُغلق التبويبة الفارغة مباشرة دون
  // أي تأكيد.
  void _handleCloseSession(BuildContext context, PosProvider posProvider, int index) {
    final itemCount = posProvider.cartCountFor(index);
    if (itemCount == 0) {
      posProvider.closeSession(index);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إغلاق التبويبة؟'),
        content: Text(
          'تحتوي "${posProvider.labelFor(index)}" على $itemCount صنف لم تُباع بعد. سيتم فقدان هذه السلة نهائياً عند الإغلاق. هل تريد الاستمرار؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () {
              posProvider.closeSession(index);
              Navigator.pop(ctx);
            },
            child: const Text('إغلاق وحذف السلة', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDebtDialog(BuildContext context, PosProvider posProvider) {
    final nameController = TextEditingController();

    // NEW: existing customer names (from past/active debts) used to power
    // the autocomplete dropdown below, so cashiers can quickly pick a
    // returning customer instead of retyping their name (and risking a
    // near-duplicate name that would fail to merge with their existing debt).
    final debtProvider = Provider.of<DebtSupplierProvider>(context, listen: false);
    final knownCustomerNames = debtProvider.knownCustomerNames;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل فاتورة دين / آجل'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'المبلغ الإجمالي للدين: ${posProvider.totalAmount.toStringAsFixed(2)} شيكل',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('اسم الزبون المدين', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              // Autocomplete searchable dropdown for customer names, with
              // a properly paired FocusNode + TextEditingController and a
              // height-constrained options list (see _DebtCustomerAutocomplete
              // above for why this needed to be its own widget).
              _DebtCustomerAutocomplete(
                nameController: nameController,
                knownCustomerNames: knownCustomerNames,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                bool success = false;
                Object? error;
                try {
                  success = await posProvider.completeSaleAsDebt(nameController.text.trim(), debtProvider);
                } catch (e) {
                  error = e;
                }

                if (!ctx.mounted) return;

                if (success) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تسجيل الدين بنجاح وتحويل الفاتورة لصفحة الديون'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else if (error != null) {
                  // The debt record was written (see PosProvider), but
                  // updating stock afterwards failed. Inform the user
                  // instead of silently reporting success.
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم تسجيل الدين، لكن حدث خطأ أثناء تحديث المخزون: $error'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تعذر إتمام العملية: الكمية المطلوبة لم تعد متوفرة بالكامل في المخزون'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('تأكيد الدين', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posProvider = Provider.of<PosProvider>(context);
    final productProvider = Provider.of<ProductProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('نقطة البيع'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
            tooltip: 'تفريغ السلة الحالية',
            onPressed: () => posProvider.clearCart(),
          ),
        ],
        // NEW: شريط تبويبات الفواتير المعلقة - يظهر دوماً أسفل العنوان،
        // ويتيح فتح نافذة بيع جديدة أو التبديل بين عدة عمليات بيع متزامنة.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _buildSessionTabsBar(context, posProvider),
        ),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'امسح الباركود أو اكتب اسم المنتج',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onSubmitted: (value) {
                      _processSearchOrBarcode(value, productProvider, posProvider);
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: DataTable(
                        // تم تصحيح ترتيب الأعمدة هنا ليتطابق تماماً مع تسلسل البيانات في الـ DataRow أدناه
                        columns: const [
                          DataColumn(label: Text('حذف')),
                          DataColumn(label: Text('الإجمالي الصافي')),
                          DataColumn(label: Text('الخصم الإجمالي')),
                          DataColumn(label: Text('           الكمية')),
                          DataColumn(label: Text('سعر القطعة')),
                          DataColumn(label: Text('اسم المنتج')),
                        ],
                        rows: List.generate(posProvider.cart.length, (index) {
                          final item = posProvider.cart[index];
                          
                          final double grossTotal = item.sellPrice * item.quantity;
                          final double totalDiscountForThisItem = item.lineDiscountTotal;
                          final double itemTotal = grossTotal - totalDiscountForThisItem;

                          final qtyController = TextEditingController(text: '${item.quantity}');
                          qtyController.selection = TextSelection.fromPosition(
                            TextPosition(offset: qtyController.text.length),
                          );

                          final discountController = TextEditingController(text: totalDiscountForThisItem > 0 ? '${totalDiscountForThisItem.toStringAsFixed(2)}' : '');
                          discountController.selection = TextSelection.fromPosition(
                            TextPosition(offset: discountController.text.length),
                          );

                          // ترتيب الخلايا هنا يتطابق بالمللي متر مع ترتيب الأعمدة في الأعلى
                          return DataRow(cells: [
                            // 1. حذف
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => posProvider.removeItem(index),
                              ),
                            ),
                            // 2. الإجمالي الصافي
                            DataCell(Text('${itemTotal.toStringAsFixed(2)} شيكل')),
                            // 3. الخصم الإجمالي
                            DataCell(
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: discountController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: 'الخصم',
                                    contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (val) {
                                    double totalDiscountInput = double.tryParse(val) ?? 0.0;
                                    
                                    final originalProduct = productProvider.products.firstWhere(
                                      (p) => p.name == item.name,
                                      orElse: () => productProvider.products.first,
                                    );

                                    double discountPerUnit = item.quantity > 0 ? (totalDiscountInput / item.quantity) : 0.0;

                                    if ((item.sellPrice - discountPerUnit) < originalProduct.costPrice) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('تنبيه: سعر البيع بعد توزيع الخصم أقل من سعر التكلفة (البيع بخسارة)!'),
                                          backgroundColor: Colors.orange,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }

                                    posProvider.updateDiscount(index, totalDiscountInput);
                                  },
                                ),
                              ),
                            ),
                            // 4. الكمية
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: () {
                                      if (item.quantity > 1) {
                                        posProvider.updateQuantity(index, item.quantity - 1);
                                      }
                                    },
                                  ),
                                  SizedBox(
                                    width: 40,
                                    child: TextField(
                                      controller: qtyController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) {
                                        int? q = int.tryParse(val);
                                        if (q != null && q > 0) {
                                          posProvider.updateQuantity(index, q);
                                        }
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () {
                                      posProvider.updateQuantity(index, item.quantity + 1);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            // 5. سعر القطعة
                            DataCell(Text('${item.sellPrice.toStringAsFixed(2)} شيكل')),
                            // 6. اسم المنتج
                            DataCell(Text(item.name)),
                          ]);
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 320,
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('ملخص الفاتورة',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Divider(),
                const Spacer(),
                const Text('المبلغ الإجمالي:', style: TextStyle(fontSize: 16)),
                Text(
                  '${posProvider.totalAmount.toStringAsFixed(2)} شيكل',
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.check_circle, size: 24, color: Colors.white),
                  label: const Text('إتمام البيع (كاش)',
                      style: TextStyle(fontSize: 16, color: Colors.white)),
                  onPressed: posProvider.cart.isEmpty
                      ? null
                      : () async {
                          bool success = false;
                          Object? error;
                          try {
                            success = await posProvider.completeSale();
                          } catch (e) {
                            error = e;
                          }
                          if (!mounted) return;
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تمت عملية البيع كاش بنجاح')),
                            );
                          } else if (error != null) {
                            // The sale record was written (see PosProvider),
                            // but updating stock afterwards failed.
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('تم تسجيل البيع، لكن حدث خطأ أثناء تحديث المخزون: $error'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تعذر إتمام العملية: الكمية المطلوبة لم تعد متوفرة بالكامل في المخزون'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.assignment_ind, size: 24, color: Colors.white),
                  label: const Text('تسجيل بالدين (آجل)',
                      style: TextStyle(fontSize: 16, color: Colors.white)),
                  onPressed: posProvider.cart.isEmpty
                      ? null
                      : () => _showDebtDialog(context, posProvider),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}