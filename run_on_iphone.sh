#!/usr/bin/env bash
# ============================================================================
# КОМПЛЕКТ — установка на iPhone с чужого Mac (бесплатно, без Apple Developer).
#
# Что делает: готовит проект к запуску на реальном устройстве —
# создаёт .env, генерирует папку ios/, прописывает разрешения и версию iOS.
# Сборку и установку запускает Xcode/Flutter на последнем шаге.
#
# Запуск:  bash run_on_iphone.sh
# ============================================================================
set -e

BUNDLE_ID="kz.komplekt.app"   # при конфликте поменяйте на своё, например kz.abelkz.komplekt

echo "──────────────────────────────────────────"
echo " КОМПЛЕКТ · подготовка к запуску на iPhone"
echo "──────────────────────────────────────────"

# 1. Проверяем инструменты
if ! command -v flutter >/dev/null 2>&1; then
  echo "✗ Flutter не установлен."
  echo "  Установите:  brew install --cask flutter"
  echo "  Или скачайте: https://docs.flutter.dev/get-started/install/macos"
  exit 1
fi
echo "✓ Flutter найден: $(flutter --version | head -1)"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "✗ Xcode не установлен. Поставьте его из App Store и откройте один раз,"
  echo "  чтобы принять лицензию, затем запустите скрипт снова."
  exit 1
fi
echo "✓ Xcode найден"

# 2. Файл с настройками. Реальные ключи можно не вписывать —
#    без них приложение поднимется на встроенных демо-данных.
if [ ! -f .env ]; then
  cp .env.example .env
  echo "✓ Создан .env (демо-режим)."
  echo "  Чтобы подключить настоящую базу, впишите в .env свои SUPABASE_URL"
  echo "  и SUPABASE_ANON_KEY, а DEMO_MODE поставьте false."
else
  echo "✓ .env уже есть"
fi

# 3. Папка ios/ в репозитории не хранится — генерируем
if [ ! -d ios ]; then
  flutter create . --platforms=ios >/dev/null
  echo "✓ Сгенерирована папка ios/"
else
  echo "✓ Папка ios/ уже есть"
fi

# 4. Разрешения. Без них iOS закрывает приложение при обращении
#    к галерее или геопозиции.
P=ios/Runner/Info.plist
set_str() {
  /usr/libexec/PlistBuddy -c "Delete :$1" "$P" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$P"
}
set_str NSPhotoLibraryUsageDescription \
  "Доступ к фото нужен, чтобы прикрепить изображение товара к вашему прайсу."
set_str NSCameraUsageDescription \
  "Доступ к камере нужен, чтобы сфотографировать товар для карточки."
set_str NSLocationWhenInUseUsageDescription \
  "Геопозиция нужна, чтобы показать поставщиков рядом с вами на карте."
/usr/libexec/PlistBuddy -c "Delete :LSApplicationQueriesSchemes" "$P" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSApplicationQueriesSchemes array" "$P"
/usr/libexec/PlistBuddy -c "Add :LSApplicationQueriesSchemes:0 string tel" "$P"
/usr/libexec/PlistBuddy -c "Add :LSApplicationQueriesSchemes:1 string whatsapp" "$P"
echo "✓ Разрешения прописаны"

# 5. Минимальная версия iOS: Firebase требует 13+
if grep -q "^# *platform :ios" ios/Podfile; then
  sed -i '' "s/^# *platform :ios.*/platform :ios, '13.0'/" ios/Podfile
elif ! grep -q "^platform :ios" ios/Podfile; then
  printf "platform :ios, '13.0'\n%s\n" "$(cat ios/Podfile)" > ios/Podfile
fi
sed -i '' -E "s/IPHONEOS_DEPLOYMENT_TARGET = 1[0-2]\.[0-9]+;/IPHONEOS_DEPLOYMENT_TARGET = 13.0;/g" \
  ios/Runner.xcodeproj/project.pbxproj
echo "✓ Минимальная версия iOS — 13.0"

# 6. Уникальное имя пакета: бесплатная учётка Apple не даст поставить
#    приложение с идентификатором, который уже кем-то занят.
sed -i '' -E "s/PRODUCT_BUNDLE_IDENTIFIER = [^;]+;/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;/g" \
  ios/Runner.xcodeproj/project.pbxproj
echo "✓ Идентификатор приложения: $BUNDLE_ID"

flutter pub get >/dev/null
echo "✓ Зависимости установлены"

echo
echo "──────────────────────────────────────────"
echo " Осталось два шага вручную"
echo "──────────────────────────────────────────"
echo
echo "1. ПОДПИСЬ (один раз):"
echo "   open ios/Runner.xcworkspace"
echo "   В Xcode слева выберите Runner → вкладка Signing & Capabilities →"
echo "   галочка «Automatically manage signing» → в поле Team выберите"
echo "   свой Apple ID (Personal Team). Если списка нет:"
echo "   Xcode → Settings → Accounts → «+» → войдите обычным Apple ID."
echo
echo "2. ЗАПУСК:"
echo "   Подключите iPhone кабелем, на телефоне нажмите «Доверять»."
echo "   Затем:  flutter devices     (убедиться, что телефон виден)"
echo "           flutter run --release"
echo
echo "После установки на iPhone откройте:"
echo "   Настройки → Основные → VPN и управление устройством →"
echo "   выберите разработчика → «Доверять»"
echo
echo "Приложение проработает 7 дней — это ограничение бесплатной учётной"
echo "записи Apple. Потом просто запустите flutter run снова."
