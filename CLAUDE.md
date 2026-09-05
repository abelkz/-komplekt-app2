# КОМПЛЕКТ — контекст проекта для Claude Code

Этот файл читается автоматически при старте сессии. Здесь всё, что нужно знать
о проекте, чтобы не изучать его заново: стек, архитектура, грабли, команды.

Язык общения и комментариев в коде — **русский**.

---

## 1. Что это за проект

Мобильное приложение-маркетплейс отделочных и строительных материалов.
Рынок — Астана, Казахстан/СНГ. Концепция: «2GIS + OLX + Pinterest» для ремонта.

Пакет: `komplekt`, версия `0.1.0+1`, bundle id для iOS — `kz.komplekt.app`.

Два типа пользователей:

- **покупатель / дизайнер / прораб** — ищет материалы, сравнивает цены
  поставщиков, собирает подборки, выгружает спецификацию в Excel/PDF;
- **поставщик** (роль `supplier`) — кабинет с товарами, ценами, импортом
  прайса из Excel/CSV, статистикой просмотров и контактов.

Монетизация: подписка «Про» (клиент 4900 ₸/мес, поставщик 9900 ₸/мес) и бусты
продвижения товара (1/3/7 дней — 1500/3500/7000 ₸) через CloudPayments.

---

## 2. Стек

| Слой | Технология |
|---|---|
| Клиент | Flutter (SDK ≥ 3.24), Dart ≥ 3.4, Material 3 |
| Состояние | `flutter_riverpod` 2.x |
| Навигация | `go_router` 14.x (`StatefulShellRoute` — 4 вкладки) |
| Бэкенд | Supabase: Postgres + PostGIS, Auth, Storage, Realtime, Edge Functions |
| Карта | `flutter_map` + OpenStreetMap (без API-ключей), `geolocator` |
| Пуши | Firebase Cloud Messaging + `flutter_local_notifications` |
| Экспорт | `pdf` + `printing` (кириллица), `excel` + свой `xlsx_reader` |
| Оплата | CloudPayments через Edge Function `create-payment` |

Полный список зависимостей с комментариями — в `pubspec.yaml`, там же объяснено,
почему взят каждый пакет.

---

## 3. Запуск с нуля (например, после переустановки системы)

```bash
git clone https://github.com/abelkz/-komplekt-app2.git
cd -komplekt-app2
cp .env.example .env          # затем вписать ключи, см. ниже
flutter create .              # генерирует android/ ios/ web/ — их нет в git
flutter pub get
flutter run
```

**`.env` не хранится в git** (он в `.gitignore`). Нужны два значения из
Supabase → Project Settings:

- `SUPABASE_URL` — из раздела **Data API** (Project URL);
- `SUPABASE_ANON_KEY` — из раздела **API Keys** (anon/publishable).

Остальные переменные (`DEMO_MODE`, `DEFAULT_CITY=Астана`, координаты центра
Астаны 51.1280 / 71.4304) уже прописаны в `.env.example`.

Без ключей приложение всё равно запустится: сработает **демо-режим** (см. §6).

---

## 4. Архитектура

Feature-first. Общий слой — `lib/core/`, фичи — `lib/features/<feature>/`
с делением на `data` (репозитории, Supabase-запросы), `domain` (модели),
`presentation` (экраны, виджеты, Riverpod-провайдеры).

```
lib/
  main.dart                 инициализация: .env → Supabase → Firebase → LocalStore
  core/
    config/                 env.dart, supabase_client.dart, local_store.dart,
                            pricing.dart, contacts.dart, build_info.dart
    router/app_router.dart   все маршруты и redirect-логика
    theme/                   AppTheme / AppColors / AppTypography («Industrial Noir»)
    providers/               общие провайдеры, настройки, refreshAppData()
    demo/                    demo_data.dart + подмена репозиториев в демо-режиме
    push/push_service.dart   регистрация FCM-токена
    moderation/              скрытие отзывов и блокировка авторов (App Store 1.2)
    widgets/, utils/, errors/, onboarding/
  features/
    admin, auth, catalog, collections, favorites, home, notifications,
    onboarding, product, profile, subscription, supplier_cabinet,
    suppliers_map, visual_search
  l10n/                     app_ru.arb (базовый), app_kk.arb, app_en.arb
```

Всего ~100 `.dart`-файлов.

### Маршруты

