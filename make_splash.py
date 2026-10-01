from PIL import Image

SRC = "assets/images/logo.png"
OUT = "assets/images/splash_logo.png"
CANVAS = 1152
LOGO_SIZE = 520  # kecilkan (mis. 440) kalau masih terasa besar

logo = Image.open(SRC).convert("RGBA")
logo.thumbnail((LOGO_SIZE, LOGO_SIZE), Image.LANCZOS)

canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
x = (CANVAS - logo.width) // 2
y = (CANVAS - logo.height) // 2
canvas.paste(logo, (x, y), logo)
canvas.save(OUT)
print("Selesai:", OUT, canvas.size)