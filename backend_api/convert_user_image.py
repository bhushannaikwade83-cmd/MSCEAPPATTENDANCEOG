import base64
import sys

# Image path provided by user
img_path = r'C:\Users\naikw\Downloads\WhatsApp Image 2026-03-04 at 23.32.03.jpeg'

try:
    # Read image file
    with open(img_path, 'rb') as f:
        img_bytes = f.read()
    
    # Convert to base64
    b64 = base64.b64encode(img_bytes).decode('utf-8')
    
    # Print info
    print("=" * 80)
    print("BASE64 CONVERSION SUCCESSFUL")
    print("=" * 80)
    print(f"Image path: {img_path}")
    print(f"Original file size: {len(img_bytes)} bytes ({len(img_bytes)/1024:.2f} KB)")
    print(f"Base64 string length: {len(b64)} characters")
    print(f"Base64 preview (first 100 chars): {b64[:100]}...")
    print(f"Base64 preview (last 100 chars): ...{b64[-100:]}")
    print("\n" + "=" * 80)
    print("FULL BASE64 STRING (copy this for API testing):")
    print("=" * 80)
    print(b64)
    print("=" * 80)
    
    # Also save to file for easy access
    output_file = 'base64_output.txt'
    with open(output_file, 'w') as f:
        f.write(b64)
    print(f"\n✅ Base64 string also saved to: {output_file}")
    
except FileNotFoundError:
    print(f"❌ Error: Image file not found at: {img_path}")
    print("Please check the file path.")
    sys.exit(1)
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
