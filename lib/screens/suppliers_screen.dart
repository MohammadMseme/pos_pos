import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/debt_supplier_provider.dart';
import '../models/supplier.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // CHANGED: now takes the Supplier object directly rather than its index
  // in the (possibly stale) cached list - see DebtSupplierProvider.addSupplierPayment.
  void _showPaymentDialog(BuildContext context, Supplier supplier) {
    final payController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تسديد دفعة للتاجر: ${supplier.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('المتبقي للتاجر حالياً: ${supplier.remainingAmount.toStringAsFixed(2)} شيكل'),
              const SizedBox(height: 12),
              TextField(
                controller: payController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'مبلغ الدفعة المدفوعة (شيكل)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'ملاحظات الدفعة (اختياري)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('سجل الدفعات السابقة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              supplier.payments.isEmpty
                  ? const Text('لا توجد دفعات مسجلة بعد', style: TextStyle(color: Colors.grey, fontSize: 12))
                  : SizedBox(
                      height: 120,
                      width: double.maxFinite,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: supplier.payments.length,
                        itemBuilder: (context, pIndex) {
                          final payment = supplier.payments[pIndex];
                          final dateStr = '${payment.date.year}-${payment.date.month.toString().padLeft(2, '0')}-${payment.date.day.toString().padLeft(2, '0')}';
                          return Card(
                            color: Colors.grey.shade100,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              dense: true,
                              title: Text('الدفعة: ${payment.amountPaid.toStringAsFixed(2)} شيكل', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                              subtitle: Text('التاريخ: $dateStr ${payment.notes.isNotEmpty ? ' | ملاحظة: ${payment.notes}' : ''}'),
                            ),
                          );
                        },
                      ),
                    ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              double pay = double.tryParse(payController.text) ?? 0.0;
              if (pay > 0) {
                final payment = SupplierPayment(
                  amountPaid: pay,
                  date: DateTime.now(),
                  notes: noteController.text.trim(),
                );
                Provider.of<DebtSupplierProvider>(context, listen: false)
                    .addSupplierPayment(supplier, payment);
                Navigator.pop(ctx);
              }
            },
            child: const Text('تسجيل الدفعة'),
          ),
        ],
      ),
    );
  }

  void _showAddSupplierDialog(BuildContext context) {
    final nameController = TextEditingController();
    final remainingController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة أو تحديث دين تاجر / مورد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'اسم التاجر / الشركة', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: remainingController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ المستحق إضافته (شيكل)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: noteController, decoration: const InputDecoration(labelText: 'ملاحظات الحساب / الدين (اختياري)', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                // سيتم دمج الدين تلقائياً إذا كان التاجر موجوداً مسبقاً، وإضافة سجل جديد إذا كان جديداً
                Provider.of<DebtSupplierProvider>(context, listen: false).addOrUpdateSupplierDebt(
                  nameController.text.trim(),
                  double.tryParse(remainingController.text) ?? 0.0,
                  noteController.text.trim(),
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supplierProvider = Provider.of<DebtSupplierProvider>(context);

    // تصفية التجار بناءً على نص البحث
    final filteredSuppliers = supplierProvider.suppliers.where((s) {
      return s.name.toLowerCase().contains(_searchQuery.trim().toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابات الموردين والتجار'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('إضافة / تحديث دين'),
              onPressed: () => _showAddSupplierDialog(context),
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // حقل البحث السريع
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'بحث باسم التاجر أو الشركة...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filteredSuppliers.isEmpty
                  ? const Center(child: Text('لا توجد حسابات مطابقة للبحث', style: TextStyle(fontSize: 16, color: Colors.grey)))
                  : ListView.builder(
                      itemCount: filteredSuppliers.length,
                      itemBuilder: (context, index) {
                        final s = filteredSuppliers[index];

                        return Card(
                          elevation: 3,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                const Icon(Icons.local_shipping, color: Colors.indigo, size: 36),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text('عدد الدفعات: ${s.payments.length}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                      if (s.notes.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text('ملاحظات: ${s.notes}', style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
                                      ],
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${s.remainingAmount.toStringAsFixed(2)} شيكل',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.brown),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                                      icon: const Icon(Icons.payment, size: 16),
                                      onPressed: () => _showPaymentDialog(context, s),
                                      label: const Text('دفع دفعة'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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