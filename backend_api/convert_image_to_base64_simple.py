"""
Simple script to convert an image to base64
Usage: python convert_image_to_base64_simple.py <image_path>
"""

import base64
import sys
import os

if len(sys.argv) < 2:
    print("❌ Please provide the image path!")
    print("\nUsage:")
    print("  python convert_image_to_base64_simple.py <image_path>")
    print("\nExample:")
    print("  python convert_image_to_base64_simple.py C:/Users/naikw/Pictures/photo.jpg")
    print("  python convert_image_to_base64_simple.py photo.png")
    sys.exit(1)

image_path = sys.argv[1]

if not os.path.exists(image_path):
    print(f"❌ Error: File not found: {image_path}")
    sys.exit(1)

try:
    # Read image and convert to base64
    with open(image_path, "rb") as image_file:
        image_bytes = image_file.read()
        base64_string = base64.b64encode(image_bytes).decode('utf-8')
    
    # Get file size
    file_size = os.path.getsize(image_path)
    
    print("\n" + "=" * 80)
    print("✅ BASE64 ENCODED IMAGE GENERATED!")
    print("=" * 80)
    print(f"\n📁 Image Path: {image_path}")
    print(f"📦 Original Size: {file_size:,} bytes ({file_size/1024:.2f} KB)")
    print(f"📏 Base64 Length: {len(base64_string):,} characters")
    print("\n" + "=" * 80)
    print("📋 COPY THIS BASE64 STRING:")
    print("=" * 80)
    print(base64_string)
    print("=" * 80)
    print("\n💡 How to use:")
    print("   1. Copy the base64 string above")
    print("   2. Go to: http://127.0.0.1:8000/docs")
    print("   3. Click '/api/v1/recognize' → 'Try it out'")
    print("   4. Paste the base64 string in 'image_base64' field")
    print("   5. Set 'institute_id' to 'INS001'")
    print("   6. Click 'Execute'")
    print("\n" + "=" * 80)
    
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
