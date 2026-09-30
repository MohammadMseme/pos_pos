import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/product.dart';
import '../models/sale.dart';
import '../models/supplier.dart';
import '../models/debt.dart';
import '../models/note.dart';

class HiveService {
  /// Names of boxes that failed to open normally during this run and had
  /// to be quarantined (their original files were moved, NOT deleted, to
  /// `hive_quarantine/` inside the app's documents folder). The app's UI
  /// layer should check this after startup and tell the user their data
  /// for these boxes needs manual recovery, instead of the previous
  /// behavior of silently wiping the box with no trace.
  static final List<String> recoveredBoxWarnings = [];

  static Future<void> init() async {
    await Hive.initFlutter();

    // تسجيل Adapters
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(SaleItemAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SaleAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SupplierPaymentAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(SupplierAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(DebtAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(NoteAdapter());
    // NEW: enum adapter backing Sale.source (typeId 7 - does not collide
    // with any existing model typeId 0-6).
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(SaleSourceAdapter());

    // فتح الصناديق مع المعالجة الآمنة
    await _openBoxSafely<Product>('products');
    await _openBoxSafely<Sale>('sales');
    await _openBoxSafely<Supplier>('suppliers');
    await _openBoxSafely<Debt>('debts');
    await _openBoxSafely<Note>('notes');
  }

  /// Opens a box, and if that fails, NEVER deletes the underlying data.
  /// Instead it:
  ///   1. Logs the failure.
  ///   2. Closes any partially-open handle.
  ///   3. Moves (not deletes) the box's on-disk files into a timestamped
  ///      quarantine folder, so the original bytes are always recoverable.
  ///   4. Opens a fresh, empty box under the original name so the app can
  ///      keep functioning.
  ///   5. Records the box name in [recoveredBoxWarnings] so the UI can
  ///      surface an explicit notice to the user after startup.
  static Future<void> _openBoxSafely<T>(String boxName) async {
    try {
      await Hive.openBox<T>(boxName);
      return; // Happy path: nothing else to do.
    } catch (e, stack) {
      debugPrint('[HiveService] Failed to open box "$boxName": $e');
      debugPrint('$stack');
    }

    // The box could not be opened normally. Make sure we don't hold a
    // half-open handle before we touch the files on disk.
    try {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box<T>(boxName).close();
      }
    } catch (e) {
      debugPrint('[HiveService] Could not cleanly close box "$boxName" before quarantine: $e');
    }

    try {
      await _quarantineBoxFiles(boxName);
    } catch (e, stack) {
      // If we can't even safely move the files aside, we deliberately do
      // NOT fall back to deleting them. Surface the failure instead of
      // risking destroying the only copy of the user's data.
      debugPrint('[HiveService] Failed to quarantine box "$boxName": $e');
      debugPrint('$stack');
      rethrow;
    }

    // The corrupted/locked files are now safely out of the way (renamed
    // into hive_quarantine/, never deleted). It's safe to start a fresh,
    // empty box under the original name so the app remains usable.
    await Hive.openBox<T>(boxName);
    recoveredBoxWarnings.add(boxName);
    debugPrint(
      '[HiveService] Box "$boxName" could not be opened; the original files '
      'were preserved under hive_quarantine/ and a new empty box was created. '
      'Manual data recovery may be needed.',
    );
  }

  /// Moves (copies then deletes the source, i.e. an effective "move") the
  /// on-disk files for [boxName] into `<app documents>/hive_quarantine/`,
  /// prefixed with a timestamp so repeated failures never overwrite each
  /// other. The files are never permanently discarded by this method.
  static Future<void> _quarantineBoxFiles(String boxName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final quarantineDir = Directory(
      '${appDir.path}${Platform.pathSeparator}hive_quarantine',
    );
    if (!quarantineDir.existsSync()) {
      quarantineDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // Hive's default file storage engine writes "<name>.hive" and
    // "<name>.lock" next to the app's documents directory.
    final candidateFileNames = ['$boxName.hive', '$boxName.lock'];

    for (final fileName in candidateFileNames) {
      final source = File('${appDir.path}${Platform.pathSeparator}$fileName');
      if (!source.existsSync()) continue;

      final destination = File(
        '${quarantineDir.path}${Platform.pathSeparator}${timestamp}_$fileName',
      );

      // Copy first, then only remove the original once the copy is
      // confirmed on disk - this way a mid-operation crash never leaves
      // us with zero copies of the data.
      await source.copy(destination.path);
      if (destination.existsSync()) {
        await source.delete();
      }
    }
  }
}