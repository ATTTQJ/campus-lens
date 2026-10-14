"""Create the original code-drawn app icon. Pillow is needed only to regenerate."""
from pathlib import Path
from PIL import Image, ImageDraw
import json

root = Path(__file__).resolve().parent.parent/"App/Assets.xcassets"
icon_dir = root/"AppIcon.appiconset"
icon_dir.mkdir(parents=True,exist_ok=True)
image = Image.new("RGB",(1024,1024),(9,37,48))
d = ImageDraw.Draw(image)
for y in range(1024):
    d.line((0,y,1024,y),fill=(9,37+int(y*0.018),48+int(y*0.03)))
d.rounded_rectangle((160,286,864,766),radius=100,fill=(38,177,166))
d.rounded_rectangle((272,218,464,340),radius=34,fill=(38,177,166))
d.ellipse((358,336,766,744),fill=(11,43,53))
d.ellipse((416,394,708,686),outline=(222,255,238),width=22)
# Campus roof and columns within the lens.
d.polygon([(462,507),(562,448),(662,507)],fill=(222,255,238))
for x in (474,548,622):
    d.rounded_rectangle((x,529,x+28,608),radius=5,fill=(222,255,238))
d.rounded_rectangle((459,630,668,648),radius=7,fill=(222,255,238))
d.ellipse((228,374,288,434),fill=(222,255,238))
image.save(icon_dir/"AppIcon.png")
(root/"Contents.json").write_text(json.dumps({"info":{"author":"xcode","version":1}},indent=2)+"\n")
(icon_dir/"Contents.json").write_text(json.dumps({"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}},indent=2)+"\n")
print("Created code-drawn 1024px RGB icon")
