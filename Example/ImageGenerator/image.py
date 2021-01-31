import os
import sys
import textwrap
from PIL import Image, ImageDraw, ImageFont


if __name__ == "__main__":
  if len(sys.argv) != 3:
    print("Needs 2 arguments!", sys.argv)
    sys.exit()

  title = sys.argv[1]
  output_path = sys.argv[2]
  image = Image.open('background.png')
  font = ImageFont.truetype('Roboto-Regular.ttf', 55, encoding='unic')

  draw = ImageDraw.Draw(image)

  offset = 60
  for line in textwrap.wrap(title, width=36):
      draw.text((30, offset), line, font=font, fill="#FFFFFF")
      offset += 70

  image.save(output_path, format="PNG")
