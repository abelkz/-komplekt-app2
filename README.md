# КОМПЛЕКТ

Мобильное приложение-маркетплейс отделочных и строительных материалов
(Астана, Казахстан/СНГ). Концепция «2GIS + OLX + Pinterest» для ремонта.

**Стек:** Flutter · Dart · Material 3 · Riverpod · go_router · Supabase
(Postgres + PostGIS, Auth, Storage) · flutter_map + OpenStreetMap.

---

## Что уже реализовано (MVP)

- Онбординг (выбор города) и авторизация (email + телефон через Supabase Auth)
- Главная: поиск, категории, лента вдохновения (masonry-сетка)
- Каталог категории с фильтрами (город, наличие) и сортировкой
- Карточка товара: галерея, сравнение цен поставщиков, отзывы, связь
  (звонок / WhatsApp / сайт)
- Карта поставщиков рядом (геолокация + маркеры OSM, PostGIS-поиск)
- Избранное, Подборки (количество, итог, экспорт спецификации в **Excel** и
  **PDF** с кириллицей + копирование текстом)
- **Пуш-уведомления о снижении цены** на товары из избранного (FCM): триггер
  в БД → очередь → Edge Function → Firebase
- Экран **истории уведомлений** о снижении цены (старая → новая цена, −%)
- Профиль (город, тёмная тема, выход)
- Витрина продавца
- **Кабинет поставщика** (роль `supplier`): заявка с проверкой админом,
  добавление товаров и цен, **загрузка фото товара** в Supabase Storage,
  импорт прайса из Excel с сопоставлением колонок, статистика
  просмотров/контактов
- Поиск по фото — заглушка (кнопка есть, логика позже)

Тёмная тема, состояния loading/empty/error, ключи только через `.env`.

---

## Архитектура

Feature-first: `lib/features/<feature>/{data,domain,presentation}`,
общий слой — `lib/core/`. Подробное дерево — в чате этапа 1.

---

## Быстро «пощупать» — демо-режим (без Supabase и Firebase)

Чтобы просто потыкать приложение, бэкенд не нужен. В демо-режиме оно работает
на встроенных тестовых данных (категории, товары, цены, поставщики), вход в
аккаунт пропускается.

1. Установите Flutter и эмулятор (раздел «Запуск на Windows», шаг 0).
2. `flutter create .` в папке проекта.
3. Скопируйте `.env.example` → `.env` (в нём уже `DEMO_MODE=true`).
4. `flutter pub get` → `flutter run`.

Откроется онбординг → выбор города → главная с каталогом, сравнением цен,
картой, избранным и подборками. Кабинет поставщика и загрузка фото в демо
отключены (требуют бэкенд).

Когда захотите подключить реальную базу — впишите в `.env` ключи Supabase и
поставьте `DEMO_MODE=false`.

## Запуск на Windows (с нуля)

### 0. Что нужно один раз установить
- **Flutter SDK** (stable) — распакуйте в `C:\src\flutter`, добавьте
  `C:\src\flutter\bin` в переменную среды Path.
- **Android Studio** + Android SDK + эмулятор (Pixel, Android 14).
- Проверьте: `flutter doctor` — без красных крестов по Flutter и Android.

### 1. Сгенерировать платформенные папки
Проект содержит `lib/`, `pubspec.yaml` и т.д., но не содержит папок
`android/`, `ios/`, `windows/`. Создайте их одной командой в корне проекта
(она НЕ перезапишет наш код в `lib/`):

```bash
flutter create .
```
> Для iOS из-за Firebase поднимите минимум платформы: в `ios/Podfile`
> раскомментируйте и поставьте `platform :ios, '13.0'`.

### 2. Создать проект Supabase и применить схему
1. На supabase.com → **New project** (`komplekt`), сохраните пароль БД.
2. Откройте **SQL Editor** → New query → вставьте и выполните по очереди:
   - `supabase/migrations/0001_init.sql` (таблицы, PostGIS, RLS)
   - `supabase/migrations/0002_seed.sql` (демо-данные)
   - `supabase/migrations/0003_supplier.sql` (кабинет поставщика: статусы,
     события/статистика, защита роли)
   - `supabase/migrations/0004_storage.sql` (бакет фото товаров + политики)
   - `supabase/migrations/0005_push.sql` (токены устройств, очередь и триггер
     уведомлений о снижении цены)
3. **Authentication → Providers → Email**: на время разработки отключите
   «Confirm email» (тогда регистрация сразу логинит пользователя).
4. Для входа по телефону включите провайдер **Phone** и подключите SMS-шлюз
   (иначе используйте email — он работает без настройки).

