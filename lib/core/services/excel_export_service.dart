import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../../shared/models/loan.dart';

/// Service for exporting loan data to Excel format
/// Columns: Name, Phone 1, Phone 2, Address, Amount, Total Paid, Outstanding
class ExcelExportService {
  static final ExcelExportService instance = ExcelExportService._internal();
  ExcelExportService._internal();

  final DatabaseService _databaseService = DatabaseService.instance;
  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  /// Export loans to Excel with optional status filter
  /// If status is null, exports all loans
  Future<String?> exportLoans({LoanStatus? status}) async {
    try {
      final excel = Excel.createExcel();
      
      // Sheet name based on status
      String sheetName;
      if (status == null) {
        sheetName = 'All Loans';
      } else if (status == LoanStatus.active) {
        sheetName = 'Active Loans';
      } else if (status == LoanStatus.overdue) {
        sheetName = 'Overdue Loans';
      } else {
        sheetName = 'Loans';
      }
      
      final sheet = excel[sheetName];
      
      // Remove default sheet
      excel.delete('Sheet1');

      var loansData = await _databaseService.getLoansWithCustomers();
      
      // Filter by status if specified
      if (status != null) {
        loansData = loansData.where((loan) => loan['status'] == status.index).toList();
      }
      
      if (loansData.isEmpty) {
        sheet.appendRow([TextCellValue('No loans found')]);
        return await _saveExcel(excel, status);
      }

      // Create header row - Simple columns as requested
      final headers = <CellValue>[
        TextCellValue('Name'),
        TextCellValue('Phone 1'),
        TextCellValue('Phone 2'),
        TextCellValue('Address'),
        TextCellValue('Amount'),
        TextCellValue('Total Paid'),
        TextCellValue('Outstanding'),
      ];
      
      sheet.appendRow(headers);
      
      // Style header row
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.blue200,
          horizontalAlign: HorizontalAlign.Center,
        );
      }

      // Add data rows
      for (final loanData in loansData) {
        final row = <CellValue>[
          TextCellValue(loanData['customer_name']?.toString() ?? ''),
          TextCellValue(loanData['customer_phone']?.toString() ?? ''),
          TextCellValue(loanData['customer_phone2']?.toString() ?? ''), // Blank if null
          TextCellValue(loanData['customer_address']?.toString() ?? ''), // Blank if null
          TextCellValue(_formatAmount(loanData['principal_amount'])),
          TextCellValue(_formatAmount(loanData['paid_amount'])),
          TextCellValue(_formatAmount(loanData['remaining_amount'])),
        ];
        
        sheet.appendRow(row);
      }

      // Set column widths
      sheet.setColumnWidth(0, 20); // Name
      sheet.setColumnWidth(1, 15); // Phone 1
      sheet.setColumnWidth(2, 15); // Phone 2
      sheet.setColumnWidth(3, 30); // Address
      sheet.setColumnWidth(4, 15); // Amount
      sheet.setColumnWidth(5, 15); // Total Paid
      sheet.setColumnWidth(6, 15); // Outstanding

      return await _saveExcel(excel, status);
    } catch (e) {
      debugPrint('Excel export error: $e');
      return null;
    }
  }

  /// Save Excel file and return path
  Future<String?> _saveExcel(Excel excel, LoanStatus? status) async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    
    String statusName;
    if (status == null) {
      statusName = 'All';
    } else if (status == LoanStatus.active) {
      statusName = 'Active';
    } else if (status == LoanStatus.overdue) {
      statusName = 'Overdue';
    } else {
      statusName = 'Loans';
    }
    
    final fileName = 'LoanReport_${statusName}_$timestamp.xlsx';
    final filePath = '${directory.path}/$fileName';
    
    final fileBytes = excel.save();
    if (fileBytes != null) {
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);
      return filePath;
    }
    return null;
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '₹0';
    final value = double.tryParse(amount.toString()) ?? 0;
    return _currencyFormat.format(value);
  }

  /// Export and share Excel file
  Future<bool> exportAndShare({LoanStatus? status}) async {
    final filePath = await exportLoans(status: status);
    if (filePath != null) {
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'Loan Report',
        text: 'Please find the loan report attached.',
      );
      return true;
    }
    return false;
  }
}
