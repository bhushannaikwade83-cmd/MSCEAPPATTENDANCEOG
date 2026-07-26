import os
import requests
import psycopg2
from pathlib import Path

# Read .env manually
env_file = Path('.env')
env_vars = {}
if env_file.exists():
    with open(env_file) as f:
        for line in f:
            if '=' in line and not line.startswith('#'):
                key, value = line.strip().split('=', 1)
                env_vars[key] = value.strip('"')

BREVO_API_KEY = env_vars.get('BREVO_API_KEY')
DB_URL = env_vars.get('DATABASE_SESSION_POOL_URL')

if not BREVO_API_KEY or not DB_URL:
    print("❌ Missing BREVO_API_KEY or DATABASE_SESSION_POOL_URL")
    exit(1)

headers = {
    "accept": "application/json",
    "api-key": BREVO_API_KEY,
    "content-type": "application/json"
}

try:
    conn = psycopg2.connect(DB_URL)
    cursor = conn.cursor()
    
    # Get only the 126 newly updated ones
    cursor.execute("""
        SELECT DISTINCT admin_email
        FROM public.institutes
        WHERE admin_full_name IS NOT NULL 
          AND admin_emailS NOT NULL 
          AND admin_email NOT IN (
              SELECT DISTINCT email FROM public.admin_invites WHERE email IS NOT NULL
          )
        ORDER BY admin_email
    """)
    
    emails = [row[0] for row in cursor.fetchall()]
    cursor.close()
    conn.close()
    
    print(f"📧 Found {len(emails)} new admin emails to resubscribe\n")
    
    success = 0
    for i, email in enumerate(emails, 1):
        try:
            url = "https://api.brevo.com/v3/contacts"
            data = {
                "email": email,
                "attributes": {"DOUBLE_OPT_IN": 0},
                "listIds": [2],
                "updateEnabled": True
            }
            
            response = requests.post(url, headers=headers, json=data)
            
            if response.status_code in [201, 200]:
                success += 1
                print(f"✅ [{i}/{len(emails)}] {email}")
            else:
                print(f"⚠️  [{i}/{len(emails)}] {email}: {response.status_code}")
        excetion as e:
            print(f"❌ [{i}/{len(emails)}] {email}: {e}")
    
    print(f"\n✅ Resubscribed: {success}/{len(emails)}")

except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()