Пути собраны в классе `Routes` (`lib/core/router/app_router.dart`).
Четыре вкладки нижней навигации: `/home`, `/favorites`, `/collections`,
`/profile`. Полноэкранные: `/product/:id`, `/catalog/:slug`, `/supplier/:id`,
`/map`, `/supplier-cabinet`, `/notifications`, `/visual-search`, `/admin`,
`/pro`, `/search`, `/auth`, `/onboarding`, `/new-password`.

`redirect` работает по порядку: онбординг (выбор города) → авторизация →
приложение. Исключения: `/new-password` пропускается всегда (переход из письма),
корень `/` всегда уводит на `/home` (возврат после OAuth приходил именно туда и
падал с «no routes for location: /»).

### Тема

Дизайн «Industrial Noir»: глубокий графит слоями (`paper #121414`,
`card #1E2020`), тёплый золотой акцент (`brandYellow #FABD00`) только для
действий, тонкие тёплые линейки вместо теней. Шрифты: Inter — основной текст,
Manrope — заголовки и цены, JetBrains Mono — числа.
**Тёмная тема по умолчанию** (`LocalStore.themeMode` возвращает `'dark'`).

Цвета берутся из `ThemeExtension` `AppColors`, в виджетах не хардкодятся.
Два исторических имени сбивают с толку: поле `AppColors.orange` хранит
**жёлтый** акцент (есть понятный геттер `accent`), а `AppTypography.unbounded()`
возвращает **Manrope** — шрифт Unbounded из раннего прототипа не прижился, а имя
метода осталось.

---

## 5. Бэкенд (Supabase)

### Миграции

`supabase/migrations/0001…0023`, применяются **по порядку**. Пока накатываются
руками через SQL Editor; перевод на `supabase db push` — в бэклоге.

Основные таблицы: `categories`, `brands`, `products`, `product_images`,
`offers`, `suppliers`, `users`/`profiles`, `favorites`, `collections`,
`collection_items`, `reviews`, `supplier_reviews`, `events`, `device_tokens`,
`price_drops`, `price_history`, `promotions`, `boost_orders`, `boost_credits`,
`subscription_requests`, `payments`.

Ключевые RPC: `catalog_search`, `nearby_suppliers` (PostGIS), `become_supplier`,
`delete_my_account`, `order_boost`, `promote_offer`, `my_boost_status`,
`supplier_stats`, `fulfill_payment`, `plan_active` / `supplier_plan_active`,
админские `admin_set_supplier_plan`, `admin_activate_request`,
`admin_grant_boost`, `admin_set_supplier_verified`.

Защитные триггеры: `protect_user_role` (нельзя одобрить себя поставщиком),
`enforce_offer_owner` / `enforce_product_owner` (нельзя выставить цену от чужой
компании), `recalc_product_rating` / `recalc_supplier_rating`.

### Edge Functions (`supabase/functions/`)

- `create-payment` — счёт в CloudPayments (секреты `CLOUDPAYMENTS_PUBLIC_ID`,
  `CLOUDPAYMENTS_API_SECRET`);
- `cloudpayments-webhook` — подтверждение оплаты, выдача тарифа/буста;
- `send-price-alerts` — пуши о снижении цены через FCM (секреты
  `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`);
- `photo-search` — поиск по фото (в разработке).

### Как работают пуши о снижении цены

Поставщик снижает цену → триггер в БД пишет строки в `price_drops` (по одной на
каждого, у кого товар в избранном) → Database Webhook (Insert на `price_drops`)
вызывает `send-price-alerts` → FCM. Плюс Realtime-подписка на `price_drops` в
`main.dart` показывает снекбар прямо в приложении.

---

## 6. Грабли и важные особенности

Прочитать до того, как что-то править.

1. **Схема живой базы расходится с миграциями.** Живую базу использует ещё и
   Telegram mini-app: ключи там **целочисленные** (`products.id = 2`), а не
   uuid; колонки `products.brand` нет — марка лежит в `brands(name)`; иконка
   категории называется `emoji`, а не `icon`. Миграция `0007_unify_with_live.sql`
   только **добавляет** недостающее и ничего не переименовывает. Запрос
   несуществующей колонки роняет весь PostgREST-запрос с ошибкой 42703.

2. **Строка `select` для PostgREST пишется без пробелов и переносов.**
   Эталон — `CatalogRepository.productSelect`.

3. **Демо-режим.** `Env.demoMode` = true, если `DEMO_MODE=true` **или** если
   `SUPABASE_URL` остался placeholder-ом. В нём репозитории подменяются на
   `demoOverrides()` из `lib/core/demo/`, Supabase и Firebase не инициализируются,
   вход пропускается. На этом режиме собираются публичные APK и веб-превью,
   чтобы ключи не утекали.

