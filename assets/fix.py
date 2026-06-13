import os
import xml.etree.ElementTree as ET

# Configuration
SOURCE_DIR = 'raw_pieces'
TARGET_DIR = 'assets/pieces'
os.makedirs(TARGET_DIR, exist_ok=True)

# Map filenames to Flutter asset suffixes
PIECE_MAP = {
    'pawn': 'P', 'knight': 'N', 'bishop': 'B', 
    'rook': 'R', 'queen': 'Q', 'king': 'K'
}

# Register the SVG namespace so the output file doesn't have "ns0:" prefixes
ET.register_namespace('', "http://www.w3.org/2000/svg")
SVG_NS = "{http://www.w3.org/2000/svg}"

def style_element_for_white(elem):
    """Sets fill to white and adds a black stroke."""
    elem.set('fill', '#ffffff')
    elem.set('stroke', '#000000')
    # Stroke width 2 is good for a 50x50 viewbox. 
    # If lines look too thick/thin, adjust this number.
    elem.set('stroke-width', '2') 
    elem.set('stroke-linejoin', 'round')

def style_element_for_black(elem):
    """Sets fill to black and adds a thin white stroke for contrast."""
    elem.set('fill', '#000000')
    elem.set('stroke', '#ffffff')
    elem.set('stroke-width', '0.5') # Subtle outline to separate from dark squares
    elem.set('stroke-linejoin', 'round')

def process_pieces():
    print(f"Processing SVGs from '{SOURCE_DIR}'...")

    for name, code in PIECE_MAP.items():
        source_path = os.path.join(SOURCE_DIR, f"{name}.svg")
        
        if not os.path.exists(source_path):
            print(f"⚠️  Skipping {name}.svg (not found)")
            continue

        # --- Parse the XML ---
        try:
            tree = ET.parse(source_path)
            root = tree.getroot()
        except ET.ParseError as e:
            print(f"❌ Error parsing {name}.svg: {e}")
            continue

        # Identify shapes to style (paths, circles, rects, etc.)
        # We look for tags ending in these names to handle namespaces automatically
        shape_tags = ['path', 'circle', 'rect', 'polygon', 'ellipse']

        # --- Create BLACK Version ---
        # Reload tree to ensure clean state
        tree_b = ET.parse(source_path)
        root_b = tree_b.getroot()
        
        for elem in root_b.iter():
            # Check if tag is a shape (ignoring the namespace prefix)
            if any(elem.tag.endswith(t) for t in shape_tags):
                style_element_for_black(elem)

        tree_b.write(os.path.join(TARGET_DIR, f"b{code}.svg"), encoding='utf-8', xml_declaration=False)
        print(f"  Created b{code}.svg")

        # --- Create WHITE Version ---
        # Reload tree again for the white version
        tree_w = ET.parse(source_path)
        root_w = tree_w.getroot()

        for elem in root_w.iter():
            if any(elem.tag.endswith(t) for t in shape_tags):
                style_element_for_white(elem)

        tree_w.write(os.path.join(TARGET_DIR, f"w{code}.svg"), encoding='utf-8', xml_declaration=False)
        print(f"  Created w{code}.svg")

    print(f"\n✅ Success! SVGs saved to {TARGET_DIR}")

if __name__ == "__main__":
    process_pieces()
