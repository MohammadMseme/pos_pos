import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../models/product.dart';

class ProductProvider extends ChangeNotifier {
  Box<Product> get _productBox => Hive.box<Product>('products');

  List<Product> get products => _productBox.values.toList();

  // إضافة منتج مع التحقق من شروط الاسم والباركود
  String addProductWithRules(Product newProduct) {
    String trimmedNewName = newProduct.name.trim().toLowerCase();
    String trimmedNewBarcode = newProduct.barcode.trim();

    // 1. البحث عما إذا كان الباركود موجوداً مسبقاً لصنف آخر
    Product? existingByBarcode;
    try {
      existingByBarcode = _productBox.values.firstWhere(
        (p) => p.barcode.trim() == trimmedNewBarcode,
      );
    } catch (_) {
      existingByBarcode = null;
    }

    // 2. البحث عما إذا كان اسم المنتج موجوداً مسبقاً
    Product? existingByName;
    try {
      existingByName = _productBox.values.firstWhere(
        (p) => p.name.trim().toLowerCase() == trimmedNewName,
      );
    } catch (_) {
      existingByName = null;
    }

    // الحالة الأولى: الباركود موجود مسبقاً ولكن لصنف آخر (اسم مختلف) -> رفض الإضافة
    if (existingByBarcode != null && existingByBarcode.name.trim().toLowerCase() != trimmedNewName) {
      return 'rejected_barcode_conflict';
    }

    // الحالة الثانية: تطابق الاسم والباركود معاً، أو تطابق الاسم فقط لصنف موجود -> زيادة الكمية
    if (existingByName != null) {
      existingByName.stockQuantity += newProduct.stockQuantity;
      // تحديث الأسعار أو الباركود إذا لزم الأمر، أو الاكتفاء بزيادة المخزون
      existingByName.save();
      notifyListeners();
      return 'updated_existing';
    }

    // الحالة الثالثة: الباركود موجود مسبقاً (لنفس الصنف تماماً لأن الاسم متطابق وتم فحصه بالاعلى)
    if (existingByBarcode != null) {
      existingByBarcode.stockQuantity += newProduct.stockQuantity;
      existingByBarcode.save();
      notifyListeners();
      return 'updated_existing';
    }

    // إذا كان صنفاً جديداً كلياً -> إضافته بشكل طبيعي
    _productBox.put(newProduct.barcode, newProduct);
    notifyListeners();
    return 'added_new';
  }

  void updateProduct(Product product) {
    product.save();
    notifyListeners();
  }

  void deleteProduct(Product product) {
    product.delete();
    notifyListeners();
  }

  void refreshProducts() {
  notifyListeners();
}

  Product? getByBarcode(String barcode) {
    return _productBox.get(barcode);
  }
}