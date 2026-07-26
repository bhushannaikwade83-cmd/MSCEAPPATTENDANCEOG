#!/usr/bin/env python3
"""
Bulk resubscribe all institute admin emails to Brevo contact list
"""

import os
import requests
import json
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

BREVO_API_KEY = os.getenv('BREVO_API_KEY')
BREVO_API_URL = "https://api.brevo.com/v3"

if not BREVO_API_KEY:
    print("❌ BREVO_API_KEY not found in .env")
    exit(1)

headers = {
    "accept": "application/json",
    "api-key": BREVO_API_KEY,
    "content-type": "application/json"
}

def get_all_institute_emails():
    """Get all unique admin emails from institutes table via Supabase"""
    import psycopg2
    from psycopg2 import sql

    db_url = os.getenv('DATABASE_SESSION_POOL_URL')
    if not db_url:
        print("❌ DATABASE_SESSION_POOL_URL not found in .env")
        return []

    try:
        conn = psycopg2.connect(db_url)
        cursor = conn.cursor()

        cursor.execute("""
            SELECT DISTINCT admin_email
            FROM public.institutes
            WHERE admin_email IS NOT NULL AND admin_email != ''
            ORDER BY admin_email
        """)

        emails = [row[0] for row in cursor.fetchall()]
        cursor.close()
        conn.close()

        return emails
    except Exception as e:
        print(f"❌ Database error: {e}")
        return []

def resubscribe_email_to_brevo(email):
    """Resubscribe a single email to Brevo"""
    try:
        url = f"{BREVO_API_URL}/contacts"

        data = {
            "email": email,
            "attributes": {
                "DOUBLE_OPT_IN": 0  # Skip double opt-in
            },
            "listIds": [2],  # Add to default list (adjust if needed)
            "updateEnabled": True  # Update if already exists
        }

        response = requests.post(url, headers=headers, json=data)

        if response.status_code in [201, 200]:
            return True
        else:
            print(f"  ⚠️  {email}: {response.status_code} - {response.text}")
            return False
    except Exception as e:
        print(f"  ❌ {email}: {e}")
        return False

def main():
    print("📧 Getting all institute admin emails...")
    emails = get_all_institute_emails()

    if not emails:
        print("❌ No emails found")
        return

    print(f"✅ Found {len(emails)} unique emails\n")

    success = 0
    failed = 0

    print("🔄 Resubscribing to Brevo...")
    for i, email in enumerate(emails, 1):
        if resubscribe_email_to_brevo(email):
            success += 1
            print(f"  ✅ [{i}/{len(emails)}] {email}")
        else:
            failed += 1

        # Rate limit: 1 request per 0.1 seconds for Brevo free tier
        if i % 10 == 0:
            print(f"     Progress: {i}/{len(emails)}")

    print(f"\n📊 Summary:")
    print(f"   ✅ Successfully resubscribed: {success}")
    print(f"   ❌ Failed: {failed}")
    print(f"   📧 Total: {len(emails)}")

if __name__ == "__main__":
    main()
