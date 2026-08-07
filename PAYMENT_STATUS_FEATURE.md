# 💳 Payment Status Feature - Student Registration Control

## 🎯 What It Does

Control student registration ability via `status` column in students table:

```
status = 1 → Student can register ✅ "Register" button enabled
status = 2 → Student blocked ❌ "Fees Due" button disabled + message
```

---

## 📊 Database Setup

### Add column to students table:

```sql
ALTER TABLE students ADD COLUMN status INTEGER DEFAULT 1;

-- Explanation:
-- status = 1 (default) → Can register
-- status = 2 → Payment pending, cannot register

-- Set specific students as pending payment
UPDATE students SET status = 2 WHERE sr_no IN ('SR001', 'SR002', 'SR003');

-- Check status
SELECT sr_no, fname, status FROM students WHERE status = 2;
```

---

## 🎨 UI Behavior

### When status = 1 (Can Register):

```
Button: Register ✅
Icon: Person + (add icon)
Color: Grey
Action: Open face registration camera
```

### When status = 2 (Payment Pending):

```
Button: Fees Due 🔒
Icon: Lock icon
Color: Red (#FF6B6B)
Action: Show message "❌ Please pay exam fees initially on MSCE portal"
Message: Stays for 3 seconds
Click again: Message repeats (can't skip)
```

### When Already Registered:

```
Button: Registered ✅
Icon: Check circle
Color: Green
Action: Show "✅ Already Registered" message
```

---

## 🔄 Implementation Details

### Files Modified:

**`lib/presentation/screens/student_management_screen.dart`**

1. **Line 81:** Added `status` to select columns
   ```dart
   _studentSelectCols = '...status,...'
   ```

2. **Lines 2129-2131:** Extract payment status
   ```dart
   final paymentStatus = data['status'] as int? ?? 1;
   final isPaymentPending = paymentStatus == 2;
   ```

3. **Lines 2772-2810:** Updated button logic
   - Check `isPaymentPending`
   - If true: Show fee payment message
   - If false: Allow registration

4. **Visual Updates:**
   - Button color: Grey → Red when payment due
   - Button icon: Person add → Lock when payment due
   - Button text: "Register" → "Fees Due" when payment due

---

## 📱 User Experience

### Student with status = 1:
```
Student taps "Register" button
        ↓
Opens face camera
        ↓
Completes face registration
        ↓
Status changes to "Registered" ✅
```

### Student with status = 2:
```
Student taps "Fees Due" button
        ↓
Shows message:
"❌ Please pay exam fees initially on MSCE portal"
        ↓
Message disappears after 3 seconds
        ↓
Button remains locked (red) 🔒
        ↓
After payment, admin changes status to 1
        ↓
Student can now register ✅
```

---

## 🔧 How to Manage Status

### View all students with payment pending:
```sql
SELECT sr_no, fname, lname, status FROM students WHERE status = 2;
```

### Change student status (allow registration):
```sql
UPDATE students SET status = 1 WHERE sr_no = 'SR001';
```

### Bulk update status:
```sql
-- Allow all students in institute to register
UPDATE students SET status = 1 WHERE institute_id = 'INST123';

-- Block specific students from registering
UPDATE students SET status = 2 WHERE sr_no IN ('SR001', 'SR002');
```

### Check student status:
```sql
SELECT sr_no, fname, status, face_registration_status, created_at 
FROM students 
WHERE sr_no = 'SR001';
```

---

## 🎯 Use Cases

### Case 1: Student hasn't paid fees
```
Admin sets: status = 2
Result: Student sees "Fees Due" button, can't register
After payment: Admin sets status = 1
Student can now register
```

### Case 2: Bulk payment verification
```
After fees submission period:
UPDATE students SET status = 1 
WHERE institute_id = 'INST123' AND paid_date <= '2026-08-10';
```

### Case 3: Selective registration (merit-based)
```
Allow only merit students initially:
UPDATE students SET status = 2; -- Block all
UPDATE students SET status = 1 
WHERE merit_rank <= 100; -- Allow top 100
```

---

## 🔒 Security

- ✅ **Tamper-proof:** Status controlled in database, not by app
- ✅ **Clear message:** User knows reason for blocking
- ✅ **Admin controlled:** Only backend can change status
- ✅ **Audit trail:** Timestamp shows when user tried to register

---

## 📊 Status Values

| Value | Meaning | Button | Color | Icon |
|-------|---------|--------|-------|------|
| 1 | Can register | Register | Grey | Person + |
| 2 | Payment pending | Fees Due | Red | Lock |
| (registered) | Already done | Registered | Green | Check |

---

## 🚀 Deployment

1. Add status column to database (see SQL above)
2. Rebuild app (APK already built)
3. Update student statuses as needed
4. Deploy APK to students

---

## 💡 Tips

- **Default:** New students get status = 1 (can register)
- **Quick update:** Use SQL directly for bulk changes
- **Feedback:** Message is 3 seconds, user sees clearly
- **No bypass:** Button click does nothing if status = 2

---

## Testing

### Test status = 1:
1. Create test student with status = 1
2. App shows "Register" button
3. Click → Opens camera ✅

### Test status = 2:
1. Create test student with status = 2
2. App shows "Fees Due" button (red, locked)
3. Click → Shows "Please pay exam fees" message ✅
4. Cannot proceed to camera ✅

### Test transition:
1. Start with status = 2 (locked)
2. Admin changes to status = 1
3. Refresh app
4. Now shows "Register" button ✅

---

Done! Students with `status = 2` can't register! 🔒
