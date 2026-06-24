import 'package:flutter/material.dart';

/// A bordered -/+ stepper for cart line quantities — shared by
/// SaleEntryScreen and PurchaseEntryScreen so both POS-style cart
/// screens look and behave identically.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.quantity, required this.onDecrement, required this.onIncrement});

  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            onPressed: onDecrement,
          ),
          SizedBox(width: 28, child: Text('$quantity', textAlign: TextAlign.center)),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            onPressed: onIncrement,
          ),
        ],
      ),
    );
  }
}
