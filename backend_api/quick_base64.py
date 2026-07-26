"""
Quick interactive script to convert image to base64
Just run: python quick_base64.py
"""

import base64
import os
import sys

print("\n" + "=" * 80)
print("🖼️  IMAGE TO BASE64 CONVERTER")
print("=" * 80)
print()

# Get image path
if len(sys.argv) > 1:
    image_path = sys.argv[1]
else:
    image_path = input("📁 Enter the full path to your image file: ").strip().strip('"').strip("'")

# Check if file exists
if not os.path.exists(image_path):
    print(f"\n❌ Error: File not found: {image_path}")
    print("\n💡 Make sure:")
    print("   • The file path is correct")
    print("   • You've saved the image to your computer first")
    print("   • Use full path like: C:\\Users\\naikw\\Desktop\\image.jpg")
    sys.exit(1)

try:
    # Read and convert
    print(f"\n🔄 Converting: {image_path}")
    with open(image_path, "rb") as f:
        image_bytes = f.read()
        base64_string = base64.b64encode(image_bytes).decode('utf-8')
    
    file_size = os.path.getsize(image_path)
    
    print("\n" + "=" * 80)
    print("✅ SUCCESS! BASE64 STRING GENERATED")
    print("=" * 80)
    print(f"\n📁 Image: {image_path}")
    print(f"📦 Size: {file_size:,} bytes ({file_size/1024:.2f} KB)")
    print(f"📏 Base64 Length: {len(base64_string):,} characters")
    print("\n" + "=" * 80)
    print("📋 COPY THIS BASE64 STRING (it's very long):")
    print("=" * 80)
    print()
    print(base64_string)
    print()
    print("=" * 80)
    print("\n💡 Next Steps:")
    print("   1. Copy the entire base64 string above")
    print("   2. Open: http://127.0.0.1:8000/docs")
    print("   3. Click '/api/v1/recognize' → 'Try it out'")
    print("   4. Paste base64 in 'image_base64' field")
    print("   5. Set 'institute_id': 'INS001'")
    print("   6. Click 'Execute'")
    print("\n" + "=" * 80)
    
except Exception as e:
    print(f"\n❌ Error: {e}")
    sys.exit(1)
