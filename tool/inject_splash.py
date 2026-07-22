"""Вшивает заставку из web_splash.html в сгенерированный web/index.html.

Папка web/ в репозитории не хранится — её создаёт `flutter create` при
сборке, поэтому правку делаем в CI, сразу после генерации.

Запуск: python3 tool/inject_splash.py
"""

import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
INDEX = ROOT / "web" / "index.html"
SPLASH = ROOT / "web_splash.html"
LOGO = ROOT / "brand" / "logo.png"
MARKER = 'id="k-splash"'

# буквенный знак по умолчанию и его замена картинкой
TEXT_MARK = '<div class="mark" id="k-mark">К<i></i></div>'
IMAGE_MARK = '<img class="logo" id="k-mark" src="logo.png" alt="КОМПЛЕКТ">'


def main() -> int:
    if not INDEX.exists():
        print("web/index.html не найден — сначала flutter create . --platforms=web")
        return 1
    if not SPLASH.exists():
        print("web_splash.html не найден")
        return 1

    html = INDEX.read_text(encoding="utf-8")
    if MARKER in html:
        print("заставка уже вшита — пропускаю")
        return 0
    if "</body>" not in html:
        print("в index.html нет </body> — вшивать некуда")
        return 1

    splash = SPLASH.read_text(encoding="utf-8")

    # Есть фирменный знак — подставляем картинку вместо буквенного знака
    if LOGO.exists():
        shutil.copyfile(LOGO, INDEX.parent / "logo.png")
        splash = splash.replace(TEXT_MARK, IMAGE_MARK)
        print("логотип brand/logo.png подставлен в заставку")
    else:
        print("brand/logo.png нет — оставляю буквенный знак")

    INDEX.write_text(html.replace("</body>", splash + "</body>"), encoding="utf-8")
    print("заставка вшита в web/index.html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
