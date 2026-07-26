import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/date_range_filter.dart';

class DateRangeSelector extends StatefulWidget {
  final Function(DateRangeFilter) onDateRangeSelected;
  final DateRangeFilter initialRange;

  const DateRangeSelector({
    Key? key,
    required this.onDateRangeSelected,
    required this.initialRange,
  }) : super(key: key);

  @override
  State<DateRangeSelector> createState() => _DateRangeSelectorState();
}

class _DateRangeSelectorState extends State<DateRangeSelector> {
  late DateRangeFilter selectedRange;
  late TextEditingController startDateController;
  late TextEditingController endDateController;

  @override
  void initState() {
    super.initState();
    selectedRange = widget.initialRange;
    startDateController = TextEditingController(
      text: DateFormat('MMM dd, yyyy').format(selectedRange.startDate),
    );
    endDateController = TextEditingController(
      text: DateFormat('MMM dd, yyyy').format(selectedRange.endDate),
    );
  }

  @override
  void dispose() {
    startDateController.dispose();
    endDateController.dispose();
    super.dispose();
  }

  void _selectQuickRange(DateRangeFilter newRange) {
    setState(() {
      selectedRange = newRange;
      startDateController.text =
          DateFormat('MMM dd, yyyy').format(selectedRange.startDate);
      endDateController.text =
          DateFormat('MMM dd, yyyy').format(selectedRange.endDate);
    });
    widget.onDateRangeSelected(selectedRange);
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedRange.startDate,
      firstDate: DateTime(2020),
      lastDate: selectedRange.endDate,
    );

    if (picked != null) {
      setState(() {
        selectedRange = DateRangeFilter.custom(picked, selectedRange.endDate);
        startDateController.text =
            DateFormat('MMM dd, yyyy').format(selectedRange.startDate);
      });
      widget.onDateRangeSelected(selectedRange);
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedRange.endDate,
      firstDate: selectedRange.startDate,
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        selectedRange = DateRangeFilter.custom(selectedRange.startDate, picked);
        endDateController.text =
            DateFormat('MMM dd, yyyy').format(selectedRange.endDate);
      });
      widget.onDateRangeSelected(selectedRange);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Quick select buttons
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _QuickSelectButton(
                label: '1 Week',
                isSelected: selectedRange.type == DateRangeType.oneWeek,
                onPressed: () => _selectQuickRange(DateRangeFilter.oneWeek()),
              ),
              SizedBox(width: 8),
              _QuickSelectButton(
                label: '1 Month',
                isSelected: selectedRange.type == DateRangeType.oneMonth,
                onPressed: () => _selectQuickRange(DateRangeFilter.oneMonth()),
              ),
              SizedBox(width: 8),
              _QuickSelectButton(
                label: '3 Months',
                isSelected: selectedRange.type == DateRangeType.threeMonths,
                onPressed: () =>
                    _selectQuickRange(DateRangeFilter.threeMonths()),
              ),
              SizedBox(width: 8),
              _QuickSelectButton(
                label: '6 Months',
                isSelected: selectedRange.type == DateRangeType.sixMonths,
                onPressed: () => _selectQuickRange(DateRangeFilter.sixMonths()),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        // Custom date range
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _selectStartDate,
                child: TextField(
                  controller: startDateController,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'Start Date',
                    hintText: 'Select start date',
                    suffixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _selectEndDate,
                child: TextField(
                  controller: endDateController,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'End Date',
                    hintText: 'Select end date',
                    suffixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        // Display selected range info
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Showing: ${selectedRange.formatRange()} (${selectedRange.getDayCount()} days)',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue[900],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickSelectButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  const _QuickSelectButton({
    Key? key,
    required this.label,
    required this.isSelected,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            isSelected ? Colors.blue : Colors.grey[300],
        foregroundColor: isSelected ? Colors.white : Colors.black87,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
