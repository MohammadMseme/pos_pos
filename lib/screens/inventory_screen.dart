import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/debt_supplier_provider.dart';
import '../providers/product_provider.dart';
import '../models/sale.dart';
import '../models/product.dart';
import '../models/debt.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _selectedPeriod = 'يومي';

  // NEW: selected timeframe (in days) for the "Best-Selling Items" widget.
  // Kept separate from `_selectedPeriod` above (which drives the financial
  // report / sales log) since the two widgets can be viewed on different
  // timeframes independently.
  int _bestSellersDays = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DebtSupplierProvider>(context, listen: false).loadDebts();
    });
  }

  // دالة النسخ الاحتياطي الذكي الشامل لكل بيانات البرنامج
  Future<void> _smartBackupToExternalDrive(BuildContext context) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbDirectory = Directory(appDir.path);

      if (!dbDirectory.existsSync()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مجلد البيانات غير موجود!'), backgroundColor: Colors.red),
        );
        return;
      }

      Directory? externalDrive;
      for (var letter in ['D','G','H','I','J']) {
        final dir = Directory('$letter:\\');
        if (dir.existsSync()) {
          externalDrive = dir;
          break;
        }
      }

      if (!mounted) return;
      if (externalDrive == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الرجاء التأكد من توصيل الفلاشة أو الهارد الخارجي أولاً!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final backupDir = Directory('${externalDrive.path}SamaBackup');
      if (!backupDir.existsSync()) {
        backupDir.createSync(recursive: true);
      }

      final files = dbDirectory.listSync();
      int copiedCount = 0;

      for (var file in files) {
        if (file is File) {
          final fileName = file.path.split(Platform.pathSeparator).last;
          final targetPath = '${backupDir.path}${Platform.pathSeparator}$fileName';
          final targetFile = File(targetPath);

          bool shouldCopy = false;

          if (!targetFile.existsSync()) {
            shouldCopy = true;
          } else {
            final sourceModified = file.lastModifiedSync();
            final targetModified = targetFile.lastModifiedSync();
            if (sourceModified.isAfter(targetModified)) {
              shouldCopy = true;
            }
          }

          if (shouldCopy) {
            file.copySync(targetPath);
            copiedCount++;
          }
        }
      }

      if (!mounted) return;
      if (copiedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم بنجاح: نسخ وتحديث ($copiedCount) من الملفات الشاملة على الهارد الخارجي.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('جميع البيانات منسوخة مسبقاً ولا توجد بيانات جديدة لتحديثها!'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء النسخ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Sale> _getFilteredSales(List<Sale> sales) {
    if (_selectedPeriod == 'الكل') {
      return sales;
    }
    final now = DateTime.now();
    return sales.where((sale) {
      if (_selectedPeriod == 'يومي') {
        return sale.createdAt.day == now.day &&
            sale.createdAt.month == now.month &&
            sale.createdAt.year == now.year;
      } else if (_selectedPeriod == 'أسبوعي') {
        return now.difference(sale.createdAt).inDays <= 7;
      } else if (_selectedPeriod == 'شهري') {
        return sale.createdAt.month == now.month && sale.createdAt.year == now.year;
      } else {
        return sale.createdAt.year == now.year;
      }
    }).toList();
  }

  List<Product> _getFilteredPurchases(List<Product> products) {
    if (_selectedPeriod == 'الكل') {
      return products;
    }
    final now = DateTime.now();
    return products.where((product) {
      if (_selectedPeriod == 'يومي') {
        return product.createdAt.day == now.day &&
            product.createdAt.month == now.month &&
            product.createdAt.year == now.year;
      } else if (_selectedPeriod == 'أسبوعي') {
        return now.difference(product.createdAt).inDays <= 7;
      } else if (_selectedPeriod == 'شهري') {
        return product.createdAt.month == now.month && product.createdAt.year == now.year;
      } else {
        return product.createdAt.year == now.year;
      }
    }).toList();
  }

  // NEW: تُطبِّق فلتر الفترة الزمنية المختار حالياً في هذه الصفحة
  // (يومي/أسبوعي/شهري/سنوي/الكل) على قائمة الديون - بالضبط بنفس المنطق
  // المستخدم مع المبيعات والمشتريات أعلاه، لكن بالاعتماد على
  // `debt.createdAt` (تاريخ إنشاء الدين). هذا يجعل "ديون مستحقة" وصندوق
  // "جرد ومرابح الديون المعلقة" في هذه الصفحة يعكسان فقط الديون التي تقع
  // ضمن الفترة المختارة، على عكس صفحة "ديون التجار والموردين" التي تعرض
  // كل الديون دوماً دون أي قيد زمني.
  List<Debt> _getFilteredDebts(List<Debt> debts) {
    if (_selectedPeriod == 'الكل') {
      return debts;
    }
    final now = DateTime.now();
    return debts.where((debt) {
      if (_selectedPeriod == 'يومي') {
        return debt.createdAt.day == now.day &&
            debt.createdAt.month == now.month &&
            debt.createdAt.year == now.year;
      } else if (_selectedPeriod == 'أسبوعي') {
        return now.difference(debt.createdAt).inDays <= 7;
      } else if (_selectedPeriod == 'شهري') {
        return debt.createdAt.month == now.month && debt.createdAt.year == now.year;
      } else {
        return debt.createdAt.year == now.year;
      }
    }).toList();
  }

  void _showPurchasesDialog(BuildContext context, List<Product> purchases) {
    double totalPurchasesCost = purchases.fold(0.0, (sum, p) => sum + (p.costPrice * p.stockQuantity));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.shopping_cart, color: Colors.orange),
            SizedBox(width: 8),
            Text('تفاصيل المشتريات خلال الفترة'),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('إجمالي التكلفة: ${totalPurchasesCost.toStringAsFixed(2)} شيكل', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('عدد الأصناف: ${purchases.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('قائمة الأصناف التي تم شراؤها أو إضافتها:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Expanded(
                child: purchases.isEmpty
                    ? const Center(child: Text('لا توجد مشتريات جديدة مسجلة في هذه الفترة!'))
                    : ListView.builder(
                        itemCount: purchases.length,
                        itemBuilder: (context, index) {
                          final product = purchases[index];
                          double totalItemCost = product.costPrice * product.stockQuantity;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('الكمية: ${product.stockQuantity} | سعر الجملة: ${product.costPrice} شيكل'),
                              trailing: Text('${totalItemCost.toStringAsFixed(2)} شيكل', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showLowStockDialog(BuildContext context, List lowStockList) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('قائمة نواقص المخزون'),
          ],
        ),
        content: SizedBox(
          width: 400,
          height: 350,
          child: lowStockList.isEmpty
              ? const Center(child: Text('لا توجد أصناف منتهية حالياً!'))
              : ListView.builder(
                  itemCount: lowStockList.length,
                  itemBuilder: (context, index) {
                    final product = lowStockList[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('الباركود: ${product.barcode}'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'المتبقي: ${product.stockQuantity}',
                            style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // CHANGED: يستقبل الآن قائمة الديون بعد فلترتها بالفترة الزمنية المختارة
  // حالياً في الصفحة (`filteredDebts`)، بدلاً من أن يقرأ المزوّد كل الديون
  // مباشرة - لتعرض هذه النافذة فقط الديون التي تقع ضمن الفترة المحددة.
  void _showDebtInventoryDialog(
    BuildContext context,
    InventoryProvider inventory,
    List<Debt> filteredDebts,
  ) {
    final pendingRows = inventory.pendingDebtInventoryRowsFor(filteredDebts);
    final expectedProfit = inventory.totalExpectedDebtProfitFor(filteredDebts);
    final totalDebts = inventory.totalCustomerDebtsFor(filteredDebts);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.account_balance_wallet, color: Colors.purple),
            SizedBox(width: 8),
            Text('جرد ومرابح الديون المعلقة'),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('إجمالي الديون: ${totalDebts.toStringAsFixed(2)} شيكل', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('الأرباح المتوقعة: ${expectedProfit.toStringAsFixed(2)} شيكل', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('الأصناف المباعة بالدين ولم تُسدد بعد:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Expanded(
                child: pendingRows.isEmpty
                    ? const Center(child: Text('لا توجد أصناف معلقة في الديون حالياً!'))
                    : ListView.builder(
                        itemCount: pendingRows.length,
                        itemBuilder: (context, index) {
                          final row = pendingRows[index];
                          // NEW: whether رأس المال لهذا الدين تم استرداده
                          // بالكامل بعد (انظر Debt.isCapitalRecovered -
                          // السداد يُخصَّص لرأس المال أولاً على مستوى
                          // الدين ككل).
                          final bool capitalRecovered = row['capitalRecovered'] as bool;
                          final double remainingCapital = row['remainingCapital'] as double;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(row['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('الزبون: ${row['customerName']}'),
                                  if (!capitalRecovered)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'المتبقي لاسترداد رأس المال: ${remainingCapital.toStringAsFixed(2)} شيكل',
                                        style: const TextStyle(fontSize: 11, color: Colors.orange),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: capitalRecovered ? Colors.green.shade100 : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  capitalRecovered ? 'تم استرداد رأس المال' : 'لم يُسترد رأس المال بعد',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: capitalRecovered ? Colors.green.shade800 : Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // NEW: "Best-Selling Items" widget. Collapsed by default as a small
  // header card; tapping it expands to reveal the timeframe filter
  // (today / every 2 days / weekly / monthly) and the ranked list,
  // sourced from InventoryProvider.getBestSellingItems.
  Widget _buildBestSellersCard(InventoryProvider inventory) {
    final bestSellers = inventory.getBestSellingItems(days: _bestSellersDays, topN: 10);

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.teal.withValues(alpha: 0.05),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.teal.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // ExpansionTile draws a divider above/below its children by
        // default when expanded - suppressed here so it matches this
        // screen's existing bordered-card look instead.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // Collapsed by default, as requested - expands only on tap.
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: const Icon(Icons.trending_up, color: Colors.teal),
          title: const Text(
            'الأصناف الأكثر مبيعاً',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            'اضغط لعرض القائمة وفلترة الفترة الزمنية',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('الفترة: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                DropdownButton<int>(
                  value: _bestSellersDays,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('اليوم')),
                    DropdownMenuItem(value: 2, child: Text('آخر يومين')),
                    DropdownMenuItem(value: 7, child: Text('آخر أسبوع')),
                    DropdownMenuItem(value: 30, child: Text('آخر شهر')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _bestSellersDays = val;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (bestSellers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('لا توجد مبيعات مسجلة خلال هذه الفترة', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: bestSellers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final entry = bestSellers[index];
                    return Container(
                      width: 160,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '#${index + 1}',
                            style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${entry.value} قطعة مباعة',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = Provider.of<InventoryProvider>(context);
    final debtProvider = Provider.of<DebtSupplierProvider>(context);
    final productProvider = Provider.of<ProductProvider>(context);

    // CHANGED: الديون الظاهرة في هذه الصفحة (في بطاقة "ديون مستحقة" وفي
    // نافذة "جرد ومرابح الديون المعلقة") تُفلتَر الآن بنفس فلتر الفترة
    // الزمنية المختار أعلاه (يومي/أسبوعي/شهري/سنوي/الكل)، تماماً كالمبيعات
    // والمشتريات. نبدأ من activeDebts (غير المسددة) ثم نطبّق فلتر الفترة.
    final filteredDebts = _getFilteredDebts(debtProvider.activeDebts);
    double totalCustomerDebts = filteredDebts.fold(0.0, (sum, debt) => sum + debt.remainingAmount);

    final filteredSales = _getFilteredSales(inventory.allSales);
    final filteredPurchases = _getFilteredPurchases(productProvider.products);

    double totalPurchasesCost = filteredPurchases.fold(0.0, (sum, p) => sum + (p.costPrice * p.stockQuantity));

    double totalRevenue = 0.0;
    double grossProfit = 0.0;

    List<Map<String, dynamic>> individualSaleRows = [];

    for (var sale in filteredSales) {
      totalRevenue += sale.totalAmount;
      grossProfit += sale.totalProfit;

      for (var item in sale.items) {
        double actualSellPrice = item.sellPrice - item.discountPerUnit;
        double itemProfit = (actualSellPrice - item.costPrice) * item.quantity;

        individualSaleRows.add({
          'saleObject': sale,
          'date': sale.createdAt,
          'name': item.name,
          'quantity': item.quantity,
          'costPrice': item.costPrice,
          'sellPrice': item.sellPrice,
          'discount': item.discountPerUnit,
          'actualSellPrice': actualSellPrice,
          'profit': itemProfit,
        });
      }
    }

    double realizedProfitFromSales = grossProfit;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الجرد والتقارير المالية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sd_storage),
            tooltip: 'نسخ احتياطي شامل للهارد الخارجي',
            onPressed: () => _smartBackupToExternalDrive(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'الكل', label: Text('الكل')),
                ButtonSegment(value: 'يومي', label: Text('يومي')),
                ButtonSegment(value: 'أسبوعي', label: Text('أسبوعي')),
                ButtonSegment(value: 'شهري', label: Text('شهري')),
                ButtonSegment(value: 'سنوي', label: Text('سنوي')),
              ],
              selected: {_selectedPeriod},
              onSelectionChanged: (val) {
                setState(() {
                  _selectedPeriod = val.first;
                });
              },
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                _buildStatCard('إجمالي المبيعات', '${totalRevenue.toStringAsFixed(2)} شيكل', Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _showPurchasesDialog(context, filteredPurchases),
                    borderRadius: BorderRadius.circular(10),
                    child: _buildStatCardWidget(
                      'قيمة المشتريات',
                      '${totalPurchasesCost.toStringAsFixed(2)} شيكل',
                      Colors.orange,
                      hasArrow: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatCard('الربح المحقق من المبيعات', '${realizedProfitFromSales.toStringAsFixed(2)} شيكل', realizedProfitFromSales >= 0 ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _showDebtInventoryDialog(context, inventory, filteredDebts),
                    borderRadius: BorderRadius.circular(10),
                    child: _buildStatCardWidget(
                      'ديون مستحقة',
                      '${totalCustomerDebts.toStringAsFixed(2)} شيكل',
                      Colors.purple,
                      hasArrow: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _showLowStockDialog(context, inventory.lowStockProducts),
                    borderRadius: BorderRadius.circular(10),
                    child: _buildStatCardWidget(
                      'نواقص المخزون',
                      '${inventory.lowStockProducts.length} منتجات',
                      Colors.redAccent,
                      hasArrow: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // NEW: Best-Selling Items widget
            _buildBestSellersCard(inventory),
            const SizedBox(height: 20),

            const Align(
              alignment: Alignment.centerRight,
              child: Text('سجل حركات البيع المفصلة خلال الفترة:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('الوقت')),
                      DataColumn(label: Text('اسم الصنف')),
                      DataColumn(label: Text('الكمية')),
                      DataColumn(label: Text('سعر الجملة')),
                      DataColumn(label: Text('السعر الأصلي')),
                      DataColumn(label: Text('الخصم')),
                      DataColumn(label: Text('سعر البيع الفعلي')),
                      DataColumn(label: Text('إجمالي الربح')),
                      DataColumn(label: Text('حذف')),
                    ],
                    rows: individualSaleRows.map((row) {
                      final DateTime date = row['date'];
                      final timeFormatted = '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      final Sale saleObj = row['saleObject'];

                      return DataRow(cells: [
                        DataCell(Text(timeFormatted)),
                        DataCell(Text(row['name'])),
                        DataCell(Text('${row['quantity']}')),
                        DataCell(Text('${row['costPrice']} شيكل')),
                        DataCell(Text('${row['sellPrice']} شيكل')),
                        DataCell(Text('${row['discount']} شيكل', style: const TextStyle(color: Colors.red))),
                        DataCell(Text('${row['actualSellPrice'].toStringAsFixed(2)} شيكل', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                        DataCell(Text('${row['profit'].toStringAsFixed(2)} شيكل', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            tooltip: 'حذف هذه الحركة وإعادة الكميات للمخزون',
                            onPressed: () async {
                              // تأكيد الحذف
                              bool? confirm = await showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('تأكيد الحذف وإرجاع الكميات'),
                                  content: const Text('هل أنت متأكد من حذف حركة البيع؟ سيتم إعادة الكميات المباعة تلقائياً إلى المخزون.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('إلغاء'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('حذف وإرجاع', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                final productBox = Hive.box<Product>('products');

                                // 1. إعادة الكميات المباعة إلى مخزون المنتجات
                                for (var item in saleObj.items) {
                                  for (var product in productBox.values) {
                                    if (product.name == item.name) {
                                      product.stockQuantity += item.quantity;
                                      product.save();
                                      break;
                                    }
                                  }
                                }

                                // 2. حذف سجل البيع نفسه
                                await saleObj.delete(); 

                                // 3. تحديث الواجهة والـ Providers بالكامل
                                setState(() {});
                                Provider.of<ProductProvider>(context, listen: false).refreshProducts();

                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم حذف حركة البيع وإعادة الكميات إلى المخزون بنجاح'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: Colors.grey.shade800, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCardWidget(String title, String value, Color color, {bool hasArrow = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.bold)),
              if (hasArrow) Icon(Icons.arrow_drop_down_circle, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}