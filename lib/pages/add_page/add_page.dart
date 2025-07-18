import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/style.dart';
import '../../model/transaction.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../ui/device.dart';
import '../../ui/extensions.dart';
import "widgets/account_selector.dart";
import 'widgets/amount_section.dart';
import "widgets/category_selector.dart";
import 'widgets/details_list_tile.dart';
import 'widgets/duplicate_transaction_dialog.dart';
import 'widgets/label_list_tile.dart';
import 'widgets/recurrence_list_tile.dart';

class AddPage extends ConsumerStatefulWidget {
  final bool recurrencyEditingPermitted;

  const AddPage({super.key, this.recurrencyEditingPermitted = true});

  @override
  ConsumerState<AddPage> createState() => _AddPageState();
}

class _AddPageState extends ConsumerState<AddPage> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  bool? recurrencyEditingPermittedFromRoute;
  bool _isSaveEnabled = false;

  @override
  void initState() {
    if (ref.read(selectedTransactionUpdateProvider) != null) {
      _isSaveEnabled = true;
    }
    amountController.text =
        ref.read(selectedTransactionUpdateProvider)?.amount.toCurrency() ?? '';
    noteController.text =
        ref.read(selectedTransactionUpdateProvider)?.note ?? '';
    amountController.addListener(_updateAmount);

    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if arguments are being passed
    final args = ModalRoute.of(context)?.settings.arguments;

    if (recurrencyEditingPermittedFromRoute == null) {
      final argsMap = args as Map<String, dynamic>?;
      recurrencyEditingPermittedFromRoute =
          argsMap?['recurrencyEditingPermitted'] ??
              widget.recurrencyEditingPermitted;
    }
  }

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  String getCleanAmountString() {
    // Remove all non-numeric characters
    var cleanNumberString =
        amountController.text.replaceAll(RegExp(r'[^0-9\.]'), '');

    // Remove leading zeros only if the number does not start with "0."
    if (!cleanNumberString.startsWith('0.')) {
      cleanNumberString =
          cleanNumberString.replaceAll(RegExp(r'^0+(?!\.)'), '');
    }

    if (cleanNumberString.startsWith('.')) {
      cleanNumberString = '0$cleanNumberString';
    }

    return cleanNumberString;
  }

  void _updateAmount() {
    final selectedType = ref.read(transactionTypeProvider);

    var toBeWritten = getCleanAmountString();

    if (selectedType == TransactionType.expense) {
      // apply the minus sign if it's an expense
      if (toBeWritten.isNotEmpty) {
        toBeWritten = "-$toBeWritten";
      }
    }

    if (toBeWritten != amountController.text) {
      // only update the controller if the value is different
      amountController.text = toBeWritten;
      amountController.selection = TextSelection.fromPosition(
        TextPosition(offset: toBeWritten.length),
      );
    }
    final selectedAccount = ref.watch(bankAccountProvider) != null;
    final selectedAccountTransfer =
        ref.watch(bankAccountTransferProvider) != null;
    final selectedCategory = ref.watch(categoryProvider) != null;
    setState(() {
      _isSaveEnabled = amountController.text.isNotEmpty && selectedAccount;
      switch (selectedType) {
        case TransactionType.expense:
        case TransactionType.income:
          _isSaveEnabled &= selectedCategory;
          break;
        case TransactionType.transfer:
          _isSaveEnabled &= selectedAccountTransfer;
          break;
      }
    });
  }

  // TODO: This should be inside addTransaction
  void _refreshAccountAndNavigateBack() {
    ref
        .read(accountsProvider.notifier)
        .refreshAccount(ref.read(bankAccountProvider)!)
        .whenComplete(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _createOrUpdateTransaction() {
    final selectedType = ref.read(transactionTypeProvider);
    final selectedTransaction = ref.read(selectedTransactionUpdateProvider);

    final cleanAmount = getCleanAmountString();

    // Check that an amount has been provided
    if (cleanAmount != '') {
      if (selectedTransaction != null) {
        // if the original transaction is not recurrent, but user sets a recurrency, add the corrispondent record
        // and edit the original transaction
        if (ref.read(selectedRecurringPayProvider) &&
            !selectedTransaction.recurring) {
          ref
              .read(transactionsProvider.notifier)
              .addRecurringTransaction(
                  cleanAmount.toNum(), noteController.text, selectedType)
              .then((value) {
            if (value != null) {
              ref
                  .read(transactionsProvider.notifier)
                  .updateTransaction(
                      cleanAmount.toNum(), noteController.text, value.id)
                  .whenComplete(() => _refreshAccountAndNavigateBack());
            }
          });
        } else {
          ref
              .read(transactionsProvider.notifier)
              .updateTransaction(cleanAmount.toNum(), noteController.text,
                  selectedTransaction.idRecurringTransaction)
              .whenComplete(() => _refreshAccountAndNavigateBack());
        }
      } else {
        if (selectedType == TransactionType.transfer) {
          if (ref.read(bankAccountTransferProvider) != null) {
            ref
                .read(transactionsProvider.notifier)
                .addTransaction(cleanAmount.toNum(), noteController.text)
                .whenComplete(() => _refreshAccountAndNavigateBack());
          }
        } else {
          // It's an income or an expense
          if (ref.read(categoryProvider) != null) {
            if (ref.read(selectedRecurringPayProvider)) {
              ref
                  .read(transactionsProvider.notifier)
                  .addRecurringTransaction(
                      cleanAmount.toNum(), noteController.text, selectedType)
                  .whenComplete(() => _refreshAccountAndNavigateBack());
            } else {
              ref
                  .read(transactionsProvider.notifier)
                  .addTransaction(cleanAmount.toNum(), noteController.text)
                  .whenComplete(() => _refreshAccountAndNavigateBack());
            }
          }
        }
      }
    }
  }

  void _deleteTransaction() {
    final selectedTransaction = ref.read(selectedTransactionUpdateProvider);
    ref
        .read(transactionsProvider.notifier)
        .deleteTransaction(selectedTransaction!.id!)
        .whenComplete(() => _refreshAccountAndNavigateBack());
  }

  @override
  Widget build(BuildContext context) {
    final selectedType = ref.watch(transactionTypeProvider);
    final selectedTransaction = ref.watch(selectedTransactionUpdateProvider);

    _updateAmount();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (selectedTransaction != null)
              ? "Editing transaction"
              : "New transaction",
        ),
        actions: [
          if (selectedTransaction != null) ...[
            IconButton(
              icon: Icon(
                Icons.copy,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => DuplicateTransactionDialog(
                  transaction: selectedTransaction,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: _deleteTransaction,
            ),
          ]
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: Sizes.md * 6),
              child: Column(
                children: [
                  AmountSection(amountController),
                  Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(
                        left: Sizes.lg, top: Sizes.xxl, bottom: Sizes.sm),
                    child: Text(
                      "DETAILS",
                      style: Theme.of(context).textTheme.labelLarge!.copyWith(
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  Container(
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(
                      children: [
                        LabelListTile(noteController),
                        const Divider(),
                        if (selectedType != TransactionType.transfer) ...[
                          DetailsListTile(
                            title: "Account",
                            icon: Icons.account_balance_wallet,
                            value: ref.watch(bankAccountProvider)?.name,
                            callback: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              showModalBottomSheet(
                                context: context,
                                clipBehavior: Clip.antiAliasWithSaveLayer,
                                isScrollControlled: true,
                                useSafeArea: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.only(
                                    topLeft:
                                        Radius.circular(Sizes.borderRadius),
                                    topRight:
                                        Radius.circular(Sizes.borderRadius),
                                  ),
                                ),
                                builder: (_) => DraggableScrollableSheet(
                                  expand: false,
                                  minChildSize: 0.5,
                                  initialChildSize: 0.7,
                                  maxChildSize: 0.9,
                                  builder: (_, controller) => AccountSelector(
                                    scrollController: controller,
                                  ),
                                ),
                              );
                            },
                          ),
                          const Divider(),
                          DetailsListTile(
                            title: "Category",
                            icon: Icons.list_alt,
                            value: ref.watch(categoryProvider)?.name,
                            callback: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              showModalBottomSheet(
                                context: context,
                                clipBehavior: Clip.antiAliasWithSaveLayer,
                                isScrollControlled: true,
                                useSafeArea: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.only(
                                    topLeft:
                                        Radius.circular(Sizes.borderRadius),
                                    topRight:
                                        Radius.circular(Sizes.borderRadius),
                                  ),
                                ),
                                builder: (_) => DraggableScrollableSheet(
                                  expand: false,
                                  minChildSize: 0.5,
                                  initialChildSize: 0.7,
                                  maxChildSize: 0.9,
                                  builder: (_, controller) => CategorySelector(
                                    scrollController: controller,
                                  ),
                                ),
                              );
                            },
                          ),
                          const Divider(),
                        ],
                        DetailsListTile(
                          title: "Date",
                          icon: Icons.calendar_month,
                          value: ref.watch(dateProvider).formatEDMY(),
                          callback: () async {
                            FocusManager.instance.primaryFocus?.unfocus();
                            if (Platform.isIOS) {
                              showCupertinoModalPopup(
                                context: context,
                                builder: (_) => Container(
                                  height: 300,
                                  color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.secondarySystemBackground,
                                    context,
                                  ),
                                  child: CupertinoDatePicker(
                                    initialDateTime: ref.watch(dateProvider),
                                    minimumYear: 2015,
                                    maximumYear: 2050,
                                    mode: CupertinoDatePickerMode.date,
                                    onDateTimeChanged: (date) => ref
                                        .read(dateProvider.notifier)
                                        .state = date,
                                  ),
                                ),
                              );
                            } else if (Platform.isAndroid) {
                              final DateTime? pickedDate = await showDatePicker(
                                context: context,
                                initialDate: ref.watch(dateProvider),
                                firstDate: DateTime(2015),
                                lastDate: DateTime(2050),
                              );
                              if (pickedDate != null) {
                                ref.read(dateProvider.notifier).state =
                                    pickedDate;
                              }
                            }
                          },
                        ),
                        RecurrenceListTile(
                          recurrencyEditingPermitted:
                              widget.recurrencyEditingPermitted,
                          selectedTransaction:
                              ref.read(selectedTransactionUpdateProvider),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Container(
              alignment: Alignment.bottomCenter,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.15),
                    blurRadius: 5.0,
                    offset: const Offset(0, -1.0),
                  )
                ],
              ),
              padding: const EdgeInsets.fromLTRB(
                  Sizes.xl, Sizes.md, Sizes.xl, Sizes.xl),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  boxShadow: [defaultShadow],
                  borderRadius: BorderRadius.circular(Sizes.borderRadius),
                ),
                child: ElevatedButton(
                  onPressed: _isSaveEnabled ? _createOrUpdateTransaction : null,
                  child: Text(
                    selectedTransaction != null
                        ? "UPDATE TRANSACTION"
                        : "ADD TRANSACTION",
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
