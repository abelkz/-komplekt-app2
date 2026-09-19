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

Полная инструкция, включая установку самого Claude Code, Flutter и Android
Studio — в `ЛОКАЛЬНЫЙ_ЗАПУСК.md`. Ниже — кратко для того, у кого окружение
уже настроено.

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

`supabase/migrations/0001…0025`, применяются **по порядку**.

Накатывать можно двумя способами:

- **Через GitHub Actions** — вкладка Actions → «Миграция базы» → Run workflow →
  имя файла (`.github/workflows/migrate.yaml`). Нужен один секрет
  `SUPABASE_DB_PASSWORD` — пароль базы; адрес пулера и имя пользователя
  workflow собирает сам из ref проекта и региона (переопределяются
  переменными `SUPABASE_PROJECT_REF` и `SUPABASE_REGION`). Для нестандартного
  адреса можно задать `SUPABASE_DB_URL` — он имеет приоритет. Это основной путь.
- Вручную через SQL Editor — если доступа к Actions нет под рукой.

Основные таблицы: `categories`, `brands`, `products`, `product_images`,
`offers`, `suppliers`, `users`/`profiles`, `favorites`, `collections`,
`collection_items`, `reviews`, `supplier_reviews`, `events`, `device_tokens`,
`price_drops`, `price_history`, `promotions`, `boost_orders`, `boost_credits`,
`subscription_requests`, `payments`.

Ключевые RPC: `catalog_search`, `become_supplier`,
`delete_my_account`, `order_boost`, `promote_offer`, `my_boost_status`,
`supplier_stats`, `fulfill_payment`, `plan_active` / `supplier_plan_active`,
админские `admin_set_supplier_plan`, `admin_activate_request`,
`admin_grant_boost`, `admin_set_supplier_verified`.

Защитные триггеры: `protect_user_role` (нельзя одобрить себя поставщиком),
`enforce_offer_owner` / `enforce_product_owner` (нельзя выставить цену от чужой
компании), `recalc_product_rating` / `recalc_supplier_rating`.

### Edge Functions (`supabase/functions/`)

> **Ни одна из них не задеплоена в живой проект** (проверено 19.09.2026 —
> в дашборде пустой экран «Deploy your first edge function»). Код в
> репозитории есть, на сервере его нет. Отсюда два следствия: пуши о
> снижении цены не уходят, и оплата через CloudPayments не работает —
> она идёт через `create-payment`. В `payments` ноль строк, сходится.
> Что настроить — в `ПУШИ_И_ФУНКЦИИ.md`.

- `create-payment` — счёт в CloudPayments (секреты `CLOUDPAYMENTS_PUBLIC_ID`,
  `CLOUDPAYMENTS_API_SECRET`);
- `cloudpayments-webhook` — подтверждение оплаты, выдача тарифа/буста;
- `send-price-alerts` — пуши о снижении цены через FCM (секреты
  `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`);
- `photo-search` — поиск по фото (в разработке).

### Как работают пуши о снижении цены

> **Сейчас не работают вообще, ни на одной платформе.** `device_tokens` в
> живой базе — 0 строк за всё время: в репозитории нет `firebase_options.dart`
> и нативных конфигов Firebase, а положить их в `android/`/`ios/` нельзя —
> те папки генерируются заново каждой сборкой (§6.4). Поэтому
> `Firebase.initializeApp()` падает всегда, падение гасится `try/catch`
> в `main.dart`, `PushService._ready` остаётся `false` и `syncToken()`
> выходит сразу. Ниже описано, как задумано; как это включить —
> в `ПУШИ_И_ФУНКЦИИ.md`.

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

   Марку у товара **не пишут запросом** — только через RPC
   `set_product_brand` (миграция `0034`): таблица `brands` закрыта на вставку,
   а функция сама приводит название к уже заведённой марке без учёта
   регистра и пробелов. Иначе «Kerama Marazzi» за месяц расползлась бы по
   десятку написаний, и фильтр по марке перестал бы что-либо фильтровать.

   **Таблицы `public.users` в живой базе НЕТ** — она есть только в схеме из
   `0001_init.sql`. Профиль и роль лежат в `public.profiles`. Поэтому проверка
   администратора всегда пишется так:

   ```sql
   exists (select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin')
   ```

   Образцы — `0015`, `0017`, `0020`, `0021`. Скопировать проверку из
   `0001_init.sql` (там `public.users`) — значит получить
   `ERROR: 42P01: relation "public.users" does not exist` при применении.
   **Любую новую миграцию сверять с поздними, а не с `0001`.**

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

