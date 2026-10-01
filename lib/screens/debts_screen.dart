import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/debt_supplier_provider.dart';
import '../models/debt.dart';

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddDebtDialog(BuildContext context) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final itemController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة دين جديد يدوياً'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'اسم الزبون'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'إجمالي مبلغ الدين (شيكل)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: itemController,
              decoration: const InputDecoration(labelText: 'ملاحظة / الاصناف المأخوذة'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final amount = double.tryParse(amountController.text) ?? 0.0;
              final item = itemController.text.trim();

              if (name.isNotEmpty && amount > 0) {
                final newDebt = Debt(
                  customerName: name,
                  totalAmount: amount,
                  paidAmount: 0.0,
                  remainingAmount: amount,
                  itemsTaken: item.isNotEmpty ? [item] : ['إضافة يدوية'],
                  createdAt: DateTime.now(),
                );
                Provider.of<DebtSupplierProvider>(context, listen: false).addDebt(newDebt);
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog(BuildContext context, Debt debt) {
    final payController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تسديد دين: ${debt.customerName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المبلغ المتبقي حالياً: ${debt.remainingAmount.toStringAsFixed(2)} شيكل'),
            const SizedBox(height: 8),
            // توضيح لمنطق "رأس المال أولاً، ثم الربح": كل دفعة تُضاف فوراً
            // بالكامل إلى إجمالي المبيعات بمجرد سدادها. طالما لم يُسترد
            // رأس المال بالكامل، تُحتسب الدفعة كاسترداد رأس مال فقط (بدون
            // أي إضافة للأرباح)؛ وبعد اكتمال استرداد رأس المال، أي دفعة
            // لاحقة (أو الجزء الزائد من الدفعة الحالية) يُضاف إلى الأرباح
            // أيضاً بالتوازي مع إجمالي المبيعات (انظر
            // DebtSupplierProvider.payCustomerDebt).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('رأس المال المتبقي:', style: TextStyle(fontSize: 12)),
                      Text(
                        '${debt.remainingCapital.toStringAsFixed(2)} شيكل',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الربح المتبقي:', style: TextStyle(fontSize: 12)),
                      Text(
                        '${debt.remainingProfit.toStringAsFixed(2)} شيكل',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (debt.isCapitalRecovered)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '✓ تم استرداد رأس المال بالكامل - أي دفعة الآن تُضاف كاملة إلى الأرباح',
                        style: TextStyle(fontSize: 11, color: Colors.green),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'ملاحظة: هذه الدفعة تُضاف فوراً إلى إجمالي المبيعات، لكنها تُحتسب استرداد رأس مال فقط حتى يكتمل سداد رأس المال بالكامل.',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: payController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المبلغ المدفوع (شيكل)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              double pay = double.tryParse(payController.text) ?? 0.0;
              if (pay > 0) {
                Provider.of<DebtSupplierProvider>(context, listen: false).payCustomerDebt(debt, pay);
                Navigator.pop(ctx);
              }
            },
            child: const Text('تسجيل السداد'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debtProvider = Provider.of<DebtSupplierProvider>(context);

    // CHANGED: هذه الصفحة تعرض دوماً كل الديون النشطة دون أي قيد زمني -
    // لا يوجد هنا فلتر فترة (يوم/شهر/الكل)؛ ذلك الفلتر أصبح خاصاً بصفحة
    // الجرد فقط (انظر inventory_screen.dart)، بينما تبقى هذه الصفحة
    // (ديون التجار والموردين) تعرض كل سجل دين نشط بشكل شامل دائماً.
    // الفلترة هنا تقتصر على نص البحث عن اسم الزبون فقط.
    // ملاحظة: نستخدم activeDebts بدلاً من debts لأن الديون المسددة بالكامل
    // أصبحت تُؤرشف (isPaid = true) بدلاً من حذفها، ولا يجب أن تظهر هنا.
    final filteredDebts = debtProvider.activeDebts.where((debt) {
      return debt.customerName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة ديون الزبائن'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDebtDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('إضافة دين يدوياً'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // حقل البحث عن الزبون
            TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                labelText: 'بحث باسم الزبون...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // قائمة الديون
            Expanded(
              child: filteredDebts.isEmpty
                  ? Center(
                      child: Text(_searchQuery.isEmpty
                          ? 'لا يوجد أي ديون مسجلة حالياً'
                          : 'لا يوجد زبون مطابق لـ "$_searchQuery"'),
                    )
                  : ListView.builder(
                      itemCount: filteredDebts.length,
                      itemBuilder: (context, index) {
                        final debt = filteredDebts[index];
                        return Card(
                          elevation: 3,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ExpansionTile(
                            leading: const Icon(Icons.person, color: Colors.blue, size: 30),
                            title: Text(
                              'الزبون: ${debt.customerName}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            subtitle: Text(
                              'إجمالي الدين: ${debt.totalAmount.toStringAsFixed(2)} شيكل | المسدد: ${debt.paidAmount.toStringAsFixed(2)} شيكل',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'المتبقي: ${debt.remainingAmount.toStringAsFixed(2)} شيكل',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () => _showPaymentDialog(context, debt),
                                  child: const Text('سداد'),
                                ),
                              ],
                            ),
                            children: [
                              const Divider(),
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('المنتجات المأخوذة في هذه الطلبية:',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                                    const SizedBox(height: 6),
                                    if (debt.itemsTaken.isEmpty)
                                      const Text('لا يوجد تسجيل تفصيلي للمنتجات')
                                    else
                                      ...debt.itemsTaken.map((item) => Text('• $item')).toList(),
                                  ],
                                ),
                              )
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
}