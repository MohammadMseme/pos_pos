import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import '../providers/product_provider.dart';
import '../providers/debt_supplier_provider.dart';

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

  void _showDebtDialog(BuildContext context, PosProvider posProvider) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل فاتورة دين / آجل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'المبلغ الإجمالي للدين: ${posProvider.totalAmount.toStringAsFixed(2)} شيكل',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الزبون المدين',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                final debtProvider = Provider.of<DebtSupplierProvider>(context, listen: false);

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
            tooltip: 'تفريغ السلة',
            onPressed: () => posProvider.clearCart(),
          ),
        ],
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