#!/usr/bin/env bash
# Доводит сгенерированную папку android/ до рабочего состояния.
#
# ЗАЧЕМ ОТДЕЛЬНЫЙ ФАЙЛ. Папки android/ в git нет — её создаёт
# `flutter create . --platforms=android` в каждой сборке (CLAUDE.md §6.4),
# поэтому все правки манифеста и Gradle живут скриптом. Раньше скрипт
# лежал прямо в ci.yaml. С появлением сборки для Google Play их стало бы
# два, и они разошлись бы при первой же правке: отладочный APK с одним
# набором разрешений, выпуск в магазин — с другим. Теперь источник один.
#
# Запуск: из корня проекта, после `flutter create . --platforms=android`.
#
# Подпись выпуска включается, только если задана переменная
# ANDROID_KEYSTORE_PATH. Без неё выпуск подписывается отладочным ключом,
# как и было, — отладочному APK боевой ключ не нужен, и давать его каждой
# сборке незачем.
set -euo pipefail

python3 - <<'PY'
path = 'android/app/src/main/AndroidManifest.xml'
xml = open(path, encoding='utf-8').read()

if 'login-callback' not in xml:
    block = (
        '        <intent-filter>\n'
        '            <action android:name="android.intent.action.VIEW" />\n'
        '            <category android:name="android.intent.category.DEFAULT" />\n'
        '            <category android:name="android.intent.category.BROWSABLE" />\n'
        '            <data android:scheme="kz.komplekt.app" android:host="login-callback" />\n'
        '        </intent-filter>\n'
    )
    xml = xml.replace('</activity>', block + '        </activity>', 1)

# Android 13+ не показывает уведомления без этого разрешения, причём
# молча: FirebaseMessaging.requestPermission() показывает системный
# запрос только если разрешение объявлено в манифесте.
#
# Геопозиция — для «Поставщики рядом». Без этих двух строк geolocator
# на Android не показывает запрос вовсе: он отвечает «в манифесте не
# объявлено ни одного разрешения геопозиции», и карта остаётся без точки
# пользователя. На iOS описания геопозиции добавляет codemagic.yaml, а на
# Android их просто никогда не было — отладочный APK этим мало кто
# проверял.
for name in ('POST_NOTIFICATIONS', 'ACCESS_COARSE_LOCATION',
             'ACCESS_FINE_LOCATION'):
    if name not in xml:
        perm = ('<uses-permission '
                'android:name="android.permission.%s" />\n    ' % name)
        xml = xml.replace('<application', perm + '<application', 1)

# Android 11+: без <queries> url_launcher не открывает браузер,
# tel: и WhatsApp — canLaunchUrl/launch не находят приложение.
#
# Проверяем по своей записи, а не по наличию блока: шаблон Flutter уже
# содержит <queries> (для PROCESS_TEXT). Пока условием было «блока нет»,
# оно не выполнялось никогда, и наши записи в манифест не попадали вовсе.
if 'android:scheme="tel"' not in xml:
    intents = (
        '        <intent>\n'
        '            <action android:name="android.intent.action.VIEW" />\n'
        '            <data android:scheme="https" />\n'
        '        </intent>\n'
        '        <intent>\n'
        '            <action android:name="android.intent.action.VIEW" />\n'
        '            <data android:scheme="http" />\n'
        '        </intent>\n'
        '        <intent>\n'
        '            <action android:name="android.intent.action.DIAL" />\n'
        '            <data android:scheme="tel" />\n'
        '        </intent>\n'
    )
    if '<queries>' in xml:
        xml = xml.replace('<queries>\n', '<queries>\n' + intents, 1)
    else:
        xml = xml.replace(
            '<application',
            '<queries>\n' + intents + '    </queries>\n    <application', 1)
    if 'android:scheme="tel"' not in xml:
        raise SystemExit('::error::Не удалось добавить <queries> в манифест')

open(path, 'w', encoding='utf-8').write(xml)
print('→ манифест: вход по ссылке, уведомления, геопозиция, queries')
PY

