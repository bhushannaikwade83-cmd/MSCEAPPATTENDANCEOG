"""
Test script to send base64 image to the API
This properly handles the large base64 string and JSON encoding
"""

import json
import requests
import sys

def test_recognize(base64_string, institute_id="INS001", threshold=0.85):
    """Test the /api/v1/recognize endpoint"""
    url = "http://127.0.0.1:8000/api/v1/recognize"
    
    payload = {
        "image_base64": base64_string,
        "institute_id": institute_id,
        "threshold": threshold
    }
    
    print("=" * 80)
    print("TESTING /api/v1/recognize")
    print("=" * 80)
    print(f"URL: {url}")
    print(f"Institute ID: {institute_id}")
    print(f"Threshold: {threshold}")
    print(f"Base64 length: {len(base64_string)} characters")
    print(f"JSON payload size: {len(json.dumps(payload))} characters")
    print("=" * 80)
    
    try:
        response = requests.post(
            url,
            json=payload,  # Use json parameter - requests will handle encoding
            headers={"Content-Type": "application/json"},
            timeout=60
        )
        
        print(f"\nStatus Code: {response.status_code}")
        print(f"Response Headers: {dict(response.headers)}")
        
        if response.status_code == 200:
            print("\n✅ SUCCESS!")
            print(json.dumps(response.json(), indent=2))
        else:
            print(f"\n❌ ERROR: {response.status_code}")
            try:
                error_data = response.json()
                print(json.dumps(error_data, indent=2))
            except:
                print(f"Response body: {response.text[:500]}")
        
        return response
        
    except requests.exceptions.RequestException as e:
        print(f"\n❌ REQUEST ERROR: {e}")
        return None

def test_register(base64_string, institute_id="INS001", student_id="STU001", roll_number="001", name="Test Student"):
    """Test the /api/v1/register endpoint"""
    url = "http://127.0.0.1:8000/api/v1/register"
    
    payload = {
        "image_base64": base64_string,
        "institute_id": institute_id,
        "student_id": student_id,
        "roll_number": roll_number,
        "name": name
    }
    
    print("\n" + "=" * 80)
    print("TESTING /api/v1/register")
    print("=" * 80)
    print(f"URL: {url}")
    print(f"Institute ID: {institute_id}")
    print(f"Student ID: {student_id}")
    print(f"Roll Number: {roll_number}")
    print(f"Name: {name}")
    print(f"Base64 length: {len(base64_string)} characters")
    print(f"JSON payload size: {len(json.dumps(payload))} characters")
    print("=" * 80)
    
    try:
        response = requests.post(
            url,
            json=payload,  # Use json parameter - requests will handle encoding
            headers={"Content-Type": "application/json"},
            timeout=60
        )
        
        print(f"\nStatus Code: {response.status_code}")
        
        if response.status_code == 200:
            print("\n✅ SUCCESS!")
            print(json.dumps(response.json(), indent=2))
        else:
            print(f"\n❌ ERROR: {response.status_code}")
            try:
                error_data = response.json()
                print(json.dumps(error_data, indent=2))
            except:
                print(f"Response body: {response.text[:500]}")
        
        return response
        
    except requests.exceptions.RequestException as e:
        print(f"\n❌ REQUEST ERROR: {e}")
        return None

if __name__ == "__main__":
    # Read base64 string from file
    base64_file = "base64_output.txt"
    
    try:
        with open(base64_file, 'r', encoding='utf-8') as f:
            base64_string = f.read().strip()
        
        if not base64_string:
            print(f"❌ Error: {base64_file} is empty")
            sys.exit(1)
        
        print(f"✅ Loaded base64 string from {base64_file}")
        print(f"   Length: {len(base64_string)} characters")
        
        # Test recognize endpoint
        test_recognize(base64_string)
        
        # Uncomment to test register endpoint
        # test_register(base64_string)
        
    except FileNotFoundError:
        print(f"❌ Error: {base64_file} not found")
        print("   Please run convert_user_image.ps1 first to generate the base64 string")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)
