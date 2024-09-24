# *****************************************************************************
# STAGE 1: Build the project
# *****************************************************************************
FROM node:20-alpine AS builder

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

RUN apk add --no-cache libc6-compat

WORKDIR /app

RUN yarn global add turbo
COPY . .

RUN turbo prune --scope=web --scope=space --scope=admin --docker

# *****************************************************************************
# STAGE 2: Install dependencies & build the project
# *****************************************************************************
FROM node:20-alpine AS installer

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

RUN apk add --no-cache libc6-compat

WORKDIR /app

COPY .gitignore .gitignore
COPY --from=builder /app/out/json/ .
COPY --from=builder /app/out/yarn.lock ./yarn.lock
# RUN yarn cache clean
RUN yarn install

COPY --from=builder /app/out/full/ .
COPY turbo.json turbo.json

ARG NEXT_PUBLIC_API_BASE_URL=""
ENV NEXT_PUBLIC_API_BASE_URL=$NEXT_PUBLIC_API_BASE_URL

ARG NEXT_PUBLIC_ADMIN_BASE_URL=""
ENV NEXT_PUBLIC_ADMIN_BASE_URL=$NEXT_PUBLIC_ADMIN_BASE_URL

ARG NEXT_PUBLIC_ADMIN_BASE_PATH="/god-mode"
ENV NEXT_PUBLIC_ADMIN_BASE_PATH=$NEXT_PUBLIC_ADMIN_BASE_PATH

ARG NEXT_PUBLIC_SPACE_BASE_URL=""
ENV NEXT_PUBLIC_SPACE_BASE_URL=$NEXT_PUBLIC_SPACE_BASE_URL

ARG NEXT_PUBLIC_SPACE_BASE_PATH="/spaces"
ENV NEXT_PUBLIC_SPACE_BASE_PATH=$NEXT_PUBLIC_SPACE_BASE_PATH

ARG NEXT_PUBLIC_WEB_BASE_URL=""
ENV NEXT_PUBLIC_WEB_BASE_URL=$NEXT_PUBLIC_WEB_BASE_URL

ENV NEXT_TELEMETRY_DISABLED=1
ENV TURBO_TELEMETRY_DISABLED=1

RUN yarn turbo run build --filter=web --filter=space --filter=admin

# *****************************************************************************
# STAGE 3: Copy the project and start it
# *****************************************************************************
FROM python:3.12-alpine AS runner

WORKDIR /app

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

RUN apk add --no-cache \
    gnupg curl ca-certificates lsb-release build-base openssl-dev \
    zlib-dev bzip2-dev readline-dev sqlite-dev wget llvm \
    ncurses-libs ncurses-terminfo xz tk-dev libffi-dev \
    xz-dev supervisor html2text vim openssh-client \
    sudo lsof net-tools postgresql-dev procps gettext

RUN apk add --no-cache nodejs npm

RUN python -m pip install --upgrade pip

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 

COPY apiserver/requirements.txt ./api/
COPY apiserver/requirements ./api/requirements

RUN pip install -r ./api/requirements.txt --compile --no-cache-dir

COPY apiserver/manage.py ./api/manage.py
COPY apiserver/plane ./api/plane/
COPY apiserver/templates ./api/templates/
COPY package.json ./api/package.json

COPY apiserver/bin ./api/bin/

RUN chmod +x ./api/bin/*
RUN chmod -R 777 ./api/

COPY --from=installer /app/web/next.config.js ./web/
COPY --from=installer /app/web/package.json ./web/
COPY --from=installer /app/web/.next/standalone ./web
COPY --from=installer /app/web/.next/static ./web/web/.next/static
COPY --from=installer /app/web/public ./web/web/public

COPY --from=installer /app/space/next.config.js ./space/
COPY --from=installer /app/space/package.json ./space/
COPY --from=installer /app/space/.next/standalone ./space
COPY --from=installer /app/space/.next/static ./space/space/.next/static
COPY --from=installer /app/space/public ./space/space/public

COPY --from=installer /app/admin/next.config.js ./admin/
COPY --from=installer /app/admin/package.json ./admin/
COPY --from=installer /app/admin/.next/standalone ./admin
COPY --from=installer /app/admin/.next/static ./admin/admin/.next/static
COPY --from=installer /app/admin/public ./admin/admin/public

ARG NEXT_PUBLIC_API_BASE_URL=""
ENV NEXT_PUBLIC_API_BASE_URL=$NEXT_PUBLIC_API_BASE_URL

ARG NEXT_PUBLIC_ADMIN_BASE_URL=""
ENV NEXT_PUBLIC_ADMIN_BASE_URL=$NEXT_PUBLIC_ADMIN_BASE_URL

ARG NEXT_PUBLIC_ADMIN_BASE_PATH="/god-mode"
ENV NEXT_PUBLIC_ADMIN_BASE_PATH=$NEXT_PUBLIC_ADMIN_BASE_PATH

ARG NEXT_PUBLIC_SPACE_BASE_URL=""
ENV NEXT_PUBLIC_SPACE_BASE_URL=$NEXT_PUBLIC_SPACE_BASE_URL

ARG NEXT_PUBLIC_SPACE_BASE_PATH="/spaces"
ENV NEXT_PUBLIC_SPACE_BASE_PATH=$NEXT_PUBLIC_SPACE_BASE_PATH

ARG NEXT_PUBLIC_WEB_BASE_URL=""
ENV NEXT_PUBLIC_WEB_BASE_URL=$NEXT_PUBLIC_WEB_BASE_URL

ENV NEXT_TELEMETRY_DISABLED=1
ENV TURBO_TELEMETRY_DISABLED=1

COPY aio/supervisord-app /app/supervisord-app
RUN cat /app/supervisord-app >> /app/supervisord.conf && \
    rm /app/supervisord-app

# *****************************************************************************
#  APPLICATION ENVIRONMENT SETTINGS
# *****************************************************************************
ENV APP_DOMAIN=localhost

ENV WEB_URL=http://${APP_DOMAIN}
ENV DEBUG=0
ENV SENTRY_DSN=
ENV SENTRY_ENVIRONMENT=production
ENV CORS_ALLOWED_ORIGINS=http://${APP_DOMAIN},https://${APP_DOMAIN}
# Secret Key
ENV SECRET_KEY=60gp0byfz2dvffa45cxl20p1scy9xbpf6d8c5y0geejgkyp1b5
# Gunicorn Workers
ENV GUNICORN_WORKERS=1

ENV POSTGRES_USER="plane"
ENV POSTGRES_PASSWORD="plane"
ENV POSTGRES_DB="plane"
ENV POSTGRES_HOST="localhost"
ENV POSTGRES_PORT="5432"
ENV DATABASE_URL="postgresql://plane:plane@localhost:5432/plane"

ENV REDIS_HOST="localhost"
ENV REDIS_PORT="6379"
ENV REDIS_URL="redis://localhost:6379"

ENV USE_MINIO="1"
ENV AWS_REGION=""
ENV AWS_ACCESS_KEY_ID="access-key"
ENV AWS_SECRET_ACCESS_KEY="secret-key"
ENV AWS_S3_ENDPOINT_URL="http://localhost:9000"
ENV AWS_S3_BUCKET_NAME="uploads"
ENV MINIO_ROOT_USER="access-key"
ENV MINIO_ROOT_PASSWORD="secret-key"
ENV BUCKET_NAME="uploads"
ENV FILE_SIZE_LIMIT="5242880"

CMD ["/usr/bin/supervisord", "-c", "/app/supervisord.conf"]