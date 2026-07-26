#!/usr/bin/env python3
"""
Add email to Brevo contact list directly
"""

import requests
import os
from dotenv import load_dotenv

load_dotenv()

BREVO_API_KEY = os.getenv('BREVO_API_KEY')
if not BREVO_API_KEY:
    print("❌ BREVO_API_KEY not found in .env")
    exit(1)

email = 'nitin.kirdakar@gmail.com'
full_name = 'Nitin Duryodhan Kirdakar'

# Brevo API endpoint to add contact to list
url = "https://api.brevo.com/v3/contacts"

headers = {
    "accept": "application/json",
    "api-key": BREVO_API_KEY,
    "content-type": "application/json"
}

data = {
    "email": email,
    "attributes": {
        "FIRSTNAME": "Nitin",
        "LASTNAME": "Kirdakar",
        "DOUBLE_OPT_IN": 0  # Skip double opt-in
    },
    "listIds": [2],  # Default list (adjust if needed)
    "updateEnabled": True  # Update if already exists
}

print(f"📧 Adding {email} to Brevo...")

try:
    response = requests.post(url, headers=headers, json=data)

    if response.status_code in [201, 200]:
        print(f"✅ Successfully added {email} to Brevo")
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.json()}")
    else:
        print(f"❌ Failed to add email")
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.text}")
except Exception as e:
    print(f"❌ Error: {e}")