4. **Платформенные папки `android/`, `ios/`, `web/` в git не хранятся.** Их
   генерирует `flutter create .` — локально и в каждом CI-скрипте. Поэтому все
   правки манифеста, `Info.plist`, `Podfile` и `project.pbxproj` живут не в
   репозитории, а **скриптами внутри workflow-файлов** (`.github/workflows/*.yaml`
   и `codemagic.yaml`). Правку разрешений или bundle id вносить туда.

5. **`pubspec.lock` в `.gitignore`.** Версии пакетов не зафиксированы —
   ломающий минор в `firebase_*`, `excel`, `flutter_map`, `geolocator` уронит
   сборку. Зафиксировать — в бэклоге.

6. **Свой парсер `.xlsx`.** Пакет `excel` падает на части реальных файлов,
   поэтому есть `lib/features/supplier_cabinet/data/xlsx_reader.dart` на
   `archive` + `xml`. Импорт прайса — самое хрупкое место, править осторожно.

7. **iOS: покупки скрыты.** `iapPurchasesHidden` в `lib/core/config/pricing.dart`
   прячет кнопки оплаты в iOS-сборке — App Store требует продавать цифровые
   услуги только через свой IAP (правило 3.1.1). На вебе и Android оплата через
   CloudPayments работает.

8. **Цены дублируются в двух местах.** `lib/core/config/pricing.dart` — то, что
   видит человек; `supabase/functions/create-payment/index.ts` — то, что реально
   спишется. Менять **оба**, клиенту сумму доверять нельзя.

9. **Auth в implicit-режиме, не PKCE.** В PKCE терялся `code_verifier` при
   очистке кэша или переходе в другую вкладку, и смена пароля из письма падала.

10. **Локализация не задействована.** ARB-файлы есть и генерация настроена,
    но `AppLocalizations` в коде не используется — строки захардкожены по-русски.

11. **Одобрение поставщика — вручную.** Есть экран `/admin` и админские RPC, но
    базовый путь — SQL:
    `update public.users set status = 'approved' where id = (select id from auth.users where email = '…');`

12. **PDF-экспорт требует интернета** при первом формировании: шрифт Open Sans
    с кириллицей скачивается на лету.

---

## 7. CI/CD

| Файл | Что делает |
|---|---|
| `.github/workflows/ci.yaml` | analyze + test + debug-APK; публикует `komplekt.apk` в релиз с тегом `latest` |
| `.github/workflows/ios.yaml` | сборка под iOS-симулятор на macOS-раннере (без подписи) |
| `.github/workflows/web.yaml` | сборка веб-версии и деплой на GitHub Pages, `--base-href /-komplekt-app2/` |
| `codemagic.yaml` | боевая iOS-сборка: подпись, `.ipa`, автозаливка в TestFlight |

Постоянная ссылка на свежий APK:
`https://github.com/abelkz/-komplekt-app2/releases/download/latest/komplekt.apk`

Секреты: `SUPABASE_URL` и `SUPABASE_ANON_KEY` — в GitHub Secrets; для Codemagic —
группа переменных `supabase`, интеграция App Store Connect с именем
`komplekt_appstore` и `CERTIFICATE_PRIVATE_KEY` (base64). Если секретов нет,
сборка не падает — уходит в демо-режим.

`BUILD_TAG` (короткий хеш коммита) прокидывается через `--dart-define` и
показывается внизу экрана «Профиль» — так видно, открыта свежая версия или
закэшированная старая.

Гейт в `ci.yaml`: `flutter analyze --no-fatal-infos --no-fatal-warnings`
(падаем только на ошибках) и `flutter test` (падающий тест блокирует сборку).

---

## 8. Команды

```bash
flutter pub get
flutter analyze                # линт и статический анализ
flutter test                   # тесты в test/ (домен, фильтры, деньги/вход, виджеты)
flutter run                    # запуск на эмуляторе/устройстве
flutter build apk --debug      # APK для Android
flutter build web --release --base-href "/-komplekt-app2/"
flutter gen-l10n               # генерация локализаций из lib/l10n/*.arb
dart run flutter_launcher_icons # иконки из brand/logo.png
```

Перед коммитом прогонять `flutter analyze` и `flutter test` — ровно те же
гейты стоят в CI.

---

## 9. Конвенции кода

Правила из `analysis_options.yaml` поверх `flutter_lints`:

- одинарные кавычки (`prefer_single_quotes`);
- никаких `print` — только `debugPrint` (`avoid_print`);
- обязательные висячие запятые (`require_trailing_commas`).

