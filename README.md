# AmneziaWG 3.1 — Docker image

Небольшой Docker-образ AmneziaWG для Ubuntu 24.04 и других Linux-хостов с Docker Engine. Профиль рассчитан на низкую дополнительную нагрузку для игрового VPN Call of Duty Mobile. Образ собирается из закреплённых upstream-тегов, поддерживает `linux/amd64` и `linux/arm64`, а публикация в GitHub Container Registry запускается GitHub Actions при push тега `3.*`.

## Что находится в каталоге

- `Dockerfile` — сборка `amneziawg-go` и `amneziawg-tools` из upstream-исходников.
- `compose.yaml` — контейнер с минимальными Linux capabilities, read-only root filesystem и ограниченными логами.
- `scripts/init-server.sh` — безопасная генерация ключей и конфигов сервера и одного клиента.
- `.github/workflows/publish-ghcr.yml` — multi-arch публикация в GHCR по git-тегу.
- `LICENSES/` и `THIRD_PARTY_NOTICES.md` — лицензии включённых upstream-компонентов.

## Опубликовать образ в GitHub Container Registry

1. Файлы сборки и workflow уже находятся в корне этого репозитория. Не добавляйте `.env`, каталог `config/` и клиентские конфиги с приватными ключами.
2. В GitHub проверьте, что Actions разрешены для репозитория и workflow имеет `packages: write` (это право уже задано в файле).
3. Отправьте изменения в ветку `master`, затем создайте версионный тег:

   ```bash
   git add .
   git commit -m "Prepare AmneziaWG image"
   git push origin master
   git tag 3.1.20261116
   git push origin 3.1.20261116
   ```

4. Откройте **Actions** и дождитесь workflow `Publish AmneziaWG image`. Он соберёт `linux/amd64` и `linux/arm64` и опубликует два тега: версию и `latest`.
5. После первой публикации откройте созданный package в GitHub → **Packages** → **Package settings** и установите **Visibility: Public**, если сервер должен скачивать образ без аутентификации.

Имя образа формируется из GitHub owner и repository в нижнем регистре:

```text
ghcr.io/OWNER/REPOSITORY:3.1.20261116
ghcr.io/OWNER/REPOSITORY:latest
```

GitHub Actions автоматически использует фактический owner/repository. Для этого репозитория адрес — `ghcr.io/thekhabaroff/awg`. Публичный package разрешает pull без входа в GHCR.

## Развернуть на Ubuntu 24.04

### 1. Установить Docker

```bash
sudo curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
sudo docker run --rm hello-world
sudo docker compose version
```

### 2. Подготовить проект

Клонируйте этот публичный репозиторий на сервер:

```bash
sudo apt-get update
sudo apt-get install -y git
sudo git clone https://github.com/thekhabaroff/AWG.git /opt/awg
sudo chown -R root:root /opt/awg
sudo chmod 0755 /opt/awg/scripts/init-server.sh /opt/awg/publish.sh
cd /opt/awg
sudo cp .env.example .env
sudo chmod 0600 .env
```

Файл `/opt/awg/.env` уже содержит адрес публичного образа `ghcr.io/thekhabaroff/awg:3.1.20261116`. Измените `AWG_IMAGE` только если хотите использовать другой опубликованный тег. `SERVER_PORT` по умолчанию `51820`.

Загрузите опубликованный образ до генерации конфигов:

```bash
sudo docker compose pull awg
```

### 3. Сгенерировать ключи и конфиги

Подставьте публичный IPv4 или DNS-имя сервера:

```bash
sudo ./scripts/init-server.sh YOUR_SERVER_IP_OR_DOMAIN 51820 phone
```

Скрипт создаст `config/wg0.conf` и `config/phone.conf`, ограничит права каталога `0700`, файлов `0600`, не печатает ключи и не перезаписывает уже созданные профили. Каталог `config/` исключён из git и Docker build context.

Разрешите UDP-порт `51820` в панели firewall вашего провайдера. Если используется UFW:

```bash
sudo ufw allow 51820/udp
sudo ufw status
```