F=android/app/build.gradle.kts
# flutter create без --org даёт applicationId com.example.komplekt.
# Фиксируем тот же идентификатор, что и у iOS: под ним заводится
# приложение в Firebase, а с com.example.* публикация в Google Play
# невозможна в принципе. namespace не трогаем — он задаёт пакет
# класса R и к сопоставлению с Firebase отношения не имеет.
sed -i -E 's/applicationId = "[^"]*"/applicationId = "kz.komplekt.app"/' "$F"
sed -i '/compileOptions {/a\        isCoreLibraryDesugaringEnabled = true' "$F"
sed -i -E '/^[[:space:]]*compileSdk[[:space:]]*=/ s/=.*/= 36/' "$F"
sed -i -E '/^[[:space:]]*minSdk[[:space:]]*=/ s/=.*/= 23/' "$F"
# Google Play с 31.08.2026 принимает новые приложения и обновления только
# с targetSdk 36 (Android 16). Что подставит Flutter по умолчанию, зависит
# от его версии на раннере, поэтому задаём явно: иначе загрузка однажды
# отобьётся уже в консоли Play, после получаса сборки.
sed -i -E '/^[[:space:]]*targetSdk[[:space:]]*=/ s/=.*/= 36/' "$F"
printf '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n' >> "$F"

G=android/build.gradle.kts
{ printf 'subprojects {\n    afterEvaluate {\n        val a = extensions.findByName("android")\n        if (a is com.android.build.gradle.BaseExtension) { a.compileSdkVersion(36) }\n    }\n}\n\n'; cat "$G"; } > "$G.tmp" && mv "$G.tmp" "$G"
echo "→ Gradle: kz.komplekt.app, minSdk 23, compileSdk/targetSdk 36"

# Файл настроек .env обязан попасть в сборку.
#
# Он объявлен ресурсом в pubspec.yaml, и Flutter честно кладёт его к
# остальным. Но упаковщик Android по умолчанию МОЛЧА выбрасывает всё, что
# начинается с точки (в его списке исключений стоит «.*»). В итоге в
# списке ресурсов .env значится, а в APK его нет: приложение падает на
# первой же строке main() с FileNotFoundError, и человек видит заставку,
# которая не кончается. Ни сборка, ни анализ, ни тесты этого не замечают —
# нашлось только запуском на эмуляторе 15.11.2026.
#
# Убираем «.*» из списка исключений; остальное — как в стандартном.
python3 - <<'PY'
import re
import sys

path = 'android/app/build.gradle.kts'
src = open(path, encoding='utf-8').read()
if 'ignoreAssetsPattern' not in src:
    if len(re.findall(r'^android \{$', src, flags=re.M)) != 1:
        sys.exit('::error::Шаблон android/app/build.gradle.kts изменился: '
                 'не нашёл блок android, чтобы сохранить .env в сборке. '
                 'Поправьте tool/prepare_android.sh.')
    keep = ('android {\n'
            '    androidResources {\n'
            '        ignoreAssetsPattern = '
            '"!.svn:!.git:!.ds_store:!*.scc:!CVS:!thumbs.db:!picasa.ini:!*~"\n'
            '    }\n')
    src = re.sub(r'^android \{$\n', keep, src, count=1, flags=re.M)
    open(path, 'w', encoding='utf-8').write(src)
print('→ упаковщик не выбрасывает .env')
PY

if [ -n "${ANDROID_KEYSTORE_PATH:-}" ]; then
  python3 - <<'PY'
import sys

path = 'android/app/build.gradle.kts'
src = open(path, encoding='utf-8').read()

# Пароли читает сам Gradle из переменных окружения, а не из файла:
# в key.properties пришлось бы экранировать спецсимволы пароля, и
# ошибка в этом выглядит как «неверный пароль хранилища».
signing = '''    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH"))
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }

'''
anchor = '    buildTypes {'
debug = 'signingConfigs.getByName("debug")'

# Шаблон Flutter меняется от версии к версии. Если он изменился, лучше
# упасть здесь с понятным текстом, чем молча собрать выпуск с отладочной
# подписью: такой файл Google Play не примет, а узнаем мы об этом уже
# при загрузке.
if src.count(anchor) != 1 or src.count(debug) != 1:
    sys.exit('::error::Шаблон android/app/build.gradle.kts изменился: '
             'не нашёл, куда подставить подпись выпуска. Поправьте '
             'tool/prepare_android.sh.')

src = src.replace(anchor, signing + anchor)
src = src.replace(debug, 'signingConfigs.getByName("release")')
open(path, 'w', encoding='utf-8').write(src)
print('→ выпуск подписывается ключом из ANDROID_KEYSTORE_PATH')
PY
else
  echo "→ ключ выпуска не задан: выпуск подписывается отладочным ключом"
fi
