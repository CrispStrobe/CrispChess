import os
import re

# Configuration
SOURCE_DIR = 'raw_pieces'
TARGET_DIR = 'assets/pieces'
os.makedirs(TARGET_DIR, exist_ok=True)

# Map standard names to the 1-letter suffix used by your Flutter app
# Filename -> Suffix (e.g., pawn -> P)
PIECE_MAP = {
    'pawn': 'P',
    'knight': 'N',
    'bishop': 'B',
    'rook': 'R',
    'queen': 'Q',
    'king': 'K'
}

def process_pieces():
    print(f"Processing SVGs from '{SOURCE_DIR}'...")

    for name, code in PIECE_MAP.items():
        source_path = os.path.join(SOURCE_DIR, f"{name}.svg")
        
        if not os.path.exists(source_path):
            print(f"⚠️ Warning: {name}.svg not found in {SOURCE_DIR}")
            continue

        with open(source_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # --- 1. Save Black Piece (bP.svg, bK.svg...) ---
        # We assume the source is already black. We just copy/rename it.
        black_filename = f"b{code}.svg"
        with open(os.path.join(TARGET_DIR, black_filename), 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Created {black_filename}")

        # --- 2. Create White Piece (wP.svg, wK.svg...) ---
        # Strategy: 
        # 1. Find the main path/g/svg tag and force fill="white" and stroke="black".
        # 2. This is a naive regex approach but works for 99% of simple icon SVGs.
        
        # Replace existing fill colors (black/000) with white
        white_content = re.sub(r'fill="[^"]+"', 'fill="#ffffff"', content)
        white_content = re.sub(r'fill:[^;]+;', 'fill:#ffffff;', white_content)
        
        # If there was no fill attribute, we inject it into the <path> or <g> tag
        # We also ADD a stroke so the white piece is visible on white squares
        stroke_style = ' stroke="#000000" stroke-width="10" stroke-linejoin="round" '
        
        # Inject stroke into <path> tags
        if '<path' in white_content:
            white_content = white_content.replace('<path', f'<path fill="#ffffff" {stroke_style}')
        elif '<g' in white_content:
             white_content = white_content.replace('<g', f'<g fill="#ffffff" {stroke_style}')

        # Cleanup: If we accidentally doubled attributes, remove the old black fill if it persisted
        # (Regex to ensure we didn't leave a fill="#000000" overriding our new one)
        # This part assumes standard SVG formatting.
        
        white_filename = f"w{code}.svg"
        with open(os.path.join(TARGET_DIR, white_filename), 'w', encoding='utf-8') as f:
            f.write(white_content)
        print(f"Created {white_filename} (with outline)")

    print(f"\n✅ Done! Check the '{TARGET_DIR}' folder.")

if __name__ == "__main__":
    process_pieces()