### 3. Вписать ключи
1. Скопируйте `.env.example` → `.env`.
2. Project Settings → **Data API** скопируйте Project URL → `SUPABASE_URL`.
3. Project Settings → **API Keys** скопируйте anon/publishable ключ →
   `SUPABASE_ANON_KEY`.

> Файл `.env` не коммитится (он в `.gitignore`). Без него сборка не запустится —
> это защита от утечки ключей.

### 4. Разрешения геолокации (после `flutter create .`)
**Android** — в `android/app/src/main/AndroidManifest.xml` внутри `<manifest>`:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```
**iOS** — в `ios/Runner/Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Чтобы показать поставщиков материалов рядом с вами.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Чтобы прикрепить фото товара из галереи.</string>
```

### 5. Установить зависимости и запустить
```bash
flutter pub get
flutter run
```
Выберите запущенный эмулятор. Приложение откроется на онбординге → выбор
города → регистрация/вход → главная.

### Проверка
```bash
flutter analyze   # статический анализ
flutter test      # юнит-тесты форматтеров
```

---

## Кабинет поставщика
Открывается из Профиля. Любой пользователь может подать заявку («Стать
поставщиком») — статус станет `pending`. **Одобрение делает админ**: в Supabase
выполните, подставив email поставщика:
```sql
update public.users set status = 'approved'
where id = (select id from auth.users where email = 'supplier@mail.kz');
```
После этого в кабинете открывается управление товарами, ценами, импорт прайса
(.xlsx/.xls) и статистика. Триггер `protect_user_role` не даёт пользователю
одобрить себя самостоятельно.

## Заметки
- Экспорт PDF использует шрифт Open Sans (кириллица) — он скачивается один раз
  при первом формировании, поэтому нужен интернет. Excel и PDF открываются через
  системное окно «Поделиться».

## Пуш-уведомления о снижении цены (FCM) — настройка

Приложение работает и **без** этой настройки (пуши просто отключены). Чтобы
включить — нужен бесплатный проект Firebase; для iOS-пушей дополнительно нужен
платный Apple Developer ($99/год, для APNs-ключа).

**Как это работает:** при снижении цены предложения триггер в БД кладёт строки
в `price_drops` (по одному на каждого, у кого товар в избранном) → Database
Webhook вызывает Edge Function `send-price-alerts` → она шлёт пуш в FCM.

### 1. Firebase проект и привязка к приложению
1. console.firebase.google.com → создайте проект.
2. Установите FlutterFire CLI и привяжите:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   Команда создаст `lib/firebase_options.dart`, `android/app/google-services.json`
   и iOS-конфиг, и добавит нужные Gradle-строки.
3. iOS: в Xcode включите capability **Push Notifications** и
   **Background Modes → Remote notifications**; в Apple Developer создайте
   **APNs Auth Key (.p8)** и загрузите его в Firebase → Project settings →
   Cloud Messaging.
4. iOS: в `ios/Podfile` поднимите минимум до `platform :ios, '13.0'`.

### 2. Секреты Edge Function
В Firebase → Project settings → **Service accounts** → Generate new private key
(скачается JSON). Из него возьмите `project_id`, `client_email`, `private_key`
и задайте секреты функции:
```bash
supabase secrets set FCM_PROJECT_ID=your-project-id
supabase secrets set FCM_CLIENT_EMAIL=firebase-adminsdk-...@your-project.iam.gserviceaccount.com
supabase secrets set FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

### 3. Деплой функции
```bash
supabase functions deploy send-price-alerts
```

### 4. Database Webhook
Supabase Dashboard → Database → **Webhooks** → Create:
- таблица `public.price_drops`, событие **Insert**;
- тип **Supabase Edge Functions** → функция `send-price-alerts`.

### Проверка
Добавьте товар в избранное, затем в кабинете поставщика снизьте его цену.
Должен прийти пуш «Цена снизилась». Очередь и статусы видно в таблице
`price_drops`. Порог снижения и вкл/выкл — в Профиле → «Настройки уведомлений».

### Realtime цен
Чтобы цена обновлялась на карточке товара без перезахода, включите
**Replication** для таблицы `offers`: Dashboard → Database → Replication →
добавьте `offers` в публикацию `supabase_realtime`.

## Заметки по безопасности
- anon-ключ Supabase публичный — доступ ограничен политиками **RLS**
  (см. `0001_init.sql`). Каждый пользователь видит и меняет только свои
  избранное, подборки и отзывы; каталог доступен на чтение всем.
- Никаких секретов в коде — только `.env`.