Дополнительно, по сложившемуся стилю репозитория:

- комментарии и сообщения об ошибках — по-русски, doc-комментарии объясняют
  **почему** так сделано, а не что делает строчка;
- ошибки Supabase заворачиваются через `mapError` из `core/errors/failure.dart`
  в понятный пользователю текст;
- никаких секретов в коде — только через `.env` и `Env`;
- состояния loading / empty / error обязательны для любого списка
  (`core/widgets/async_value_view.dart`, `skeletons.dart`).

Коммиты — короткие, по-русски, в духе: `Профиль: показывать реальную причину
ошибки удаления аккаунта`, `iOS: скрыть покупки (App Store 3.1.1)`.

---

## 10. Текущее состояние

**Приложение прошло ревью и опубликовано в App Store — доступно всем.**
Замечания ревью закрыты: 1.2 (модерация пользовательского контента),
3.1.1 (покупки), ITMS-90683 (описания геопозиции). Вход через Apple работает,
удаление аккаунта работает. Веб-версия и Android-APK собираются автоматически,
iOS — через Codemagic в TestFlight.

Текущий фокус — **привлечение поставщиков**: без наполненного каталога
сравнение цен не работает, а это ядро продукта.

### Хвосты, за которыми надо следить

1. **Фикс `delete_my_account` может отсутствовать в миграциях.** Удаление
   аккаунта чинили после коммита `0e84670` (он только выводил реальную ошибку).
   Ни одна миграция после `0006_hardening.sql` функцию не переопределяет — если
   правку делали SQL-ом прямо в дашборде, её нужно оформить отдельной миграцией,
   иначе она потеряется при разворачивании базы с нуля.

2. **Таблицы `content_reports` нет ни в одной миграции.** Жалоба на отзыв
   (`lib/core/moderation/review_moderation.dart`) пишется в неё, но insert
   обёрнут в пустой `try/catch` — ошибка проглатывается молча, жалобы никуда не
   доходят. Для ревью хватило локального скрытия, но фактической модерации нет.

3. **Одобрение поставщика идёт SQL-ом вручную** (см. §6.11). При наплыве
   поставщиков это узкое место — экран `/admin` и RPC `admin_activate_request`
   есть, но основной путь всё ещё через SQL Editor.

### Что запланировано на следующее обновление

- **Аватарки** пользователей и поставщиков. Наполовину готово: колонки
  `users.avatar_url` и `suppliers.logo_url` в базе уже есть, модели
  `AppUser.avatarUrl` и `Supplier.logoUrl` их читают, `nearby_suppliers`
  возвращает `logo_url`. Не хватает бакета в Storage, загрузки и показа в UI —
  сейчас ни одно из этих полей нигде не выводится.
- **Нормальный показ фото товара.** Сейчас `_Hero` в `product_screen.dart`
  жёстко 320 px с `BoxFit.cover` (кадрирует товар) и градиентом до `black87`,
  который затемняет нижние 60% снимка. Галерея `product_images` приезжает в
  запросе, но не показывается — виден только `primaryImageUrl`. Нужны листалка
  по фото, полноэкранный просмотр с зумом и `BoxFit.contain`.

### Крупное, за рамками ближайшего обновления

- **матчинг каталога** — сейчас каждый поставщик заводит свои строки
  `products`, поэтому один и тот же товар от двух продавцов даёт две карточки и
  сравнения цен между ними не происходит. Это ключевая ценность продукта и
  отдельная большая фича;
- **Apple IAP** — чтобы вернуть покупки в iOS-сборке;
- **поиск по фото** — экран и Edge Function есть, логика не доделана;
- keyset-пагинация вместо `limit(100)`, кластеризация маркеров на карте,
  вынос строк в ARB, фиксация `pubspec.lock`, мониторинг ошибок в проде.

**`ROADMAP.md` сильно устарел** — он написан, когда код ещё ни разу не
компилировался, и почти весь его P0/P1 давно закрыт (CI, RLS-триггеры, удаление
аккаунта, полнотекстовый поиск, Realtime, настройки уведомлений, скелетоны,
релиз в сторе). Читать как список идей, а не как актуальный статус.

---

## 11. Документация в репозитории

- `README.md` — техническая инструкция: установка, Supabase, Firebase, пуши;
- `НАЧНИ_ОТСЮДА.md` — то же самое для человека без опыта программирования;
- `BUILD_APK.md` — как получить APK без установки Flutter;
- `ROADMAP.md` — инженерный бэклог (см. оговорку выше).
