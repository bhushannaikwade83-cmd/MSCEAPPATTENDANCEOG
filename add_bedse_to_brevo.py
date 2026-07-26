#!/usr/bin/env python3
"""
Add Nandkumar Bedse email to Brevo contact list
"""

import requests
import os
from dotenv import load_dotenv

load_dotenv()

BREVO_API_KEY = os.getenv('BREVO_API_KEY')
if not BREVO_API_KEY:
    print("❌ BREVO_API_KEY not found in .env")
    exit(1)

email = 'bedse2014@gmail.com'
first_name = 'Nandkumar'
last_name = 'Bedse'

# Brevo API endpoint
url = "https://api.brevo.com/v3/contacts"

headers = {
    "accept": "application/json",
    "api-key": BREVO_API_KEY,
    "content-type": "application/json"
}

data = {
    "email": email,
    "attributes": {
        "FIRSTNAME": first_name,
        "LASTNAME": last_name,
        "DOUBLE_OPT_IN": 0  # Skip double opt-in
    },
    "listIds": [2],  # Default list
    "updateEnabled": True
}

print(f"📧 Adding {email} to Brevo...")

try:
    response = requests.post(url, headers=headers, json=data)

    if response.status_code in [201, 200]:
        print(f"✅ Successfully added {email} to Brevo")
        print(f"   Name: {first_name} {last_name}")
        print(f"   Institute: 9999")
        print(f"   Status: {response.status_code}")
    else:
        print(f"❌ Failed to add email")
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.text}")
except Exception as e:
    print(f"❌ Error: {e}")
