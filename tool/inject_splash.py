"""Вшивает заставку из web_splash.html в сгенерированный web/index.html.

Папка web/ в репозитории не хранится — её создаёт `flutter create` при
сборке, поэтому правку делаем в CI, сразу после генерации.

Запуск: python3 tool/inject_splash.py
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
INDEX = ROOT / "web" / "index.html"
SPLASH = ROOT / "web_splash.html"
MARKER = 'id="k-splash"'


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

    INDEX.write_text(
        html.replace("</body>", SPLASH.read_text(encoding="utf-8") + "</body>"),
        encoding="utf-8",
    )
    print("заставка вшита в web/index.html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
