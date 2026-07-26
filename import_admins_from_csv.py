#!/usr/bin/env python3
"""
Import admin data from my_institutes.csv to admin_invites table
"""

import csv
import os
from pathlib import Path

# Get the CSV file
csv_path = Path(__file__).parent / "scripts" / "my_institutes.csv"

if not csv_path.exists():
    print(f"❌ File not found: {csv_path}")
    exit(1)

# Read CSV and generate SQL
sql_statements = []
sql_statements.append("BEGIN;")
sql_statements.append("DELETE FROM public.admin_invites;")
sql_statements.append("")

count = 0
with open(csv_path, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            # Extract data
            first_name = row.get('FIRST NAME', '').strip()
            middle_name = row.get('MIDDLE NAME', '').strip()
            last_name = row.get('LAST NAME', '').strip()
            email = row.get('emailid', '').strip()
            phone = row.get('MOBILE NO', '').strip()
            institute_id = row.get('GCCINSTCODE', '').strip()

            # Skip if critical fields are missing
            if not institute_id or not email:
                continue

            # Build full name
            full_name_parts = [p for p in [first_name, middle_name, last_name] if p]
            full_name = ' '.join(full_name_parts) or 'Admin'

            # Escape single quotes
            full_name = full_name.replace("'", "''")
            email = email.replace("'", "''")
            phone = phone.replace("'", "''")

            # Generate SQL
            sql = f"""INSERT INTO public.admin_invites (id, institute_id, full_name, email, phone, claimed, created_at)
VALUES (gen_random_uuid(), '{institute_id}', '{full_name}', '{email}', '{phone}', false, NOW());"""

            sql_statements.append(sql)
            count += 1

        except Exception as e:
            print(f"⚠️  Skipping row: {e}")
            continue

sql_statements.append("")
sql_statements.append(f"-- Total imported: {count}")
sql_statements.append(f"SELECT COUNT(*) as total_pending FROM public.admin_invites;")
sql_statements.append("COMMIT;")

# Print SQL
full_sql = "\n".join(sql_statements)
print(full_sql)

# Save to file
output_file = Path(__file__).parent / "IMPORT_ADMINS_FROM_CSV.sql"
with open(output_file, 'w', encoding='utf-8') as f:
    f.write(full_sql)

print(f"\n✅ Generated SQL saved to: {output_file}")
print(f"📊 Total records to import: {count}")
