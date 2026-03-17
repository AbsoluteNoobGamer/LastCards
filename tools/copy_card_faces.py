"""Copy user card images to project with correct naming for the app."""
import shutil
from pathlib import Path

SRC = Path(r"C:\Users\AbsoluteNoobGamer\.cursor\projects\c-Users-AbsoluteNoobGamer-Desktop-dev-cards\assets")
OUT = Path("assets/images/cardfaces/default")
JOKER_OUT = Path("assets/images/jokercover")

RANK_MAP = {
    "ace": "ace", "2": "two", "3": "three", "4": "four", "5": "five",
    "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten",
    "jack": "jack", "queen": "queen", "king": "king",
}
SUITS = ["spades", "clubs", "hearts", "diamonds"]

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    JOKER_OUT.mkdir(parents=True, exist_ok=True)

    copied = 0
    for f in SRC.glob("*.png"):
        name = f.stem
        if "_" not in name or not name.startswith("c__"):
            continue
        # Extract logical name: images_ace_of_spades-uuid -> ace_of_spades
        try:
            idx = name.index("images_") + 7
            rest = name[idx:].split("-")[0]
            logical = rest.replace("_of_", "_")  # ace_of_spades -> ace_spades
        except ValueError:
            continue
        # Skip alternate versions (e.g. ace_of_spades2)
        if logical[-1].isdigit():
            continue
        # Check if it's a suited card: rank_suit
        parts = logical.split("_")
        if len(parts) == 2 and parts[1] in SUITS:
            rank = RANK_MAP.get(parts[0])
            if rank:
                dest = OUT / f"{rank}_{parts[1]}.png"
                shutil.copy2(f, dest)
                copied += 1
        # Jokers
        elif "black_joker" in name or "black_joker" in logical:
            shutil.copy2(f, JOKER_OUT / "Black Joker.png")
            copied += 1
        elif "red_joker" in name or "red_joker" in logical:
            shutil.copy2(f, JOKER_OUT / "Red Joker.png")
            copied += 1
    # Handle ace_of_spades when we have ace_of_spades2 (use non-2)
    for f in SRC.glob("*ace_of_spades*.png"):
        name = f.stem
        if "images_" not in name: continue
        idx = name.index("images_") + 7
        rest = name[idx:].split("-")[0]
        if rest == "ace_of_spades" and "2" not in rest:
            shutil.copy2(f, OUT / "ace_spades.png")
            copied += 1
            break
    print(f"Copied {copied} images")

if __name__ == "__main__":
    main()