5. **`pubspec.lock` лежит в git и обновляется только через CI.** Версии
   пакетов зафиксированы (19.09.2026): ломающий минор в `firebase_*`,
   `excel`, `flutter_map` или `geolocator` больше не приезжает в сборку сам
   собой. Файл собирает workflow «Обновить pubspec.lock»
   (`.github/workflows/lockfile.yaml`) — руками его не пишут: он
   запускается сам при правке `pubspec.yaml` и коммитит результат от имени
   `github-actions[bot]`.

   Обратная сторона: замок теперь может разойтись с Flutter на раннере
   (`channel: stable` двигается). Если `flutter pub get` вдруг падает во
   **всех** workflow сразу — это оно; лечится перезапуском workflow замка,
   а не правкой кода.

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

11. **Каталог открыт гостю.** `redirect` в `app_router.dart` пускает без
    аккаунта на главную, поиск, карту, карточки товаров и витрины
    поставщиков. Аккаунт нужен только для маршрутов из `_needsAccount()`
    (кабинет, уведомления, оплата, админка). Вкладки «Избранное»,
    «Подборки», «Профиль» не редиректят, а показывают `SignInRequired`.
    Действия, требующие входа, зовут `promptSignIn()`. RLS это позволяет:
    политики каталога — `for select using (true)`, то есть и для `anon`.

12. **Админка `/admin` работает, SQL-ом одобрять не нужно.** Четыре вкладки:
    «Поставщики» (одобрить / отклонить / вернуть на проверку), «Тарифы»,
    «Буст», «Жалобы». Ожидающие решения сортируются наверх, их число видно
    счётчиком в профиле (`adminPendingCountProvider`).

    Права проверяет база: без `role = 'admin'` политики ничего не отдадут,
    скрытый пункт меню — только удобство. Статус меняется в `public.profiles`
    (не в `users`, см. пункт 1).

13. **PDF-экспорт требует интернета** при первом формировании: шрифт Open Sans
    с кириллицей скачивается на лету.

---

## 7. CI/CD

| Файл | Что делает |
|---|---|
| `.github/workflows/ci.yaml` | analyze + test + debug-APK; публикует `komplekt.apk` в релиз с тегом `latest` |
| `.github/workflows/ios.yaml` | сборка под iOS-симулятор на macOS-раннере (без подписи) |
| `.github/workflows/web.yaml` | сборка веб-версии и деплой на GitHub Pages, `--base-href /-komplekt-app2/` |
| `.github/workflows/migrate.yaml` | применяет выбранный файл миграции к живой базе (вручную, по кнопке) |
| `.github/workflows/lockfile.yaml` | пересобирает и коммитит `pubspec.lock` при правке `pubspec.yaml` |
| `codemagic.yaml` | боевая iOS-сборка: подпись, `.ipa`, автозаливка в TestFlight |

Постоянная ссылка на свежий APK:
`https://github.com/abelkz/-komplekt-app2/releases/download/latest/komplekt.apk`

Секреты: `SUPABASE_URL`, `SUPABASE_ANON_KEY` и `SENTRY_DSN` — в GitHub Secrets;
`SUPABASE_DB_PASSWORD` (или `SUPABASE_DB_URL`) — там же, только для workflow
миграций: даёт полный доступ к базе; для Codemagic —
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

1. **`delete_my_account` расходился с репозиторием — закрыто миграцией `0026`.**
   Проверено 18.09.2026: в живой базе лежала переписанная версия (953 символа
   против 137 в `0006_hardening.sql`) — её чинили SQL-ом прямо в дашборде, мимо
   репозитория. Текст снят с базы через `pg_get_functiondef` и зафиксирован в
   `0026_delete_my_account_fix.sql`. Саму живую базу трогать не нужно: там уже
   рабочая версия, миграция нужна только для разворачивания с нуля.

   Урок на будущее: правки, сделанные в SQL Editor, в репозиторий сами не
   попадают. Сверить функцию с миграцией можно так — совпадение `md5(prosrc)`
   из `pg_proc` с телом функции в файле миграции.

