import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// فیلد ورود مبلغ با ماشین‌حساب داخلی و دکمه‌های افزودن صفر
class AmountCalculatorField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final bool enabled;

  const AmountCalculatorField({
    super.key,
    required this.controller,
    this.label = 'مبلغ به ریال',
    this.validator,
    this.enabled = true,
  });

  @override
  State<AmountCalculatorField> createState() => _AmountCalculatorFieldState();
}

class _AmountCalculatorFieldState extends State<AmountCalculatorField> {
  int _parse(String value) {
    final cleaned =
        value.replaceAll(',', '').replaceAll('٬', '').replaceAll(' ', '');
    return int.tryParse(cleaned) ?? 0;
  }

  String _format(int value) {
    if (value < 0) return value.toString();
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  void _appendZeros(int count) {
    final current = _parse(widget.controller.text);
    if (current == 0) return;
    final next = current * (count == 3 ? 1000 : 100);
    widget.controller.text = _format(next);
  }

  Future<void> _openCalculator() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _CalculatorSheet(initialValue: _parse(widget.controller.text)),
    );
    if (result != null && result > 0) {
      widget.controller.text = _format(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.calculate_outlined),
              tooltip: 'ماشین‌حساب',
              onPressed: widget.enabled ? _openCalculator : null,
            ),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9,٬ ]')),
          ],
          validator: widget.validator ??
              (v) {
                if (_parse(v ?? '') <= 0) return 'مبلغ معتبر وارد کنید';
                return null;
              },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.enabled ? () => _appendZeros(3) : null,
                child: const Text('+ ۰۰۰'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: widget.enabled ? () => _appendZeros(2) : null,
                child: const Text('+ ۰۰'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CalculatorSheet extends StatefulWidget {
  final int initialValue;
  const _CalculatorSheet({required this.initialValue});

  @override
  State<_CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<_CalculatorSheet> {
  late String _display;
  int? _accumulator;
  String? _pendingOp;
  bool _resetOnNextDigit = false;

  @override
  void initState() {
    super.initState();
    _display = widget.initialValue > 0 ? widget.initialValue.toString() : '0';
  }

  void _inputDigit(String digit) {
    setState(() {
      if (_resetOnNextDigit || _display == '0') {
        _display = digit;
        _resetOnNextDigit = false;
      } else {
        _display += digit;
      }
    });
  }

  void _setOperator(String op) {
    setState(() {
      final current = int.tryParse(_display) ?? 0;
      if (_accumulator != null && _pendingOp != null && !_resetOnNextDigit) {
        _accumulator = _apply(_accumulator!, current, _pendingOp!);
        _display = _accumulator.toString();
      } else {
        _accumulator = current;
      }
      _pendingOp = op;
      _resetOnNextDigit = true;
    });
  }

  int _apply(int a, int b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b == 0 ? a : a ~/ b;
      default:
        return b;
    }
  }

  void _equals() {
    setState(() {
      final current = int.tryParse(_display) ?? 0;
      if (_accumulator != null && _pendingOp != null) {
        _accumulator = _apply(_accumulator!, current, _pendingOp!);
        _display = _accumulator.toString();
      } else {
        _accumulator = current;
      }
      _pendingOp = null;
      _resetOnNextDigit = true;
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _accumulator = null;
      _pendingOp = null;
      _resetOnNextDigit = false;
    });
  }

  void _backspace() {
    setState(() {
      if (_display.length > 1) {
        _display = _display.substring(0, _display.length - 1);
      } else {
        _display = '0';
      }
    });
  }

  String _formatDisplay() {
    final value = int.tryParse(_display) ?? 0;
    if (value < 0) return value.toString();
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['7', '8', '9', '÷'],
      ['4', '5', '6', '×'],
      ['1', '2', '3', '-'],
      ['0', '00', '=', '+'],
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_pendingOp != null)
                    Text(
                      '$_pendingOp ${_formatDisplay()}',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  Text(
                    _formatDisplay(),
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clear,
                    child: const Text('C'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _backspace,
                    child: const Icon(Icons.backspace_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    for (final label in row)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _calcButton(label),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.pop(context, int.tryParse(_display) ?? 0),
                child: const Text('تأیید مبلغ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calcButton(String label) {
    final isOp = ['+', '-', '×', '÷', '='].contains(label);
    return SizedBox(
      height: 52,
      child: isOp
          ? FilledButton.tonal(
              onPressed: () {
                if (label == '=') {
                  _equals();
                } else {
                  _setOperator(label);
                }
              },
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
            )
          : OutlinedButton(
              onPressed: () {
                if (label == '00') {
                  _inputDigit('0');
                  _inputDigit('0');
                } else {
                  _inputDigit(label);
                }
              },
              child: Text(label, style: const TextStyle(fontSize: 20)),
            ),
    );
  }
}