Docker-публикация портов может обходить обычные правила UFW; для строгой политики входящих соединений учитывайте правила Docker firewall.

### 4. Запустить сервис

```bash
sudo docker compose up -d
sudo docker compose ps
sudo docker compose logs --tail=100 awg
sudo docker exec amneziawg awg show wg0
```

Сервис сбрасывает все Linux capabilities и добавляет только `NET_ADMIN`, подключает `/dev/net/tun`, работает с read-only root filesystem и временными `/run` и `/tmp`, ограничивает размер логов и перезапускается после сбоя. Он не использует `privileged` или `SYS_MODULE`. `/run` требуется для control socket AmneziaWG и блокировки iptables.

### 5. Импортировать клиентский профиль

`config/phone.conf` содержит приватный и preshared ключи. Передавайте файл только по доверенному каналу, не коммитьте и не публикуйте его. Для временного копирования в домашний каталог SSH-пользователя:

```bash
sudo install -m 0600 -o "$USER" -g "$(id -gn)" \
  /opt/awg/config/phone.conf "$HOME/phone.conf"
```

Скачайте файл через `scp` и импортируйте в AmneziaWG-клиент, поддерживающий пользовательские `H1–H4` и поля AWG 3.1.

## Игровой профиль

Генератор применяет одинаковые DNS, MTU и AWG-параметры на клиенте и сервере:

```ini
DNS = 1.1.1.1, 1.0.0.1
MTU = 1280
Jc = 0
Jmin = 0
Jmax = 0
S1 = 0
S2 = 0
S3 = 0
S4 = 0
H1 = 5
H2 = 100000005
H3 = 200000005
H4 = 300000005
RandomTrailers = off
```

Junk-пакеты, случайные префиксы, Content Padding, Header Protection и Random Trailers отключены ради меньшей дополнительной обработки. Это профиль с ограниченной маскировкой, а не полный профиль AWG 3.1; если сеть блокирует WireGuard-подобный трафик, может потребоваться включить механизмы маскировки. `PersistentKeepalive = 25` оставлен на мобильном клиенте для поддержания UDP-сессии через NAT. В этой конфигурации маршрутизируется IPv4; IPv6 не настроен.

`awg-quick` сначала использует доступный модуль AmneziaWG ядра хоста, а при его отсутствии запускает встроенную реализацию `amneziawg-go` в userspace. Userspace-режим может потреблять больше CPU и иметь меньшую пропускную способность под нагрузкой.

## Локальная публикация вручную (необязательно)

Обычный путь — создать git-тег и дать GitHub Actions опубликовать образ. Для ручной публикации с компьютера войдите в GHCR через Docker CLI и запустите:

```bash
docker login ghcr.io -u YOUR_GITHUB_USERNAME
./publish.sh ghcr.io/OWNER/REPOSITORY:TAG
```

Docker CLI запросит токен интерактивно. Для ручного push нужен GitHub Personal Access Token с правом `write:packages`. Скрипт создаст локальный amd64-архив в каталоге проекта и отправит multi-arch образ в GHCR. Архив игнорируется git и его не нужно копировать в GitHub.

## Резервная копия и обновление

Храните резервную копию ключей отдельно от сервера:

```bash
sudo tar -C /opt/awg -czf /root/awg-config-backup.tar.gz config
sudo chmod 0600 /root/awg-config-backup.tar.gz
```

Для нового релиза обновите версии upstream в `Dockerfile`, измените тег в `.env`, закоммитьте изменения и отправьте новый версионный тег. Не удаляйте и не перезаписывайте `config/` при обновлении образа.

## Исходники

- [Документация AmneziaWG](https://docs.amnezia.org/documentation/amnezia-wg/)
- [amneziawg-go v3.1.20261116](https://github.com/amnezia-vpn/amneziawg-go/tree/v3.1.20261116)
- [amneziawg-tools v3.1.20260812](https://github.com/amnezia-vpn/amneziawg-tools/tree/v3.1.20260812)
- [Docker Engine для Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Публикация Docker images в GitHub Packages](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images)