2. **Жалобы на отзывы.** Таблица `content_reports` и функция
   `admin_delete_review` заведены миграцией `0025`
   (до неё insert падал в пустой `catch`, и жалобы никуда не доходили).
   `review_id` там **текстовый**: у `reviews.id` тип uuid, а у
   `supplier_reviews.id` — bigint, внешнего ключа быть не может. Куда смотреть,
   говорит колонка `target` (`product_review` / `supplier_review`) — её
   передаёт `ReportMenu`. Разбор — во вкладке «Жалобы» админки: удалить
   отзыв, отклонить жалобу или пометить разобранной. Удаляет `admin_delete_review`
   с правами `security definer` — обычным запросом нельзя, политики
   `reviews` и `supplier_reviews` дают право удалять только автору.

3. **Организация Supabase на тарифе FREE.** Проект уже дважды вставал: один раз
   из-за неоплаченного счёта, и автопауза после 7 дней без обращений к API
   никуда не делась. Пока приложение в сторе живёт на бесплатном тарифе, оно
   ляжет снова — вопрос только когда. Апгрейд: Supabase → Settings →
   Subscription.

### Сделано после релиза (ещё не выпущено в сторе)

- **Таймауты на запросы** — `TimeoutHttpClient` (20 с, загрузка в Storage
  2 мин). Без них зависший запрос не падал никогда и вместо ошибки крутилась
  вечная загрузка. Падение `Supabase.initialize` больше не даёт чёрный экран —
  показывается `StartupErrorApp` с кнопкой «Повторить».
- **Гостевой просмотр каталога** — см. §6.11.
- **Sentry** (DSN в `.env`, без него молчит) и **продуктовая аналитика** в
  таблице `app_events` (миграция 0024, сервис `Analytics`).
- **Сводка в админке** — агрегаты считает база (`0030`), вкладка «Сводка».
- **Аватарки и логотипы** — колонки, бакет и политики (`0031`), виджет
  `core/widgets/avatar.dart`, загрузка в профиле и кабинете, показ в
  профиле, на витрине поставщика и на карте.
- **Блокировка и удаление поставщика** (`0032`, `0033`) — во вкладке
  «Поставщики» админки: срок 3/7/14/30 дней или навсегда, причина,
  удаление с подтверждением по названию компании.
- **Марка товара в кабинете** (`0034`) — поле с подсказками по уже
  заведённым маркам, запись через `set_product_brand` (см. §6.1).
- **Зафиксированы версии пакетов** — `pubspec.lock` в git (см. §6.5).

Миграции `0024` и `0025` **применены** к живой базе (18.09.2026, через
SQL Editor): созданы таблица `app_events`, таблица `content_reports` и функция
`admin_delete_review`. Но записи в них пойдут только после выката 1.0.1:
код, который пишет события и жалобы, есть лишь в новой версии, а в сторе
пока 1.0.0.

Осталось по желанию: `SENTRY_DSN` в секреты GitHub и в группу `supabase`
в Codemagic. Без него приложение работает, просто не шлёт отчёты о падениях.

**Релиз 1.0.1 ещё не выпущен.** Собирается в Codemagic (номер сборки растёт
сам), дальше TestFlight и ревью Apple. Перед отправкой проверить на устройстве
гостевой вход: удалить приложение, поставить заново, убедиться, что каталог
открывается без регистрации.

### Что запланировано дальше

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
  вынос строк в ARB, мониторинг ошибок в проде.

**`ROADMAP.md` сильно устарел** — он написан, когда код ещё ни разу не
компилировался, и почти весь его P0/P1 давно закрыт (CI, RLS-триггеры, удаление
аккаунта, полнотекстовый поиск, Realtime, настройки уведомлений, скелетоны,
релиз в сторе). Читать как список идей, а не как актуальный статус.

---

## 11. Документация в репозитории

- `ЛОКАЛЬНЫЙ_ЗАПУСК.md` — установка Claude Code, проекта и Flutter на чистую
  систему, с прямыми ссылками на нужные разделы дашборда Supabase;
- `README.md` — техническая инструкция: установка, Supabase, Firebase, пуши;
- `НАЧНИ_ОТСЮДА.md` — то же самое для человека без опыта программирования;
- `BUILD_APK.md` — как получить APK без установки Flutter;
- `ПУШИ_И_ФУНКЦИИ.md` — разовая настройка Firebase, APNs и Supabase, без
  которой не работают уведомления и оплата (см. оговорки в §5);
- `ROADMAP.md` — инженерный бэклог (см. оговорку выше).
