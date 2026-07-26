"""
Quick test script to convert image to base64
Usage: python test_base64.py [image_path]
If no path provided, will look for common image files in current directory
"""

import base64
import os
import sys
import glob

def find_image_file():
    """Try to find an image file in current directory"""
    extensions = ['*.jpg', '*.jpeg', '*.png', '*.JPG', '*.JPEG', '*.PNG']
    for ext in extensions:
        files = glob.glob(ext)
        if files:
            return files[0]
    return None

if __name__ == "__main__":
    # Get image path from command line or try to find one
    if len(sys.argv) > 1:
        image_path = sys.argv[1]
    else:
        # Try to find an image file
        image_path = find_image_file()
        if not image_path:
            print("❌ No image file found!")
            print("\nUsage:")
            print("  python test_base64.py <image_path>")
            print("\nExample:")
            print("  python test_base64.py face.jpg")
            print("  python test_base64.py C:/Users/naikw/Pictures/photo.jpg")
            sys.exit(1)
        else:
            print(f"📸 Found image: {image_path}")
    
    # Check if file exists
    if not os.path.exists(image_path):
        print(f"❌ Error: File not found: {image_path}")
        sys.exit(1)
    
    # Convert to base64
    try:
        with open(image_path, "rb") as image_file:
            base64_string = base64.b64encode(image_file.read()).decode()
        
        print("\n" + "=" * 80)
        print("✅ BASE64 ENCODED IMAGE:")
        print("=" * 80)
        print(base64_string)
        print("=" * 80)
        print(f"\n📋 Copy the base64 string above and use it in:")
        print(f"   • Postman: Paste as 'image_base64' value")
        print(f"   • Swagger: http://127.0.0.1:8000/docs")
        print(f"   • curl: Use in JSON body")
        print(f"\n📏 Base64 length: {len(base64_string):,} characters")
        print(f"📦 Image size: {os.path.getsize(image_path):,} bytes ({os.path.getsize(image_path)/1024:.2f} KB)")
        print(f"📁 Image path: {image_path}")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)
