"""
Quick script to convert image to base64 for Postman testing
Usage: python convert_image_to_base64.py path/to/image.jpg
"""

import sys
import base64
import os

def image_to_base64(image_path):
    """Convert image file to base64 string"""
    if not os.path.exists(image_path):
        print(f"❌ Error: File not found: {image_path}")
        return None
    
    try:
        with open(image_path, "rb") as image_file:
            encoded = base64.b64encode(image_file.read()).decode('utf-8')
            return encoded
    except Exception as e:
        print(f"❌ Error converting image: {e}")
        return None

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python convert_image_to_base64.py <image_path>")
        print("Example: python convert_image_to_base64.py face.jpg")
        sys.exit(1)
    
    image_path = sys.argv[1]
    base64_string = image_to_base64(image_path)
    
    if base64_string:
        print("\n✅ Base64 encoded image:")
        print("=" * 80)
        print(base64_string)
        print("=" * 80)
        print(f"\n📋 Copy this string and paste it in Postman as 'image_base64' value")
        print(f"📏 Base64 length: {len(base64_string)} characters")
        print(f"📦 Image size: {os.path.getsize(image_path)} bytes")
    else:
        sys.exit(1)
