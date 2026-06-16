#!/usr/bin/env python3
"""Convert a binary file to a C header with an embedded byte array."""

import sys
import os

def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <input.bin> <output.h> <variable_name>")
        sys.exit(1)

    in_path = sys.argv[1]
    out_path = sys.argv[2]
    var_name = sys.argv[3]

    with open(in_path, "rb") as f:
        data = f.read()

    size = len(data)
    var_name_upper = var_name.upper()

    with open(out_path, "w") as f:
        f.write(f"// Auto-generated from {os.path.basename(in_path)}\n")
        f.write(f"#ifndef {var_name_upper}_H\n")
        f.write(f"#define {var_name_upper}_H\n\n")
        f.write(f"#ifdef __cplusplus\n")
        f.write(f"extern \"C\" {{\n")
        f.write(f"#endif\n\n")
        f.write(f"static const unsigned char k{var_name}Spv[] = {{\n")

        for i in range(0, size, 12):
            chunk = data[i:i+12]
            hex_str = ", ".join(f"0x{b:02x}" for b in chunk)
            f.write(f"  {hex_str},\n")

        f.write(f"}};\n")
        f.write(f"static const int k{var_name}SpvSize = {size};\n\n")
        f.write(f"#ifdef __cplusplus\n")
        f.write(f"}}\n")
        f.write(f"#endif\n\n")
        f.write(f"#endif // {var_name_upper}_H\n")

    print(f"Generated {out_path}: {size} bytes -> {var_name}")

if __name__ == "__main__":
    main()
