#!/usr/bin/env python3
"""
Merge NEW_INST3000.csv with institutes table for missing admin details
"""

import csv
import os
from pathlib import Path

csv_path = Path("scripts/NEW_INST3000.csv")

if not csv_path.exists():
    print(f"❌ File not found: {csv_path}")
    exit(1)

# Read CSV and prepare SQL
admin_inserts = []
institute_updates = []
count = 0

print("📖 Reading NEW_INST3000.csv...")

try:
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)

        # Skip header
        next(reader)

        for row in reader:
            if not row or len(row) < 10:
                continue

            try:
                # Columns: [1]=INSTITUTE_CODE, [2]=last_name, [3]=first_name, [4]=middle_name, [7]=EMAIL, [9]=MOB_PRINC
                inst_code = row[1].strip() if len(row) > 1 else ""
                last_name = row[2].strip() if len(row) > 2 else ""
                first_name = row[3].strip() if len(row) > 3 else ""
                middle_name = row[4].strip() if len(row) > 4 else ""
                email = row[7].strip() if len(row) > 7 else ""
                phone = row[9].strip() if len(row) > 9 else ""

                # Skip if missing critical data
                if not inst_code or not email:
                    continue

                # Build full name
                full_name = f"{first_name} {middle_name} {last_name}".strip()
                full_name = ' '.join(full_name.split())  # Remove extra spaces

                # Escape quotes
                full_name = full_name.replace("'", "''")
                email = email.replace("'", "''")
                phone = phone.replace("'", "''")

                # SQL to add to admin_invites (if not exists)
                insert_sql = f"(gen_random_uuid(), '{inst_code}', '{full_name}', '{email}', '{phone}', false, NOW())"
                admin_inserts.append(insert_sql)

                # SQL to update institutes table
                update_sql = f"('{inst_code}', '{full_name}', '{email}', '{phone}')"
                institute_updates.append(update_sql)

                count += 1

            except Exception as e:
                print(f"⚠️  Skipping row: {e}")
                continue

    print(f"✅ Found {count} records in CSV\n")

    # Generate SQL file
    sql_file = "MERGE_NEW_INST_ADMINS.sql"
    with open(sql_file, 'w') as f:
        f.write("-- Merge NEW_INST3000.csv with institutes table\n")
        f.write("-- This adds missing admin details for 126 institutes\n\n")

        # Part 1: Add to admin_invites (only for institutes without admins)
        f.write("-- Part 1: Add to admin_invites for institutes without admins\n")
        f.write("INSERT INTO public.admin_invites (id, institute_id, full_name, email, phone, claimed, created_at)\n")
        f.write("SELECT\n")
        f.write("  gen_random_uuid(),\n")
        f.write("  a.institute_id,\n")
        f.write("  a.full_name,\n")
        f.write("  a.email,\n")
        f.write("  a.phone,\n")
        f.write("  false,\n")
        f.write("  NOW()\n")
        f.write("FROM (\n")
        f.write("  VALUES\n")
        f.write(",\n".join(admin_inserts))
        f.write("\n) AS a(institute_id, full_name, email, phone)\n")
        f.write("WHERE a.institute_id NOT IN (SELECT institute_id FROM public.admin_invites)\n")
        f.write("  AND a.institute_id IN (SELECT id FROM public.institutes WHERE admin_full_name IS NULL);\n\n")

        # Part 2: Update institutes table
        f.write("-- Part 2: Update institutes table with admin details\n")
        f.write("UPDATE public.institutes i\n")
        f.write("SET\n")
        f.write("  admin_full_name = u.full_name,\n")
        f.write("  admin_email = u.email,\n")
        f.write("  admin_phone = u.phone\n")
        f.write("FROM (\n")
        f.write("  VALUES\n")
        f.write(",\n".join(institute_updates))
        f.write("\n) AS u(institute_id, full_name, email, phone)\n")
        f.write("WHERE i.id = u.institute_id\n")
        f.write("  AND i.admin_full_name IS NULL;\n\n")

        # Part 3: Verify
        f.write("-- Part 3: Verify\n")
        f.write("SELECT COUNT(*) as institutes_now_with_admin FROM public.institutes WHERE admin_full_name IS NOT NULL;\n")
        f.write("SELECT COUNT(*) as still_missing FROM public.institutes WHERE admin_full_name IS NULL;\n")

    print(f"✅ SQL file generated: {sql_file}")
    print(f"📊 Total records to merge: {count}")
    print(f"\nRun this in Supabase:")
    print(f"   cat {sql_file} | (paste in SQL Editor)")

except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
